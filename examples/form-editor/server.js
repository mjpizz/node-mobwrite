var fs = require("fs")
var path = require("path")
var http = require("http")

// You would "npm install mobwrite" and use require("mobwrite") instead.
var mobwrite = require("../../mobwrite")

// Start a basic HTTP server using the mobwrite middleware.
var mob = mobwrite()
var server = http.createServer(function(req, res) {
  mob(req, res, function next() {
    res.end(fs.readFileSync(path.resolve(__dirname, "index.html")).toString())
  })
})
server.listen(8000)
console.log("visit http://localhost:8000 in your browser")