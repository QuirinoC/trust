#!/usr/bin/env python3
"""Drive controlled Home/Away location changes for the paired UI-test lane.

This only accepts the loopback Development API, uses the paired test's
disposable Bob identity, and moves the named Core Simulator. It never contacts
production services or prints the development bearer token.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request


BASE_URL = "http://127.0.0.1:5089"
INITIAL = (47.600000, -122.330000)
FIRST_AWAY = (47.610000, -122.330000)
SECOND_AWAY = (47.620000, -122.330000)


def request_json(method: str, path: str, token: str | None = None, body: dict | None = None) -> dict:
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=8) as response:
        result = json.load(response)
    if not isinstance(result, dict):
        raise RuntimeError(f"Unexpected JSON response from {path}.")
    return result


def start_route(device_udid: str, start: tuple[float, float], end: tuple[float, float]) -> None:
    developer_dir = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    environment = dict(os.environ, DEVELOPER_DIR=developer_dir)
    command = [
        "/usr/bin/xcrun", "simctl", "location", device_udid, "start",
        "--speed=200", "--interval=1",
        f"{start[0]:.6f},{start[1]:.6f}",
        f"{end[0]:.6f},{end[1]:.6f}",
    ]
    subprocess.run(command, check=True, timeout=30, capture_output=True, text=True, env=environment)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pair-id", required=True, help="The same eight-hex test pair ID used by both XCTest runners.")
    parser.add_argument("--device-udid", required=True, help="Bob's booted iPhone Duo simulator UDID.")
    parser.add_argument("--timeout", type=int, default=480, help="Maximum wait for the two Home/Away cycles (seconds).")
    args = parser.parse_args()

    if not re.fullmatch(r"[a-fA-F0-9]{8}", args.pair_id):
        parser.error("--pair-id must be exactly eight hexadecimal characters.")
    if not re.fullmatch(r"[A-Fa-f0-9-]{20,40}", args.device_udid):
        parser.error("--device-udid must be a simulator UDID.")
    if args.timeout < 60 or args.timeout > 1800:
        parser.error("--timeout must be between 60 and 1800 seconds.")

    capabilities = request_json("GET", "/api/v1/local-test-capabilities")
    if capabilities.get("developmentOtpWithoutSms") is not True:
        raise RuntimeError("The loopback API did not confirm Development OTP without SMS; refusing to continue.")

    device_id = f"trust-pair-{args.pair_id.lower()}-bob"
    session = request_json("POST", "/api/v1/session/development", body={
        "displayName": "PairBob",
        "deviceId": device_id,
    })
    token = session.get("token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Could not create/reuse Bob's disposable Development session.")

    print("Waiting for Bob's first Home state.", flush=True)
    phase = 0
    place_id: str | None = None
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        circle = request_json("GET", "/api/v1/circle", token=token)
        home = circle.get("yourHome") or {}
        place = home.get("place") or {}
        state = home.get("state")
        current_place_id = place.get("placeId")

        if phase == 0 and state == "home" and current_place_id:
            place_id = current_place_id
            start_route(args.device_udid, INITIAL, FIRST_AWAY)
            print("First Home acknowledged; simulating departure.", flush=True)
            phase = 1
        elif phase == 1 and state == "away" and current_place_id == place_id:
            print("First Away acknowledged; waiting for Home update.", flush=True)
            phase = 2
        elif phase == 2 and state == "home" and current_place_id == place_id:
            start_route(args.device_udid, FIRST_AWAY, SECOND_AWAY)
            print("Updated Home acknowledged; simulating second departure.", flush=True)
            phase = 3
        elif phase == 3 and state == "away" and current_place_id == place_id:
            print("Second Away acknowledged; route controller complete.", flush=True)
            return 0

        time.sleep(2)

    raise TimeoutError("Timed out before both Home/Away transitions completed.")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, TimeoutError, urllib.error.URLError, subprocess.SubprocessError) as error:
        print(f"Route controller stopped safely: {error}", file=sys.stderr)
        sys.exit(1)
