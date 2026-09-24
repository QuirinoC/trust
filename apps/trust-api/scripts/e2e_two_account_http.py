#!/usr/bin/env python3
"""Trust 1.0 two-account HTTP e2e against local API (no simulators).

Usage:
  python3 apps/trust-api/scripts/e2e_two_account_http.py

Env:
  TRUST_API_BASE   default http://127.0.0.1:5088
  TRUST_PG_*       for pause restore + presence delete checks via docker exec
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

BASE = os.environ.get("TRUST_API_BASE", "http://127.0.0.1:5088").rstrip("/")
PG_CONTAINER = os.environ.get("TRUST_PG_CONTAINER", "trust-api-postgres-1")

PASS = 0
FAIL = 0
RESULTS: list[tuple[str, str, str]] = []


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def req(
    method: str,
    path: str,
    token: str | None = None,
    body: Any = None,
    expect: int | None = None,
) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as resp:
            raw = resp.read().decode()
            parsed = json.loads(raw) if raw else None
            status = resp.status
    except urllib.error.HTTPError as err:
        raw = err.read().decode()
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = raw
        status = err.code
    if expect is not None and status != expect:
        raise AssertionError(f"{method} {path} expected {expect}, got {status}: {parsed}")
    return status, parsed


def check(item: str, assertion: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    status = "PASS" if ok else "FAIL"
    if ok:
        PASS += 1
    else:
        FAIL += 1
    note = f" — {detail}" if detail else ""
    RESULTS.append((item, status, f"{assertion}{note}"))
    print(f"[{status}] {item}: {assertion}{note}")


def psql(sql: str) -> str:
    cmd = [
        "docker",
        "exec",
        "-i",
        PG_CONTAINER,
        "psql",
        "-U",
        "trust",
        "-d",
        "trust",
        "-At",
        "-c",
        sql,
    ]
    return subprocess.check_output(cmd, text=True).strip()


def session(name: str, device: str) -> dict[str, Any]:
    _, body = req(
        "POST",
        "/api/v1/session/development",
        body={"displayName": name, "deviceId": device},
        expect=200,
    )
    assert body and body.get("token") and body.get("you", {}).get("id")
    return body


def circle(token: str) -> dict[str, Any]:
    _, body = req("GET", "/api/v1/circle", token=token, expect=200)
    assert isinstance(body, dict)
    return body


def member(circ: dict[str, Any], person_id: str) -> dict[str, Any]:
    for row in circ["members"]:
        if row["person"]["id"] == person_id:
            return row
    raise AssertionError(f"person {person_id} not in circle members")


def grant_plus(token: str) -> None:
    req(
        "POST",
        "/api/v1/circle/entitlement",
        token=token,
        body={"reviewUnlock": True, "productId": None, "signedTransactionInfo": None},
        expect=204,
    )


def main() -> int:
    suffix = uuid.uuid4().hex[:10]
    print(f"BASE={BASE} suffix={suffix}")

    sam = session("E2E-Sam", f"e2e-sam-{suffix}")
    jordan = session("E2E-Jordan", f"e2e-jordan-{suffix}")
    sam_id = sam["you"]["id"]
    jordan_id = jordan["you"]["id"]
    sam_tok = sam["token"]
    jordan_tok = jordan["token"]

    _, invite = req("POST", "/api/v1/invites", token=sam_tok, expect=200)
    code = invite["code"]
    req("POST", "/api/v1/invites/accept", token=jordan_tok, body={"code": code}, expect=204)

    j_circ = circle(jordan_tok)
    check(
        "setup",
        "pair exists after invite/accept",
        any(m["person"]["id"] == sam_id for m in j_circ["members"]),
        f"members={len(j_circ['members'])}",
    )
    check(
        "setup",
        "local API allows review unlock (Plus test path)",
        j_circ.get("allowsReviewUnlock") is True,
        str(j_circ.get("allowsReviewUnlock")),
    )

    # --- 1 Sealed ---
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    lat1, lon1 = 37.750, -122.410
    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(utcnow()),
            "latitude": lat1,
            "longitude": lon1,
            "batteryPercent": 80,
            "isCharging": False,
            "points": None,
        },
        expect=204,
    )

    free_circ = circle(jordan_tok)
    free_sam = member(free_circ, sam_id)
    check(
        "1 Sealed",
        "free viewer has no live pin / no live coordinates on circle",
        free_sam["inboundLive"] is False and free_sam.get("live") is None,
        f"inboundLive={free_sam['inboundLive']} live={free_sam.get('live')}",
    )

    # Prove free Always path: grant Plus on sharer only, set Always, free viewer still no coords
    grant_plus(sam_tok)
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "always", "pause": None, "timed": None},
        expect=204,
    )
    always_free = member(circle(jordan_tok), sam_id)
    check(
        "1 Sealed/Always free",
        "Always with free viewer: inboundLive true but live coords null until viewer Plus",
        always_free["inboundLive"] is True and always_free.get("live") is None,
        f"inboundLive={always_free['inboundLive']} live={always_free.get('live')} jordanPlus={circle(jordan_tok)['you']['hasCircle']}",
    )

    # Back to Sealed for Look
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    status, look = req(
        "POST",
        "/api/v1/looks",
        token=jordan_tok,
        body={"subjectId": sam_id, "confirmed": True},
        expect=200,
    )
    look_ok = (
        look
        and look.get("event", {}).get("kind") == "look"
        and look.get("live") is not None
        and abs(look["live"]["latitude"] - lat1) < 0.001
    )
    check(
        "1 Sealed",
        "Look returns snapshot to viewer (coords + look kind)",
        bool(look_ok),
        f"kind={look and look.get('event', {}).get('kind')} live={look and look.get('live')}",
    )
    after_look = member(circle(jordan_tok), sam_id)
    check(
        "1 Sealed",
        "after Look, circle still sealed (no persistent live pin)",
        after_look["inboundLive"] is False and after_look.get("live") is None,
        f"inboundLive={after_look['inboundLive']}",
    )
    j_log = circle(jordan_tok)["lookLog"]
    check(
        "1 Sealed",
        "Look appears in viewer look log",
        any(e["kind"] == "look" and e["subjectId"] == sam_id for e in j_log),
    )
    jordan_after_look = circle(jordan_tok)
    sam_after_look = circle(sam_tok)
    check(
        "1 Sealed",
        "Look is one snapshot: activeSession and beingWatched stay null on the wire",
        jordan_after_look.get("activeSession") is None
        and jordan_after_look.get("beingWatched") is None
        and sam_after_look.get("activeSession") is None
        and sam_after_look.get("beingWatched") is None,
        f"jordan active={jordan_after_look.get('activeSession')} watched={jordan_after_look.get('beingWatched')} "
        f"sam active={sam_after_look.get('activeSession')} watched={sam_after_look.get('beingWatched')}",
    )

    # --- 2 Always ---
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "always", "pause": None, "timed": None},
        expect=204,
    )
    lat2, lon2 = 37.770, -122.420
    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(utcnow()),
            "latitude": lat2,
            "longitude": lon2,
            "batteryPercent": 90,
            "isCharging": False,
            "points": None,
        },
        expect=204,
    )
    grant_plus(jordan_tok)
    plus_always = member(circle(jordan_tok), sam_id)
    check(
        "2 Always",
        "Plus viewer sees live pin/coords on Always",
        plus_always["inboundLive"] is True
        and plus_always.get("live") is not None
        and abs(plus_always["live"]["latitude"] - lat2) < 0.001,
        f"live={plus_always.get('live')}",
    )

    _, view = req(
        "POST",
        "/api/v1/views",
        token=jordan_tok,
        body={"subjectId": sam_id},
        expect=200,
    )
    check(
        "2 Always",
        "View works and logs a view event",
        bool(view and view.get("logged") is True and view.get("event", {}).get("kind") == "view"),
        str(view),
    )
    sam_log = circle(sam_tok)["lookLog"]
    check(
        "2 Always",
        "subject look log contains view from Jordan",
        any(e["kind"] == "view" and e["viewerId"] == jordan_id for e in sam_log),
    )

    # Look during Always is designed to fail (use View). Re-prove Sealed Look still works.
    look_always_status, look_always = req(
        "POST",
        "/api/v1/looks",
        token=jordan_tok,
        body={"subjectId": sam_id, "confirmed": True},
    )
    check(
        "2 Always",
        "Look during Always rejected (View is the Always path); sealed Look already proven",
        look_always_status in (400, 409)
        and isinstance(look_always, dict)
        and look_always.get("code") == "look_requires_sealed",
        f"status={look_always_status} body={look_always}",
    )

    # Peek path still succeeds after returning to Sealed (receipt path without push token)
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(utcnow()),
            "latitude": 37.751,
            "longitude": -122.411,
            "batteryPercent": 80,
            "isCharging": False,
            "points": None,
        },
        expect=204,
    )
    peek_status, peek = req(
        "POST",
        "/api/v1/looks",
        token=jordan_tok,
        body={"subjectId": sam_id, "confirmed": True},
        expect=200,
    )
    check(
        "2 Always",
        "Look peek+receipt still succeeds on Sealed without device token (push may no-op)",
        peek_status == 200 and peek.get("event", {}).get("kind") == "look",
        f"event={peek.get('event') if peek else None}",
    )

    # --- 3 Timed Pause 1h ---
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": None, "pause": "1h", "timed": None},
        expect=204,
    )
    paused = member(circle(jordan_tok), sam_id)
    check(
        "3 Pause",
        "1h pause: effective presentation paused, restoresTo untilTheyLook",
        paused["inboundShare"]["presentation"] == "paused"
        and paused["inboundShare"].get("revertsTo") == "untilTheyLook",
        str(paused["inboundShare"]),
    )
    pause_look_status, pause_look = req(
        "POST",
        "/api/v1/looks",
        token=jordan_tok,
        body={"subjectId": sam_id, "confirmed": True},
    )
    check(
        "3 Pause",
        "viewer cannot peek (Look) during pause",
        pause_look_status >= 400,
        f"status={pause_look_status} body={pause_look}",
    )

    # Advance pause_until into the past; GET /circle runs RestoreExpiredPausesAsync
    psql(
        f"UPDATE trust.shares SET pause_until = now() - interval '2 minutes' "
        f"WHERE grantor_id = '{sam_id}' AND grantee_id = '{jordan_id}';"
    )
    restored = member(circle(jordan_tok), sam_id)
    check(
        "3 Pause",
        "after advancing pause_until + circle restore sweep, previous mode restores",
        restored["inboundShare"]["presentation"] == "untilTheyLook"
        and restored["inboundShare"]["resting"] == "untilTheyLook",
        str(restored["inboundShare"]),
    )
    timed_col = psql(
        "SELECT count(*)::text FROM information_schema.columns "
        "WHERE table_schema = 'trust' AND table_name = 'shares' AND column_name = 'timed_until';"
    )
    timed_written = psql(
        f"SELECT coalesce(timed_until::text, '') FROM trust.shares "
        f"WHERE grantor_id = '{sam_id}' AND grantee_id = '{jordan_id}';"
    )
    check(
        "3 Pause",
        "migration leaves timed_until in place and the new API does not write it",
        timed_col == "1" and timed_written == "",
        f"column_count={timed_col} value={timed_written!r}",
    )

    # --- 4 Stop (Off) ---
    # Local Dev seeds Alex/Jordan/Riley with outbound Sealed/Always. Ingest accepts
    # location if ANY outbound share AcceptsLocation — so Off must be set for all peers
    # to prove "no location stored during Off".
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(utcnow()),
            "latitude": 37.760,
            "longitude": -122.415,
            "batteryPercent": 70,
            "isCharging": False,
            "points": None,
        },
        expect=204,
    )
    before_lat = psql(
        f"SELECT latitude::text FROM trust.location_points WHERE account_id = '{sam_id}' "
        f"ORDER BY recorded_at DESC LIMIT 1;"
    )
    before_count = psql(
        f"SELECT count(*)::text FROM trust.location_points WHERE account_id = '{sam_id}';"
    )

    sam_before_off = circle(sam_tok)
    for row in sam_before_off["members"]:
        req(
            "PATCH",
            f"/api/v1/people/{row['person']['id']}/share",
            token=sam_tok,
            body={"resting": "off", "pause": None, "timed": None},
            expect=204,
        )
    stopped = member(circle(jordan_tok), sam_id)
    check(
        "4 Stop",
        "person stays after Off; inbound share is off",
        stopped["inboundShare"]["presentation"] == "off",
        f"presentation={stopped['inboundShare']['presentation']}",
    )
    still_paired = any(m["person"]["id"] == sam_id for m in circle(jordan_tok)["members"])
    check("4 Stop", "pair membership retained while Off", still_paired)

    # Capture stored lats after Off (ClearLocationsIfNothingHeld may wipe trail)
    after_off_lats = psql(
        f"SELECT coalesce(string_agg(latitude::text, ','), '') FROM trust.location_points "
        f"WHERE account_id = '{sam_id}';"
    )

    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(utcnow()),
            "latitude": 37.999,
            "longitude": -122.999,
            "batteryPercent": 70,
            "isCharging": False,
            "points": None,
        },
        expect=204,
    )
    after_lat = psql(
        f"SELECT coalesce((SELECT latitude::text FROM trust.location_points "
        f"WHERE account_id = '{sam_id}' ORDER BY recorded_at DESC LIMIT 1), '')"
    )
    after_count = psql(
        f"SELECT count(*)::text FROM trust.location_points WHERE account_id = '{sam_id}';"
    )
    all_lats = psql(
        f"SELECT coalesce(string_agg(latitude::text, ','), '') FROM trust.location_points "
        f"WHERE account_id = '{sam_id}';"
    )
    check(
        "4 Stop",
        "no Off ingest location stored (latest != 37.999)",
        after_lat != "37.999" and "37.999" not in all_lats,
        f"before_lat={before_lat} after_off_lats={after_off_lats} after_lat={after_lat} "
        f"counts={before_count}->{after_count}",
    )

    # --- 5 Remove (use throwaway Ada for revoke so Sam/Jordan remain for later checks) ---
    ada = session("E2E-Ada", f"e2e-ada-{suffix}")
    ada_id = ada["you"]["id"]
    ada_tok = ada["token"]
    _, inv2 = req("POST", "/api/v1/invites", token=sam_tok, expect=200)
    req("POST", "/api/v1/invites/accept", token=ada_tok, body={"code": inv2["code"]}, expect=204)
    # Sam may still be Off toward Jordan only; set Sealed toward Ada then revoke
    req(
        "PATCH",
        f"/api/v1/people/{ada_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    req("POST", f"/api/v1/people/{ada_id}/revoke", token=sam_tok, expect=204)
    ada_circ = circle(ada_tok)
    check(
        "5 Remove",
        "pair gone after revoke",
        not any(m["person"]["id"] == sam_id for m in ada_circ["members"]),
        f"members={[m['person']['id'] for m in ada_circ['members']]}",
    )
    check(
        "5 Remove",
        "log kind removed present",
        any(e["kind"] == "removed" for e in ada_circ["lookLog"]),
        f"lookLog kinds={[e['kind'] for e in ada_circ['lookLog']]}",
    )

    # --- 6 History ---
    # Ensure Sam sharing Sealed to Jordan again (may have been Off)
    req(
        "PATCH",
        f"/api/v1/people/{jordan_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    now = utcnow()
    points = [
        (now - timedelta(days=20), 37.100, -122.100),
        (now - timedelta(hours=30), 37.200, -122.200),
        (now - timedelta(minutes=30), 37.300, -122.300),
    ]
    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(now),
            "latitude": points[-1][1],
            "longitude": points[-1][2],
            "batteryPercent": 70,
            "isCharging": False,
            "points": [
                {"timestamp": iso(ts), "latitude": la, "longitude": lo} for ts, la, lo in points
            ],
        },
        expect=204,
    )

    # Free window: temporarily strip Jordan Plus via SQL if needed — review unlock is sticky.
    # Assert free window by using a fresh free viewer (Bea) who never got Plus.
    bea = session("E2E-Bea", f"e2e-bea-{suffix}")
    bea_id = bea["you"]["id"]
    bea_tok = bea["token"]
    _, inv3 = req("POST", "/api/v1/invites", token=sam_tok, expect=200)
    req("POST", "/api/v1/invites/accept", token=bea_tok, body={"code": inv3["code"]}, expect=204)
    req(
        "PATCH",
        f"/api/v1/people/{bea_id}/share",
        token=sam_tok,
        body={"resting": "untilTheyLook", "pause": None, "timed": None},
        expect=204,
    )
    # Re-ingest so Bea share path has history (same points)
    req(
        "POST",
        "/api/v1/location",
        token=sam_tok,
        body={
            "timestamp": iso(now),
            "latitude": points[-1][1],
            "longitude": points[-1][2],
            "batteryPercent": 70,
            "isCharging": False,
            "points": [
                {"timestamp": iso(ts), "latitude": la, "longitude": lo} for ts, la, lo in points
            ],
        },
        expect=204,
    )
    _, free_hist = req("GET", f"/api/v1/people/{sam_id}/history", token=bea_tok, expect=200)
    free_lats = [p["latitude"] for p in free_hist["points"]]
    check(
        "6 History",
        "free window returns ≤24h points only (includes ~30m, excludes 30h/20d)",
        37.300 in free_lats and 37.200 not in free_lats and 37.100 not in free_lats,
        f"lats={free_lats}",
    )

    grant_plus(bea_tok)
    _, plus_hist = req("GET", f"/api/v1/people/{sam_id}/history", token=bea_tok, expect=200)
    plus_lats = [p["latitude"] for p in plus_hist["points"]]
    check(
        "6 History",
        "Plus window applies 30d (includes 30h and 20d points)",
        37.300 in plus_lats and 37.200 in plus_lats and 37.100 in plus_lats,
        f"lats={plus_lats}",
    )

    # --- 7 Presence ---
    req(
        "PUT",
        f"/api/v1/people/{jordan_id}/presence-grant",
        token=sam_tok,
        body={"enabled": True},
        expect=204,
    )
    req(
        "POST",
        "/api/v1/me/home/presence",
        token=sam_tok,
        body={"state": "home", "signaledAt": None},
        expect=204,
    )
    home_row = member(circle(jordan_tok), sam_id)
    check(
        "7 Presence",
        "Home visible on peer payload",
        home_row.get("homePresence") is not None and home_row["homePresence"]["state"] == "home",
        str(home_row.get("homePresence")),
    )
    req(
        "POST",
        "/api/v1/me/home/presence",
        token=sam_tok,
        body={"state": "away", "signaledAt": None},
        expect=204,
    )
    away_row = member(circle(jordan_tok), sam_id)
    check(
        "7 Presence",
        "Away visible on peer payload",
        away_row.get("homePresence") is not None and away_row["homePresence"]["state"] == "away",
        str(away_row.get("homePresence")),
    )
    req(
        "POST",
        "/api/v1/me/home/presence",
        token=sam_tok,
        body={"state": "hidden", "signaledAt": None},
        expect=204,
    )
    hidden_row = member(circle(jordan_tok), sam_id)
    check(
        "7 Presence",
        "Hidden omitted from peer payload",
        hidden_row.get("homePresence") is None,
        f"homePresence={hidden_row.get('homePresence')}",
    )
    # Confirm row still exists server-side
    hidden_db = psql(
        f"SELECT state FROM trust.current_home_presence WHERE account_id = '{sam_id}';"
    )
    check(
        "7 Presence",
        "Hidden still stored server-side as hidden",
        hidden_db == "hidden",
        f"db={hidden_db}",
    )

    # --- 8 Delete account clears presence (throwaway) ---
    clyde = session("E2E-Clyde", f"e2e-clyde-{suffix}")
    clyde_id = clyde["you"]["id"]
    clyde_tok = clyde["token"]
    req(
        "POST",
        "/api/v1/me/home/presence",
        token=clyde_tok,
        body={"state": "away", "signaledAt": None},
        expect=204,
    )
    before_del = psql(
        f"SELECT count(*)::text FROM trust.current_home_presence WHERE account_id = '{clyde_id}';"
    )
    req("DELETE", "/api/v1/account", token=clyde_tok, expect=204)
    after_del = psql(
        f"SELECT count(*)::text FROM trust.current_home_presence WHERE account_id = '{clyde_id}';"
    )
    acct = psql(f"SELECT count(*)::text FROM trust.accounts WHERE account_id = '{clyde_id}';")
    check(
        "8 Delete",
        "delete account clears presence rows",
        before_del == "1" and after_del == "0" and acct == "0",
        f"presence {before_del}->{after_del} account_rows={acct}",
    )

    print()
    print("=" * 72)
    print(f"SUMMARY: {PASS} passed, {FAIL} failed")
    by_item: dict[str, list[tuple[str, str]]] = {}
    for item, status, assertion in RESULTS:
        by_item.setdefault(item, []).append((status, assertion))
    for item, rows in by_item.items():
        overall = "PASS" if all(s == "PASS" for s, _ in rows) else "FAIL"
        print(f"\n## {overall} — {item}")
        for status, assertion in rows:
            print(f"  [{status}] {assertion}")

    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"FATAL: {exc}", file=sys.stderr)
        sys.exit(2)
