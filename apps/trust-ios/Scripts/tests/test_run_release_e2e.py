"""Focused stdlib tests for the release E2E runner's safety gates."""

from __future__ import annotations

import importlib.util
import json
import plistlib
import socket
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "run_release_e2e.py"
SPEC = importlib.util.spec_from_file_location("trust_release_e2e", SCRIPT)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)

VERIFY_SCRIPT = Path(__file__).resolve().parents[1] / "verify_direct_e2e_result.py"
VERIFY_SPEC = importlib.util.spec_from_file_location("trust_direct_e2e_verifier", VERIFY_SCRIPT)
assert VERIFY_SPEC and VERIFY_SPEC.loader
verifier = importlib.util.module_from_spec(VERIFY_SPEC)
sys.modules[VERIFY_SPEC.name] = verifier
VERIFY_SPEC.loader.exec_module(verifier)


class PostgresConnectionTests(unittest.TestCase):
    def test_accepts_only_literal_loopback_hosts_and_reserved_local_ports(self) -> None:
        for host in ("127.0.0.1", "localhost", "::1"):
            with self.subTest(host=host):
                fields, _ = runner.parse_pg_connection(
                    f"Host={host};Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust"
                )
                self.assertEqual(fields["host"], host)
                self.assertEqual(fields["port"], "5433")

    def test_rejects_remote_production_duplicate_alias_and_unknown_options(self) -> None:
        unsafe = (
            "Host=db.example.com;Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust",
            "Host=127.0.0.2;Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust",
            "Host=127.0.0.1;Port=5432;Database=trust_ui_e2e;Username=trust;Password=trust",
            "Host=127.0.0.1;Server=localhost;Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust",
            "Host=127.0.0.1;Host=localhost;Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust",
            "Host=127.0.0.1;Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust;SSL Mode=Require",
        )
        for connection in unsafe:
            with self.subTest(connection=connection):
                with self.assertRaises(runner.RunnerError):
                    runner.parse_pg_connection(connection)

    def test_apns_environment_is_added_only_to_api_child(self) -> None:
        api_child = object()
        proxy_child = object()
        popen_calls = []

        def fake_popen(command, **kwargs):
            popen_calls.append((command, kwargs))
            return api_child if len(popen_calls) == 1 else proxy_child

        with tempfile.TemporaryDirectory() as temporary, patch.dict(
            runner.os.environ, {"Apns__InheritedSecret": "must-not-leak"}
        ):
            with patch.object(runner, "assert_ports_free"), \
                 patch.object(runner, "wait_for_services"), \
                 patch.object(runner.subprocess, "Popen", side_effect=fake_popen):
                services = runner.start_services(
                    Path(temporary), "/xcode", extra_api_environment={
                        "Apns__ProviderPrivateKey": "secret-test-only",
                        "Apns__KeyId": "test-key-id",
                    }
                )
        self.assertIs(services.api, api_child)
        self.assertIs(services.proxy, proxy_child)
        api_environment = popen_calls[0][1]["env"]
        proxy_environment = popen_calls[1][1]["env"]
        self.assertEqual(api_environment["Apns__ProviderPrivateKey"], "secret-test-only")
        self.assertEqual(api_environment["Apns__KeyId"], "test-key-id")
        self.assertNotIn("Apns__InheritedSecret", api_environment)
        self.assertFalse(any(key.casefold().startswith("apns__") for key in proxy_environment))

    def test_temporary_database_name_is_runner_generated(self) -> None:
        connection = "Host=localhost;Port=5433;Database=trust_ui_e2e;Username=trust;Password=trust"
        result = runner.connection_with_database(connection, "trust_e2e_4321_abcdef1234")
        self.assertEqual(result, "Host=localhost;Port=5433;Database=trust_e2e_4321_abcdef1234;Username=trust;Password=trust")
        with self.assertRaises(runner.RunnerError):
            runner.connection_with_database(connection, "trust_ui_e2e")

    def test_container_mapping_must_be_loopback_only_on_all_published_ports(self) -> None:
        good = {"5432/tcp": [{"HostIp": "127.0.0.1", "HostPort": "5433"}],
                "8080/tcp": [{"HostIp": "::1", "HostPort": "8080"}]}
        with patch.object(runner, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps(good), "")) as mocked_run:
            runner.validate_container_mapping("trust-e2e-postgres", 5433)
        self.assertEqual(mocked_run.call_args.kwargs["timeout"], 30)
        for bad in (
            {"5432/tcp": [{"HostIp": "0.0.0.0", "HostPort": "5433"}]},
            {"5432/tcp": [{"HostIp": "127.0.0.1", "HostPort": "5432"}]},
            {"5432/tcp": [{"HostIp": "127.0.0.1", "HostPort": "5433"}],
             "8080/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}]},
            None,
        ):
            with self.subTest(mapping=bad):
                with patch.object(runner, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps(bad), "")):
                    with self.assertRaises(runner.RunnerError):
                        runner.validate_container_mapping("trust-e2e-postgres", 5433)

    def test_psql_uses_docker_exec_positional_container_and_hides_password_from_arguments(self) -> None:
        database = runner.RunnerDatabase(
            container="trust-e2e-postgres", name="trust_e2e_1234_abcdef1234",
            connection="Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust",
            username="trust", password="test-password", port=5433,
            developer_dir="/Applications/Xcode.app/Contents/Developer", owned_by_runner=True,
        )
        with patch.object(runner, "run") as mocked_run:
            database._psql('CREATE DATABASE "trust_e2e_1234_abcdef1234"')
        command = mocked_run.call_args.args[0]
        self.assertEqual(command[:5], ["docker", "exec", "--env", "PGPASSWORD", "trust-e2e-postgres"])
        self.assertNotIn("test-password", command)
        self.assertEqual(mocked_run.call_args.kwargs["env"]["PGPASSWORD"], "test-password")
        self.assertIn("CREATE DATABASE", command[-1])
        self.assertEqual(mocked_run.call_args.kwargs["timeout"], 30)

    def test_direct_psql_uses_only_validated_loopback_endpoint_and_bounded_timeouts(self) -> None:
        database = runner.RunnerDatabase(
            container=None, name="trust_e2e_1234_abcdef1234",
            connection="Host=localhost;Port=5433;Database=trust_ui_e2e;Username=trust;Password=test-password",
            username="trust", password="test-password", port=5433,
            developer_dir="/Applications/Xcode.app/Contents/Developer", direct=True, owned_by_runner=True,
        )
        with patch.object(runner, "run") as mocked_run:
            database._psql('CREATE DATABASE "trust_e2e_1234_abcdef1234"')
        command = mocked_run.call_args.args[0]
        self.assertEqual(command[0:5], ["psql", "--host", "localhost", "--port", "5433"])
        self.assertNotIn("test-password", command)
        env = mocked_run.call_args.kwargs["env"]
        self.assertEqual(env["PGPASSWORD"], "test-password")
        self.assertEqual(env["PGCONNECT_TIMEOUT"], "3")
        self.assertEqual(env["PGOPTIONS"], "-c statement_timeout=15000")
        self.assertEqual(mocked_run.call_args.kwargs["timeout"], 30)
        with patch.object(runner, "run") as mocked_run:
            database.drop()
        self.assertIn('DROP DATABASE IF EXISTS "trust_e2e_1234_abcdef1234" WITH (FORCE)',
                      mocked_run.call_args.args[0][-1])
        self.assertEqual(mocked_run.call_args.kwargs["timeout"], 30)

    def test_direct_backend_rejects_unowned_database_names_and_docker_mixing(self) -> None:
        connection = "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust"
        database = runner.RunnerDatabase(
            container=None, name="trust", connection=connection, username="trust", password="trust",
            port=5433, developer_dir="/xcode", direct=True,
        )
        with patch.object(runner, "run") as mocked_run:
            with self.assertRaises(runner.RunnerError):
                database.drop()
        mocked_run.assert_not_called()
        with self.assertRaises(runner.RunnerError):
            runner.RunnerDatabase.create(connection, "some-container", "/xcode", direct=True)

    def test_postgres_direct_is_explicit_and_container_is_optional_only_for_direct_mode(self) -> None:
        connection = "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust"
        direct = runner.parse_args(["--store", "postgres", "--postgres-connection", connection,
                                    "--postgres-direct"])
        self.assertTrue(direct.postgres_direct)
        self.assertIsNone(direct.postgres_container)
        with self.assertRaises(SystemExit):
            runner.parse_args(["--store", "postgres", "--postgres-connection", connection])
        with self.assertRaises(SystemExit):
            runner.parse_args(["--store", "postgres", "--postgres-connection", connection,
                               "--postgres-direct", "--postgres-container", "trust-pg"])


