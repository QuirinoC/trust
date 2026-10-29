#!/usr/bin/env python3
"""Run one genuine APNs sandbox XCTest against a local Development API.

The app and xctestrun must already be built by the caller. This runner copies signed
Debug products and requires Trust.app to carry aps-environment=development,
starts a fresh API/database with the five APNs settings read from Render in memory,
and asks xcodebuild to run one XCTest on the caller-provided fresh simulator.
APNs values are never written to disk or included in the Xcode test environment.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
import xml.parsers.expat
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
IOS = ROOT / "apps/trust-ios"
RUNNER_HELPERS = IOS / "Scripts/run_release_e2e.py"
SERVICE_ID = "srv-daabv1lg1s2s73co5gm0"
API_URL = "http://127.0.0.1:5090"
PROXY_URL = "http://127.0.0.1:5089"
TEST_TARGET = "TrustServiceUITests"
TEST_CASE = "testRealSandboxAPNsForegroundAndBackgroundLookRoute"
TEST_CASES = (
    TEST_CASE,
    "testRealSandboxAPNsNotificationSettingsRecovery",
)
TEST_CLASS = "RealPushAPNSE2ETests"
APNS_ENV_NAMES = (
    "Apns__BundleId",
    "Apns__Enabled",
    "Apns__KeyId",
    "Apns__PrivateKey",
    "Apns__TeamId",
)


class PushRunnerError(RuntimeError):
    pass


def helpers() -> Any:
    spec = importlib.util.spec_from_file_location("trust_release_e2e_helpers", RUNNER_HELPERS)
    if spec is None or spec.loader is None:
        raise PushRunnerError("Could not load the local release E2E helpers.")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_apns_settings() -> dict[str, str]:
    """Read only the five requested APNs values from Render, retaining them in memory."""
    ruby = r'''require "yaml"
require "net/http"
require "json"
require "uri"
begin
  config = YAML.load_file(File.expand_path("~/.render/cli.yaml"))
  token = config.fetch("api").fetch("key")
  uri = URI("https://api.render.com/v1/services/srv-daabv1lg1s2s73co5gm0/env-vars?limit=100")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Accept"] = "application/json"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 20) { |http| http.request(request) }
  abort("render-request-failed") unless response.is_a?(Net::HTTPSuccess)
  names = %w[Apns__BundleId Apns__Enabled Apns__KeyId Apns__PrivateKey Apns__TeamId]
  values = {}
  JSON.parse(response.body).each do |row|
    pair = row["envVar"] || {}
    values[pair["key"]] = pair["value"] if names.include?(pair["key"])
  end
  abort("apns-settings-incomplete") unless names.all? { |name| values[name].is_a?(String) && !values[name].empty? }
  abort("apns-settings-mismatch") unless values["Apns__Enabled"] == "true" && values["Apns__BundleId"] == "com.collapsetechnologies.trust"
  STDOUT.write(JSON.generate(values))
rescue StandardError
  abort("render-apns-settings-unavailable")
end
'''
    result = subprocess.run(
        ["ruby", "-e", ruby],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )
    if result.returncode != 0:
        raise PushRunnerError("Could not load and validate the five sandbox APNs settings from Render.")
    try:
        settings = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise PushRunnerError("Render returned an invalid APNs configuration response.") from exc
    if set(settings) != set(APNS_ENV_NAMES) or not all(isinstance(value, str) and value for value in settings.values()):
        raise PushRunnerError("The APNs configuration did not contain exactly the five required values.")
    if settings["Apns__Enabled"] != "true" or settings["Apns__BundleId"] != "com.collapsetechnologies.trust":
        raise PushRunnerError("The configured APNs service is disabled or targets a different bundle.")
    return settings


def read_simulator_entitlements(executable: Path, developer_dir: str) -> dict[str, Any]:
    extracted = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(executable.parent)],
        env=dict(os.environ, DEVELOPER_DIR=developer_dir),
        capture_output=True,
        check=False,
    )
    if extracted.returncode == 0:
        try:
            value = plistlib.loads(extracted.stdout)
            if (isinstance(value, dict)
                    and value.get("aps-environment") == "development"
                    and isinstance(value.get("application-identifier"), str)):
                return value
        except (ValueError, plistlib.InvalidFileException, xml.parsers.expat.ExpatError):
            pass

    # Simulator app signatures commonly report an empty entitlement plist.
    # Xcode embeds the effective simulator entitlements in this Mach-O section.
    embedded = subprocess.run(
        ["xcrun", "otool", "-arch", "arm64", "-s", "__TEXT", "__entitlements", str(executable)],
        env=dict(os.environ, DEVELOPER_DIR=developer_dir),
        capture_output=True,
        text=True,
        check=False,
    )
    if embedded.returncode != 0:
        raise PushRunnerError("Could not read the simulator app's embedded entitlements.")
    return parse_otool_entitlements(embedded.stdout)


def parse_otool_entitlements(output: str) -> dict[str, Any]:
    words: list[str] = []
    for line in output.splitlines():
        parts = line.split()
        if (len(parts) < 2 or len(parts[0]) < 8 or len(parts[0]) % 2 != 0
                or not all(c in "0123456789abcdefABCDEF" for c in parts[0])):
            continue
        for word in parts[1:]:
            if len(word) not in (2, 4, 8) or not all(c in "0123456789abcdefABCDEF" for c in word):
                raise PushRunnerError("The simulator app's embedded entitlement section has unexpected data.")
            words.append(word)
    if not words:
        raise PushRunnerError("The simulator app has no readable embedded entitlement section.")
    try:
        data = b"".join(bytes.fromhex(word)[::-1] if len(word) != 2 else bytes.fromhex(word) for word in words)
        entitlements = plistlib.loads(data.rstrip(b"\0"))
    except (ValueError, plistlib.InvalidFileException, xml.parsers.expat.ExpatError) as exc:
        raise PushRunnerError("The simulator app's embedded entitlements are unreadable.") from exc
    if not isinstance(entitlements, dict):
        raise PushRunnerError("The simulator app's embedded entitlements are not a plist dictionary.")
    return entitlements


def require_development_apns_entitlements(entitlements: dict[str, Any], expected_team_id: str) -> None:
    expected_application_id = f"{expected_team_id}.com.collapsetechnologies.trust"
    if (entitlements.get("aps-environment") != "development"
            or entitlements.get("application-identifier") != expected_application_id):
        raise PushRunnerError("The supplied Debug app must embed the matching application identifier and development APNs entitlement.")


def copy_products_and_verify_signed_app(products: Path, xctestrun: Path, destination: Path,
                                        developer_dir: str, expected_team_id: str) -> Path:
    products = products.expanduser().resolve()
    xctestrun = xctestrun.expanduser().resolve()
    if not products.is_dir() or not xctestrun.is_file() or xctestrun.parent != products:
        raise PushRunnerError("Supply the build's Build/Products directory and its xctestrun file from that directory.")
    simulator_products = products / "Debug-iphonesimulator"
    if not simulator_products.is_dir():
        raise PushRunnerError("The supplied build products do not contain Debug-iphonesimulator.")

    copied_products = destination / "BuildProducts"
    copied_products.mkdir(parents=True)
    shutil.copytree(simulator_products, copied_products / "Debug-iphonesimulator")
    copied_xctestrun = copied_products / xctestrun.name
    shutil.copy2(xctestrun, copied_xctestrun)
    app = copied_products / "Debug-iphonesimulator" / "Trust.app"
    if not app.is_dir():
        raise PushRunnerError("The copied Debug products do not contain Trust.app.")

    try:
        app_info = plistlib.loads((app / "Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException) as exc:
        raise PushRunnerError("The copied Debug app has no readable Info.plist.") from exc
    if app_info.get("CFBundleIdentifier") != "com.collapsetechnologies.trust":
        raise PushRunnerError("The copied Debug app has an unexpected bundle identifier.")

    verify = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
        env=dict(os.environ, DEVELOPER_DIR=developer_dir),
        capture_output=True,
        text=True,
        check=False,
    )
    if verify.returncode != 0:
        raise PushRunnerError("The supplied Debug app must already have a valid simulator code signature.")

    executable_name = app_info.get("CFBundleExecutable")
    if not isinstance(executable_name, str):
        raise PushRunnerError("The supplied Debug app has no executable name.")
    signed_entitlements = read_simulator_entitlements(app / executable_name, developer_dir)
    require_development_apns_entitlements(signed_entitlements, expected_team_id)
    return copied_xctestrun


def wait_for_api(api: subprocess.Popen[str], proxy: subprocess.Popen[str], module: Any, timeout: int = 45) -> None:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        if api.poll() is not None or proxy.poll() is not None:
            raise PushRunnerError("The isolated API or race proxy exited during startup.")
        try:
            caps = module.http_json(API_URL + "/api/v1/local-test-capabilities")
            if caps.get("developmentOtpWithoutSms") is not True:
                raise PushRunnerError("The API did not confirm Development OTP without SMS.")
            state = module.http_json(PROXY_URL + "/__test/state")
            if not isinstance(state, dict):
                raise PushRunnerError("The loopback proxy did not return its test state.")
            return
        except (OSError, ValueError, urllib.error.URLError) as exc:
            last_error = exc
            time.sleep(0.4)
    raise PushRunnerError(f"The local Development API did not become ready: {last_error}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, required=True, help="Existing Build/Products folder from Trust.RealServices build-for-testing.")
    parser.add_argument("--xctestrun", type=Path, required=True, help="Existing Trust.RealServices xctestrun from the same Build/Products folder.")
    parser.add_argument("--device", required=True, help="Fresh, booted iOS Simulator UDID selected by the caller.")
    parser.add_argument("--case", choices=TEST_CASES, default=TEST_CASE,
                        help="Exact APNs XCTest to run (default: foreground/background Look route).")
    parser.add_argument("--postgres-connection", default=os.environ.get("TRUST_E2E_POSTGRES_CONNECTION"), required=os.environ.get("TRUST_E2E_POSTGRES_CONNECTION") is None)
    parser.add_argument("--postgres-container", default=os.environ.get("TRUST_E2E_POSTGRES_CONTAINER"),
                        help="Docker Postgres container (required unless --postgres-direct is used).")
    parser.add_argument("--postgres-direct", action="store_true",
                        help="Create/drop the disposable database through native psql on validated loopback Postgres.")
    parser.add_argument("--developer-dir", default=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
    parser.add_argument("--output", type=Path, help="New empty evidence directory. Defaults to a unique folder in /tmp.")
    args = parser.parse_args(argv)
    if not args.postgres_direct and not args.postgres_container:
        parser.error("supply --postgres-container or use --postgres-direct")

    module = helpers()
    try:
        module.parse_pg_connection(args.postgres_connection)
        if not module.safe_port_available(5089) or not module.safe_port_available(5090):
            raise PushRunnerError("Loopback ports 5089 and 5090 must be free; unknown processes are never killed.")
        settings = read_apns_settings()
        if args.output:
            output = args.output.expanduser().resolve()
            if output.exists() and any(output.iterdir()):
                raise PushRunnerError("The evidence output directory must be new or empty.")
            output.mkdir(parents=True, exist_ok=True)
        else:
            output = Path(tempfile.mkdtemp(prefix="trust-real-apns-e2e-"))
        output.mkdir(parents=True, exist_ok=True)
        copied_xctestrun = copy_products_and_verify_signed_app(
            args.products, args.xctestrun, output, args.developer_dir, settings["Apns__TeamId"]
        )
        run_xctestrun = copied_xctestrun.with_name("RealPush.runner.xctestrun")
        module.inject_runner_environment(
            copied_xctestrun,
            run_xctestrun,
            {"TRUST_UI_TEST_BASE_URL": PROXY_URL, "TRUST_REAL_PUSH_E2E": "1"},
            target_name=TEST_TARGET,
        )
        raw_spec = run_xctestrun.read_bytes()
        if b"Apns__" in raw_spec or settings["Apns__PrivateKey"].encode() in raw_spec:
            raise PushRunnerError("Refusing to run: APNs service settings appeared in the Xcode test specification.")

        logs = output / "services"
        logs.mkdir()
        database = module.RunnerDatabase.create(
            args.postgres_connection,
            None if args.postgres_direct else args.postgres_container,
            args.developer_dir,
            direct=args.postgres_direct,
        )
        database_connection = module.connection_with_database(args.postgres_connection, database.name)
        services = None
        result_bundle = output / "RealPushAPNS.xcresult"
        try:
            extra_api_environment = dict(settings)
            # The API process must use only the Development OTP path. Explicitly clear
            # any shell-provided Twilio environment so no real SMS can be sent.
            extra_api_environment.update({
                "Twilio__AccountSid": "",
                "Twilio__AuthToken": "",
                "Twilio__FromNumber": "",
                "Twilio__MessagingServiceSid": "",
                # APNs provider requests contain a signed bearer token in the
                # authorization header; keep HTTP client diagnostics out of logs.
                "Logging__LogLevel__System.Net.Http": "Warning",
            })
            services = module.start_services(
                logs,
                args.developer_dir,
                postgres_connection=database_connection,
                extra_api_environment=extra_api_environment,
            )
            wait_for_api(services.api, services.proxy, module)

            command = [
                "xcodebuild", "test-without-building", "-xctestrun", str(run_xctestrun),
                "-destination", module.test_dest(args.device),
                "-resultBundlePath", str(result_bundle),
                "-only-testing", f"{TEST_TARGET}/{TEST_CLASS}/{args.case}",
            ]
            xcode_environment = dict(os.environ, DEVELOPER_DIR=args.developer_dir)
            for name in APNS_ENV_NAMES:
                xcode_environment.pop(name, None)
            run = subprocess.run(
                command,
                cwd=IOS,
                env=xcode_environment,
                capture_output=True,
                text=True,
                check=False,
            )
            (output / "xcodebuild.log").write_text((run.stdout or "") + (run.stderr or ""), encoding="utf-8")
            if not result_bundle.exists():
                raise PushRunnerError("Xcode produced no result bundle; inspect the retained xcodebuild log.")
            summary = module.result_summary(result_bundle, args.developer_dir)
            module.validate_result(summary, result_bundle)
            module.validate_single_case(summary, result_bundle, args.case, args.developer_dir)
            if run.returncode != 0:
                raise PushRunnerError("The genuine APNs XCTest failed; see the xcresult bundle and xcodebuild log.")
            (output / "evidence-mode.txt").write_text(
                "Real sandbox APNs via local Development API and fresh disposable PostgreSQL; "
                "fictional accounts; Development OTP with Twilio cleared; pre-signed Debug app "
                "with simulator development APNs entitlement; no simctl push.\n",
                encoding="utf-8",
            )
            print(f"Genuine APNs XCTest passed: {result_bundle}")
            return 0
        finally:
            if services is not None:
                try:
                    urllib.request.urlopen(PROXY_URL + "/__test/release", timeout=1).close()
                except Exception:
                    pass
                services.stop()
            try:
                database.drop()
            except Exception as exc:
                raise PushRunnerError("Could not drop the runner-created disposable PostgreSQL database.") from exc
    except (PushRunnerError, module.RunnerError, OSError, subprocess.SubprocessError) as exc:
        print(f"Real APNs E2E failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
