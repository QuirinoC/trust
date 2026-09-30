#!/usr/bin/env python3
"""Loopback-only fault proxy for Trust's real-API UI race regression.

Run the Development + Memory API on 127.0.0.1:5090, then run this proxy. XCTest
and the app use the proxy on 127.0.0.1:5089. It has no remote-host option and
never logs request bodies, authorization headers, phone numbers, or coordinates.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import urllib.error
import urllib.request


UPSTREAM = "http://127.0.0.1:5090"
LOCK = threading.Lock()
STATE = {
    "hold_next_circle": False,
    "hold_next_history": False,
    "hold_next_look": False,
    "fail_circle_after_release": False,
    "fail_next_circle": False,
    "fail_share_after_first_ack": False,
    "fail_next_share": False,
    "holding": False,
    "held_resource": None,
    "share_ack_count": 0,
    "share_failure_count": 0,
    "share_ack_person_ids": [],
    "share_failed_person_ids": [],
    "revoke_ack_count": 0,
    "stale_release_count": 0,
    "circle_failure_count": 0,
    "history_hold_count": 0,
    "history_release_count": 0,
    "look_hold_count": 0,
    "look_release_count": 0,
}
RELEASE_HELD = threading.Event()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        # Request paths can contain IDs. Keep the test proxy quiet by default.
        return

    def do_GET(self):
        if self.path == "/__test/state":
            self.respond_json(200, self.state_copy())
            return
        self.forward()

    def do_POST(self):
        if self.path.startswith("/__test/"):
            # XCTest's URLSession may send `{}` for control requests. Consume it
            # before responding so a keep-alive connection starts cleanly.
            length = int(self.headers.get("Content-Length", "0"))
            if length:
                self.rfile.read(length)
        if self.path == "/__test/reset":
            with LOCK:
                for key in list(STATE):
                    STATE[key] = [] if key.endswith("_person_ids") else 0 if key.endswith("_count") else False
                STATE["holding"] = False
                STATE["held_resource"] = None
                RELEASE_HELD.set()
            self.respond_json(200, {"reset": True})
            return
        if self.path == "/__test/arm":
            with LOCK:
                STATE.update({
                    "hold_next_circle": True,
                    "hold_next_history": False,
                    "hold_next_look": False,
                    "fail_circle_after_release": True,
                    "fail_next_circle": False,
                    "fail_share_after_first_ack": False,
                    "fail_next_share": False,
                    "holding": False,
                    "held_resource": None,
                    "share_ack_count": 0,
                    "share_failure_count": 0,
                    "share_ack_person_ids": [],
                    "share_failed_person_ids": [],
                    "revoke_ack_count": 0,
                    "stale_release_count": 0,
                    "circle_failure_count": 0,
                    "history_hold_count": 0,
                    "history_release_count": 0,
                    "look_hold_count": 0,
                    "look_release_count": 0,
                })
                RELEASE_HELD.clear()
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/arm-history":
            with LOCK:
                STATE.update({
                    "hold_next_circle": False,
                    "hold_next_history": True,
                    "hold_next_look": False,
                    "fail_circle_after_release": False,
                    "fail_next_circle": False,
                    "holding": False,
                    "held_resource": None,
                    "history_hold_count": 0,
                    "history_release_count": 0,
                    "look_release_count": 0,
                })
                RELEASE_HELD.clear()
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/arm-look":
            with LOCK:
                STATE.update({
                    "hold_next_circle": False,
                    "hold_next_history": False,
                    "hold_next_look": True,
                    "holding": False,
                    "held_resource": None,
                    "look_hold_count": 0,
                    "history_release_count": 0,
                    "look_release_count": 0,
                })
                RELEASE_HELD.clear()
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/arm-stop-all":
            with LOCK:
                STATE.update({
                    "hold_next_circle": False,
                    "hold_next_history": False,
                    "hold_next_look": False,
                    "fail_circle_after_release": False,
                    "fail_next_circle": False,
                    "fail_share_after_first_ack": True,
                    "fail_next_share": False,
                    "holding": False,
                    "held_resource": None,
                    "share_ack_count": 0,
                    "share_failure_count": 0,
                    "share_ack_person_ids": [],
                    "share_failed_person_ids": [],
                })
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/release":
            with LOCK:
                if not STATE["holding"]:
                    self.respond_json(409, {"released": False, "error": "no-held-circle-response"})
                    return
                STATE["holding"] = False
                released_resource = STATE["held_resource"]
                STATE["held_resource"] = None
                STATE["fail_next_circle"] = STATE["fail_circle_after_release"]
                STATE["fail_circle_after_release"] = False
                STATE["stale_release_count"] += 1
                if released_resource == "history":
                    STATE["history_release_count"] = STATE.get("history_release_count", 0) + 1
                elif released_resource == "look":
                    STATE["look_release_count"] += 1
                RELEASE_HELD.set()
            self.respond_json(200, {"released": True})
            return
        self.forward()

    def do_PUT(self):
        self.forward()

    def do_PATCH(self):
        self.forward()

    def do_DELETE(self):
        self.forward()

    def do_OPTIONS(self):
        self.forward()

    def forward(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else None
        path = self.path
        is_circle = self.command == "GET" and path.split("?", 1)[0] == "/api/v1/circle"
        is_history = self.command == "GET" and path.split("?", 1)[0].startswith("/api/v1/people/") and path.endswith("/history")
        is_look = self.command == "POST" and path.split("?", 1)[0] == "/api/v1/looks"
        is_share = self.command == "PATCH" and path.split("?", 1)[0].startswith("/api/v1/people/") and path.endswith("/share")
        person_id = path.split("/api/v1/people/", 1)[1].split("/", 1)[0] if "/api/v1/people/" in path else None

        with LOCK:
            fail_this_circle = is_circle and STATE["fail_next_circle"]
            if fail_this_circle:
                STATE["fail_next_circle"] = False
                STATE["circle_failure_count"] += 1
            hold_this_circle = is_circle and STATE["hold_next_circle"]
            if hold_this_circle:
                STATE["hold_next_circle"] = False
            hold_this_history = is_history and STATE["hold_next_history"]
            if hold_this_history:
                STATE["hold_next_history"] = False
            hold_this_look = is_look and STATE["hold_next_look"]
            if hold_this_look:
                STATE["hold_next_look"] = False
            fail_this_share = is_share and STATE["fail_next_share"]
            if fail_this_share:
                STATE["fail_next_share"] = False
                STATE["share_failure_count"] += 1
                STATE["share_failed_person_ids"].append(person_id)

        if fail_this_share:
            self.respond_json(503, {"error": "deterministic-test-share-write-failure"})
            return

        if fail_this_circle:
            self.respond_json(503, {"error": "deterministic-test-circle-read-failure"})
            return

        headers = {}
        for key in ("Accept", "Authorization", "Content-Type", "User-Agent"):
            value = self.headers.get(key)
            if value is not None:
                headers[key] = value
        request = urllib.request.Request(UPSTREAM + path, data=body, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(request, timeout=12) as response:
                status = response.status
                response_body = response.read()
                response_headers = response.headers
        except urllib.error.HTTPError as error:
            status = error.code
            response_body = error.read()
            response_headers = error.headers
        except Exception:
            self.respond_json(502, {"error": "local-test-upstream-unavailable"})
            return

        held_resource = "circle" if hold_this_circle else "history" if hold_this_history else "look" if hold_this_look else None
        if held_resource:
            with LOCK:
                STATE["holding"] = True
                STATE["held_resource"] = held_resource
                if held_resource == "history":
                    STATE["history_hold_count"] += 1
                elif held_resource == "look":
                    STATE["look_hold_count"] += 1
            if not RELEASE_HELD.wait(timeout=60):
                with LOCK:
                    STATE["holding"] = False
                    STATE["held_resource"] = None
                self.respond_json(504, {"error": "test-did-not-release-held-response"})
                return

        # Record committed writes and arm the injected second Stop All failure
        # before the client can receive the first successful response.
        if 200 <= status < 300:
            with LOCK:
                if is_share:
                    STATE["share_ack_count"] += 1
                    STATE["share_ack_person_ids"].append(person_id)
                    if STATE["fail_share_after_first_ack"] and STATE["share_ack_count"] == 1:
                        STATE["fail_next_share"] = True
                if self.command == "POST" and path.split("?", 1)[0].startswith("/api/v1/people/") and path.endswith("/revoke"):
                    STATE["revoke_ack_count"] += 1

        if status == 204 or not response_body:
            self.send_response(status)
            self.end_headers()
        else:
            self.send_response(status)
            content_type = response_headers.get("Content-Type", "application/json")
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            self.wfile.write(response_body)


    def state_copy(self):
        with LOCK:
            return dict(STATE)

    def respond_json(self, status, value):
        body = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 5089), Handler)
    print("Trust UI race proxy listening on 127.0.0.1:5089; upstream is fixed to 127.0.0.1:5090")
    server.serve_forever()
