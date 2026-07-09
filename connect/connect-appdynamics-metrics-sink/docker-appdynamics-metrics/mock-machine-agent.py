#!/usr/bin/env python3
# Mock of the AppDynamics Standalone Machine Agent HTTP metric listener.
#
# The AppDynamics Metrics sink connector (AppDClient.java) POSTs metrics to
#   {machine.agent.host}:{machine.agent.port}/api/v1/metrics
# and treats HTTP 204 (No Content) as success.
#
# A real machine agent additionally requires an AppDynamics Controller before
# it will open its HTTP listener, which makes it unusable in a self-contained
# CI test. This stub reproduces just the listener contract so the connector can
# be exercised end-to-end without any licensed binary, account, or controller.
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8293
METRICS_PATH = "/api/v1/metrics"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")
        print(f"RECEIVED POST {self.path} -> {body}", flush=True)
        if self.path == METRICS_PATH:
            self.send_response(204)  # AppDClient success code
        else:
            self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass  # silence default request logging; we log our own line above


if __name__ == "__main__":
    print(f"Mock AppDynamics machine agent listening on :{PORT}{METRICS_PATH}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
