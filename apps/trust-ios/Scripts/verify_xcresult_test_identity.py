#!/usr/bin/env python3
"""Require one specific XCTest identity to pass exactly once in an xcresult."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def find_test_nodes(value: Any, identity: str):
    if isinstance(value, dict):
        node_type = str(value.get("nodeType", "")).lower()
        identifier = str(value.get("nodeIdentifier", ""))
        identifier_parts = identifier.rstrip("()").split("/")
        identity_parts = identity.rstrip("()").split("/")
        found = len(identifier_parts) >= 2 and identifier_parts[-2:] == identity_parts[-2:]
        if found and node_type == "test case":
            yield value
        for child in value.values():
            yield from find_test_nodes(child, identity)
    elif isinstance(value, list):
        for child in value:
            yield from find_test_nodes(child, identity)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--tests", type=Path, required=True)
    parser.add_argument("--identity", required=True, help="XCTest suite/method path, such as TrustUsageTests/testLayout")
    args = parser.parse_args()

    try:
        summary = read_json(args.summary)
        tests = read_json(args.tests)
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read xcresult JSON: {error}", file=sys.stderr)
        return 1

    nodes = list(find_test_nodes(tests, args.identity))
    if len(nodes) != 1:
        print(f"Expected exactly one result node for {args.identity}, found {len(nodes)}.", file=sys.stderr)
        return 1
    if str(nodes[0].get("result", "")).lower() != "passed":
        print(f"{args.identity} must pass; xcresult reports {nodes[0].get('result')!r}.", file=sys.stderr)
        return 1

    expected = {
        "result": "Passed",
        "totalTestCount": 1,
        "passedTests": 1,
        "skippedTests": 0,
        "failedTests": 0,
    }
    mismatches = [
        f"{field}: expected {value!r}, got {summary.get(field)!r}"
        for field, value in expected.items()
        if summary.get(field) != value
    ]
    if mismatches:
        print("The wide-layout xcresult did not contain exactly one passing test:", file=sys.stderr)
        for mismatch in mismatches:
            print(f"  {mismatch}", file=sys.stderr)
        return 1

    print(f"Verified {args.identity} passed once with no skip or failure.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
