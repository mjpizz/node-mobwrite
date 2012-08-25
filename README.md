# node-mobwrite
node package of [mobwrite](http://code.google.com/p/google-mobwrite/)

# Getting Started

1. Ensure you have the system requirements:
    * node 0.6+
    * Python 2.5+
2. Install via npm: `npm install mobwrite`
3. Start up a demo server: `node -e "require('mobwrite').quickserve()`
4. Visit [http://localhost:8000](http://localhost:8000) in two browser windows
5. Type text in one browser window, and see it show up in the other window :)

# Building Your Own App

Take a look at "examples/form-editor" for an idea of how to build your own app.
You can use the `mobwrite` module as middleware for any Connect or ExpressJS app.

# Developing

If [google-mobwrite](https://code.google.com/p/google-mobwrite/) changes, you can update the internal copy by re-exporting the SVN repository:

    rm -rf ext/google-mobwrite
    svn export http://google-mobwrite.googlecode.com/svn/trunk ext/google-mobwrite