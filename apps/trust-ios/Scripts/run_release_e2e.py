#!/usr/bin/env python3
"""Repeatable local iOS release E2E orchestration.

Builds the Trust scheme once, then runs selected XCTest cases from the copied
.xctestrun with runner environment injected under TestTargets[].EnvironmentVariables.
API-backed lanes use a fresh Development API at 127.0.0.1:5090 and the fixed
loopback race proxy at 127.0.0.1:5089. Persistence is Memory by default or a
fresh disposable PostgreSQL database per API session when explicitly selected.
Cleanup is scoped to simulator, service, and database resources created here.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
import plistlib
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / "apps/trust-ios"
API_PROJECT = ROOT / "apps/trust-api/TrustApi.csproj"
PROXY = ROOT / "apps/trust-api/scripts/trust_ui_race_proxy.py"
PAIR_CONTROLLER = IOS / "Scripts/trust_pair_location_controller.py"
API_URL = "http://127.0.0.1:5090"
PROXY_URL = "http://127.0.0.1:5089"
DEFAULT_DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
HANDOFF_CASES = (
    "testSameAccountHomeHandoffOwnerSetsHome",
    "testSameAccountHomeHandoffFirstUseDeviceTakesOver",
    "testSameAccountHomeHandoffPreviousOwnerDetectsTakeoverAndClear",
)
PAIR_CASE = "testPairedRequestAcceptAndPresenceGrantRole"
TEST_SOURCE = IOS / "Tests/TrustUITests/TrustRealAPIFeatureTests.swift"
FAULT_CASE_CANDIDATES = (
    "testLatePhoneResponsesAfterEditPreserveRetryWithoutOpeningCodeOrHome",
    "testManualHomeChoicesReachServerAndRetirePreviousNotice",
    "testAdultAgeGateAppleExchangeFailureCanRetryThroughTransactionLinkIntoOnboarding",
    "testAppTransactionRetryKeepsRequestsClosedThenRecoversAcrossRelaunch",
    "testStopRemainsOffAcrossStaleCircleResponseAndRelaunch",
    "testRemoveStaysAbsentAfterStaleCircleResponseAndRelaunch",
    "testStopAllFailureDoesNotPartiallyStopAndRetryPersistsAfterRelaunch",
    "testDelayedLookResponseIsDiscardedAfterReplacementRelationship",
    "testDelayedHistoryFixtureCannotReappearAfterStopRemoveAndReconnect",
    "testDelayedHistoryFixtureStaysClosedWhenConsentRefreshIsOffline",
    "testDelayedLookStaysClosedWhenConsentRefreshIsOffline",
    "testOfflinePeerRemovalReconcilesAfterRelaunchAndReconnect",
    "testAddPersonCanRetrySameQueryAndConfirmedSendSurvivesFailedLookup",
    "testFailedAcceptKeepsNamedRequestAndOtherRequestsAvailableForRetry",
)
ALL_REAL_CASES = tuple(re.findall(r"^\s+func\s+(test[A-Za-z0-9_]+)\s*\(", TEST_SOURCE.read_text(encoding="utf-8"), re.MULTILINE))
STANDARD_OPT_IN_SETUP_SKIP_CASES = frozenset({
    "testOptInDuoFoldTransitionPreservesPeopleNavigation",
    "testOptInDuoFoldPreservesFocusedAddPersonInput",
})
EXPECTED_STANDARD_SKIP_CASES = frozenset(ALL_REAL_CASES) | STANDARD_OPT_IN_SETUP_SKIP_CASES
FAULT_CASES = tuple(FAULT_CASE_CANDIDATES)
REVIEW_FIXTURE_CASES = {
    PAIR_CASE,
    "testAlwaysSharedLocationHistoryRendersAndClearsAfterStop",
    "testDelayedHistoryFixtureCannotReappearAfterStopRemoveAndReconnect",
    "testDelayedHistoryFixtureStaysClosedWhenConsentRefreshIsOffline",
}
TEST_CLASS = "TrustUITests/TrustRealAPIFeatureTests"


class RunnerError(RuntimeError):
    pass


def run(command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None,
        capture: bool = True, check: bool = True, timeout: float | None = None) -> subprocess.CompletedProcess[str]:
    process = subprocess.Popen(
        command, cwd=cwd, env=env, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except BaseException:
        stop_process(process, process_group=True)
        raise
    result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    if check and result.returncode:
        detail = (result.stderr or result.stdout or "").strip()
        raise RunnerError(f"Command failed ({result.returncode}): {' '.join(command)}\n{detail[-6000:]}")
    return result


def safe_port_available(port: int) -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # Closed proxy connections can leave TIME_WAIT sockets; they are not live
    # services and must not make a completed cleanup look like an occupied port.
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def assert_ports_free() -> None:
    occupied = [port for port in (5089, 5090) if not safe_port_available(port)]
    if occupied:
        raise RunnerError(
            f"Refusing to touch occupied loopback port(s) {', '.join(map(str, occupied))}. "
            "Stop the service yourself or choose another time; this runner never kills unknown processes."
        )


def wait_for_ports_free(timeout: float = 8.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if all(safe_port_available(port) for port in (5089, 5090)):
            return True
        time.sleep(0.2)
    return all(safe_port_available(port) for port in (5089, 5090))


def parse_pg_connection(connection: str) -> tuple[dict[str, str], list[str]]:
    """Parse a deliberately narrow local Npgsql connection format."""
    pieces: list[str] = []
    start = 0
    quote: str | None = None
    for index, character in enumerate(connection):
        if quote:
            if character == quote:
                # Npgsql doubles the active quote character inside quoted values.
                if index + 1 < len(connection) and connection[index + 1] == quote:
                    continue
                quote = None
        elif character in "'\"{}":
            quote = "}" if character == "{" else (None if character == "}" else character)
        elif character == ";":
            pieces.append(connection[start:index].strip())
            start = index + 1
    if quote:
        raise RunnerError("Malformed PostgreSQL connection string quoting.")
    pieces.append(connection[start:].strip())
    values: dict[str, str] = {}
    raw_pieces: list[str] = []
    for piece in pieces:
        if not piece:
            continue
        if "=" not in piece:
            raise RunnerError("Malformed PostgreSQL connection string; expected key=value pairs.")
        key, raw_value = piece.split("=", 1)
        key = key.strip().lower()
        value = raw_value.strip()
        if len(value) >= 2 and ((value[0], value[-1]) in (("'", "'"), ('"', '"'), ("{", "}"))):
            quote_char = value[0]
            value = value[1:-1].replace(quote_char * 2, quote_char)
        values[key] = value
        raw_pieces.append(piece)
    allowed = {"host", "port", "database", "username", "password"}
    unknown = set(values) - allowed
    if unknown:
        raise RunnerError("PostgreSQL connection options are restricted to Host, Port, Database, Username, and Password.")
    if len(values) != len(raw_pieces):
        raise RunnerError("Duplicate PostgreSQL connection options are not allowed.")
    normalized = values
    host = normalized.get("host", "").strip().lower()
    if host not in ("127.0.0.1", "localhost", "::1"):
        raise RunnerError("PostgreSQL host must be 127.0.0.1, localhost, or ::1.")
    try:
        port = int(normalized.get("port", "5432"))
    except ValueError as exc:
        raise RunnerError("PostgreSQL port must be an integer.") from exc
    if port not in (5433, 5434, 5435):
        raise RunnerError("PostgreSQL port must be one of the reserved local test ports 5433, 5434, or 5435.")
    for key in ("database", "username", "password"):
        if not normalized.get(key):
            raise RunnerError(f"PostgreSQL connection string is missing {key}.")
    for key in ("database", "username", "password"):
        if not re.fullmatch(r"[A-Za-z0-9_.~-]{1,128}", normalized[key]):
            raise RunnerError(f"PostgreSQL {key} may contain only letters, numbers, dot, underscore, tilde, and hyphen.")
    normalized["port"] = str(port)
    return normalized, raw_pieces


def connection_with_database(connection: str, database: str) -> str:
    # Database identifiers are generated by this script and constrained below.
    if not re.fullmatch(r"trust_e2e_[0-9]+_[a-f0-9]{10}", database):
        raise RunnerError("Refusing to use a non-runner-generated temporary database name.")
    fields, _ = parse_pg_connection(connection)
    fields["database"] = database
    return ";".join(f"{key.title()}={fields[key]}" for key in ("host", "port", "database", "username", "password"))


def validate_container_mapping(container: str, postgres_port: int) -> None:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", container):
        raise RunnerError("PostgreSQL container name contains unsupported characters.")
    result = run(["docker", "inspect", "--format", "{{json .NetworkSettings.Ports}}", container], timeout=30)
    try:
        ports = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RunnerError("Could not inspect the selected PostgreSQL container port mapping.") from exc
    if not isinstance(ports, dict):
        raise RunnerError("Selected container has no inspectable published PostgreSQL port.")
    for mappings in ports.values():
        if mappings and (not isinstance(mappings, list) or any(
            not isinstance(binding, dict) or binding.get("HostIp") not in ("127.0.0.1", "::1")
            for binding in mappings
        )):
            raise RunnerError("Every published port on the selected container must be bound to loopback only.")
    bindings = ports.get("5432/tcp") or []
    if not bindings or any(
        not isinstance(binding, dict)
        or str(binding.get("HostPort")) != str(postgres_port)
        or binding.get("HostIp") not in ("127.0.0.1", "::1")
        for binding in bindings
    ):
        raise RunnerError("Selected container must map PostgreSQL 5432 only to the supplied loopback port.")


def http_json(url: str, timeout: float = 2.0) -> dict[str, Any]:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        value = json.load(response)
    if not isinstance(value, dict):
        raise RunnerError(f"Unexpected JSON from {url}")
    return value


def wait_for_services(api: subprocess.Popen[str], proxy: subprocess.Popen[str], timeout: int = 45) -> None:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        if api.poll() is not None:
            raise RunnerError("Development API exited during startup.")
        if proxy.poll() is not None:
            raise RunnerError("Fault proxy exited during startup.")
        try:
            caps = http_json(API_URL + "/api/v1/local-test-capabilities")
            if caps.get("developmentOtpWithoutSms") is not True:
                raise RunnerError("API did not confirm Development OTP without SMS.")
            # Verify the public test endpoint is actually the runner-owned proxy.
            state = http_json(PROXY_URL + "/__test/state")
            if not isinstance(state, dict):
                raise RunnerError("Fault proxy state endpoint returned invalid data.")
            return
        except (OSError, ValueError, urllib.error.URLError) as exc:
            last_error = exc
            time.sleep(0.4)
    raise RunnerError(f"Local API/proxy did not become ready in {timeout}s: {last_error}")


@dataclass
class Services:
    api: subprocess.Popen[str]
    proxy: subprocess.Popen[str]

    def stop(self) -> None:
        stop_process(self.proxy, process_group=True)
        stop_process(self.api, process_group=True)


@dataclass
class RunnerDatabase:
    container: str | None
    name: str
    connection: str
    username: str
    password: str
    port: int
    developer_dir: str
    direct: bool = False
    owned_by_runner: bool = False

    @classmethod
    def create(cls, connection: str, container: str | None, developer_dir: str, *, direct: bool = False) -> "RunnerDatabase":
        fields, _ = parse_pg_connection(connection)
        port = int(fields["port"])
        if direct:
            if container:
                raise RunnerError("Do not combine --postgres-direct with a Docker container.")
        else:
            if not container:
                raise RunnerError("Docker-backed PostgreSQL requires an explicit container.")
            validate_container_mapping(container, port)
        name = f"trust_e2e_{os.getpid()}_{uuid.uuid4().hex[:10]}"
        record = cls(container, name, connection, fields["username"], fields["password"], port,
                     developer_dir, direct, owned_by_runner=True)
        record._psql(f'CREATE DATABASE "{name}"')
        return record

    def _psql(self, sql: str) -> None:
        if not self.owned_by_runner:
            raise RunnerError("Refusing PostgreSQL admin operation on a database not created by this runner instance.")
        if not re.fullmatch(r"trust_e2e_[0-9]+_[a-f0-9]{10}", self.name):
            raise RunnerError("Refusing PostgreSQL admin operation on a database without the runner-generated name pattern.")
        env = dict(os.environ, DEVELOPER_DIR=self.developer_dir, PGPASSWORD=self.password,
                   PGCONNECT_TIMEOUT="3", PGOPTIONS="-c statement_timeout=15000")
        psql = ["psql", "--host", "127.0.0.1", "--port", str(self.port),
                "--username", self.username, "--dbname", "postgres",
                "--set", "ON_ERROR_STOP=1", "--command", sql]
        if self.direct:
            fields, _ = parse_pg_connection(self.connection)
            psql[2] = fields["host"]
            run(psql, env=env, timeout=30)
        else:
            if not self.container:
                raise RunnerError("Docker-backed PostgreSQL has no explicit container.")
            command = ["docker", "exec", "--env", "PGPASSWORD", self.container, "psql",
                       "--host", "127.0.0.1", "--port", "5432", "--username", self.username,
                       "--dbname", "postgres", "--set", "ON_ERROR_STOP=1", "--command", sql]
            run(command, env=env, timeout=30)

    def drop(self) -> None:
        if not re.fullmatch(r"trust_e2e_[0-9]+_[a-f0-9]{10}", self.name):
            raise RunnerError("Refusing to drop a database without the runner-generated prefix.")
        self._psql(f'DROP DATABASE IF EXISTS "{self.name}" WITH (FORCE)')


def stop_process(process: subprocess.Popen[str] | None, *, process_group: bool = False) -> None:
    if process is None or (process.poll() is not None and not process_group):
        return
    try:
        if process_group:
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
    except ProcessLookupError:
        return
    try:
        if process.poll() is None:
            process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        pass
    if process_group:
        # dotnet run can exit while its app child remains in the owned process group.
        time.sleep(0.4)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    elif process.poll() is None:
        process.kill()
    if process.poll() is None:
        process.wait(timeout=5)


def start_services(log_dir: Path, developer_dir: str, *, postgres_connection: str | None = None,
                   allow_review_fixture: bool = False,
                   extra_api_environment: dict[str, str] | None = None) -> Services:
    assert_ports_free()
    env = os.environ.copy()
    # Never inherit APNs provider secrets into the shared baseline environment:
    # the proxy receives this baseline and must not see API credentials.
    for key in list(env):
        if key.casefold().startswith("apns__"):
            env.pop(key)
    env.update({
        "DEVELOPER_DIR": developer_dir,
        "ASPNETCORE_ENVIRONMENT": "Development",
        "ASPNETCORE_URLS": API_URL,
        "Trust__Store": "postgres" if postgres_connection else "memory",
        "Trust__SeedReviewCircle": "false",
        "Auth__AllowDevelopmentSignIn": "true",
        "Auth__SigningKey": "development-signing-key-32bytes-min!!",
        "StoreKit__AllowReviewUnlock": "true" if allow_review_fixture else "false",
    })
    if postgres_connection:
        env["ConnectionStrings__Postgres"] = postgres_connection
    api_env = env.copy()
    api_env.update(extra_api_environment or {})
    api_log = open(log_dir / "api.log", "w", encoding="utf-8")
    try:
        api = subprocess.Popen(["dotnet", "run", "--no-launch-profile", "--project", str(API_PROJECT)],
                               cwd=ROOT, env=api_env, stdout=api_log, stderr=subprocess.STDOUT, text=True,
                               start_new_session=True)
    finally:
        api_log.close()
    proxy_env = env.copy()
    try:
        proxy_log = open(log_dir / "proxy.log", "w", encoding="utf-8")
        try:
            proxy = subprocess.Popen([sys.executable, str(PROXY)], cwd=ROOT, env=proxy_env,
                                     stdout=proxy_log, stderr=subprocess.STDOUT, text=True,
                                     start_new_session=True)
        finally:
            proxy_log.close()
    except BaseException:
        stop_process(api, process_group=True)
        wait_for_ports_free()
        raise
    try:
        wait_for_services(api, proxy)
        return Services(api, proxy)
    except BaseException:
        stop_process(proxy, process_group=True)
        stop_process(api, process_group=True)
        wait_for_ports_free()
        raise


def xctest_path(case: str) -> str:
    return f"{TEST_CLASS}/{case}"


def inject_runner_environment(source: Path, destination: Path, values: dict[str, str],
                              target_name: str = "TrustUITests") -> None:
    with source.open("rb") as stream:
        data = plistlib.load(stream)

    def rebase_testroot(value: Any) -> Any:
        if isinstance(value, str):
            return value.replace("__TESTROOT__", str(source.parent))
        if isinstance(value, list):
            return [rebase_testroot(item) for item in value]
        if isinstance(value, dict):
            return {key: rebase_testroot(item) for key, item in value.items()}
        return value

    data = rebase_testroot(data)
    targets: list[dict[str, Any]] = []
    # Xcode's format 1 stores target dictionaries at the top level, while test
    # plans use format 2's nested TestConfigurations/TestTargets representation.
    for name, target in data.items():
        if isinstance(target, dict) and (name == target_name or target.get("BlueprintName") == target_name):
            targets.append(target)
    for config in data.get("TestConfigurations", []):
        for target in config.get("TestTargets", []):
            if target.get("BlueprintName") == target_name or target_name in str(target.get("TestBundlePath", "")):
                targets.append(target)
    if not targets:
        raise RunnerError(f"Could not find {target_name} runner target in {source.name}; refusing incorrect env injection.")
    for target in targets:
        env = target.setdefault("EnvironmentVariables", {})
        if not isinstance(env, dict):
            raise RunnerError("Unexpected .xctestrun EnvironmentVariables structure.")
        env.update(values)
    with destination.open("wb") as stream:
        plistlib.dump(data, stream, sort_keys=False)


def result_summary(result_bundle: Path, developer_dir: str) -> dict[str, Any]:
    command = ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle)]
    output = run(command, env=dict(os.environ, DEVELOPER_DIR=developer_dir)).stdout
    try:
        value = json.loads(output)
    except json.JSONDecodeError as exc:
        raise RunnerError(f"xcresult summary is not JSON for {result_bundle}: {exc}") from exc
    return value


def result_test_cases(result_bundle: Path, developer_dir: str) -> list[dict[str, Any]]:
    command = ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result_bundle)]
    output = run(command, env=dict(os.environ, DEVELOPER_DIR=developer_dir)).stdout
    try:
        value = json.loads(output)
    except json.JSONDecodeError as exc:
        raise RunnerError(f"xcresult test tree is not JSON for {result_bundle}: {exc}") from exc
    cases: list[dict[str, Any]] = []

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            kind = str(node.get("nodeType", "")).lower().replace(" ", "")
            if kind == "testcase":
                cases.append(node)
            for key in ("testNodes", "children", "nodes"):
                children = node.get(key)
                if isinstance(children, list):
                    for child in children:
                        visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)

    visit(value)
    if not cases:
        raise RunnerError(f"xcresult contains no test-case nodes: {result_bundle}")
    return cases


def source_test_inventory() -> Counter[str]:
    methods: Counter[str] = Counter()
    test_roots = (IOS / "Tests/TrustCoreTests", IOS / "Tests/TrustUITests")
    for source in (file for root in test_roots if root.exists() for file in root.rglob("*.swift")):
        for method in re.findall(r"^\s+func\s+(test[A-Za-z0-9_]+)\s*\(", source.read_text(encoding="utf-8"), re.MULTILINE):
            methods[method] += 1
    return methods


def all_lane_case_partition() -> tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    """Partition every discovered case into standalone, serial handoff, or paired execution."""
    paired = (PAIR_CASE,)
    special = set(HANDOFF_CASES) | set(paired)
    standalone = tuple(case for case in ALL_REAL_CASES if case not in special)
    if len(set(ALL_REAL_CASES)) != len(ALL_REAL_CASES) or set(standalone) | special != set(ALL_REAL_CASES):
        raise RunnerError("E2E case partition does not cover each discovered source case exactly once.")
    if set(standalone) & special:
        raise RunnerError("E2E case partition contains duplicate execution ownership.")
    return standalone, HANDOFF_CASES, paired


def test_case_name(node: dict[str, Any]) -> str:
    identifier = str(node.get("name") or node.get("nodeIdentifier") or node.get("testIdentifier") or "")
    match = re.search(r"(test[A-Za-z0-9_]+)(?:\(.*\))?$", identifier)
    return match.group(1) if match else identifier


def nested_tests(summary: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = summary.get(key, [])
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, int):
        return []
    return []


def summary_count(summary: dict[str, Any], key: str, list_key: str) -> int:
    count = summary.get(key)
    if isinstance(count, int):
        return count
    return len(nested_tests(summary, list_key))


def validate_result(summary: dict[str, Any], result_bundle: Path, *, allow_skips: bool = False) -> None:
    passed = summary_count(summary, "passedTests", "passedTests")
    failed = summary_count(summary, "failedTests", "failedTests")
    skipped = summary_count(summary, "skippedTests", "skippedTests")
    executed = summary.get("totalTestCount")
    if not isinstance(executed, int):
        executed = passed + failed + skipped
    if executed == 0:
        raise RunnerError(f"No tests executed in {result_bundle}")
    if failed:
        raise RunnerError(f"{failed} XCTest failure(s) in {result_bundle}; see its xcresult bundle.")
    if skipped and not allow_skips:
        raise RunnerError(f"{skipped} skipped test(s) in {result_bundle}; no allowlist applies.")
    print(f"  xcresult: {result_bundle} — {passed} passed, {skipped} skipped, {failed} failed", flush=True)


def validate_standard_result_data(summary: dict[str, Any], result_bundle: Path,
                                  actual_nodes: list[dict[str, Any]]) -> None:
    """Validate a completed standard-lane result against source and exact setup skips."""
    validate_result(summary, result_bundle, allow_skips=True)
    expected = source_test_inventory()
    actual = Counter(test_case_name(node) for node in actual_nodes)
    passed = summary_count(summary, "passedTests", "passedTests")
    failed = summary_count(summary, "failedTests", "failedTests")
    skipped = summary_count(summary, "skippedTests", "skippedTests")
    total = summary.get("totalTestCount")
    expected_total = sum(expected.values())
    if total != expected_total or len(actual_nodes) != expected_total or actual != expected:
        raise RunnerError(
            f"Standard lane test inventory mismatch: source={expected_total}, xcresult total={total!r}, "
            f"xcresult cases={len(actual_nodes)}; missing={list((expected - actual).elements())[:12]}, "
            f"unexpected={list((actual - expected).elements())[:12]}. See {result_bundle}."
        )
    skipped_names = Counter(test_case_name(node) for node in actual_nodes
                            if str(node.get("result", "")).lower() == "skipped")
    expected_skips = Counter(EXPECTED_STANDARD_SKIP_CASES)
    unexpected = list((skipped_names - expected_skips).elements())
    missing = list((expected_skips - skipped_names).elements())
    if unexpected or missing:
        raise RunnerError(
            f"Unexpected standard-lane skips in {result_bundle}: unexpected={unexpected}, missing={missing}."
        )
    if failed or skipped != len(EXPECTED_STANDARD_SKIP_CASES) or passed + skipped != expected_total:
        raise RunnerError(
            f"Standard lane expected {expected_total - len(EXPECTED_STANDARD_SKIP_CASES)} passes and "
            f"{len(EXPECTED_STANDARD_SKIP_CASES)} named setup skips; got {passed} passed, "
            f"{skipped} skipped, {failed} failed. See {result_bundle}."
        )


def validate_standard_result(result_bundle: Path, developer_dir: str) -> dict[str, Any]:
    """Revalidate an existing completed standard xcresult without rerunning XCTest."""
    summary = result_summary(result_bundle, developer_dir)
    validate_standard_result_data(summary, result_bundle, result_test_cases(result_bundle, developer_dir))
    return summary


def validate_single_case(summary: dict[str, Any], result_bundle: Path, case: str,
                         developer_dir: str) -> None:
    passed = summary_count(summary, "passedTests", "passedTests")
    failed = summary_count(summary, "failedTests", "failedTests")
    skipped = summary_count(summary, "skippedTests", "skippedTests")
    total = summary.get("totalTestCount")
    if (passed, failed, skipped, total) != (1, 0, 0, 1):
        raise RunnerError(
            f"Expected exactly one pass and zero skips/failures for {case}; got "
            f"{passed} passed, {skipped} skipped, {failed} failed, total={total!r}: {result_bundle}"
        )
    cases = result_test_cases(result_bundle, developer_dir)
    matching = [node for node in cases if test_case_name(node) == case]
    if len(matching) != 1 or str(matching[0].get("result", "")).lower() not in ("passed", "success"):
        raise RunnerError(f"xcresult did not report {case} as one passing test case: {result_bundle}")


def xcode_test(xctestrun: Path, destination: str, result_bundle: Path, developer_dir: str,
               only: list[str] | None = None, expected_standard_skips: int | None = None) -> dict[str, Any]:
    result_bundle.parent.mkdir(parents=True, exist_ok=True)
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(xctestrun),
               "-destination", destination, "-resultBundlePath", str(result_bundle)]
    if only:
        for case in only:
            command.extend(["-only-testing", xctest_path(case)])
    environment = dict(os.environ, DEVELOPER_DIR=developer_dir)
    proc = run(command, cwd=IOS, env=environment, capture=True, check=False)
    log_path = result_bundle.with_suffix(result_bundle.suffix + ".log")
    log_path.write_text((proc.stdout or "") + (proc.stderr or ""), encoding="utf-8")
    print(f"  xcodebuild log: {log_path}", flush=True)
    if proc.returncode:
        # xcresult is still parsed for concrete test counts and retained for diagnosis.
        if not result_bundle.exists():
            raise RunnerError(f"xcodebuild exited {proc.returncode}; no xcresult was produced. Log: {log_path}")
    summary = result_summary(result_bundle, developer_dir)
    validate_result(summary, result_bundle, allow_skips=expected_standard_skips is not None)
    if expected_standard_skips is not None and summary_count(summary, "skippedTests", "skippedTests") != expected_standard_skips:
        raise RunnerError(
            f"Standard lane expected {expected_standard_skips} setup skips; got "
            f"{summary_count(summary, 'skippedTests', 'skippedTests')}. See {result_bundle}."
        )
    if proc.returncode:
        raise RunnerError(f"xcodebuild exited {proc.returncode}; see {result_bundle} and {log_path}.")
    return summary


def test_dest(udid: str) -> str:
    if not re.fullmatch(r"[A-Fa-f0-9-]{20,40}", udid):
        raise RunnerError(f"Invalid simulator UDID: {udid}")
    return f"platform=iOS Simulator,id={udid}"


def simctl(developer_dir: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["xcrun", "simctl", *args], env=dict(os.environ, DEVELOPER_DIR=developer_dir), check=check)


def create_devices(developer_dir: str, count: int, on_created: Any | None = None) -> list[str]:
    def version_key(value: str) -> tuple[int, ...]:
        match = re.fullmatch(r"(\d+(?:\.\d+)*)", value)
        if not match:
            return ()
        return tuple(int(part) for part in match.group(1).split("."))

    runtime_data = json.loads(simctl(developer_dir, "list", "runtimes", "--json").stdout)
    runtime_entries = [
        entry for entry in runtime_data.get("runtimes", [])
        if entry.get("isAvailable") is True
        and str(entry.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
        and version_key(str(entry.get("version", "")))
    ]
    types = json.loads(simctl(developer_dir, "list", "devicetypes", "--json").stdout).get("devicetypes", [])
    iphone_types = [
        entry for entry in types
        if entry.get("name", "").startswith("iPhone") and isinstance(entry.get("identifier"), str)
    ]
    if not iphone_types:
        raise RunnerError("No iPhone simulator device type is installed.")

    def supported_ids(runtime: dict[str, Any]) -> set[str]:
        raw = runtime.get("supportedDeviceTypes", [])
        ids: set[str] = set()
        if isinstance(raw, list):
            for item in raw:
                if isinstance(item, str):
                    ids.add(item)
                elif isinstance(item, dict):
                    for key in ("identifier", "bundleIdentifier"):
                        value = item.get(key)
                        if isinstance(value, str):
                            ids.add(value)
        return ids

    # Prefer the reference iPhone 17 Pro when any installed runtime supports it.
    # Otherwise choose a compatible installed iPhone type, still on the newest
    # numerically-versioned runtime that supports that type. Existing simulator
    # inventory is deliberately irrelevant: only new runner-owned devices count.
    preferred = next((entry for entry in iphone_types if entry.get("name") == "iPhone 17 Pro"), None)
    type_candidates = ([preferred] if preferred else []) + [entry for entry in iphone_types if entry is not preferred]
    candidates = []
    for device_type in type_candidates:
        compatible = [runtime for runtime in runtime_entries if device_type["identifier"] in supported_ids(runtime)]
        if compatible:
            runtime = max(compatible, key=lambda item: version_key(str(item["version"])))
            candidates.append((device_type, runtime))
            if preferred and device_type is preferred:
                break
    if not candidates:
        raise RunnerError("No available iOS runtime supports an installed iPhone simulator device type.")
    iphone, selected_runtime = candidates[0]
    runtime = selected_runtime["identifier"]
    iphone = iphone["identifier"]
    udids: list[str] = []
    for index in range(count):
        name = f"Trust Release E2E {os.getpid()} {index + 1}"
        udid = simctl(developer_dir, "create", name, iphone, runtime).stdout.strip()
        if not re.fullmatch(r"[A-Fa-f0-9-]{20,40}", udid):
            raise RunnerError(f"simctl returned an invalid UDID while creating {name}.")
        udids.append(udid)
        if on_created:
            on_created(udid)
    return udids


def boot_devices(udids: list[str], developer_dir: str, started: set[str]) -> set[str]:
    data = json.loads(simctl(developer_dir, "list", "devices", "available", "--json").stdout)
    by_id = {device.get("udid"): device for devices in data.get("devices", {}).values() for device in devices}
    booted_by_runner: set[str] = set()
    for udid in udids:
        device = by_id.get(udid)
        if not device:
            raise RunnerError(f"Simulator {udid} is not available.")
        if device.get("state") != "Booted":
            simctl(developer_dir, "boot", udid)
            booted_by_runner.add(udid)
            started.add(udid)
    for udid in booted_by_runner:
        simctl(developer_dir, "bootstatus", udid, "-b")
    return booted_by_runner


def location(developer_dir: str, udid: str, *args: str, required: bool = False) -> None:
    result = simctl(developer_dir, "location", udid, *args, check=False)
    if required and result.returncode:
        raise RunnerError(f"Could not set simulator location for {udid}: {result.stderr.strip()}")


class Harness:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.interrupted = False
        self.owned_services: Services | None = None
        self.owned_database: RunnerDatabase | None = None
        self.evidence_mode = ""
        self.owned_devices: list[str] = []
        self.booted_devices: set[str] = set()
        self.location_devices: set[str] = set()
        self.controller: subprocess.Popen[str] | None = None
        self.child_processes: set[subprocess.Popen[str]] = set()
        self.cleanup_errors: list[str] = []
        self.old_handlers: dict[int, Any] = {}
        if args.output:
            self.logs = Path(args.output).expanduser().resolve()
            if self.logs.exists() and any(self.logs.iterdir()):
                raise RunnerError(f"Output directory is not empty; refusing to overwrite results: {self.logs}")
        else:
            self.logs = Path(f"/tmp/trust-release-e2e-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}")
        self.logs.mkdir(parents=True, exist_ok=True)
        self.developer_dir = args.developer_dir

    def signal_handler(self, signum: int, _frame: Any) -> None:
        self.interrupted = True
        raise KeyboardInterrupt(f"signal {signum}")

    def install_signal_handlers(self) -> None:
        for sig in (signal.SIGINT, signal.SIGTERM):
            self.old_handlers[sig] = signal.signal(sig, self.signal_handler)

    def cleanup(self) -> None:
        for process in list(self.child_processes):
            stop_process(process, process_group=True)
        self.child_processes.clear()
        if self.controller and self.controller.poll() is None:
            stop_process(self.controller, process_group=True)
        self.stop_services()
        for udid in self.location_devices:
            location(self.developer_dir, udid, "clear")
        for udid in self.booted_devices:
            simctl(self.developer_dir, "shutdown", udid, check=False)
        for udid in self.owned_devices:
            simctl(self.developer_dir, "delete", udid, check=False)
        for sig, handler in self.old_handlers.items():
            signal.signal(sig, handler)

    def prepare_devices(self, count: int) -> list[str]:
        if self.args.create_devices:
            created = create_devices(self.developer_dir, count, self.owned_devices.append)
            if count == 1:
                return self.owned_devices
            return created
        udids = [self.args.device] if count == 1 else [self.args.alice_device, self.args.bob_device]
        if not all(udids):
            raise RunnerError("Supply simulator UDIDs or pass --create-devices.")
        if len(set(udids)) != count:
            raise RunnerError("Each simulator role must use a distinct device.")
        return udids

    def ensure_services(self, case_dir: Path) -> None:
        if self.owned_services is None:
            connection = None
            if self.args.store == "postgres":
                self.owned_database = RunnerDatabase.create(
                    self.args.postgres_connection, self.args.postgres_container, self.developer_dir,
                    direct=self.args.postgres_direct,
                )
                connection = connection_with_database(self.args.postgres_connection, self.owned_database.name)
            evidence = "postgres (fresh disposable database)" if connection else "memory"
            if self.args.allow_review_fixture:
                evidence += "; synthetic Development review-unlock fixture enabled (not StoreKit evidence)"
            self.evidence_mode = evidence
            print(f"  Evidence mode: {evidence}", flush=True)
            try:
                self.owned_services = start_services(
                    case_dir, self.developer_dir, postgres_connection=connection,
                    allow_review_fixture=self.args.allow_review_fixture,
                )
            except BaseException:
                if self.owned_database:
                    self.owned_database.drop()
                    self.owned_database = None
                raise
        (case_dir / "evidence-mode.txt").write_text(self.evidence_mode + "\n", encoding="utf-8")

    def stop_services(self) -> None:
        if self.owned_services:
            try:
                with urllib.request.urlopen(PROXY_URL + "/__test/release", timeout=1):
                    pass
            except Exception:
                pass
            self.owned_services.stop()
            self.owned_services = None
            if not wait_for_ports_free():
                message = "owned API/proxy ports 5089/5090 did not become free after process-group shutdown"
                self.cleanup_errors.append(message)
                print(f"Cleanup incomplete: {message}", file=sys.stderr)
        if self.owned_database:
            database = self.owned_database
            self.owned_database = None
            try:
                database.drop()
            except (RunnerError, OSError, subprocess.SubprocessError) as exc:
                message = f"could not drop runner-owned database {database.name}: {exc}"
                self.cleanup_errors.append(message)
                print(f"Cleanup incomplete: {message}", file=sys.stderr)

    def run_real_case(self, case: str, udid: str, *, extra: dict[str, str] | None = None,
                      allow_standard_api_skips: bool = False) -> None:
        case_dir = self.logs / case
        case_dir.mkdir(parents=True, exist_ok=True)
        self.ensure_services(case_dir)
        (case_dir / "evidence-mode.txt").write_text(self.evidence_mode + "\n", encoding="utf-8")
        env = {"TRUST_UI_TEST_BASE_URL": PROXY_URL}
        env.update(extra or {})
        xctestrun = self.logs / f"runner-{case}.xctestrun"
        inject_runner_environment(self.args.xctestrun, xctestrun, env)
        bundle = case_dir / f"{case}.xcresult"
        summary = xcode_test(xctestrun, test_dest(udid), bundle, self.developer_dir, [case])
        validate_single_case(summary, bundle, case, self.developer_dir)

    def run_standard(self, udid: str) -> None:
        xctestrun = self.logs / "runner-standard.xctestrun"
        inject_runner_environment(self.args.xctestrun, xctestrun, {"TRUST_UI_TEST_BASE_URL": ""})
        bundle = self.logs / "standard-ui.xcresult"
        summary = xcode_test(xctestrun, test_dest(udid), bundle, self.developer_dir,
                             expected_standard_skips=len(EXPECTED_STANDARD_SKIP_CASES))
        validate_standard_result_data(summary, bundle, result_test_cases(bundle, self.developer_dir))

    def run_handoff(self, a: str, b: str) -> None:
        case_dir = self.logs / "same-account-home-handoff"
        case_dir.mkdir(parents=True, exist_ok=True)
        self.ensure_services(case_dir)
        (case_dir / "evidence-mode.txt").write_text(self.evidence_mode + "\n", encoding="utf-8")
        self.location_devices.update((a, b))
        location(self.developer_dir, a, "set", "47.600000,-122.330000", required=True)
        location(self.developer_dir, b, "set", "47.620000,-122.330000", required=True)
        device_id = "trust-local-home-handoff-e2e"
        for index, (case, udid) in enumerate(zip(HANDOFF_CASES, (a, b, a)), 1):
            self.run_real_case(case, udid, extra={"TRUST_UI_HOME_HANDOFF_DEVICE_ID": device_id})

    def run_paired(self, alice: str, bob: str) -> None:
        case_dir = self.logs / "paired-two-account"
        case_dir.mkdir(parents=True, exist_ok=True)
        self.ensure_services(case_dir)
        self.location_devices.update((alice, bob))
        location(self.developer_dir, alice, "set", "47.600000,-122.330000", required=True)
        location(self.developer_dir, bob, "set", "47.600000,-122.330000", required=True)
        pair_id = uuid.uuid4().hex[:8]
        controller_log = open(case_dir / "location-controller.log", "w", encoding="utf-8")
        self.controller = subprocess.Popen(
            [sys.executable, str(PAIR_CONTROLLER), "--pair-id", pair_id, "--device-udid", bob,
             "--timeout", str(self.args.pair_timeout)],
            cwd=ROOT, env=dict(os.environ, DEVELOPER_DIR=self.developer_dir),
            stdout=controller_log, stderr=subprocess.STDOUT, text=True, start_new_session=True,
        )
        results: list[tuple[subprocess.Popen[str], str, Path]] = []
        for role, udid in (("alice", alice), ("bob", bob)):
            role_dir = case_dir / role
            role_dir.mkdir(exist_ok=True)
            (role_dir / "evidence-mode.txt").write_text(self.evidence_mode + "\n", encoding="utf-8")
            xctestrun = self.logs / f"runner-paired-{role}.xctestrun"
            inject_runner_environment(self.args.xctestrun, xctestrun, {
                "TRUST_UI_TEST_BASE_URL": PROXY_URL,
                "TRUST_UI_PAIR_ROLE": role,
                "TRUST_UI_PAIR_ID": pair_id,
            })
            bundle = role_dir / f"paired-{role}.xcresult"
            command = ["xcodebuild", "test-without-building", "-xctestrun", str(xctestrun),
                       "-destination", test_dest(udid), "-resultBundlePath", str(bundle),
                       "-only-testing", xctest_path(PAIR_CASE)]
            log = open(role_dir / "xcodebuild.log", "w", encoding="utf-8")
            process = subprocess.Popen(command, cwd=IOS, env=dict(os.environ, DEVELOPER_DIR=self.developer_dir),
                                       stdout=log, stderr=subprocess.STDOUT, text=True, start_new_session=True)
            self.child_processes.add(process)
            results.append((process, role, bundle))
        failure: list[str] = []
        for process, role, bundle in results:
            try:
                code = process.wait(timeout=self.args.pair_timeout + 90)
            except subprocess.TimeoutExpired:
                self.child_processes.discard(process)
                stop_process(process, process_group=True)
                raise RunnerError(f"{role} paired XCTest exceeded the {self.args.pair_timeout + 90}s timeout.")
            else:
                self.child_processes.discard(process)
            if not bundle.exists():
                failure.append(f"{role} xcodebuild {code}, no xcresult")
                continue
            summary = result_summary(bundle, self.developer_dir)
            validate_result(summary, bundle)
            validate_single_case(summary, bundle, PAIR_CASE, self.developer_dir)
            if code:
                failure.append(f"{role} failed or skipped (exit {code})")
        if failure:
            stop_process(self.controller, process_group=True)
        else:
            controller_code = self.controller.wait(timeout=self.args.pair_timeout + 30)
            if controller_code:
                failure.append(f"location controller exited {controller_code}")
        if failure:
            raise RunnerError("Paired lane failure: " + "; ".join(failure))


def build_once(developer_dir: str, output: Path) -> Path:
    products = output / "build"
    products.mkdir(parents=True, exist_ok=True)
    command = ["xcodebuild", "build-for-testing", "-project", "Trust.xcodeproj", "-scheme", "Trust",
               "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(products),
               "CODE_SIGNING_ALLOWED=NO"]
    run(command, cwd=IOS, env=dict(os.environ, DEVELOPER_DIR=developer_dir), capture=False)
    candidates = list(products.glob("Build/Products/*.xctestrun"))
    if not candidates:
        raise RunnerError(f"build-for-testing succeeded but did not create an .xctestrun in {products}")
    # Standard scheme creates one run spec; reject ambiguity instead of picking arbitrarily.
    if len(candidates) != 1:
        raise RunnerError("Expected one xctestrun after the single build, found: " + ", ".join(map(str, candidates)))
    return candidates[0]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", choices=("standard", "real-api", "fault-matrix", "paired", "handoff", "all"),
                        default="standard")
    parser.add_argument("--case", choices=ALL_REAL_CASES, help="One real-API XCTest case; required by --lane real-api.")
    parser.add_argument("--device", help="Booted or bootable simulator UDID for single-device lanes.")
    parser.add_argument("--alice-device", help="Simulator UDID for Alice, paired or handoff lane.")
    parser.add_argument("--bob-device", help="Simulator UDID for Bob, paired or handoff lane.")
    parser.add_argument("--create-devices", action="store_true", help="Create named disposable iPhone simulators and delete only those devices at exit.")
    parser.add_argument("--pair-timeout", type=int, default=480)
    parser.add_argument("--store", choices=("memory", "postgres"), default="memory",
                        help="Development API persistence mode; PostgreSQL uses one fresh disposable database per API session.")
    parser.add_argument("--postgres-connection", default=os.environ.get("TRUST_E2E_POSTGRES_CONNECTION"),
                        help="Loopback-only PostgreSQL connection; may come from TRUST_E2E_POSTGRES_CONNECTION.")
    parser.add_argument("--postgres-container",
                        help="Explicit local Docker container whose loopback port mapping matches the connection.")
    parser.add_argument("--postgres-direct", action="store_true",
                        help="Use native psql against the supplied loopback PostgreSQL endpoint; create/drop only this run's generated database.")
    parser.add_argument("--allow-review-fixture", action="store_true",
                        help="Explicitly enable the Development-only synthetic review entitlement fixture; this is not StoreKit evidence.")
    parser.add_argument("--developer-dir", default=os.environ.get("DEVELOPER_DIR", DEFAULT_DEVELOPER_DIR))
    parser.add_argument("--output", help="New empty output directory; default creates a unique directory under /tmp.")
    parser.add_argument("--skip-build", action="store_true", help="Reuse --xctestrun from a prior build.")
    parser.add_argument("--xctestrun", type=Path, help="Existing .xctestrun required with --skip-build.")
    args = parser.parse_args(argv)
    if args.store == "postgres" and not args.postgres_direct and not args.postgres_container:
        args.postgres_container = os.environ.get("TRUST_E2E_POSTGRES_CONTAINER")
    if args.lane == "real-api" and not args.case:
        parser.error("--lane real-api requires --case")
    if args.lane == "real-api" and args.case in {PAIR_CASE, *HANDOFF_CASES}:
        parser.error("Paired and Home handoff cases must use --lane paired or --lane handoff so required phases are orchestrated.")
    if args.lane != "real-api" and args.case:
        parser.error("--case is valid only with --lane real-api")
    if args.skip_build and not args.xctestrun:
        parser.error("--skip-build requires --xctestrun")
    if not args.skip_build and args.xctestrun:
        parser.error("--xctestrun requires --skip-build")
    if args.pair_timeout < 120 or args.pair_timeout > 1800:
        parser.error("--pair-timeout must be between 120 and 1800 seconds")
    if args.store == "postgres":
        if not args.postgres_connection:
            parser.error("--store postgres requires --postgres-connection or TRUST_E2E_POSTGRES_CONNECTION")
        if args.postgres_direct and args.postgres_container:
            parser.error("--postgres-direct cannot be combined with --postgres-container")
        if not args.postgres_direct and not args.postgres_container:
            parser.error("--store postgres requires --postgres-container, or explicit --postgres-direct native psql mode")
        try:
            parse_pg_connection(args.postgres_connection)
        except RunnerError as exc:
            parser.error(str(exc))
    elif args.postgres_connection or args.postgres_container or args.postgres_direct:
        parser.error("PostgreSQL connection/container options require --store postgres")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        harness = Harness(args)
    except (RunnerError, OSError) as exc:
        print(f"E2E failed: {exc}", file=sys.stderr)
        return 1
    harness.install_signal_handlers()
    exit_code = 0
    try:
        requested_cases: set[str] = set()
        if args.lane == "real-api":
            requested_cases.add(args.case)
        elif args.lane == "fault-matrix":
            requested_cases.update(FAULT_CASES)
        elif args.lane == "paired":
            requested_cases.add(PAIR_CASE)
        elif args.lane == "handoff":
            requested_cases.update(HANDOFF_CASES)
        elif args.lane == "all":
            requested_cases.update(ALL_REAL_CASES)
        missing = sorted(requested_cases - set(ALL_REAL_CASES))
        if missing:
            raise RunnerError("Requested case(s) are not present in TrustRealAPIFeatureTests.swift: " + ", ".join(missing))
        requires_review_fixture = requested_cases & REVIEW_FIXTURE_CASES
        if requires_review_fixture and not args.allow_review_fixture:
            raise RunnerError(
                "This lane includes a synthetic review-unlock fixture case: " + ", ".join(sorted(requires_review_fixture))
                + ". Rerun with --allow-review-fixture to label it as fixture evidence; it does not prove StoreKit."
            )
        if args.skip_build:
            source_xctestrun = args.xctestrun.expanduser().resolve()
            if not source_xctestrun.is_file():
                raise RunnerError(f"xctestrun does not exist: {source_xctestrun}")
        else:
            source_xctestrun = build_once(args.developer_dir, harness.logs)
        args.xctestrun = source_xctestrun

        lane = args.lane
        singles_needed = lane in ("standard", "real-api", "fault-matrix", "all")
        pairs_needed = lane in ("paired", "handoff", "all")
        single = harness.prepare_devices(1) if singles_needed and not args.create_devices else []
        pair = harness.prepare_devices(2) if pairs_needed and not args.create_devices else []
        if args.create_devices:
            count = 2 if pairs_needed else 1
            create_devices(args.developer_dir, count, harness.owned_devices.append)
            single = harness.owned_devices[:1] if singles_needed else []
            pair = harness.owned_devices[:2] if pairs_needed else []
        requested = list(dict.fromkeys(single + pair))
        boot_devices(requested, args.developer_dir, harness.booted_devices)
        if lane == "standard":
            harness.run_standard(single[0])
        elif lane == "real-api":
            harness.run_real_case(args.case, single[0])
        elif lane == "fault-matrix":
            for case in FAULT_CASES:
                # Fresh API memory state and fresh proxy fault counters per case.
                harness.run_real_case(case, single[0])
                harness.stop_services()
        elif lane == "paired":
            harness.run_paired(pair[0], pair[1])
        elif lane == "handoff":
            harness.run_handoff(pair[0], pair[1])
        else:
            harness.run_standard(single[0])
            standalone_cases, _handoff_cases, _paired_cases = all_lane_case_partition()
            for case in standalone_cases:
                harness.run_real_case(case, single[0])
                harness.stop_services()
            harness.run_handoff(pair[0], pair[1])
            harness.stop_services()
            harness.run_paired(pair[0], pair[1])
        print(f"E2E lane '{lane}' completed. Results and service logs: {harness.logs}", flush=True)
    except KeyboardInterrupt:
        print("Interrupted; cleaning up runner-owned resources.", file=sys.stderr)
        exit_code = 130
    except (RunnerError, OSError, subprocess.SubprocessError, urllib.error.URLError, ValueError) as exc:
        print(f"E2E failed: {exc}", file=sys.stderr)
        exit_code = 1
    finally:
        harness.cleanup()
    if harness.cleanup_errors:
        print("The run is marked incomplete because runner-owned database cleanup failed; see the database name above.", file=sys.stderr)
        return 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
