fs = require("fs")
net = require("net")
path = require("path")
spawn = require("child_process").spawn
EventEmitter = require("events").EventEmitter
xmlrpc = require("xmlrpc")
connect = require("connect")

MOBWRITE_SAMPLE_ENDPOINT_PATTERN = /\/scripts\/q.(py|php|jsp)/
MOBWRITE_PATH = path.resolve(__dirname, "..", "ext", "google-mobwrite")
DAEMON_TIMEOUT_IN_MILLISECONDS = 10*1000
DEFAULT_DAEMON_HOST = "localhost"
DEFAULT_DAEMON_PORT = 3017
DEFAULT_XMLRPC_SERVER_HOST = "localhost"
DEFAULT_XMLRPC_SERVER_PORT = 3018
DEFAULT_MIN_SYNC_INTERVAL = 250
DEFAULT_MAX_SYNC_INTERVAL = 1250

getMobwriteDebugJavascript = ->
  return """
    ;(function(){
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/diff_match_patch_uncompressed.js"))};
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/mobwrite_core.js"))};
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/mobwrite_form.js"))};
    }).call(this);
    """

getMobwriteMinifiedJavascript = ->
  return """
    ;(function(){
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/compressed_form.js"))};
    }).call(this);
    """

serve = (options) ->
  port = options?.port or DEFAULT_DAEMON_PORT
  logger = options?.logger
  loadDocument = options?.loadDocument

  # Notify the user if they are trying to customize port (will be supported
  # in the future, just needs modifications in daemon.py).
  if port and port isnt DEFAULT_DAEMON_PORT
    throw new Error("overriding daemon port is not supported yet")

  # Serve out our loadDocument() callback over XMLRPC.
  if loadDocument
    logger.info("using custom document loader.")
    xmlrpcServer = xmlrpc.createServer
      host: DEFAULT_XMLRPC_SERVER_HOST
      port: DEFAULT_XMLRPC_SERVER_PORT
    xmlrpcServer.on "loadDocument", (err, params, callback) ->
      filename = params[0]
      loadDocument(filename, callback)
    xmlrpcServerUri = "http://#{DEFAULT_XMLRPC_SERVER_HOST}:#{DEFAULT_XMLRPC_SERVER_PORT}"
  else
    xmlrpcServerUri = ""

  # Start the Python mobwrite daemon as a child process.
  daemonProcess = spawn(
    "python"
    ["daemon.py", MOBWRITE_PATH, xmlrpcServerUri]
    {cwd: path.resolve(__dirname)}
    )

  # Ensure that the child process is cleaned up on exit.
  cleanedUp = false
  cleanup = (err, exitIfCleanedAlready) ->
    unless cleanedUp
      cleanedUp = true
      logger?.error(err) if err
      daemonProcess.kill()
  process.on("exit", cleanup)
  process.on("uncaughtException", cleanup)
  process.on "SIGINT", ->
    if daemonExited
      process.exit()
    else
      daemonProcess.on("exit", -> process.exit())
      process.nextTick(cleanup)

  # Propagate stdout/stderr to console, if requested.
  if logger?
    log = (name, data) ->
      lines = data.toString().split("\n")
      for line in lines
        unless /^\s*$/.test(line)
          logger?.log("#{name}: #{line}")
    daemonProcess.stdout.on("data", (d) -> log("daemon.py [out]", d))
    daemonProcess.stderr.on("data", (d) -> log("daemon.py [err]", d))

  # Watch for daemon exits.
  daemonExited = false
  daemonProcess.on "exit", (exitCode, signal) ->
    daemonExited = true
    if signal and exitCode isnt null and exitCode isnt 0
      logger?.error("daemon.py [sys] exited with code #{exitCode} due to signal #{signal}")
    else if signal
      logger?.error("daemon.py [sys] exited due to signal #{signal}")
    else if exitCode isnt 0
      logger?.error("daemon.py [sys] exited with code #{exitCode}")

  # # Return an object representing this daemon process.
  return daemon =
    getDocument: (filename, callback) ->
      callback(null, "TextObj content retrieval not implemented yet")

