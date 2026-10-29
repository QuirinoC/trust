#!/usr/bin/env python3
"""Verify CI's plain-HTTP local API UI lane against named XCTest inventory.

This lane intentionally has no race proxy or paired-device roles. The explicit
skip map documents those unsupported scenarios; passing this lane is not proof
of proxy races, paired-device handoff, production API behavior, or StoreKit.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SOURCE = Path(__file__).resolve().parents[1] / "Tests/TrustUITests/TrustRealAPIFeatureTests.swift"
SERIAL_EXCLUSIONS = {
    "testSameAccountHomeHandoffOwnerSetsHome": "requires shared A/B/A Home marker and synthetic device locations",
    "testSameAccountHomeHandoffFirstUseDeviceTakesOver": "requires the preceding A phase and same shared Home marker",
    "testSameAccountHomeHandoffPreviousOwnerDetectsTakeoverAndClear": "requires the preceding A/B phases and same shared Home marker",
}
DIRECT_PASS_CASES = {
    "testRequiredPhoneCorrectionsCooldownEditRelaunchAndReturningVerifiedAccount",
    "testAppleSignInFailureCanRetryDirectlyToOnboarding",
    "testPrivacyHeldAccountCanDeleteAfterRelaunch",
    "testSharingTabRefreshShowsPeerAcceptedAfterInitialFetch",
    "testAlwaysSharedLocationHistoryRendersAndClearsAfterStop",
    "testRealOnboardingHandleRequestAcceptAndStopSharing",
    "testPauseShowsMultiDayEndAndExplicitResumeRestoresOnlyThatPerson",
    "testProfilePictureIsStagedAndDiscoveryStaysExplicitAcrossRelaunch",
}
DIRECT_SKIP_REASONS = {
    "testConsentRevokedResponseKeepsAccountBlocked": "requires fault proxy to inject a consent-revoked response",
    "testLatePhoneResponsesAfterEditPreserveRetryWithoutOpeningCodeOrHome": "requires fault proxy to hold phone send/verify responses",
    "testManualHomeChoicesReachServerAndRetirePreviousNotice": "requires fault proxy to hold Home presence responses",
    "testPairedRequestAcceptAndPresenceGrantRole": "requires explicit Alice/Bob runner roles and shared pair ID",
    "testStopRemainsOffAcrossStaleCircleResponseAndRelaunch": "requires fault proxy to hold and fail stale circle reads",
    "testShareModeSelectionWaitsForSuccessAndPreservesPausedStateOnFailure": "requires fault proxy to delay and fail share writes",
    "testRemoveStaysAbsentAfterStaleCircleResponseAndRelaunch": "requires fault proxy stale-read controls",
    "testStopAllFailureDoesNotPartiallyStopAndRetryPersistsAfterRelaunch": "requires fault proxy to inject atomic Stop All failure",
    "testDelayedLookResponseIsDiscardedAfterReplacementRelationship": "requires fault proxy to delay a Look response",
    "testDelayedHistoryFixtureCannotReappearAfterStopRemoveAndReconnect": "requires fault proxy history delay and synthetic entitlement fixture",
    "testDelayedHistoryFixtureStaysClosedWhenConsentRefreshIsOffline": "requires fault proxy offline refresh and synthetic entitlement fixture",
    "testDelayedLookStaysClosedWhenConsentRefreshIsOffline": "requires fault proxy offline consent-refresh control",
    "testOfflinePeerRemovalReconcilesAfterRelaunchAndReconnect": "requires fault proxy offline/reconnect control",
    "testAddPersonCanRetrySameQueryAndConfirmedSendSurvivesFailedLookup": "requires fault proxy failed lookup control",
    "testFailedAcceptKeepsNamedRequestAndOtherRequestsAvailableForRetry": "requires fault proxy failed acceptance control",
}


class VerificationError(RuntimeError):
    pass


def source_case_names(source: Path = SOURCE) -> list[str]:
    return re.findall(r"^\s+func\s+(test[A-Za-z0-9_]+)\s*\(", source.read_text(encoding="utf-8"), re.MULTILINE)


def result_cases(tree: dict[str, Any]) -> dict[str, str]:
    cases: dict[str, str] = {}

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            if str(node.get("nodeType", "")).lower().replace(" ", "") == "testcase":
                identifier = str(node.get("nodeIdentifier") or node.get("testIdentifier") or node.get("name") or "")
                match = re.search(r"(test[A-Za-z0-9_]+)(?:\(.*\))?$", identifier)
                if not match:
                    raise VerificationError(f"Could not identify an XCTest case node: {identifier!r}")
                name = match.group(1)
                if name in cases:
                    raise VerificationError(f"xcresult contains duplicate test case {name}")
                cases[name] = str(node.get("result", "")).lower()
            for key in ("testNodes", "children", "nodes"):
                children = node.get(key)
                if isinstance(children, list):
                    for child in children:
                        walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)

    walk(tree)
    if not cases:
        raise VerificationError("xcresult test tree contains no leaf test cases")
    return cases


def verify(source_names: list[str], summary: dict[str, Any], tree: dict[str, Any]) -> str:
    source_counts = Counter(source_names)
    if not source_counts or any(count != 1 for count in source_counts.values()):
        raise VerificationError("Swift E2E source inventory is empty or contains duplicate test method names")
    expected_cases = set(source_counts)
    excluded = set(SERIAL_EXCLUSIONS)
    classified = DIRECT_PASS_CASES | set(DIRECT_SKIP_REASONS)
    if expected_cases - excluded != classified:
        missing = sorted((expected_cases - excluded) - classified)
        stale = sorted(classified - (expected_cases - excluded))
        raise VerificationError(f"Direct-lane classification differs from source; unclassified={missing}, stale={stale}")
    if not excluded <= expected_cases:
        raise VerificationError(f"Serial Home handoff exclusion missing from source: {sorted(excluded - expected_cases)}")

    actual = result_cases(tree)
    selected = expected_cases - excluded
    if set(actual) != selected:
        raise VerificationError(f"xcresult source inventory mismatch; missing={sorted(selected-set(actual))}, extra={sorted(set(actual)-selected)}")

    wrong_pass = sorted(name for name in DIRECT_PASS_CASES if actual[name] not in ("passed", "success"))
    wrong_skip = sorted(name for name in DIRECT_SKIP_REASONS if actual[name] != "skipped")
    if wrong_pass or wrong_skip:
        raise VerificationError(f"Unexpected direct-lane statuses; expected passes not passed={wrong_pass}, expected skips not skipped={wrong_skip}")

    expected_total = len(selected)
    counts = {
        "totalTestCount": summary.get("totalTestCount"),
        "passedTests": summary.get("passedTests"),
        "skippedTests": summary.get("skippedTests"),
        "failedTests": summary.get("failedTests"),
    }
    expected_counts = {
        "totalTestCount": expected_total,
        "passedTests": len(DIRECT_PASS_CASES),
        "skippedTests": len(DIRECT_SKIP_REASONS),
        "failedTests": 0,
    }
    if summary.get("result") != "Passed" or counts != expected_counts:
        raise VerificationError(f"xcresult summary mismatch; expected={expected_counts} and result=Passed, actual={counts}, result={summary.get('result')!r}")

    lines = [
        f"Verified plain-HTTP Development API lane: {expected_total} selected cases, "
        f"{len(DIRECT_PASS_CASES)} expected passes, {len(DIRECT_SKIP_REASONS)} named proxy/role skips, zero failures.",
        "Excluded serial A/B/A Home phases (not executed in this lane):",
    ]
    lines.extend(f"  {name}: {reason}" for name, reason in SERIAL_EXCLUSIONS.items())
    lines.append("Named skips (expected by this direct-API lane):")
    lines.extend(f"  {name}: {reason}" for name, reason in DIRECT_SKIP_REASONS.items())
    lines.append("Synthetic Development review unlock is fixture evidence, not StoreKit evidence.")
    return "\n".join(lines)


def read_json(command: list[str]) -> dict[str, Any]:
    try:
        output = subprocess.run(command, check=True, text=True, capture_output=True).stdout
        result = json.loads(output)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        raise VerificationError(f"Could not read xcresult data with {' '.join(command)}: {error}") from error
    if not isinstance(result, dict):
        raise VerificationError(f"xcresult command returned non-object JSON: {' '.join(command)}")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle", type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE)
    args = parser.parse_args(argv)
    try:
        bundle = args.result_bundle.resolve()
        if not bundle.is_dir():
            raise VerificationError(f"xcresult bundle is missing: {bundle}")
        summary = read_json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)])
        tree = read_json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)])
        print(verify(source_case_names(args.source), summary, tree))
        return 0
    except (VerificationError, OSError) as error:
        print(f"Direct API result verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
