fs = require("fs")
path = require("path")
connect = require("connect")
Daemon = require("./daemon").Daemon

MOBWRITE_SAMPLE_ENDPOINT_PATTERN = /\/scripts\/q.(py|php|jsp)/
MOBWRITE_PATH = path.resolve(__dirname, "..", "ext", "google-mobwrite")
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

middleware = (options) ->

  # Parse configuration options.
  debug = options?.debug is true
  logger = options?.logger
  root = options?.root or "mobwrite"

  # Allow caching to be turned off when developing mobwrite.
  cache = if options?.cache is false then false else true

  # Create a mobwrite daemon to route our requests to.
  daemon = new Daemon
    logger: logger
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

  # Leverage connect() middleware to parse POST bodies and querystrings.
  bodyParser = connect.bodyParser()
  queryParser = connect.query()
  prepareRequest = (req, res, next) ->
    if req.body and req.query
      next()
    else if req.body
      queryParser(req, res, next)
    else if req.query
      bodyParser(req, res, next)
    else
      bodyParser(req, res, -> queryParser(req, res, next))

  # Create a connect middleware (e.g. for use in ExpressJS).
  mobwriteMiddleware = (req, res, next) ->
    prepareRequest req, res, ->

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

        # Make a request to the daemon.
        daemon.sendRawRequest daemonRequest, (err, daemonResponse) ->
          if err
            res.writeHead(500)
            res.end(err.toString())
            return

          # JSONP responses need to be serialized onto a single line and
          # sent to the global mobwrite.callback() function.
          # TODO: allow this callback to be customized with JS monkeypatching?
          if clientNeedsJsonp
            daemonResponse = daemonResponse.replace(new RegExp("\\\\", "g"), "\\\\")
            daemonResponse = daemonResponse.replace(new RegExp("\\\"", "g"), "\\\"")
            daemonResponse = daemonResponse.replace(new RegExp("\\n", "g"), "\\n")
            daemonResponse = daemonResponse.replace(new RegExp("\\r", "g"), "\\r")
            daemonResponse = "mobwrite.callback(\"#{daemonResponse}\");"

          res.writeHead(200, {"Content-Type": "text/javascript"})
          res.end(daemonResponse)

      # Otherwise, we pass control to the next piece of middleware.
      else
        next()

  # Add some helper methods to the middleware object before returning it.
  mobwriteMiddleware.readDocument = -> daemon.readDocument.apply(daemon, arguments)
  mobwriteMiddleware.on = -> daemon.on.apply(daemon, arguments)
  return mobwriteMiddleware

module.exports = middleware
