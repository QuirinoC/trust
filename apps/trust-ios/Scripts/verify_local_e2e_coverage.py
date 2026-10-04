#!/usr/bin/env python3
"""Verify the opt-in API UI lane by test identity and declared skip reason."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_SKIPS = {
    "testLatePhoneResponsesAfterEditPreserveRetryWithoutOpeningCodeOrHome":
        "Requires the isolated loopback fault proxy.",
    "testManualHomeChoicesReachServerAndRetirePreviousNotice":
        "Requires the isolated loopback fault proxy.",
    "testAdultAgeGateAppleExchangeFailureCanRetryThroughTransactionLinkIntoOnboarding":
        "age-assurance request-count scenario requires the loopback fault proxy on port 5089",
    "testAppTransactionRetryKeepsRequestsClosedThenRecoversAcrossRelaunch":
        "age-assurance request-count scenario requires the loopback fault proxy on port 5089",
    "testAgeAndPrivacyBlocksSuppressAccountLocationAndPushRequests":
        "age-assurance request-count scenario requires the loopback fault proxy on port 5089",
    "testPairedRequestAcceptAndPresenceGrantRole":
        "Set TRUST_UI_PAIR_ROLE=alice|bob and one shared eight-hex TRUST_UI_PAIR_ID",
    "testStopRemainsOffAcrossStaleCircleResponseAndRelaunch":
        "requires the loopback race proxy on port 5089",
    "testRemoveStaysAbsentAfterStaleCircleResponseAndRelaunch":
        "requires the loopback race proxy on port 5089",
    "testStopAllFailureDoesNotPartiallyStopAndRetryPersistsAfterRelaunch":
        "requires the loopback fault proxy on port 5089",
    "testDelayedLookResponseIsDiscardedAfterReplacementRelationship":
        "requires the loopback fault proxy on port 5089",
    "testOfflineCircleReadKeepsTheShareUntilReconnectShowsPeerStop":
        "Requires the isolated loopback fault proxy.",
}

EXPECTED_PASSES = {
    "testRequiredPhoneCorrectionsCooldownEditRelaunchAndReturningVerifiedAccount",
    "testPrivacyHeldAccountCanDeleteAfterRelaunch",
    "testSharingTabRefreshShowsPeerAcceptedAfterInitialFetch",
    "testAlwaysSharedLocationHistoryRendersAndClearsAfterStop",
    "testRealOnboardingHandleRequestAcceptAndStopSharing",
    "testYouDiscoveryOffBlocksPhoneSearchAndDeleteRemovesTheAccount",
    "testPauseForOneHourThenSealedAgainPersistsOnTheServer",
    "testPauseForEightHoursPersistsTheEndTime",
    "testPauseFromAlwaysForOneDayRestoresAlways",
    "testFreeHistoryOmitsTheTwoDayOldPointThatPlusKeeps",
    "testPauseForTwoDaysAndThreeDaysPersistsTheEndTimes",
    "testViewerSeesPauseAndNoTrailWhileSharingIsPaused",
    "testAlwaysPointOlderThanFiveMinutesShowsTheStaleCue",
    "testRelaunchAfterPeerStopDropsTheCachedAlwaysShare",
    "testFreeSeatLimitStopsTheSixthPersonUntilPlus",
    "testFreeViewerSeesTheTrailButNotTheLivePin",
    "testViewerMapShowsTheAlwaysPointAndItsTime",
    "testCoveredAccountCanChooseAlwaysFromTheSharingControl",
    "testCoveredAccountCanExportTheActivityLog",
    "testFreeAccountWithActivityDoesNotSeeExport",
    "testYouLegalLinksOpenThePublicPages",
    "testActivityShowsLooksInBothDirections",
    "testActivityShowsViewsInBothDirectionsAndARemoval",
    "testDiscoveryOffHidesUnconnectedPicturesAndKeepsTheConnectedOne",
    "testYouCanChooseAProfileIconAndAConnectedPersonReceivesIt",
    "testRemovingTheProfileIconClearsItForAConnectedPerson",
    "testSignOutReturnsToTheAgeGateWithoutDeletingTheAccount",
    "testFreeAccountAlwaysOpensThePaywallAndDoesNotStartSharing",
    "testStoreKitTestingPaywallListsTheLocalPrices",
}

EXPECTED_EXCLUSIONS = {
    "testSameAccountHomeHandoffOwnerSetsHome":
        "Requires a serial multi-device home-handoff run; excluded from this single-simulator lane.",
    "testSameAccountHomeHandoffFirstUseDeviceTakesOver":
        "Requires a serial multi-device home-handoff run; excluded from this single-simulator lane.",
    "testSameAccountHomeHandoffPreviousOwnerDetectsTakeoverAndClear":
        "Requires a serial multi-device home-handoff run; excluded from this single-simulator lane.",
}

TEST_METHOD = re.compile(r"\btest[A-Za-z0-9_]+\b")


def read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def method_names_from_source(path: Path) -> set[str]:
    source = path.read_text(encoding="utf-8")
    return set(re.findall(r"\bfunc\s+(test[A-Za-z0-9_]+)\s*\(", source))


def result_nodes(value: Any):
    if isinstance(value, dict):
        node_type = str(value.get("nodeType", "")).lower()
        identifier = str(value.get("nodeIdentifier", ""))
        identifier_parts = identifier.rstrip("()").split("/")
        method = TEST_METHOD.fullmatch(identifier_parts[-1]) if identifier_parts else None
        if (
            node_type == "test case"
            and len(identifier_parts) >= 2
            and identifier_parts[-2] == "TrustRealAPIFeatureTests"
            and method is not None
        ):
            yield method.group(0), value
        for child in value.values():
            yield from result_nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from result_nodes(child)


def node_reason(node: dict[str, Any]) -> str:
    chunks: list[str] = []

    def collect(value: Any) -> None:
        if isinstance(value, dict):
            if value.get("nodeType") == "Skip Message":
                chunks.append(str(value.get("name", "")))
            for child in value.values():
                collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)

    collect(node.get("children", []))
    return " ".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--tests", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()

    for path in (args.summary, args.tests, args.source):
        if not path.is_file():
            print(f"Required coverage input is missing: {path}", file=sys.stderr)
            return 1

    try:
        summary = read_json(args.summary)
        tests = read_json(args.tests)
        source_methods = method_names_from_source(args.source)
    except (OSError, json.JSONDecodeError) as error:
        print(f"Could not read coverage input: {error}", file=sys.stderr)
        return 1

    if not source_methods:
        print("No XCTest methods were found in the LocalE2E source file.", file=sys.stderr)
        return 1

    policy_methods = EXPECTED_PASSES | EXPECTED_SKIPS.keys() | EXPECTED_EXCLUSIONS.keys()
    missing_policy = source_methods - policy_methods
    stale_policy = policy_methods - source_methods
    if missing_policy or stale_policy:
        print("LocalE2E skip/exclusion policy no longer matches the test class:", file=sys.stderr)
        for method in sorted(missing_policy):
            print(f"  missing an explicit pass/skip/exclusion policy: {method}", file=sys.stderr)
        for method in sorted(stale_policy):
            print(f"  policy references a removed test: {method}", file=sys.stderr)
        return 1

    observed: dict[str, list[dict[str, Any]]] = {}
    for method, node in result_nodes(tests):
        if method in source_methods:
            observed.setdefault(method, []).append(node)

    errors: list[str] = []
    passed_count = 0
    skipped_count = 0
    for method in sorted(EXPECTED_PASSES | EXPECTED_SKIPS.keys()):
        nodes = observed.get(method, [])
        if len(nodes) != 1:
            errors.append(f"{method}: expected exactly one result node, found {len(nodes)}")
            continue
        node = nodes[0]
        result = str(node.get("result", "")).lower()
        if method in EXPECTED_SKIPS:
            reason = EXPECTED_SKIPS[method]
            recorded_reason = node_reason(node)
            if result != "skipped":
                errors.append(f"{method}: expected an explicit skip ({reason}), got {node.get('result')!r}")
            elif reason.lower() not in recorded_reason.lower():
                errors.append(f"{method}: skip reason did not match {reason!r}; recorded details: {recorded_reason!r}")
            else:
                skipped_count += 1
        elif method in EXPECTED_PASSES and result == "passed":
            passed_count += 1
        else:
            errors.append(f"{method}: expected Passed, got {node.get('result')!r}")

    excluded_skipped_count = 0
    for method, reason in EXPECTED_EXCLUSIONS.items():
        nodes = observed.get(method, [])
        if len(nodes) > 1:
            errors.append(f"{method}: expected at most one result node, found {len(nodes)}")
        elif nodes:
            result = str(nodes[0].get("result", "")).lower()
            if result == "passed":
                errors.append(f"{method}: CI exclusion was unexpectedly executed; declared reason: {reason}")
            elif result == "skipped":
                excluded_skipped_count += 1
            else:
                errors.append(f"{method}: CI exclusion has unexpected result {nodes[0].get('result')!r}; declared reason: {reason}")

    expected_summary_skipped = skipped_count + excluded_skipped_count
    expected_total = passed_count + expected_summary_skipped
    expected_summary = {
        "result": "Passed",
        "totalTestCount": expected_total,
        "passedTests": passed_count,
        "skippedTests": expected_summary_skipped,
        "failedTests": 0,
    }
    for field, expected in expected_summary.items():
        if summary.get(field) != expected:
            errors.append(f"summary {field}: expected {expected!r}, got {summary.get(field)!r}")

    if errors:
        print("LocalE2E coverage verification failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    print(
        f"Verified {passed_count} required LocalE2E test identities passed; "
        f"{skipped_count} declared proxy/pair-dependent tests skipped for their expected reasons; "
        f"{len(EXPECTED_EXCLUSIONS)} serial home-handoff tests were explicitly excluded."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
