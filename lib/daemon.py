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
MOBWRITE_PATH = os.path.normpath(os.path.join(
    os.path.dirname(__file__) or os.getcwd(),
    "..",
    "ext",
    "google-mobwrite",
    ))
sys.path.insert(0, os.path.join(MOBWRITE_PATH, "daemon"))
sys.path.insert(0, os.path.join(MOBWRITE_PATH, "daemon", "lib"))
import mobwrite_core, mobwrite_daemon
mobwrite_daemon.ROOT_DIR = os.path.join(MOBWRITE_PATH, "daemon") + os.path.sep

if __name__ == "__main__":
    mobwrite_core.logging.basicConfig()
    mobwrite_daemon.main()
    mobwrite_core.logging.shutdown()