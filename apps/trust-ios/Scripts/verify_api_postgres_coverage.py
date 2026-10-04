#!/usr/bin/env python3
"""Require representative PostgreSQL-backed API tests to pass in CI."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


REQUIRED_TESTS = {
    "PostgresMigrationUpgradeTests.PopulatedSchemaAt013UpgradesTo022AndRemainsRepeatable",
    "TwoAccountPostgresTests.TwoAccountsCoverShareHistoryPauseStopRemoveAndDelete",
    "PostgresAgeAssuranceAccountStoreTests.LinksAndRevocationsPersistAndDeduplicateAcrossStoreInstances",
    "PostgresAgeAssurancePrivacyHoldTests.PrivacyHoldPersistsOnlyFixedMinimalFieldsAndDoesNotChangeOnReplay",
    "DiscoveryConsentPostgresTests.ConsentIsPersistedAndLegacyHandleUpdatesPreserveIt",
    "PostgresPhoneSmsConsentTests.PhoneSmsConsentPersistsAcrossStoreInstancesAndCascadesOnAccountDeletion",
    "PostgresConnectionRequestTests.ConcurrentReciprocalRequestsAndAcceptsAreIdempotentAndDeclineCooldownIsDirectional",
}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trx", type=Path, help="Path to dotnet test's TRX result")
    args = parser.parse_args()

    if not args.trx.is_file():
        print(f"TRX result is missing: {args.trx}", file=sys.stderr)
        return 1

    try:
        root = ET.parse(args.trx).getroot()
    except (ET.ParseError, OSError) as error:
        print(f"Could not read TRX result: {error}", file=sys.stderr)
        return 1

    methods_by_id: dict[str, tuple[str, str]] = {}
    for node in root.iter():
        if local_name(node.tag) != "UnitTest":
            continue
        test_method = next((child for child in node if local_name(child.tag) == "TestMethod"), None)
        if test_method is None:
            continue
        test_id = node.attrib.get("id")
        class_name = test_method.attrib.get("className")
        method_name = test_method.attrib.get("name")
        if test_id and class_name and method_name:
            methods_by_id[test_id] = (class_name, method_name)

    results: dict[str, list[str]] = {}
    for node in root.iter():
        if local_name(node.tag) != "UnitTestResult":
            continue
        test_id = node.attrib.get("testId", "")
        identity = methods_by_id.get(test_id)
        outcome = node.attrib.get("outcome", "").lower()
        if identity is None:
            continue
        class_name, method_name = identity
        for required in REQUIRED_TESTS:
            class_suffix, required_method = required.rsplit(".", 1)
            if class_name == f"TrustApi.Tests.{class_suffix}" and method_name == required_method:
                results.setdefault(required, []).append(outcome)

    missing = sorted(REQUIRED_TESTS - results.keys())
    not_passed = sorted(
        f"{name}: {', '.join(outcomes)}"
        for name, outcomes in results.items()
        if outcomes != ["passed"]
    )
    if missing or not_passed:
        if missing:
            print("Required PostgreSQL test identities are missing:", file=sys.stderr)
            for name in missing:
                print(f"  {name}", file=sys.stderr)
        if not_passed:
            print("Required PostgreSQL tests did not pass exactly once:", file=sys.stderr)
            for item in not_passed:
                print(f"  {item}", file=sys.stderr)
        return 1

    print(f"Verified {len(REQUIRED_TESTS)} named PostgreSQL integration tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
