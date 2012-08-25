fs = require("fs")
net = require("net")
path = require("path")
spawn = require("child_process").spawn
connect = require("connect")

MOBWRITE_SAMPLE_ENDPOINT_PATTERN = /\/scripts\/q.(py|php|jsp)/
MOBWRITE_PATH = path.resolve(__dirname, "..", "ext", "google-mobwrite")
DAEMON_TIMEOUT_IN_MILLISECONDS = 10*1000
DEFAULT_DAEMON_HOST = "localhost"
DEFAULT_DAEMON_PORT = 3017

serve = (options) ->
  port = options?.port or DEFAULT_DAEMON_PORT
  logger = options?.logger

  # Notify the user if they are trying to customize port (will be supported
  # in the future, just needs modifications in daemon.py).
  if port and port isnt DEFAULT_DAEMON_PORT
    throw new Error("overriding daemon port is not supported yet")

  # Start the Python mobwrite daemon as a child process.
  daemonProcess = spawn(
    "python"
    ["daemon.py"]
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
    daemonProcess.on "exit", (exitCode, signal) ->
      if signal and exitCode isnt null and exitCode isnt 0
        logger?.error("daemon.py [sys] exited with code #{exitCode} due to signal #{signal}")
      else if signal
        logger?.error("daemon.py [sys] exited due to signal #{signal}")
      else if exitCode isnt 0
        logger?.error("daemon.py [sys] exited with code #{exitCode}")

middleware = (options) ->

  # Start the Python mobwrite daemon.
  logger = options?.logger
  daemonPort = options?.port or DEFAULT_DAEMON_PORT
  daemonHost = options?.host or DEFAULT_DAEMON_HOST
  root = options?.root or "__mobwrite__"
  serve({logger: logger, port: daemonPort, host: daemonHost})

  # Make a pattern that we can match inbound requests for mobwrite middleware.
  rootPattern = new RegExp("#{root}/([^\/]+)")

  # Create a connect middleware (e.g. for use in ExpressJS).
  # TODO: verify that this works with plain http.createServer()
  bodyParser = connect.bodyParser()
  return (req, res, next) ->
    bodyParser req, res, ->

      # Respond to any requests to the sample q.py/q.php/q.jsp endpoints
      # by grabbing the "q" or "p" parameters and interacting with the Daemon.
      # TODO: implement as "special" URLs, and offer JS from here
      # /__mobwrite__/sync (POST)
      # /__mobwrite__/client.js (GET)
      # /__mobwrite__/forms.js (GET)
      if MOBWRITE_SAMPLE_ENDPOINT_PATTERN.test(req.url) or rootPattern.test(req.url)
        clientNeedsJsonp = req.query.p?
        daemonRequest = req.body?.q or req.query.p or "\n"
        daemonResponse = ""

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

module.exports = middleware

if module is require.main
  express = require("express")
  app = express()
  app.get "/editor", (req, res) ->
    res.send("""
      <html>
      <head>
      <title>MobWrite as a Collaborative Editor (Remote)</title>
      <style type="text/css">
          body {
            background-color: white;
            font-family: sans-serif;
          }
          h1, h2, h3 { font-weight: normal; }
          table{ width:100%; height:100%; }
          input{ width:50%; }
          textarea {
              width:100%;
              height:100%;
              font-family: sans-serif;
          }
      </style>
      <script>
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/diff_match_patch_uncompressed.js"))};
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/mobwrite_core.js"))};
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/mobwrite_form.js"))};
      </script>
      </head>
      <body>
          <form id="mobwrite-form" action="" method="post" accept-charset="utf-8">
              <table border="0" cellspacing="0" cellpadding="0">
                  <tr>
                      <td height="1">
                          <H1>MobWrite as a Collaborative Editor</H1>
                          <H2>Calling remotely via JSON-P.</H2>
                      </td>
                  </tr>
                  <tr>
                      <td height="1">
                          <input type="text" id="editor-title" placeholder="Your name" style="width:50%;">
                      </td>
                  </tr>
                  <tr>
                      <td>
                          <textarea id="editor-text" style="width:100%; height:100%;"></textarea>
                      </td>
                  </tr>
              </table>
          </form>
          <script>
              //mobwrite.syncGateway = location.protocol + '//' + location.host + "/__mobwrite__/";
              mobwrite.debug = true;
              mobwrite.syncInterval = 250
              mobwrite.minSyncInterval = 250
              mobwrite.maxSyncInterval = 1250
              mobwrite.share('mobwrite-form');
          </script>
      </body>
      </html>
      """)
  app.use(express.logger({format: '[:date] [:response-time] [:status] [:method] [:url]'}))
  app.use(middleware({logger: console}))
  app.listen(8000)
