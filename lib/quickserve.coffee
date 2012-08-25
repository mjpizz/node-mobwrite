middleware = require("./middleware")
connect = require("connect")

quickserve = ->
  app = connect()
  app.use(connect.query())
  app.use(middleware({logger: console}))
  app.use (req, res) ->
    res.writeHead(200, {"Content-Type": "text/html"})
    res.end("""
      <html>
      <head>
        <title>[node-mobwrite] Form Editor Example</title>
        <style type="text/css">
          input {
            width: 100%;
            font-family: monospace;
          }
          textarea {
            width: 100%;
            height: 500px;
            font-family: monospace;
          }
        </style>
        <script src="/mobwrite/mobwrite-client.js"></script>
      </head>
      <body>
        <form id="my-form" action="" method="post" accept-charset="utf-8">
          <input type="text" id="my-title" placeholder="Write something in here" style="width:50%;">
          <textarea id="my-notes"></textarea>
        </form>
        <script>
          mobwrite.share("my-form")
        </script>
      </body>
      </html>
      """)
  app.listen(8000)

module.exports = quickserve