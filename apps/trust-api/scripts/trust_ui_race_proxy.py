#!/usr/bin/env python3
"""Loopback-only fault proxy for Trust's real-API UI race regression.

Run the Development + Memory API on 127.0.0.1:5090, then run this proxy. XCTest
and the app use the proxy on 127.0.0.1:5089. It has no remote-host option and
never logs request bodies, authorization headers, phone numbers, or coordinates.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64
import copy
import hashlib
import json
import re
import threading
import urllib.error
import urllib.request
import uuid


UPSTREAM = "http://127.0.0.1:5090"
LOCK = threading.Lock()
STATE = {
    "hold_next_phone_send": False,
    "hold_next_phone_verify": False,
    "hold_next_circle": False,
    "hold_next_history": False,
    "hold_next_look": False,
    "hold_next_share": False,
    "share_failure_after_release": False,
    "hold_next_home_presence": False,
    "home_presence_responses": {},
    "fail_circle_after_release": False,
    "fail_next_circle": False,
    "fail_next_consent_revoked": False,
    "consent_revoked_count": 0,
    "fail_next_stop_all": False,
    "holding": False,
    "held_resource": None,
    "share_ack_count": 0,
    "share_ack_person_ids": [],
    "share_hold_count": 0,
    "share_release_count": 0,
    "share_failure_count": 0,
    "stop_all_ack_count": 0,
    "stop_all_failure_count": 0,
    "revoke_ack_count": 0,
    "push_registration_ack_count": 0,
    "sandbox_push_registration_ack_count": 0,
    "stale_release_count": 0,
    "circle_failure_count": 0,
    "history_hold_count": 0,
    "history_release_count": 0,
    "history_status_count": 0,
    "history_point_count": 0,
    "look_hold_count": 0,
    "look_release_count": 0,
    "request_counts": {},
    "app_transaction_test_enabled": False,
    "fail_next_app_transaction": False,
    "app_transaction_request_count": 0,
    "app_transaction_failure_count": 0,
    "app_transaction_success_count": 0,
    "offline_account_id": None,
    "offline_token_hash": None,
    "offline_request_count": 0,
    "offline_circle_count": 0,
    "fail_next_lookup": False,
    "fail_lookup_after_send": False,
    "fail_next_connection_action": False,
    "lookup_failure_count": 0,
    "connection_action_failure_count": 0,
    "connection_send_count": 0,
    "fail_requests_after_action": False,
    "fail_next_requests": False,
    "request_list_failure_count": 0,
    "stale_lookup_after_send": False,
    "stale_next_lookup": False,
    "pair_location_stages": {},
}
PAIR_LOCATION_STAGES = {
    "first-home-ready",
    "first-away-held",
    "second-home-ready",
    "complete",
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
        control_body = b""
        if self.path.startswith("/__test/"):
            # XCTest's URLSession may send `{}` for control requests. Consume it
            # before responding so a keep-alive connection starts cleanly.
            length = int(self.headers.get("Content-Length", "0"))
            if length:
                control_body = self.rfile.read(length)
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
        if self.path == "/__test/pair-location":
            try:
                value = json.loads(control_body)
            except (json.JSONDecodeError, UnicodeDecodeError):
                self.respond_json(400, {"updated": False, "error": "invalid-json"})
                return
            if not isinstance(value, dict) or set(value) != {"pairId", "stage"}:
                self.respond_json(400, {"updated": False, "error": "invalid-control-body"})
                return
            pair_id = value.get("pairId")
            stage = value.get("stage")
            if not isinstance(pair_id, str) or not re.fullmatch(r"[a-fA-F0-9]{8}", pair_id):
                self.respond_json(400, {"updated": False, "error": "invalid-pair-id"})
                return
            if not isinstance(stage, str) or stage not in PAIR_LOCATION_STAGES:
                self.respond_json(400, {"updated": False, "error": "invalid-stage"})
                return
            pair_id = pair_id.lower()
            with LOCK:
                stages = STATE["pair_location_stages"].setdefault(pair_id, {})
                stages[stage] = True
            self.respond_json(200, {"updated": True, "pairId": pair_id, "stage": stage})
            return
        if self.path in ("/__test/arm-lookup-failure", "/__test/arm-lookup-failure-after-send", "/__test/arm-request-action-failure", "/__test/arm-stale-lookup"):
            with LOCK:
                key = {
                    "/__test/arm-lookup-failure": "fail_next_lookup",
                    "/__test/arm-lookup-failure-after-send": "fail_lookup_after_send",
                    "/__test/arm-request-action-failure": "fail_next_connection_action",
                    "/__test/arm-stale-lookup": "stale_next_lookup",
                }[self.path]
                STATE[key] = True
            self.respond_json(200, {"armed": True})
            return
        if self.path in ("/__test/arm-request-refresh-failure", "/__test/arm-stale-lookup-after-send"):
            with LOCK:
                STATE["fail_requests_after_action" if self.path.endswith("refresh-failure") else "stale_lookup_after_send"] = True
            self.respond_json(200, {"armed": True})
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
        if self.path == "/__test/arm-consent-revoked":
            with LOCK:
                STATE["fail_next_consent_revoked"] = True
                STATE["consent_revoked_count"] = 0
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/arm-offline":
            try:
                value = json.loads(control_body or b"{}")
            except (json.JSONDecodeError, UnicodeDecodeError):
                self.respond_json(400, {"armed": False, "error": "invalid-json"})
                return
            account_id = value.get("accountId") if isinstance(value, dict) else None
            token_hash = value.get("tokenHash") if isinstance(value, dict) else None
            if account_id is not None:
                try:
                    account_id = str(uuid.UUID(str(account_id)))
                except (ValueError, AttributeError, TypeError):
                    self.respond_json(400, {"armed": False, "error": "invalid-account-id"})
                    return
            if token_hash is not None and (not isinstance(token_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", token_hash)):
                self.respond_json(400, {"armed": False, "error": "invalid-token-hash"})
                return
            if (account_id is None) == (token_hash is None):
                self.respond_json(400, {"armed": False, "error": "provide-one-account-id-or-token-hash"})
                return
            with LOCK:
                STATE["offline_account_id"] = account_id
                STATE["offline_token_hash"] = token_hash.lower() if token_hash else None
                STATE["offline_request_count"] = 0
                STATE["offline_circle_count"] = 0
            self.respond_json(200, {"armed": True, "offline_request_count": 0})
            return
        if self.path == "/__test/reconnect":
            with LOCK:
                STATE["offline_account_id"] = None
                STATE["offline_token_hash"] = None
                offline_request_count = STATE["offline_request_count"]
            self.respond_json(200, {"reconnected": True, "offline_request_count": offline_request_count})
            return
        if self.path == "/__test/arm":
            with LOCK:
                STATE.update({
                    "hold_next_circle": True,
                    "hold_next_history": False,
                    "hold_next_look": False,
                    "hold_next_share": False,
                    "share_failure_after_release": False,
                    "fail_circle_after_release": True,
                    "fail_next_circle": False,
                    "fail_next_stop_all": False,
                    "holding": False,
                    "held_resource": None,
                    "share_ack_count": 0,
                    "share_ack_person_ids": [],
                    "share_hold_count": 0,
                    "share_release_count": 0,
                    "share_failure_count": 0,
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
        if self.path in ("/__test/arm-share", "/__test/arm-share-failure"):
            with LOCK:
                STATE.update({
                    "hold_next_share": True,
                    "share_failure_after_release": self.path.endswith("-failure"),
                    "holding": False,
                    "held_resource": None,
                    "share_ack_count": 0,
                    "share_ack_person_ids": [],
                    "share_hold_count": 0,
                    "share_release_count": 0,
                    "share_failure_count": 0,
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
        if self.path in ("/__test/arm-phone-send", "/__test/arm-phone-verify"):
            with LOCK:
                STATE["hold_next_phone_send" if self.path.endswith("send") else "hold_next_phone_verify"] = True
                RELEASE_HELD.clear()
            self.respond_json(200, {"armed": True})
            return
        if self.path == "/__test/arm-home-presence":
            with LOCK:
                STATE["hold_next_home_presence"] = True
                RELEASE_HELD.clear()
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
                if released_resource == "share":
                    STATE["share_failure_after_release"] = False
                if released_resource != "share":
                    STATE["stale_release_count"] += 1
                if released_resource == "history":
                    STATE["history_release_count"] = STATE.get("history_release_count", 0) + 1
                elif released_resource == "look":
                    STATE["look_release_count"] += 1
                elif released_resource == "share":
                    STATE["share_release_count"] += 1
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
        if self.offline_request_matches():
            with LOCK:
                STATE["offline_request_count"] += 1
                if self.command == "GET" and path.split("?", 1)[0] == "/api/v1/circle":
                    STATE["offline_circle_count"] += 1
            self.respond_json(503, {"code": "test_account_offline", "message": "The account is offline in this local test."})
            return
        normalized_path = path.split("?", 1)[0]
        is_lookup = self.command == "POST" and normalized_path == "/api/v1/people/lookup"
        is_connection_send = self.command == "POST" and normalized_path == "/api/v1/connection-requests"
        is_connection_action = self.command in ("POST", "DELETE") and normalized_path.startswith("/api/v1/connection-requests/")
        is_request_list = self.command == "GET" and normalized_path == "/api/v1/connection-requests"
        with LOCK:
            fail_lookup = is_lookup and STATE["fail_next_lookup"]
            fail_action = is_connection_action and STATE["fail_next_connection_action"]
            fail_requests = is_request_list and STATE["fail_next_requests"]
            stale_lookup = is_lookup and STATE["stale_next_lookup"]
            if fail_lookup:
                STATE["fail_next_lookup"] = False
                STATE["lookup_failure_count"] += 1
            if fail_action:
                STATE["fail_next_connection_action"] = False
                STATE["connection_action_failure_count"] += 1
            if fail_requests:
                STATE["fail_next_requests"] = False
                STATE["request_list_failure_count"] += 1
            if stale_lookup:
                STATE["stale_next_lookup"] = False
        if fail_lookup or fail_action or fail_requests:
            self.respond_json(503, {"code": "test_temporary_failure", "message": "A temporary failure was injected by the local test service."})
            return
        is_phone_send = self.command == "POST" and path.split("?", 1)[0] == "/api/v1/me/phone/send"
        is_phone_verify = self.command == "POST" and path.split("?", 1)[0] == "/api/v1/me/phone/verify"
        is_circle = self.command == "GET" and path.split("?", 1)[0] == "/api/v1/circle"
        is_home_presence = self.command == "POST" and path.split("?", 1)[0] == "/api/v1/me/home/presence"
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

        authorization = self.headers.get("Authorization", "")
        is_authenticated_circle = is_circle and bool(re.fullmatch(r"Bearer\s+\S+", authorization, re.IGNORECASE))
        with LOCK:
            consent_revoked = is_authenticated_circle and STATE["fail_next_consent_revoked"]
            if consent_revoked:
                STATE["fail_next_consent_revoked"] = False
                STATE["consent_revoked_count"] += 1
        if consent_revoked:
            self.respond_json(409, {"code": "consent_revoked", "message": "Consent has been revoked."})
            return

        with LOCK:
            hold_this_phone_send = is_phone_send and STATE["hold_next_phone_send"]
            hold_this_phone_verify = is_phone_verify and STATE["hold_next_phone_verify"]
            if hold_this_phone_send: STATE["hold_next_phone_send"] = False
            if hold_this_phone_verify: STATE["hold_next_phone_verify"] = False
            hold_this_home_presence = is_home_presence and STATE["hold_next_home_presence"]
            if hold_this_home_presence:
                STATE["hold_next_home_presence"] = False
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
            hold_this_share = is_share and STATE["hold_next_share"]
            fail_share_after_release = hold_this_share and STATE["share_failure_after_release"]
            if hold_this_share:
                STATE["hold_next_share"] = False
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

        if fail_share_after_release:
            with LOCK:
                STATE["holding"] = True
                STATE["held_resource"] = "share"
                STATE["share_hold_count"] += 1
                share_release_count_at_hold = STATE["share_release_count"]
            if not RELEASE_HELD.wait(timeout=60):
                with LOCK:
                    STATE["holding"] = False
                    STATE["held_resource"] = None
                self.respond_json(504, {"error": "test-did-not-release-held-share-failure"})
                return
            with LOCK:
                was_explicitly_released = STATE["share_release_count"] > share_release_count_at_hold
                if was_explicitly_released:
                    STATE["share_failure_count"] += 1
            # The failure outcome is captured with this request before waiting. A proxy reset
            # may also wake the event, but it must never turn this armed failure into an upstream write.
            self.respond_json(503, {"error": "deterministic-test-share-write-failure"})
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

        if self.command == "POST" and normalized_path == "/api/v1/push/devices" and status == 204:
            # Record only acknowledgement counts. Device tokens and installation
            # identifiers must never be exposed by the test control endpoint.
            try:
                sandbox = json.loads(body or b"{}").get("environment") == "sandbox"
            except (ValueError, AttributeError):
                sandbox = False
            with LOCK:
                STATE["push_registration_ack_count"] += 1
                if sandbox:
                    STATE["sandbox_push_registration_ack_count"] += 1
        if is_home_presence:
            with LOCK:
                key = str(status)
                STATE["home_presence_responses"][key] = STATE["home_presence_responses"].get(key, 0) + 1
        if stale_lookup and 200 <= status < 300:
            payload = json.loads(response_body)
            payload["relationship"] = "none"
            payload["requestId"] = None
            response_body = json.dumps(payload, separators=(",", ":")).encode()
        held_resource = "phone_send" if hold_this_phone_send else "phone_verify" if hold_this_phone_verify else "circle" if hold_this_circle else "history" if hold_this_history else "look" if hold_this_look else "home_presence" if hold_this_home_presence else "share" if hold_this_share else None
        if held_resource:
            with LOCK:
                STATE["holding"] = True
                STATE["held_resource"] = held_resource
                if held_resource == "history":
                    STATE["history_hold_count"] += 1
                    STATE["history_status_count"] = status
                    try:
                        STATE["history_point_count"] = len(json.loads(response_body).get("points", []))
                    except (ValueError, TypeError, AttributeError):
                        STATE["history_point_count"] = 0
                elif held_resource == "look":
                    STATE["look_hold_count"] += 1
                elif held_resource == "share":
                    STATE["share_hold_count"] += 1
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
                if is_connection_send:
                    STATE["connection_send_count"] += 1
                    if STATE["fail_lookup_after_send"]:
                        STATE["fail_lookup_after_send"] = False
                        STATE["fail_next_lookup"] = True
                    if STATE["stale_lookup_after_send"]:
                        STATE["stale_lookup_after_send"] = False
                        STATE["stale_next_lookup"] = True
                if is_connection_action and STATE["fail_requests_after_action"]:
                    STATE["fail_requests_after_action"] = False
                    STATE["fail_next_requests"] = True
                if is_share:
                    STATE["share_ack_count"] += 1
                    STATE["share_ack_person_ids"].append(person_id)
                if is_stop_all:
                    STATE["stop_all_ack_count"] += 1
                if self.command == "POST" and path.split("?", 1)[0].startswith("/api/v1/people/") and path.endswith("/revoke"):
                    STATE["revoke_ack_count"] += 1

        if status == 204 or not response_body:
            self.send_response(status)
            if status != 204:
                self.send_header("Content-Length", "0")
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
            return copy.deepcopy(STATE)

    def offline_request_matches(self):
        authorization = self.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            return False
        token = authorization[7:]
        with LOCK:
            account_id = STATE["offline_account_id"]
            token_hash = STATE["offline_token_hash"]
        if account_id:
            try:
                parts = token.split(".")
                if len(parts) != 3:
                    return False
                payload = parts[1] + "=" * (-len(parts[1]) % 4)
                claims = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")))
                return str(claims.get("sub", "")).lower() == account_id.lower()
            except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
                return False
        if token_hash:
            return hashlib.sha256(token.encode()).hexdigest() == token_hash
        return False

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
