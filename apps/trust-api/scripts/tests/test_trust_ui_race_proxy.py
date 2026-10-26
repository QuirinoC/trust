"""Real-HTTP tests for the loopback-only Trust UI fault proxy controls."""

from __future__ import annotations

import contextlib
import hashlib
import http.server
import io
import json
import socket
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid
from collections import Counter
from pathlib import Path
from typing import Any
from unittest.mock import patch

import importlib.util
import sys


PROXY_SCRIPT = Path(__file__).resolve().parents[1] / "trust_ui_race_proxy.py"
PROXY_SPEC = importlib.util.spec_from_file_location("trust_ui_race_proxy_under_test", PROXY_SCRIPT)
assert PROXY_SPEC and PROXY_SPEC.loader
proxy = importlib.util.module_from_spec(PROXY_SPEC)
sys.modules[PROXY_SPEC.name] = proxy
PROXY_SPEC.loader.exec_module(proxy)


def encode_jwt_sub(account_id: str) -> str:
    import base64

    def segment(value: dict[str, str]) -> str:
        return base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).decode().rstrip("=")

    return f"{segment({'alg': 'none', 'typ': 'JWT'})}.{segment({'sub': account_id})}.sig"


class FakeAPIHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def _serve(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        self.server.calls.append((self.command, self.path, body))  # type: ignore[attr-defined]
        status, headers, payload = self.server.responder(self.command, self.path, self.headers, body)  # type: ignore[attr-defined]
        response = payload if isinstance(payload, bytes) else json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        if status != 204:
            self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        if status != 204 and response:
            self.wfile.write(response)

    do_GET = _serve
    do_POST = _serve
    do_PUT = _serve
    do_PATCH = _serve
    do_DELETE = _serve


class ProxyHTTPTests(unittest.TestCase):
    def setUp(self) -> None:
        self._original_upstream = proxy.UPSTREAM
        self._request_threads: list[threading.Thread] = []
        self._responses: list[tuple[int, bytes]] = []

        def responder(method: str, path: str, _headers, _body):
            normalized = path.split("?", 1)[0]
            if method == "GET" and normalized.endswith("/history"):
                return 200, {"Content-Type": "application/json"}, {
                    "points": [
                        {"latitude": 47.612345, "longitude": -122.398765},
                        {"latitude": 47.623456, "longitude": -122.387654},
                    ]
                }
            if method == "GET" and normalized == "/api/v1/circle":
                return 200, {"Content-Type": "application/json"}, {"circle": "upstream"}
            if method == "GET" and normalized == "/api/v1/connection-requests":
                return 200, {"Content-Type": "application/json"}, {"incoming": [], "sent": []}
            if method == "POST" and normalized == "/api/v1/people/lookup":
                return 200, {"Content-Type": "application/json"}, {"relationship": "connected", "requestId": "req-live"}
            if method == "POST" and normalized == "/api/v1/connection-requests":
                return 201, {"Content-Type": "application/json"}, {"id": "request-live"}
            if method == "POST" and normalized.startswith("/api/v1/connection-requests/"):
                return 204, {}, b""
            return 200, {"Content-Type": "application/json"}, {"ok": True, "method": method, "path": normalized}

        self.upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeAPIHandler)
        self.upstream.daemon_threads = True
        self.upstream.block_on_close = False
        self.upstream.calls = []  # type: ignore[attr-defined]
        self.upstream.responder = responder  # type: ignore[attr-defined]
        self.upstream_thread = threading.Thread(target=self.upstream.serve_forever, name="fake-trust-api", daemon=True)
        self.upstream_thread.start()

        proxy.UPSTREAM = f"http://127.0.0.1:{self.upstream.server_port}"
        self.front = http.server.ThreadingHTTPServer(("127.0.0.1", 0), proxy.Handler)
        self.front.daemon_threads = True
        self.front.block_on_close = False
        self.front_thread = threading.Thread(target=self.front.serve_forever, name="trust-ui-race-proxy-test", daemon=True)
        self.front_thread.start()
        self.base = f"http://127.0.0.1:{self.front.server_port}"
        self.control("/reset")

    def tearDown(self) -> None:
        try:
            self.control("/release")
        except Exception:
            pass
        proxy.RELEASE_HELD.set()
        for thread in self._request_threads:
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive(), "HTTP client request thread leaked")
        self.front.shutdown()
        self.front.server_close()
        self.front_thread.join(timeout=3)
        self.upstream.shutdown()
        self.upstream.server_close()
        self.upstream_thread.join(timeout=3)
        proxy.UPSTREAM = self._original_upstream
        self.assertFalse(self.front_thread.is_alive(), "proxy server thread leaked")
        self.assertFalse(self.upstream_thread.is_alive(), "fake API server thread leaked")

    def request(self, method: str, path: str, *, token: str | None = None,
                body: dict[str, Any] | None = None) -> tuple[int, bytes]:
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body, separators=(",", ":")).encode()
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=4) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.read()

    def control(self, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        status, payload = self.request("POST", "/__test" + path, body=body or {})
        self.assertEqual(status, 200, payload)
        return json.loads(payload)

    def state(self) -> dict[str, Any]:
        status, payload = self.request("GET", "/__test/state")
        self.assertEqual(status, 200)
        return json.loads(payload)

    def upstream_count(self, method: str, path: str) -> int:
        normalized = path.split("?", 1)[0]
        return sum(1 for call_method, call_path, _body in self.upstream.calls
                   if call_method == method and call_path.split("?", 1)[0] == normalized)  # type: ignore[attr-defined]

    def wait_for_state(self, predicate, timeout: float = 3) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        last = {}
        while time.monotonic() < deadline:
            last = self.state()
            if predicate(last):
                return last
            time.sleep(0.03)
        self.fail(f"Timed out waiting for proxy state: {last}")

    def test_push_ack_counts_require_success_and_never_expose_device_credentials(self) -> None:
        replies = iter([503, 204, 204])
        self.upstream.responder = lambda *_args: (next(replies), {}, b"")
        sandbox = {"environment": "sandbox", "token": "fictional-private-device-token", "installationId": str(uuid.uuid4())}
        self.assertEqual(self.request("POST", "/api/v1/push/devices", body=sandbox)[0], 503)
        self.assertEqual(self.state()["push_registration_ack_count"], 0)
        self.assertEqual(self.request("POST", "/api/v1/push/devices", body=sandbox)[0], 204)
        self.assertEqual(self.request("POST", "/api/v1/push/devices", body={**sandbox, "environment": "production"})[0], 204)
        state = self.state()
        self.assertEqual(state["push_registration_ack_count"], 2)
        self.assertEqual(state["sandbox_push_registration_ack_count"], 1)
        self.assertNotIn(sandbox["token"], json.dumps(state))
        self.assertNotIn(sandbox["installationId"], json.dumps(state))
        self.control("/reset")
        self.assertEqual(self.state()["sandbox_push_registration_ack_count"], 0)

    def test_offline_account_selector_blocks_only_target_then_reconnect_and_reset_clear_it(self) -> None:
        account_id = str(uuid.uuid4())
        target = encode_jwt_sub(account_id)
        peer = encode_jwt_sub(str(uuid.uuid4()))
        self.control("/arm-offline", {"accountId": account_id})

        self.assertEqual(self.request("GET", "/api/v1/circle", token=target)[0], 503)
        status, body = self.request("GET", "/api/v1/circle", token=peer)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"circle": "upstream"})
        state = self.state()
        self.assertEqual(state["offline_request_count"], 1)
        self.assertEqual(state["offline_circle_count"], 1)
        self.assertEqual(self.upstream_count("GET", "/api/v1/circle"), 1)

        reconnected = self.control("/reconnect")
        self.assertEqual(reconnected, {"reconnected": True, "offline_request_count": 1})
        self.assertEqual(self.request("GET", "/api/v1/circle", token=target)[0], 200)
        state = self.state()
        self.assertIsNone(state["offline_account_id"])
        self.assertIsNone(state["offline_token_hash"])
        self.assertEqual(state["offline_request_count"], 1)

        token = "opaque-local-session-token"
        digest = hashlib.sha256(token.encode()).hexdigest()
        self.control("/arm-offline", {"tokenHash": digest})
        self.assertEqual(self.request("GET", "/api/v1/circle", token="wrong-peer-token")[0], 200)
        self.assertEqual(self.request("GET", "/api/v1/circle", token=token)[0], 503)
        state = self.state()
        self.assertEqual(state["offline_request_count"], 1)
        self.assertEqual(state["offline_circle_count"], 1)

        self.control("/reset")
        state = self.state()
        self.assertFalse(state["offline_account_id"])
        self.assertFalse(state["offline_token_hash"])
        self.assertEqual(state["offline_request_count"], 0)
        self.assertEqual(self.request("GET", "/api/v1/circle", token=token)[0], 200)

    def test_lookup_and_connection_action_failures_are_one_shot_and_never_reach_upstream(self) -> None:
        self.control("/arm-lookup-failure")
        lookup = "/api/v1/people/lookup"
        self.assertEqual(self.request("POST", lookup, body={"handle": "peer"})[0], 503)
        self.assertEqual(self.upstream_count("POST", lookup), 0)
        self.assertEqual(self.request("POST", lookup, body={"handle": "peer"})[0], 200)
        self.assertEqual(self.upstream_count("POST", lookup), 1)

        self.control("/arm-request-action-failure")
        action = "/api/v1/connection-requests/request-1/accept"
        self.assertEqual(self.request("POST", action)[0], 503)
        self.assertEqual(self.upstream_count("POST", action), 0)
        self.assertEqual(self.request("POST", action)[0], 204)
        self.assertEqual(self.upstream_count("POST", action), 1)
        state = self.state()
        self.assertEqual(state["lookup_failure_count"], 1)
        self.assertEqual(state["connection_action_failure_count"], 1)

    def test_delete_cancel_has_one_shot_failure_and_committed_refresh_failure(self) -> None:
        action = "/api/v1/connection-requests/request-cancel"
        self.control("/arm-request-action-failure")
        self.assertEqual(self.request("DELETE", action)[0], 503)
        self.assertEqual(self.upstream_count("DELETE", action), 0)
        self.control("/arm-request-refresh-failure")
        self.assertEqual(self.request("DELETE", action)[0], 200)
        self.assertEqual(self.upstream_count("DELETE", action), 1)
        self.assertEqual(self.request("GET", "/api/v1/connection-requests")[0], 503)
        self.assertEqual(self.request("GET", "/api/v1/connection-requests")[0], 200)
        self.assertEqual(self.state()["request_list_failure_count"], 1)

    def test_send_can_arm_single_failed_lookup_then_stale_success_is_redacted(self) -> None:
        send = "/api/v1/connection-requests"
        lookup = "/api/v1/people/lookup"
        self.control("/arm-lookup-failure-after-send")
        self.assertEqual(self.request("POST", send, body={"recipientId": "peer"})[0], 201)
        state = self.state()
        self.assertEqual(state["connection_send_count"], 1)
        self.assertTrue(state["fail_next_lookup"])
        self.assertEqual(self.request("POST", lookup, body={"handle": "peer"})[0], 503)
        self.assertEqual(self.request("POST", lookup, body={"handle": "peer"})[0], 200)
        state = self.state()
        self.assertEqual(state["lookup_failure_count"], 1)
        self.assertEqual(self.upstream_count("POST", lookup), 1)

        self.control("/arm-stale-lookup-after-send")
        self.assertEqual(self.request("POST", send, body={"recipientId": "peer"})[0], 201)
        status, payload = self.request("POST", lookup, body={"handle": "peer"})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(payload), {"relationship": "none", "requestId": None})
        self.assertEqual(self.upstream_count("POST", lookup), 2)
        state = self.state()
        self.assertEqual(state["connection_send_count"], 2)
        self.assertFalse(state["stale_lookup_after_send"])
        self.assertFalse(state["stale_next_lookup"])

    def test_successful_action_can_fail_the_following_request_list_once(self) -> None:
        self.control("/arm-request-refresh-failure")
        action = "/api/v1/connection-requests/request-2/accept"
        request_list = "/api/v1/connection-requests"
        self.assertEqual(self.request("POST", action)[0], 204)
        self.assertEqual(self.request("GET", request_list)[0], 503)
        self.assertEqual(self.upstream_count("GET", request_list), 0)
        self.assertEqual(self.request("GET", request_list)[0], 200)
        self.assertEqual(self.upstream_count("GET", request_list), 1)
        state = self.state()
        self.assertEqual(state["request_list_failure_count"], 1)
        self.assertFalse(state["fail_requests_after_action"])

    def test_held_history_reports_only_status_and_point_count_then_releases_original_body(self) -> None:
        coordinates = ("47.612345", "-122.398765", "47.623456", "-122.387654")
        self.control("/arm-history")
        captured = io.StringIO()
        result: list[tuple[int, bytes]] = []
        error: list[BaseException] = []

        def request_history() -> None:
            try:
                result.append(self.request("GET", "/api/v1/people/person-private/history", token="opaque-token"))
            except BaseException as caught:
                error.append(caught)

        with contextlib.redirect_stderr(captured):
            thread = threading.Thread(target=request_history, name="held-history-client", daemon=True)
            self._request_threads.append(thread)
            thread.start()
            state = self.wait_for_state(lambda current: current.get("holding") is True)
            self.assertEqual(state["held_resource"], "history")
            self.assertEqual(state["history_hold_count"], 1)
            self.assertEqual(state["history_status_count"], 200)
            self.assertEqual(state["history_point_count"], 2)
            self.assertFalse(any(coordinate in json.dumps(state) for coordinate in coordinates))
            self.assertEqual(self.upstream_count("GET", "/api/v1/people/person-private/history"), 1)
            self.assertEqual(self.control("/release"), {"released": True})
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive(), "held history response was not released")

        self.assertFalse(error, repr(error))
        self.assertEqual(len(result), 1)
        status, payload = result[0]
        self.assertEqual(status, 200)
        decoded = json.loads(payload)
        self.assertEqual(len(decoded["points"]), 2)
        self.assertEqual(captured.getvalue(), "")
        self.assertFalse(any(coordinate in captured.getvalue() for coordinate in coordinates))
        state = self.state()
        self.assertEqual(state["history_release_count"], 1)
        self.assertFalse(state["holding"])
        self.assertIsNone(state["held_resource"])


if __name__ == "__main__":
    unittest.main()
