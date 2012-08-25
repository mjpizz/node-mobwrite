fs = require("fs")
net = require("net")
path = require("path")
spawn = require("child_process").spawn
express = require("express")

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
  serve({logger: logger, port: daemonPort, host: daemonHost})

  # Create a connect middleware (e.g. for use in ExpressJS).
  bodyParser = express.bodyParser()
  return (req, res, next) ->

    # Parse the POST body and bail out if there was no data in there.
    bodyParser req, res, ->
      if not req.body?
        req.on "end", ->
        res.send(500, "missing body in POST")

      # Respond to any requests to the sample q.py/q.php/q.jsp endpoints
      # by grabbing the "q" or "p" parameters and interacting with the Daemon.
      # TODO: implement as "special" URLs, and offer JS from here
      # /__mobwrite__/sync (POST)
      # /__mobwrite__/client.js (GET)
      # /__mobwrite__/forms.js (GET)
      else if MOBWRITE_SAMPLE_ENDPOINT_PATTERN.test(req.url)
        clientNeedsJsonp = req.body?.p?
        daemonRequest = req.body.q or req.body.p or "\n"
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
          if clientNeedsJsonp
            daemonResponse = daemonResponse.replace("\\", "\\\\").replace("\"", "\\\"")
            daemonResponse = daemonResponse.replace("\n", "\\n").replace("\r", "\\r")
            daemonResponse = "mobwrite.callback(\"#{daemonResponse}\");"
          res.send(daemonResponse)

        daemonSocket.on "timeout", (err) ->
          logger?.log("!!! socket timeout: #{err}")
          res.send(500, err.toString())

        daemonSocket.on "error", (err) ->
          logger?.log("!!! socket error: #{err}")
          res.send(500, err.toString())

module.exports = middleware

if module is require.main
  app = express()
  app.get "/editor", (req, res) ->
    res.send("""
      <HTML>
      <HEAD>
      <TITLE>MobWrite as a Collaborative Editor</TITLE>
      <STYLE type="text/css">
      BODY {
        background-color: white;
        font-family: sans-serif;
      }
      H1, H2, H3 {
        font-weight: normal;
      }
      TEXTAREA {
        font-family: sans-serif;
      }
      </STYLE>
      <SCRIPT>
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/diff_match_patch_uncompressed.js"))};
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/mobwrite_core.js"))};
      #{fs.readFileSync(path.resolve(MOBWRITE_PATH, "html/mobwrite_form.js"))};
      mobwrite.debug = true;
      </SCRIPT>
      </HEAD>
      <BODY ONLOAD="mobwrite.share('demo_editor_title', 'demo_editor_text');">

      <TABLE STYLE="height: 100%; width: 100%">

      <TR><TD HEIGHT=1><H1>MobWrite as a Collaborative Editor</H1></TD></TR>

      <TR><TD HEIGHT=1><INPUT TYPE="text" ID="demo_editor_title" STYLE="width: 50%"></TD></TR>

      <TR><TD><TEXTAREA ID="demo_editor_text" STYLE="width: 100%; height: 100%"></TEXTAREA></TD></TR>

      </TABLE>

      </BODY>
      </HTML>
      """)
  app.use(middleware({logger: console}))
  app.listen(8000)
