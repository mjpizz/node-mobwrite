import os, sys

# Monkeypatch ThreadingTCPServer to allow mobwrite to be killed and restarted
# without waiting a long time for the socket to be released for reuse.
# http://stackoverflow.com/questions/3137640/shutting-down-gracefully-from-threadingtcpserver
# http://stackoverflow.com/questions/5875177/how-to-close-a-socket-left-open-by-a-killed-program/5875178#5875178
import SocketServer
class ReusableThreadingTCPServer(SocketServer.ThreadingTCPServer):
    allow_reuse_address = True
SocketServer.ThreadingTCPServer = ReusableThreadingTCPServer

# Now that the monkeypatches are in place, adjust our import paths to point
# at the google-mobwrite directory and import the mobwrite internals.
MOBWRITE_PATH = sys.argv[1]
sys.path.insert(0, os.path.join(MOBWRITE_PATH, "daemon"))
sys.path.insert(0, os.path.join(MOBWRITE_PATH, "lib"))
import mobwrite_core, mobwrite_daemon
mobwrite_daemon.ROOT_DIR = os.path.join(MOBWRITE_PATH, "daemon") + os.path.sep

# If the parent process gave us a document loader, connect to
# it over XMLRPC.
# TODO: consider JSON-formatted shared memory or memcached
if len(sys.argv) == 3 and sys.argv[2]:
    print sys.argv[2]
    import xmlrpclib
    class NodeMobwriteTextObj(mobwrite_daemon.TextObj):
        server_proxy = xmlrpclib.ServerProxy(sys.argv[2])
        def load(self):
            try:
                mobwrite_core.LOG.info("loading document: %s" % self.name)
                text = self.server_proxy.loadDocument(self.name)
                self.setText(text.decode("utf-8"))
                self.changed = False
            except:
                mobwrite_core.LOG.critical("failed to load document: %s" % self.name, exc_info=True)
    mobwrite_daemon.TextObj = NodeMobwriteTextObj

# Run the daemon.
if __name__ == "__main__":
    mobwrite_core.logging.basicConfig()
    mobwrite_daemon.main()
    mobwrite_core.logging.shutdown()