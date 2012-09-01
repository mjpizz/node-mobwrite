# node-mobwrite

This is a node port of [google-mobwrite](http://code.google.com/p/google-mobwrite/),
which enables live collaborative editing of text (e.g. in forms).

# Getting Started

1. Ensure you have the system requirements:
    * node 0.6+
    * Python 2.5+
2. Install via npm: `npm install mobwrite`
3. Start up a demo server: `node node_modules/mobwrite/examples/form-editor/server.js`
4. Visit [http://localhost:8000](http://localhost:8000) in two browser windows
5. Type text in one browser window, and see it show up in the other window :)

# Building Your Own App

To start, create a demo page like `demo.html`:

```html
<html>
<head>
  <script src="/mobwrite/mobwrite-client.js"></script>
</head>
<body>
  <strong>
    Open this page in multiple browser windows, edits will sync between them :)
  </strong>
  <form>
    <textarea rows="20" cols="60" id="my-notes"></textarea>
  </form>
  <script>
    mobwrite.share("my-notes")
  </script>
</body>
</html>
```

This will share a document with a filename of "my-notes".

Next, connect your demo to a webserver with the mobwrite middleware.
You have a couple options:

1. express web framework (see below)
2. the builtin `http` module in node (see below)

You can also take a look at the [examples](https://github.com/mjpizz/node-mobwrite/tree/master/examples)
for more ideas.

### Option 1: mobwrite + express web framework

If you are using [express](http://expressjs.com/) as your webserver, you can
easily `use()` mobwrite functionality as middleware.

First, make sure that you have the `express` module installed:

    npm install express

Next, create an `app.js` in the same directory as your `demo.html`:

```javascript
var mobwrite = require("mobwrite")
var express = require("express")

var app = express()
app.use(express.static(__dirname))

app.use(mobwrite())

app.listen(8000)
console.log("visit http://localhost:8000/demo.html in your browser")
```

Then, start the server from the commandline:

    node app.js

You can visit your demo at [http://localhost:8000/demo.html](http://localhost:8000/demo.html).

### Option 2: mobwrite + builtin node HTTP server

Create an `app.js` in the same directory as your `demo.html`:

```javascript
var fs = require("fs")
var path = require("path")
var http = require("http")
var mobwrite = require("mobwrite")

var mob = mobwrite()
var server = http.createServer(function(req, res) {
  mob(req, res, function next() {
    res.end(fs.readFileSync(path.resolve(__dirname, "demo.html")).toString())
  })
})

server.listen(8000)
console.log("visit http://localhost:8000/demo.html in your browser")
```

Then, start the server from the commandline:

    node app.js

You can visit your demo at [http://localhost:8000/demo.html](http://localhost:8000/demo.html).

# Using Advanced Features

There are a few configuration options you can use to customize the behavior
of mobwrite:

```javascript
var mobwrite = require("mobwrite")
var mob = mobwrite({

  // View server logs in your terminal.
  logger: console,

  // Show debug logs in the browser, and use an uncompressed copy of Javascript.
  // This also increases the verbosity of server-side logs.
  debug: true,

  // Set the root path for the middleware.  This is "mobwrite" by default,
  // which is why you load the Javascript from "/mobwrite/mobwrite-client.js".
  // Change this if you already have something else using the "/mobwrite" path.
  root: "mobwrite",

  // Tell mobwrite how to load custom documents (e.g. from your database).
  // Otherwise, mobwrite just creates a new in-memory copy of each document.
  loadDocument: function(filename, callback) {
    try {
      var doc = mydatabase.getDoc(filename)
      callback(null, doc)
    } catch(err) {
      callback(err)
    }
  }

})
```

You can also keep up-to-date on the current contents of a document:

* `on("document:change", callback)` triggers when a document changes inside of mobwrite
* `readDocument(callback)` reads the document from mobwrite

For example, you could set up auto-saving to your database:

```javascript
var mobwrite = require("mobwrite")
var mob = mobwrite()

// This event handler gets called anytime a browser client makes a change
// to a document in mobwrite.
mob.on("document:change", function(filename) {

  // Save the document to your database.
  mob.readDocument(filename, function(data) {
    mydatabase.saveDoc(filename, data)
  })

})
```

# Developing

If [google-mobwrite](https://code.google.com/p/google-mobwrite/) changes, you
can update the internal copy by re-exporting the SVN repository:

    rm -rf ext/google-mobwrite
    svn export http://google-mobwrite.googlecode.com/svn/trunk ext/google-mobwrite

# Contributing

Improvements and additions are welcome!  Here's a list of ideas:

* socket.io gateway (faster, cleaner, less polling)
* configuration handling for mobwrite daemon (right now it uses baked-in configs)
* memcache-based document loading (rather than transferring via XMLRPC)
* browser-side event for merge conflicts (e.g. so the browser could warn the user)
* ability to connect middleware to an existing mobwrite daemon or AppEngine instance
* reconnect behavior for clients (when the server is restarted)
