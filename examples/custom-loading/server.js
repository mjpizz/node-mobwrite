var fs = require("fs")
var path = require("path")
var http = require("http")

// You would "npm install mobwrite" and use require("mobwrite") instead.
var mobwrite = require("../../mobwrite")

mob = mobwrite({

  // Set a custom document loader.  This example just uses a hardcoded sentence,
  // but you can imagine reading it out of a database too.
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

// Every time the document changes, we log that happening.  You could use this
// to decide when it's time to auto-save the document back to your database.
mob.on("document:change", function(filename) {
  console.log("document changed:", filename)
  mob.readDocument(filename, function(err, data) {
    if (err) {
      console.error("failed to get document contents for", filename, "due to", err)
    } else {
      console.log("new document contents for", filename, "=", data.toString())
    }
  })
})

// Start a basic HTTP server using the mobwrite middleware.
var server = http.createServer(function(req, res) {
  mob(req, res, function next() {
    res.end(fs.readFileSync(path.resolve(__dirname, "index.html")).toString())
  })
})
server.listen(8000)
console.log("visit http://localhost:8000 in your browser")