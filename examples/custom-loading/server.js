var mobwrite = require("../../mobwrite")
var connect = require("connect")
var app = connect()
app.use(connect.static(__dirname))
app.use(connect.query())
mob = mobwrite({
  logger: console,
  loadDocument: function(filename, callback) {
    var text
    if (filename === "my-notes") {
      text = "This field is prepopulated from our custom document loader."
    } else {
      text = null
    }
    callback(null, text)
  }
})
mob.on("document:change", function(filename) {
  console.log("document changed:", filename)
  mob.getDocument(filename, function(err, text) {
    if (err) {
      console.error("failed to get document contents for", filanem, "due to", err)
    } else {
      console.log("new document contents for", filename, "=", text)
    }
  })
})
app.use(mob)
app.listen(8000)