"""Focused tests for simulator APNs entitlement validation."""

from __future__ import annotations

import importlib.util
import plistlib
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "run_real_push_e2e.py"
SPEC = importlib.util.spec_from_file_location("trust_real_push_e2e", SCRIPT)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


def otool_section_for_plist(value: dict[str, str]) -> str:
    data = plistlib.dumps(value, fmt=plistlib.FMT_XML)
    rows = ["Contents of (__TEXT,__entitlements) section"]
    for offset in range(0, len(data), 4):
        chunk = data[offset:offset + 4]
        if len(chunk) == 4:
            words = [chunk[::-1].hex()]
        else:
            # otool prints the short final columns as individual bytes.
            words = [byte.hex() for byte in chunk]
        rows.append(f"{offset:016x} {' '.join(words)}")
    return "\n".join(rows)


class EmbeddedSimulatorEntitlementTests(unittest.TestCase):
    def test_parses_xcode_otool_words_and_short_final_bytes(self) -> None:
        expected = {
            "aps-environment": "development",
            "application-identifier": "3S529.com.collapsetechnologies.trust",
        }
        actual = runner.parse_otool_entitlements(otool_section_for_plist(expected))
        self.assertEqual(actual, expected)
        runner.require_development_apns_entitlements(actual, "3S529")

    def test_rejects_production_apns_environment(self) -> None:
        entitlements = {
            "aps-environment": "production",
            "application-identifier": "3S529.com.collapsetechnologies.trust",
        }
        with self.assertRaises(runner.PushRunnerError):
            runner.require_development_apns_entitlements(entitlements, "3S529")

    def test_rejects_mismatched_application_identifier(self) -> None:
        entitlements = {
            "aps-environment": "development",
            "application-identifier": "3S529.com.example.other",
        }
        with self.assertRaises(runner.PushRunnerError):
            runner.require_development_apns_entitlements(entitlements, "3S529")

    def test_rejects_missing_embedded_section(self) -> None:
        with self.assertRaises(runner.PushRunnerError):
            runner.parse_otool_entitlements("Contents of (__TEXT,__entitlements) section")

    def test_case_allowlist_preserves_foreground_background_default(self) -> None:
        self.assertEqual(runner.TEST_CASE, "testRealSandboxAPNsForegroundAndBackgroundLookRoute")
        self.assertEqual(
            runner.TEST_CASES,
            (
                "testRealSandboxAPNsForegroundAndBackgroundLookRoute",
                "testRealSandboxAPNsNotificationSettingsRecovery",
            ),
        )


if __name__ == "__main__":
    unittest.main()
