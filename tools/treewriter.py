#!/usr/bin/env python3
"""Tiny localhost writer so the Upgrade Tree Editor plugin can save to disk.

Studio plugins have no filesystem access, so the plugin POSTs the generated
Upgrades.luau here and this writes it. Rojo then syncs it straight back into
Studio, which closes the loop.

    python3 tools/treewriter.py [path-to-Upgrades.luau]

Binds to 127.0.0.1 only, and writes exactly one file -- the path is fixed at
startup, never taken from the request.
"""
import http.server
import os
import sys

Default = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "src", "Shared", "Configs", "Upgrades.luau")
Target = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else Default
Port = 8790


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.reply(200, b"treewriter ok")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(length).decode("utf-8")

        # refuse anything that is not recognisably the upgrades config, so a
        # stray request cannot blank the file
        if "local Upgrades" not in data or "return {" not in data:
            self.reply(400, b"rejected: does not look like Upgrades.luau")
            return
        if len(data) < 200:
            self.reply(400, b"rejected: suspiciously short")
            return

        with open(Target, "w", encoding="utf-8") as handle:
            handle.write(data)
        print(f"wrote {len(data)} bytes -> {Target}", flush=True)
        self.reply(200, b"ok")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if not os.path.isdir(os.path.dirname(Target)):
        sys.exit(f"target directory does not exist: {os.path.dirname(Target)}")
    print(f"treewriter listening on http://127.0.0.1:{Port}")
    print(f"writing to {Target}")
    http.server.HTTPServer(("127.0.0.1", Port), Handler).serve_forever()
