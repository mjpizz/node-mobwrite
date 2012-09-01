net = require("net")
path = require("path")
spawn = require("child_process").spawn
EventEmitter = require("events").EventEmitter
xmlrpc = require("xmlrpc")

MOBWRITE_PATH = path.resolve(__dirname, "..", "ext", "google-mobwrite")
DEFAULT_DAEMON_PORT = 3017
DEFAULT_DAEMON_HOST = "localhost"
DEFAULT_DAEMON_TIMEOUT_IN_MILLISECONDS = 10*1000
DEFAULT_XMLRPC_DOC_LOADER_PORT = 3018
DEFAULT_XMLRPC_DOC_LOADER_HOST = "localhost"

# Helper for serving out a document loader callback over XMLRPC.
serveXmlrpcDocumentLoader = (port, host, loadDocument) ->
  xmlrpcServer = xmlrpc.createServer({port: port, host: host})
  xmlrpcServer.on "loadDocument", (err, params, callback) ->
    filename = params[0]
    loadDocument(filename, callback)
  return "http://#{host}:#{port}"

###
Daemon(host, port)

Runs a single instance of the Python mobwrite daemon in a child process.

This implementation is currently designed to be used with as many mobwrite
middleware instances as desired - however, there cannot be multiple daemons.
To scale past a single instance, the Python daemon must distribute its state
(specifically ViewObj and TextObj objects).

Protocol reference:
http://code.google.com/p/google-mobwrite/wiki/Protocol
###
class Daemon

  # Public Daemon interface.
  sendRawRequest: (req, callback) -> @priv.sendRawRequest(req, callback)
  readDocument: (filename, callback) -> @priv.readDocument(filename, callback)
  on: (eventName, callback) -> @priv.on(eventName, callback)

  # Daemon implementation.
  constructor: (options) ->
    logger = options.logger

    # Parse configuration options for the Python child process.
    port = options.port or DEFAULT_DAEMON_PORT
    host = options.host or DEFAULT_DAEMON_HOST
    timeoutInMilliseconds = DEFAULT_DAEMON_TIMEOUT_IN_MILLISECONDS

    # Notify the user if they are trying to customize port (will be supported
    # in the future, just needs modifications in daemon.py).
    # TODO: propagate port/host in daemonOptions?
    if port and port isnt DEFAULT_DAEMON_PORT
      throw new Error("overriding daemon port is not supported yet")

    # Populate daemon options to give to daemon.py.
    daemonOptions =
      mobwritePath: MOBWRITE_PATH

    # Parse configuration options for document loading.
    loadDocument = options.loadDocument
    if loadDocument
      # TODO: implement other methods that would allow horizontal scalability, e.g memcache
      xmlrpcPort = options.xmlrpcPort or DEFAULT_XMLRPC_DOC_LOADER_PORT
      xmlrpcHost = options.xmlrpcHost or DEFAULT_XMLRPC_DOC_LOADER_HOST
      xmlrpcUri = serveXmlrpcDocumentLoader(xmlrpcPort, xmlrpcHost, loadDocument)
      logger?.info("[daemon-client] using XMLRPC document loader @ #{xmlrpcUri}")
      daemonOptions.xmlrpcDocumentLoader = {uri: xmlrpcUri}

    # Create an event emitter for events like "document:change".
    emitter = new EventEmitter()

    # Start the Python mobwrite daemon as a child process.
    startPythonDaemon = ->
      daemonProcess = spawn(
        "python"
        ["daemon.py", JSON.stringify(daemonOptions)]
        {cwd: path.resolve(__dirname)}
        )

      # Ensure that the child process is cleaned up on exit.
      cleanedUp = false
      cleanup = (err) ->
        unless cleanedUp
          cleanedUp = true
          daemonProcess.kill()
      cleanupAndExit = (err) ->
        if err
          logger?.error("[daemon-system] exiting due to error:", err)
        if daemonExited
          process.exit()
        else
          daemonProcess.on("exit", -> process.exit())
          process.nextTick(cleanup)
      process.on("exit", cleanup)
      process.on("uncaughtException", cleanupAndExit)
      process.on("SIGINT", cleanupAndExit)
      process.on("SIGTERM", cleanupAndExit)

      # Propagate stdout/stderr to console, if requested.
      if logger?
        log = (prefix, data) ->
          lines = data.toString().split("\n")
          for line in lines
            unless /^\s*$/.test(line)
              logger?.info("#{prefix} #{line}")
        daemonProcess.stdout.on("data", (d) -> log("[daemon-stdout]", d))
        daemonProcess.stderr.on("data", (d) -> log("[daemon-stderr]", d))

      # Watch for daemon exits.
      # TODO: auto-restart?
      daemonExited = false
      daemonProcess.on "exit", (exitCode, signal) ->
        daemonExited = true
        if signal and exitCode isnt null and exitCode isnt 0
          logger?.error("[daemon-system] exited with code #{exitCode} due to signal #{signal}")
        else if signal
          logger?.error("[daemon-system] exited due to signal #{signal}")
        else if exitCode isnt 0
          logger?.error("[daemon-system] exited with code #{exitCode}")

    # Define a helper that issues a raw request to the daemon and returns
    # the raw response from the daemon.  If there are any errors, it gives
    # that as the first argument to the callback.
    # http://code.google.com/p/google-mobwrite/wiki/Protocol
    sendRawRequest = (req, callback) ->
      daemonSocket = net.createConnection(port, host)
      daemonSocket.setTimeout(timeoutInMilliseconds)

      # Parse out the filename for this request.
      filenameMatches = /^F\:\d+\:([^\n]+)$/m.exec(req)
      unless filenameMatches
        logger?.warn("missing filename in patch request:", req)
        res.writeHead(500)
        res.end("missing filename in patch request")
        return
      filename = filenameMatches[1]

      # Parse out the patch content for this request.
      patchContentMatches = /^d\:\d+\:\=\d+\s*([^\d][^\n]+)$/m.exec(req)

      # Listen for all the stages of the socket request.
      daemonSocket.on "connect", ->
        logger?.info("[daemon-client] socket connected, sending request:\n#{req}")
        daemonSocket.write(req)

      rawResponse = ""
      daemonSocket.on "data", (data) ->
        logger?.info("[daemon-client] socket received #{data.length} bytes")
        rawResponse += data

      daemonSocket.on "end", ->
        rawResponse += "\n"
        logger?.info("[daemon-client] socket finished receiving:\n#{rawResponse}")
        callback(null, rawResponse)

        # If this patch actually made changes to the document, emit an event
        # for that.
        if patchContentMatches and patchContentMatches[1].length > 0
          emitter.emit("document:change", filename)

      daemonSocket.on "timeout", (err) ->
        logger?.error("[daemon-client] socket timed out:", err)
        callback(err)

      daemonSocket.on "error", (err) ->
        logger?.error("[daemon-client] socket errored out:", err)
        callback(err)

    # Define a helper that can read the current contents of a document
    # from the mobwrite Python daemon.
    readDocument = (filename, callback) ->
      callback(null, "not implemented yet")

    startPythonDaemon()
    @priv =
      sendRawRequest: sendRawRequest
      readDocument: readDocument
      on: (eventName, callback) -> emitter.on(eventName, callback)

exports.Daemon = Daemon