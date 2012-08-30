var mobwrite = require("../../mobwrite")
var connect = require("connect")
var app = connect()
app.use(connect.static(__dirname))
app.use(connect.query())
mob = mobwrite({
  logger: console,
  loadDocument: function (filename, callback) {
    var text
    if (filename === "my-notes") {
      text = "This field is prepopulated from our custom document loader."
    } else {
      text = null
    }
    callback(null, text)
  }
})
app.use(mob)
app.listen(8000)