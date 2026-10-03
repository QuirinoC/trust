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
    "fail_next_stop_all": False,
    "holding": False,
    "held_resource": None,
    "share_ack_count": 0,
    "share_ack_person_ids": [],
    "stop_all_ack_count": 0,
    "stop_all_failure_count": 0,
    "revoke_ack_count": 0,
    "stale_release_count": 0,
    "circle_failure_count": 0,
    "history_hold_count": 0,
    "history_release_count": 0,
    "look_hold_count": 0,
    "look_release_count": 0,
    "request_counts": {},
    "app_transaction_test_enabled": False,
    "fail_next_app_transaction": False,
    "app_transaction_request_count": 0,
    "app_transaction_failure_count": 0,
    "app_transaction_success_count": 0,
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
                    if key.endswith("_person_ids"):
                        STATE[key] = []
                    elif key.endswith("_count"):
                        STATE[key] = 0
                    elif isinstance(STATE[key], dict):
                        STATE[key] = {}
                    else:
                        STATE[key] = False
                STATE["holding"] = False
                STATE["held_resource"] = None
                RELEASE_HELD.set()
            self.respond_json(200, {"reset": True})
            return
        if self.path in ("/__test/arm-app-transaction", "/__test/arm-app-transaction-retry"):
            with LOCK:
                STATE.update({
                    "app_transaction_test_enabled": True,
                    "fail_next_app_transaction": self.path.endswith("-retry"),
                    "app_transaction_request_count": 0,
                    "app_transaction_failure_count": 0,
                    "app_transaction_success_count": 0,
                })
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/arm":
            with LOCK:
                STATE.update({
                    "hold_next_circle": True,
                    "hold_next_history": False,
                    "hold_next_look": False,
                    "fail_circle_after_release": True,
                    "fail_next_circle": False,
                    "fail_next_stop_all": False,
                    "holding": False,
                    "held_resource": None,
                    "share_ack_count": 0,
                    "share_ack_person_ids": [],
                    "stop_all_ack_count": 0,
                    "stop_all_failure_count": 0,
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
                    "fail_next_stop_all": True,
                    "holding": False,
                    "held_resource": None,
                    "share_ack_count": 0,
                    "share_ack_person_ids": [],
                    "stop_all_ack_count": 0,
                    "stop_all_failure_count": 0,
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
        is_stop_all = self.command == "POST" and path.split("?", 1)[0] == "/api/v1/me/sharing/stop-all"
        is_app_transaction = self.command == "PUT" and path.split("?", 1)[0] == "/api/v1/age-assurance/app-transaction"
        person_id = path.split("/api/v1/people/", 1)[1].split("/", 1)[0] if "/api/v1/people/" in path else None
        normalized_path = path.split("?", 1)[0]
        observed_paths = {
            "/api/v1/circle",
            "/api/v1/location",
            "/api/v1/push/devices",
            "/api/v1/me/home",
            "/api/v1/me/home/presence",
            "/api/v1/storekit/account-token",
            "/api/v1/circle/entitlement",
            "/api/v1/age-assurance/privacy-hold",
            "/api/v1/session/apple",
            "/api/v1/session/development",
            "/api/v1/age-assurance/app-transaction",
        }
        local_transaction_fixture = (
            is_app_transaction
            and self.headers.get("X-Trust-Local-Test-App-Transaction") == "1"
        )
        if normalized_path in observed_paths and not local_transaction_fixture:
            key = f"{self.command} {normalized_path}"
            with LOCK:
                STATE["request_counts"][key] = STATE["request_counts"].get(key, 0) + 1

        if local_transaction_fixture:
            with LOCK:
                STATE["app_transaction_request_count"] += 1
                key = f"{self.command} {normalized_path}"
                STATE["request_counts"][key] = STATE["request_counts"].get(key, 0) + 1
                fixture_enabled = STATE["app_transaction_test_enabled"]
                fail_this_app_transaction = fixture_enabled and STATE["fail_next_app_transaction"]
                if fail_this_app_transaction:
                    STATE["fail_next_app_transaction"] = False
                    STATE["app_transaction_failure_count"] += 1
                elif fixture_enabled:
                    STATE["app_transaction_success_count"] += 1
            if not fixture_enabled:
                self.respond_json(409, {"error": "local-app-transaction-test-not-armed"})
            elif fail_this_app_transaction:
                self.respond_json(503, {"error": "deterministic-local-app-transaction-failure"})
            else:
                self.send_response(204)
                self.end_headers()
            return

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
            fail_this_stop_all = is_stop_all and STATE["fail_next_stop_all"]
            if fail_this_stop_all:
                STATE["fail_next_stop_all"] = False
                STATE["stop_all_failure_count"] += 1

        if fail_this_stop_all:
            self.respond_json(503, {"error": "deterministic-test-stop-all-failure"})
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
                if is_stop_all:
                    STATE["stop_all_ack_count"] += 1
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
