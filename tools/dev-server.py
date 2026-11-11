"""Static file server for local development. Sends no-store so edits show up
on reload instead of being served from Chrome's cache."""
import functools, os, http.server, socketserver, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8777


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, max-age=0')
        super().end_headers()


if __name__ == '__main__':
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(('127.0.0.1', PORT), functools.partial(Handler, directory=ROOT)) as srv:
        print(f'serving {ROOT} on http://localhost:{PORT}')
        srv.serve_forever()