middleware = (options) ->

  # Start the Python mobwrite daemon.
  debug = options?.debug is true
  cache = options?.cache is true
  logger = options?.logger
  daemonPort = options?.port or DEFAULT_DAEMON_PORT
  daemonHost = options?.host or DEFAULT_DAEMON_HOST
  root = options?.root or "mobwrite"
  daemon = serve
    logger: logger
    port: daemonPort
    host: daemonHost
    loadDocument: options?.loadDocument

  # Make a pattern that we can match inbound requests for mobwrite middleware.
  rootPattern = new RegExp("#{root}/([^\\/\\?]+)")

  # Set up default Javascript configs. These can always be overridden in the
  # HTML anyway, but setting sane defaults helps.
  clientOptions =
    debug: debug
    syncGateway: "/#{root}/sync"
    syncInterval: options?.minSyncInterval or DEFAULT_MIN_SYNC_INTERVAL
    minSyncInterval: options?.minSyncInterval or DEFAULT_MIN_SYNC_INTERVAL
    maxSyncInterval: options?.maxSyncInterval or DEFAULT_MAX_SYNC_INTERVAL
  getClientJavascript = ->
    return """
      ;(function(){
        #{if debug then getMobwriteDebugJavascript() else getMobwriteMinifiedJavascript()}
        var options = JSON.parse(#{JSON.stringify(JSON.stringify(clientOptions))})
        for (var key in options) {
          if (options.hasOwnProperty(key)) {
            mobwrite[key] = options[key]
          }
        }
      }).call(this);
      """
  clientJavascriptCache = getClientJavascript()

  # Create an event emitter for events like "document:change".
  emitter = new EventEmitter()

  # Create a connect middleware (e.g. for use in ExpressJS).
  # TODO: verify that this works with plain http.createServer()
  bodyParser = connect.bodyParser()
  mobwriteMiddleware = (req, res, next) ->
    bodyParser req, res, ->

      # Respond to requests for the "mobwrite-client.js" file.
      rootPath = rootPattern.exec(req.url)?[1]
      if rootPath is "mobwrite-client.js"
        res.writeHead(200, {"Content-Type": "text/javascript"})
        res.end(if cache then clientJavascriptCache else getClientJavascript())

      # Respond to any requests to the sync endpoint (or to the typical
      # mobwrite sample code q.py/q.php/q.jsp endpoints) by grabbing the
      # "q" (AJAX) or "p" (JSONP) parameters and forwarding them to the Daemon.
      else if rootPath is "sync" or MOBWRITE_SAMPLE_ENDPOINT_PATTERN.test(req.url)
        clientNeedsJsonp = req.query.p?
        daemonRequest = req.body?.q or req.query.p or "\n"
        daemonResponse = ""

        # Parse out the filename for this request.
        filenameMatches = /^F\:\d+\:([^\n]+)$/m.exec(daemonRequest)
        unless filenameMatches
          logger.warn("missing filename in patch request:", daemonRequest)
          res.writeHead(500)
          res.end("missing filename in patch request")
          return
        filename = filenameMatches[1]

        # Parse out the patch content for this request.
        patchContentMatches = /^d\:\d+\:\=\d+\s*([^\d][^\n]+)$/m.exec(daemonRequest)
        if patchContentMatches and patchContentMatches[1].length > 0
          console.log daemonRequest
          emitter.emit("document:change", filename)

        # Open a socket to the daemon.
        daemonSocket = net.createConnection(daemonPort, daemonHost)
        daemonSocket.setTimeout(DAEMON_TIMEOUT_IN_MILLISECONDS)

        daemonSocket.on "connect", ->
          logger?.log(">>> socket connected, writing request:\n---#{daemonRequest}---")
          daemonSocket.write(daemonRequest)

        daemonSocket.on "data", (data) ->
          logger?.log(">>> socket received data:\n#{data}")
          daemonResponse += data

        daemonSocket.on "end", ->
          logger?.log(">>> socket finished reading from daemon")

          # JSONP responses need to be serialized onto a single line and
          # sent to the global mobwrite.callback() function.
          # TODO: allow this callback to be customized with JS monkeypatching?
          if clientNeedsJsonp
            daemonResponse = daemonResponse.replace(new RegExp("\\\\", "g"), "\\\\")
            daemonResponse = daemonResponse.replace(new RegExp("\\\"", "g"), "\\\"")
            daemonResponse = daemonResponse.replace(new RegExp("\\n", "g"), "\\n")
            daemonResponse = daemonResponse.replace(new RegExp("\\r", "g"), "\\r")
            daemonResponse = "mobwrite.callback(\"#{daemonResponse}\");"

          # AJAX responses need an extra newline at the end.
          else
            daemonResponse += "\n"

          console.warn(">> sending to client\n---\n#{daemonResponse}\n---")
          res.writeHead(200, {"Content-Type": "text/javascript"})
          res.end(daemonResponse)

        daemonSocket.on "timeout", (err) ->
          logger?.log("!!! socket timeout: #{err}")
          res.writeHead(500)
          res.end(err.toString())

        daemonSocket.on "error", (err) ->
          logger?.log("!!! socket error: #{err}")
          res.writeHead(500)
          res.end(err.toString())

      # Otherwise, we pass control to the next piece of middleware.
      else
        next()

  # Add some helper methods to the middleware object before returning it.
  mobwriteMiddleware.getDocument = -> daemon.getDocument.apply(daemon, arguments)
  mobwriteMiddleware.on = -> emitter.on.apply(emitter, arguments)
  return mobwriteMiddleware

module.exports = middleware
