#!/usr/bin/env python3
"""Stub minimo do Object Storage do OCI: aceita PUT/GET/HEAD de objetos e registra as requisições assinadas."""
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

STORE, LOG = {}, []


class H(BaseHTTPRequestHandler):
    def _rec(self):
        LOG.append({"m": self.command, "p": self.path, "auth": (self.headers.get("Authorization") or "")[:60],
                    "date": self.headers.get("Date") or self.headers.get("x-date")})

    def _send(self, code, body=b"", extra=None):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_PUT(self):
        n = int(self.headers.get("Content-Length", 0))
        STORE[urllib.parse.unquote(self.path.split("?")[0])] = self.rfile.read(n)
        self._rec(); self._send(200, b"", {"ETag": "x"})

    def do_POST(self):
        self._rec(); self.rfile.read(int(self.headers.get("Content-Length", 0))); self._send(200, b"{}")

    def do_HEAD(self):
        self._rec(); b = STORE.get(urllib.parse.unquote(self.path.split("?")[0]))
        self.send_response(404 if b is None else 200)
        self.send_header("Content-Length", "0" if b is None else str(len(b)))
        if b is not None:
            self.send_header("ETag", "x"); self.send_header("Content-Type", "text/csv")
            self.send_header("Last-Modified", "Sun, 11 Oct 2026 19:00:00 GMT")
        self.end_headers()

    def do_GET(self):
        self._rec(); path = urllib.parse.unquote(self.path.split("?")[0])
        if path == "/__log": return self._send(200, json.dumps(LOG).encode())
        if "/o/" in path:
            b = STORE.get(path)
            return self._send(200, b, {"Content-Type": "text/csv"}) if b is not None else self._send(404, b"{}")
        if path.endswith("/o"):
            objs = [{"name": p.split("/o/", 1)[1], "size": len(b)} for p, b in STORE.items()]
            return self._send(200, json.dumps({"objects": objs}).encode(), {"Content-Type": "application/json"})
        self._send(200, json.dumps({"name": "bucket-teste", "namespace": "nsx"}).encode(), {"Content-Type": "application/json"})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 18080), H).serve_forever()