class XctestRunTests(unittest.TestCase):
    def test_injects_runner_environment_and_rebases_testroot_without_touching_test_target_env(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Build" / "Products" / "Trust.xctestrun"
            source.parent.mkdir(parents=True)
            target = root / "copied.xctestrun"
            original = {
                "TestConfigurations": [{
                    "TestTargets": [{
                        "BlueprintName": "TrustUITests",
                        "TestBundlePath": "__TESTROOT__/Debug-iphonesimulator/TrustUITests.xctest",
                        "EnvironmentVariables": {"PRESERVE": "existing"},
                        "TestingEnvironmentVariables": {"DO_NOT_WRITE_HERE": "1"},
                    }]
                }]
            }
            with source.open("wb") as output:
                plistlib.dump(original, output)
            runner.inject_runner_environment(source, target, {"TRUST_UI_TEST_BASE_URL": "http://127.0.0.1:5089"})
            with target.open("rb") as input_file:
                written = plistlib.load(input_file)
            test_target = written["TestConfigurations"][0]["TestTargets"][0]
            self.assertEqual(test_target["TestBundlePath"], str(source.parent / "Debug-iphonesimulator/TrustUITests.xctest"))
            self.assertEqual(test_target["EnvironmentVariables"], {
                "PRESERVE": "existing", "TRUST_UI_TEST_BASE_URL": "http://127.0.0.1:5089"
            })
            self.assertEqual(test_target["TestingEnvironmentVariables"], {"DO_NOT_WRITE_HERE": "1"})

    def test_format_one_flat_xctestrun_receives_runner_environment_and_rebases_testroot(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Products" / "Trust.xctestrun"
            source.parent.mkdir(parents=True)
            destination = root / "copy.xctestrun"
            with source.open("wb") as output:
                plistlib.dump({
                    "TrustUITests": {
                        "TestBundlePath": "__TESTROOT__/Debug-iphonesimulator/TrustUITests.xctest",
                        "EnvironmentVariables": {"KEEP": "yes"},
                        "TestingEnvironmentVariables": {"DO_NOT_CHANGE": "yes"},
                    },
                    "FormatVersion": 1,
                }, output)
            runner.inject_runner_environment(source, destination, {"TRUST_UI_PAIR_ROLE": "alice"})
            with destination.open("rb") as input_file:
                result = plistlib.load(input_file)
            target = result["TrustUITests"]
            self.assertEqual(target["TestBundlePath"], str(source.parent / "Debug-iphonesimulator/TrustUITests.xctest"))
            self.assertEqual(target["EnvironmentVariables"], {"KEEP": "yes", "TRUST_UI_PAIR_ROLE": "alice"})
            self.assertEqual(target["TestingEnvironmentVariables"], {"DO_NOT_CHANGE": "yes"})

    def test_optional_target_name_injects_only_requested_test_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Build" / "Trust.xctestrun"
            source.parent.mkdir(parents=True)
            destination = root / "copy.xctestrun"
            with source.open("wb") as output:
                plistlib.dump({
                    "TrustUITests": {"BlueprintName": "TrustUITests", "EnvironmentVariables": {"KEEP": "ui"}},
                    "TrustServiceUITests": {"BlueprintName": "TrustServiceUITests", "EnvironmentVariables": {"KEEP": "service"}},
                    "FormatVersion": 1,
                }, output)
            runner.inject_runner_environment(
                source, destination, {"TRUST_SERVICE_TEST_CASE": "apns"}, target_name="TrustServiceUITests"
            )
            with destination.open("rb") as input_file:
                result = plistlib.load(input_file)
        self.assertEqual(result["TrustUITests"]["EnvironmentVariables"], {"KEEP": "ui"})
        self.assertEqual(result["TrustServiceUITests"]["EnvironmentVariables"], {
            "KEEP": "service", "TRUST_SERVICE_TEST_CASE": "apns"
        })


class InventoryScopeTests(unittest.TestCase):
    def test_inventory_includes_core_and_standard_ui_targets_but_excludes_service_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ios = Path(temporary)
            for target, method in (
                ("TrustCoreTests", "testCoreMethod"),
                ("TrustUITests", "testUIFeature"),
                ("TrustServiceUITests", "testRealAPNsDelivery"),
            ):
                target_dir = ios / "Tests" / target
                target_dir.mkdir(parents=True)
                (target_dir / "Example.swift").write_text(f"    func {method}() {{}}\n", encoding="utf-8")
            with patch.object(runner, "IOS", ios):
                inventory = runner.source_test_inventory()
        self.assertEqual(inventory, {"testCoreMethod": 1, "testUIFeature": 1})


class HandoffOrchestrationTests(unittest.TestCase):
    def test_home_handoff_runs_a_b_a_serially_with_one_marker_and_locations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            harness = runner.Harness.__new__(runner.Harness)
            harness.logs = Path(temporary)
            harness.developer_dir = "/xcode"
            harness.evidence_mode = "memory"
            harness.location_devices = set()
            events = []

            def record_location(_developer_dir, udid, action, coordinates, *, required=False):
                events.append(("location", udid, action, coordinates, required))

            def record_run(case, udid, *, extra=None):
                events.append(("case", case, udid, extra))

            with patch.object(harness, "ensure_services", side_effect=lambda _path: events.append(("services",))), \
                 patch.object(runner, "location", side_effect=record_location), \
                 patch.object(harness, "run_real_case", side_effect=record_run):
                harness.run_handoff("sim-a", "sim-b")

        self.assertEqual(events[0], ("services",))
        self.assertEqual(events[1:3], [
            ("location", "sim-a", "set", "47.600000,-122.330000", True),
            ("location", "sim-b", "set", "47.620000,-122.330000", True),
        ])
        phases = events[3:]
        self.assertEqual([(event[1], event[2]) for event in phases], list(zip(runner.HANDOFF_CASES, ("sim-a", "sim-b", "sim-a"))))
        self.assertEqual({event[3]["TRUST_UI_HOME_HANDOFF_DEVICE_ID"] for event in phases}, {"trust-local-home-handoff-e2e"})
        self.assertEqual(harness.location_devices, {"sim-a", "sim-b"})


class SimulatorCreationTests(unittest.TestCase):
    @staticmethod
    def fixture_responses():
        runtimes = {
            "runtimes": [
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                    "version": "18.4", "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"name": "iPhone 17 Pro", "bundleIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                    "version": "26.5", "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"name": "iPhone 17 Pro", "bundleIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
                        {"name": "iPhone 17", "bundleIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"},
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
                    "version": "27.1", "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"name": "iPhone Duo", "bundleIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"}
                    ],
                },
            ]
        }
        types = {"devicetypes": [
            {"name": "iPhone 17 Pro", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
            {"name": "iPhone 17", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"},
        ]}
        return runtimes, types

    def test_chooses_newest_numeric_runtime_supporting_preferred_type_without_existing_devices(self) -> None:
        runtimes, types = self.fixture_responses()
        created = []
        create_calls = []

        def fake_simctl(_developer_dir, *args, **_kwargs):
            if args[:3] == ("list", "runtimes", "--json"):
                return subprocess.CompletedProcess(args, 0, json.dumps(runtimes), "")
            if args[:3] == ("list", "devicetypes", "--json"):
                return subprocess.CompletedProcess(args, 0, json.dumps(types), "")
            if args[0] == "create":
                create_calls.append(args)
                return subprocess.CompletedProcess(args, 0, f"00000000-0000-0000-0000-00000000000{len(created) + 1}", "")
            self.fail(f"Unexpected simctl call: {args}")

        with patch.object(runner, "simctl", side_effect=fake_simctl):
            udids = runner.create_devices("/xcode", 1, created.append)
        self.assertEqual(udids, created)
        self.assertEqual(len(udids), 1)
        # 27.1 sorts newest but supports only the uninstalled Duo device; Pro works on 26.5.
        self.assertEqual(created[0], "00000000-0000-0000-0000-000000000001")
        create_args = create_calls[0]
        self.assertEqual(create_args[2], "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
        self.assertEqual(create_args[3], "com.apple.CoreSimulator.SimRuntime.iOS-26-5")

    def test_falls_back_to_compatible_iphone_when_preferred_type_is_not_supported(self) -> None:
        runtimes, types = self.fixture_responses()
        runtimes["runtimes"] = [runtimes["runtimes"][2]]
        created = []
        create_calls = []

        def fake_simctl(_developer_dir, *args, **_kwargs):
            if args[:3] == ("list", "runtimes", "--json"):
                return subprocess.CompletedProcess(args, 0, json.dumps(runtimes), "")
            if args[:3] == ("list", "devicetypes", "--json"):
                types["devicetypes"].append({"name": "iPhone Duo", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"})
                return subprocess.CompletedProcess(args, 0, json.dumps(types), "")
            if args[0] == "create":
                create_calls.append(args)
                return subprocess.CompletedProcess(args, 0, "00000000-0000-0000-0000-000000000001", "")
            self.fail(f"Unexpected simctl call: {args}")

        with patch.object(runner, "simctl", side_effect=fake_simctl):
            runner.create_devices("/xcode", 1, created.append)
        create_args = create_calls[0]
        self.assertEqual(create_args[2], "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo")
        self.assertEqual(create_args[3], "com.apple.CoreSimulator.SimRuntime.iOS-27-1")
        self.assertEqual(len(created), 1)

    def test_partial_create_failure_keeps_first_device_in_ownership_callback(self) -> None:
        runtimes, types = self.fixture_responses()
        created = []
        create_count = 0

        def fake_simctl(_developer_dir, *args, **_kwargs):
            nonlocal create_count
            if args[:3] == ("list", "runtimes", "--json"):
                return subprocess.CompletedProcess(args, 0, json.dumps(runtimes), "")
            if args[:3] == ("list", "devicetypes", "--json"):
                return subprocess.CompletedProcess(args, 0, json.dumps(types), "")
            if args[0] == "create":
                create_count += 1
                if create_count == 2:
                    raise runner.RunnerError("simctl second create failed")
                return subprocess.CompletedProcess(args, 0, "00000000-0000-0000-0000-000000000001", "")
            self.fail(f"Unexpected simctl call: {args}")

        with patch.object(runner, "simctl", side_effect=fake_simctl):
            with self.assertRaises(runner.RunnerError):
                runner.create_devices("/xcode", 2, created.append)
        self.assertEqual(created, ["00000000-0000-0000-0000-000000000001"])


class ResultValidationTests(unittest.TestCase):
    def test_zero_skipped_and_failed_cases_are_rejected(self) -> None:
        path = Path("/tmp/not-created.xcresult")
        with self.assertRaises(runner.RunnerError):
            runner.validate_result({"passedTests": 0, "failedTests": 0, "skippedTests": 0, "totalTestCount": 0}, path)
        with self.assertRaises(runner.RunnerError):
            runner.validate_result({"passedTests": 0, "failedTests": 0, "skippedTests": 1, "totalTestCount": 1}, path)
        with self.assertRaises(runner.RunnerError):
            runner.validate_result({"passedTests": 0, "failedTests": 1, "skippedTests": 0, "totalTestCount": 1}, path)

    def test_selected_case_requires_one_exact_pass_and_matching_test_name(self) -> None:
        path = Path("/tmp/not-created.xcresult")
        case = "testOfflinePeerRemovalReconcilesAfterRelaunchAndReconnect"
        passing = {"passedTests": 1, "failedTests": 0, "skippedTests": 0, "totalTestCount": 1}
        with patch.object(runner, "result_test_cases", return_value=[{
            "nodeType": "Test Case", "name": f"TrustUITests/TrustRealAPIFeatureTests/{case}()", "result": "Passed"
        }] ):
            runner.validate_single_case(passing, path, case, "unused")
        for summary in (
            {"passedTests": 0, "failedTests": 0, "skippedTests": 0, "totalTestCount": 0},
            {"passedTests": 0, "failedTests": 0, "skippedTests": 1, "totalTestCount": 1},
            {"passedTests": 0, "failedTests": 1, "skippedTests": 0, "totalTestCount": 1},
            {"passedTests": 2, "failedTests": 0, "skippedTests": 0, "totalTestCount": 2},
        ):
            with self.subTest(summary=summary), self.assertRaises(runner.RunnerError):
                runner.validate_single_case(summary, path, case, "unused")
        with patch.object(runner, "result_test_cases", return_value=[{
            "nodeType": "Test Case", "name": "TrustUITests/TrustRealAPIFeatureTests/testWrongCase()", "result": "Passed"
        }]):
            with self.assertRaises(runner.RunnerError):
                runner.validate_single_case(passing, path, case, "unused")

    def test_dynamic_source_inventory_partitions_all_discovered_real_api_cases(self) -> None:
        inventory = runner.source_test_inventory()
        standalone, handoff, paired = runner.all_lane_case_partition()
        self.assertEqual(set(inventory) & set(runner.ALL_REAL_CASES), set(runner.ALL_REAL_CASES))
        self.assertEqual(set(standalone) | set(handoff) | set(paired), set(runner.ALL_REAL_CASES))
        self.assertEqual(sum(map(len, (standalone, handoff, paired))), len(runner.ALL_REAL_CASES))
        self.assertIn("testOfflinePeerRemovalReconcilesAfterRelaunchAndReconnect", runner.ALL_REAL_CASES)
        self.assertIn("testDelayedHistoryFixtureCannotReappearAfterStopRemoveAndReconnect", runner.ALL_REAL_CASES)

    def test_direct_api_verifier_requires_exact_source_inventory_and_named_statuses(self) -> None:
        source = verifier.source_case_names()
        excluded = set(verifier.SERIAL_EXCLUSIONS)
        selected = set(source) - excluded
        nodes = [{
            "nodeType": "Test Case",
            "nodeIdentifier": f"TrustUITests/TrustRealAPIFeatureTests/{name}()",
            "result": "Passed" if name in verifier.DIRECT_PASS_CASES else "Skipped",
        } for name in sorted(selected)]
        summary = {
            "result": "Passed", "totalTestCount": len(selected),
            "passedTests": len(verifier.DIRECT_PASS_CASES),
            "skippedTests": len(verifier.DIRECT_SKIP_REASONS), "failedTests": 0,
        }
        report = verifier.verify(source, summary, {"testNodes": nodes})
        self.assertIn(f"{len(verifier.DIRECT_PASS_CASES)} expected passes", report)
        self.assertIn("17 named proxy/role skips", report)
        self.assertIn("not StoreKit evidence", report)
        for invalid_summary in (
            {**summary, "totalTestCount": 0},
            {**summary, "passedTests": 0},
            {**summary, "skippedTests": 0},
            {**summary, "failedTests": 1},
        ):
            with self.subTest(summary=invalid_summary), self.assertRaises(verifier.VerificationError):
                verifier.verify(source, invalid_summary, {"testNodes": nodes})
        wrong_case_tree = {"testNodes": nodes[:-1] + [{
            "nodeType": "Test Case", "nodeIdentifier": "TrustUITests/TrustRealAPIFeatureTests/testWrong()",
            "result": "Passed",
        }]}
        with self.assertRaises(verifier.VerificationError):
            verifier.verify(source, summary, wrong_case_tree)


class SubprocessCleanupTests(unittest.TestCase):
    def test_owned_process_group_is_terminated(self) -> None:
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], start_new_session=True)
        runner.stop_process(process, process_group=True)
        self.assertIsNotNone(process.poll())

    def test_active_listener_is_not_mistaken_for_an_available_service_port(self) -> None:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            self.assertFalse(runner.safe_port_available(port))
        finally:
            listener.close()

    def test_port_probe_enables_reuseaddr_for_closed_time_wait_sockets(self) -> None:
        class FakeSocket:
            def __init__(self) -> None:
                self.options = []
            def setsockopt(self, *args) -> None:
                self.options.append(args)
            def bind(self, _address) -> None:
                return None
            def close(self) -> None:
                return None

        fake = FakeSocket()
        with patch.object(runner.socket, "socket", return_value=fake):
            self.assertTrue(runner.safe_port_available(54321))
        self.assertIn((socket.SOL_SOCKET, socket.SO_REUSEADDR, 1), fake.options)


if __name__ == "__main__":
    unittest.main()
