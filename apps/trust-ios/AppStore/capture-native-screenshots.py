#!/usr/bin/env python3
"""Capture current Trust App Store screens without drawing into screenshots.

The shell entry point builds Trust.RealServices once. This driver captures People
and the expanded Look sheet with AppStoreNativeCaptureTests, and the other four
storyboard routes directly. It only creates, boots, and deletes simulators it owns.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit("Install the repository's Pillow dependency before capture.") from exc

BUNDLE_ID = "com.collapsetechnologies.trust"
HINGE_HELPER_SHA256 = "1997bd4788c561596ad8616e1bf0a1cc71b10685d7807ff88a37b126d1124a84"
INTERRUPTION_SIGNALS = (signal.SIGINT, signal.SIGTERM)
CLASSIC_DEVICES = {
    "iphone-69": ("iPhone-17-Pro-Max", (1320, 2868)),
    "iphone-65": ("iPhone-11-Pro-Max", (1242, 2688)),
    "iphone-medium": ("iPhone-17-Pro", (1206, 2622)),
    "ipad-13": ("iPad-Pro-13-inch-M5-12GB", (2064, 2752)),
}
DUO_DEVICES = {
    "duo-outer": ("iPhone-Duo", (1398, 2034), 0.0, "1"),
    "duo-inner": ("iPhone-Duo", (2853, 2007), 180.0, "3"),
}
STATIC_ROUTES = ("share", "log", "view", "lookup")
NATIVE_ROUTES = {
    "hero-live": "testHeroLivePeople",
    "look-expanded": "testLookExpandedConsentSheet",
    "paywall-real-catalog": "testPaywallRealCatalog",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class CaptureInterrupted(RuntimeError):
    """A requested process interruption that should pass through capture cleanup."""


def handle_capture_signal(signum: int, _frame: Any) -> None:
    # Ignore repeat interrupts while the first one unwinds active subprocesses and simulators.
    for handled_signal in INTERRUPTION_SIGNALS:
        signal.signal(handled_signal, signal.SIG_IGN)
    name = signal.Signals(signum).name
    raise CaptureInterrupted(f"Received {name}; stopping capture and cleaning up owned resources.")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    fd, temp_path = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(data, out, indent=2, sort_keys=True)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(temp_path, path)
        os.chmod(path, 0o600)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def command(args: list[str], *, timeout: int = 60, check: bool = True,
            env: dict[str, str] | None = None, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True, timeout=timeout,
                            env=env, cwd=cwd)
    if check and result.returncode:
        detail = result.stderr.strip()[-1000:] or result.stdout.strip()[-1000:]
        raise RuntimeError(f"{args[0]} exited {result.returncode}: {detail}")
    return result


def simctl(*args: str, timeout: int = 60, check: bool = True) -> str:
    return command(["xcrun", "simctl", *args], timeout=timeout, check=check).stdout.strip()


def version_key(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", text))


def select_runtime(device_type: str, override: str | None) -> tuple[str, str]:
    data = json.loads(command(["xcrun", "simctl", "list", "runtimes", "-j"]).stdout)
    device_identifier = (device_type if device_type.startswith("com.apple.CoreSimulator.SimDeviceType.")
                        else "com.apple.CoreSimulator.SimDeviceType." + device_type)
    matches: list[tuple[tuple[int, ...], str, str]] = []
    for runtime in data.get("runtimes", []):
        if runtime.get("isAvailable") is not True:
            continue
        supported = runtime.get("supportedDeviceTypes", [])
        identifiers = {item if isinstance(item, str) else item.get("identifier", item.get("bundleIdentifier", ""))
                       for item in supported}
        if device_identifier not in identifiers:
            continue
        identifier = runtime.get("identifier", "")
        if override and identifier != override:
            continue
        matches.append((version_key(runtime.get("version", "0")), identifier, runtime.get("version", "")))
    if not matches:
        suffix = f" matching TRUST_SIM_RUNTIME={override}" if override else ""
        raise RuntimeError(f"No available iOS runtime supports {device_type}{suffix}.")
    _, identifier, version = max(matches)
    return identifier, version


def find_xctestrun(products: Path, explicit: Path | None) -> Path:
    if explicit:
        path = explicit.resolve()
        if not path.is_file() or not path.name.startswith("Trust.RealServices_") or not path.name.endswith(".xctestrun"):
            raise ValueError("TRUST_XCTESTRUN must point to a Trust.RealServices_*.xctestrun file.")
        return path
    candidates = list(products.glob("Trust.RealServices_*.xctestrun"))
    if not candidates:
        raise FileNotFoundError(f"No Trust.RealServices_*.xctestrun found in {products}; build-for-testing first.")
    return max(candidates, key=lambda path: (path.stat().st_mtime_ns, path.name))


def capture_size(path: Path, expected: tuple[int, int]) -> dict[str, Any]:
    with Image.open(path) as image:
        image.load()
        if image.size != expected:
            raise ValueError(f"Unexpected screenshot dimensions at {path}: {image.size}, expected {expected}.")
        if image.mode not in ("RGB", "RGBA"):
            raise ValueError(f"Screenshot must be native RGB or RGBA: {path} has {image.mode}.")
        if image.mode == "RGBA" and image.getchannel("A").getextrema() != (255, 255):
            raise ValueError(f"Screenshot alpha channel must be fully opaque: {path} has {image.getchannel('A').getextrema()}.")
        return {"width": image.width, "height": image.height, "mode": image.mode}


def export_opaque_paywall_rgb(source: Path, destination: Path,
                              expected: tuple[int, int]) -> dict[str, Any]:
    """Drop only an all-opaque alpha channel for the optional Apple review image."""
    with Image.open(source) as native:
        native.load()
        if native.size != expected or native.mode not in ("RGB", "RGBA"):
            raise ValueError(f"Paywall source must be native RGB/RGBA at {expected}: {native.size} {native.mode}.")
        if native.mode == "RGBA":
            alpha_extrema = native.getchannel("A").getextrema()
            if alpha_extrema != (255, 255):
                raise ValueError(f"Paywall source alpha is not fully opaque: {alpha_extrema}.")
            original_rgb = Image.merge("RGB", native.split()[:3])
        else:
            original_rgb = native.copy()
        expected_bytes = original_rgb.tobytes()
        destination.parent.mkdir(parents=True, exist_ok=True)
        original_rgb.save(destination, format="PNG", optimize=False)
        os.chmod(destination, 0o600)
        with Image.open(destination) as normalized:
            normalized.load()
            if normalized.size != expected or normalized.mode != "RGB":
                raise ValueError(f"Normalized paywall must be RGB at {expected}: {normalized.size} {normalized.mode}.")
            if normalized.tobytes() != expected_bytes:
                raise ValueError("Dropping the opaque paywall alpha channel changed RGB pixel bytes.")
            return {"path": str(destination), "sha256": sha256(destination),
                    "width": normalized.width, "height": normalized.height, "mode": normalized.mode,
                    "sourceToNormalizedRGBBytesIdentical": True}


def copy_previous(path: Path, log_root: Path) -> str | None:
    if not path.exists():
        return None
    dest = log_root / "previous-raw" / path.parent.name / path.name
    dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copy2(path, dest)
    os.chmod(dest, 0o600)
    return str(dest)


def write_simulator_capture(device: str, path: Path, expected: tuple[int, int],
                            display: str | None, ledger: dict[str, Any], save: Any) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    previous = copy_previous(path, Path(ledger["logRoot"]))
    args = ["io", device, "screenshot"]
    if display:
        args.append(f"--display={display}")
    args.append(str(path))
    try:
        simctl(*args, timeout=60)
        geometry = capture_size(path, expected)
    except BaseException:
        if path.exists():
            path.unlink()
        raise
    record = {"path": str(path), "sha256": sha256(path), "previousCopy": previous,
              **geometry, "capturedAtUTC": utc_now()}
    ledger.setdefault("rawCaptures", []).append(record)
    save()
    return record


def app_environment(route: str) -> dict[str, str]:
    env = dict(os.environ)
    env.update({"SIMCTL_CHILD_TRUST_DEMO": "1", "SIMCTL_CHILD_TRUST_UI_TEST": "1",
                "SIMCTL_CHILD_TRUST_SCREENSHOT": route})
    return env


def launch_route(device: str, route: str) -> None:
    result = command(["xcrun", "simctl", "launch", "--terminate-running-process", device,
                      BUNDLE_ID, "-trust.appLanguage", "en"],
                     timeout=35, env=app_environment(route))
    if not result.stdout.strip():
        raise RuntimeError(f"Route launch produced no process information: {route}.")


def prepare_simulator(device: str) -> None:
    simctl("boot", device)
    simctl("bootstatus", device, "-b", timeout=180)
    simctl("ui", device, "appearance", "light")
    simctl("status_bar", device, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active",
           "--cellularBars", "4", "--operatorName", "", "--batteryState", "charged", "--batteryLevel", "100", check=False)
    simctl("location", device, "set", "37.7749,-122.4194", check=False)


def ensure_helper(helper: Path | None) -> Path:
    if helper is None:
        raise ValueError("Duo capture requires an explicitly supplied TRUST_HINGE_HELPER path.")
    helper = helper.expanduser().resolve()
    if not helper.is_file():
        raise FileNotFoundError(f"Explicit hinge helper does not exist: {helper}")
    digest = sha256(helper)
    if digest != HINGE_HELPER_SHA256:
        raise ValueError("Hinge helper SHA-256 does not match the pinned approved helper.")
    return helper


def set_hinge_posture(device: str, helper: Path, degrees: float,
                      ledger: dict[str, Any], save: Any) -> None:
    record: dict[str, Any] = {"device": device, "requestedDegrees": degrees,
                              "startedAtUTC": utc_now(), "actualAngleQueries": [],
                              "postconditionTimeoutSeconds": 15, "verified": False}
    ledger.setdefault("hingePostures", []).append(record)
    save()

    def query_actual_angle() -> float | None:
        query: dict[str, Any] = {"queriedAtUTC": utc_now()}
        try:
            result = simctl("spawn", device, str(helper), "get", timeout=5)
            values = re.findall(r"-?\d+(?:\.\d+)?", result)
            if not values:
                raise RuntimeError("Pinned hinge helper returned no posture angle.")
            angle = float(values[-1])
            query.update({"reportedDegrees": angle, "helperOutput": result[-800:]})
            record["actualAngleQueries"].append(query)
            save()
            return angle
        except Exception as exc:
            query["error"] = f"{type(exc).__name__}: {exc}"
            record["actualAngleQueries"].append(query)
            save()
            return None

    before = query_actual_angle()
    record["beforeDegrees"] = before
    if before is None or abs(before - degrees) > 0.5:
        try:
            setter = command(["xcrun", "simctl", "spawn", device, str(helper), "set", str(degrees), "10"],
                             timeout=45, check=False)
            record["setterOutcome"] = {"timedOut": False, "returnCode": setter.returncode,
                                       "stdout": setter.stdout[-1000:], "stderr": setter.stderr[-1000:]}
        except subprocess.TimeoutExpired as exc:
            def output_text(value: str | bytes | None) -> str:
                if isinstance(value, bytes):
                    return value.decode("utf-8", errors="replace")[-1000:]
                return (value or "")[-1000:]
            record["setterOutcome"] = {"timedOut": True, "timeoutSeconds": 45,
                                       "stdout": output_text(exc.stdout), "stderr": output_text(exc.stderr)}
    else:
        record["setterOutcome"] = {"timedOut": False, "returnCode": 0,
                                   "skipped": "Current physical angle already matches request."}
    save()

    deadline = time.monotonic() + 15
    stable_matches = 0
    after: float | None = None
    while time.monotonic() < deadline:
        after = query_actual_angle()
        if after is not None and abs(after - degrees) <= 0.5:
            stable_matches += 1
            if stable_matches >= 2:
                record["reportedDegrees"] = after
                record["verified"] = True
                record["verifiedAtUTC"] = utc_now()
                save()
                return
        else:
            stable_matches = 0
        time.sleep(0.5)

    record["reportedDegrees"] = after
    record["verificationFailedAtUTC"] = utc_now()
    save()
    raise RuntimeError(f"Duo physical posture did not settle at {degrees} degrees within 15 seconds (last actual angle {after}).")


def install_app(device: str, app_path: Path) -> None:
    simctl("install", device, str(app_path), timeout=120)


def capture_static(device: str, fmt: str, output_root: Path, size: tuple[int, int],
                   route: str, ledger: dict[str, Any], save: Any, display: str | None) -> None:
    launch_route(device, route)
    time.sleep(6)
    output = output_root / fmt / f"{route}.png"
    result = write_simulator_capture(device, output, size, display, ledger, save)
    ledger.setdefault("staticCaptures", []).append({"format": fmt, "route": route, "device": device,
                                                      "runtime": ledger["activeSimulator"]["runtime"], **result})
    save()
    simctl("terminate", device, BUNDLE_ID, check=False)
    print(f"Captured {fmt}/{route}.png", flush=True)


def inject_capture_environment(spec: Any, marker_dir: Path, scenario: str, orientation: str) -> None:
    if isinstance(spec, dict):
        if "UITargetAppPath" in spec:
            env = spec.setdefault("EnvironmentVariables", {})
            env.update({"TRUST_STORE_CAPTURE_DIR": str(marker_dir),
                        "TRUST_STORE_CAPTURE_SCENARIO": scenario,
                        "TRUST_STORE_CAPTURE_ORIENTATION": orientation})
        for value in spec.values():
            inject_capture_environment(value, marker_dir, scenario, orientation)
    elif isinstance(spec, list):
        for value in spec:
            inject_capture_environment(value, marker_dir, scenario, orientation)


def export_test_diagnostics(result_bundle: Path, case_dir: Path, method: str) -> dict[str, Any]:
    info: dict[str, Any] = {"resultBundle": str(result_bundle), "activities": "not available"}
    if not result_bundle.exists():
        return info
    summary = command(["xcrun", "xcresulttool", "get", "test-results", "summary",
                       "--path", str(result_bundle), "--format", "json"], check=False, timeout=60)
    if summary.stdout:
        (case_dir / "summary.json").write_text(summary.stdout, encoding="utf-8")
        info["summaryExitCode"] = summary.returncode
    else:
        (case_dir / "summary-error.log").write_text(summary.stderr, encoding="utf-8")
    test_id = f"TrustServiceUITests/AppStoreNativeCaptureTests/{method}()"
    activities = command(["xcrun", "xcresulttool", "get", "test-results", "activities",
                          "--path", str(result_bundle), "--test-id", test_id, "--format", "json"],
                         check=False, timeout=90)
    target = case_dir / "unifiedInteractionFlow.json"
    if activities.stdout:
        target.write_text(activities.stdout, encoding="utf-8")
        info["activities"] = str(target)
        info["activitiesExitCode"] = activities.returncode
    else:
        (case_dir / "unifiedInteractionFlow-error.log").write_text(activities.stderr, encoding="utf-8")
        info["activitiesError"] = "xcresulttool did not export test activity JSON; see error log and xcodebuild.log."
    return info


def save_failure_capture(device: str, case_dir: Path, display: str | None,
                         expected: tuple[int, int] | None = None) -> str | None:
    path = case_dir / "native-failure.png"
    try:
        args = ["io", device, "screenshot"]
        if display:
            args.append(f"--display={display}")
        args.append(str(path))
        simctl(*args, timeout=60)
        if expected:
            capture_size(path, expected)
        os.chmod(path, 0o600)
        return str(path)
    except Exception as exc:
        (case_dir / "native-failure-capture-error.log").write_text(f"{type(exc).__name__}: {exc}\n", encoding="utf-8")
        return None


def capture_native_case(device: str, fmt: str, scenario: str, method: str,
                        output: Path, expected: tuple[int, int], display: str | None,
                        orientation: str,
                        xctestrun: Path, app_root: Path, log_root: Path,
                        ledger: dict[str, Any], save: Any) -> dict[str, Any]:
    case_name = f"{fmt}-{scenario}"
    case_dir = log_root / "cases" / case_name
    case_dir.mkdir(parents=True, exist_ok=False, mode=0o700)
    marker_dir = case_dir / "markers"
    marker_dir.mkdir(mode=0o700)
    ready = marker_dir / "ready.json"
    proceed = marker_dir / "continue"
    spec = plistlib.loads(xctestrun.read_bytes())
    inject_capture_environment(spec, marker_dir, scenario, orientation)
    case_xctestrun = case_dir / (case_name + ".xctestrun")
    case_xctestrun.write_bytes(plistlib.dumps(spec))
    os.chmod(case_xctestrun, 0o600)
    result_bundle = case_dir / "result.xcresult"
    xcode_log = case_dir / "xcodebuild.log"
    is_paywall_review = scenario == "paywall-real-catalog"
    native_output = case_dir / "native-original.png" if is_paywall_review else output
    command_line = ["xcodebuild", "test-without-building", "-xctestrun", str(case_xctestrun),
                    "-destination", f"platform=iOS Simulator,id={device}",
                    "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result_bundle),
                    "-only-testing:TrustServiceUITests/AppStoreNativeCaptureTests/" + method]
    process: subprocess.Popen[bytes] | None = None
    raw: dict[str, Any] | None = None
    diagnostic: dict[str, Any] = {}
    output_written = False
    try:
        with xcode_log.open("wb") as log:
            process = subprocess.Popen(command_line, cwd=app_root, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            deadline = time.monotonic() + 100
            while not ready.exists():
                if process.poll() is not None:
                    raise RuntimeError(f"{case_name} ended before the native ready marker (exit {process.returncode}).")
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"{case_name} did not publish a native ready marker within 100 seconds.")
                time.sleep(0.2)
            time.sleep(2)
            marker = json.loads(ready.read_text(encoding="utf-8"))
            native_output.parent.mkdir(parents=True, exist_ok=True)
            previous = None if is_paywall_review else copy_previous(output, log_root)
            output_written = not is_paywall_review
            capture_args = ["io", device, "screenshot"]
            if display:
                capture_args.append(f"--display={display}")
            capture_args.append(str(native_output))
            simctl(*capture_args, timeout=60)
            geometry = capture_size(native_output, expected)
            native_source = {"path": str(native_output), "sha256": sha256(native_output),
                             **geometry, "capturedAtUTC": utc_now()}
            if is_paywall_review:
                raw = {"path": str(native_output), "sha256": native_source["sha256"],
                       "mode": geometry["mode"], "nativeSource": native_source}
            else:
                raw = {"path": str(output), "sha256": native_source["sha256"],
                       "previousCopy": previous, **geometry, "capturedAtUTC": native_source["capturedAtUTC"]}
            proceed.write_text("captured\n", encoding="utf-8")
            code = process.wait(timeout=60)
        diagnostic = export_test_diagnostics(result_bundle, case_dir, method)
        if code != 0:
            raise RuntimeError(f"{case_name} UI test failed with exit {code}; diagnostics are in {case_dir}.")
        summary_path = case_dir / "summary.json"
        summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else {}
        if summary.get("passedTests") != 1 or summary.get("failedTests") != 0 or summary.get("skippedTests") != 0:
            raise RuntimeError(f"{case_name} did not report exactly one pass, zero failures, and zero skips; diagnostics are in {case_dir}.")
        if is_paywall_review:
            previous = copy_previous(output, log_root)
            output_written = True
            normalized = export_opaque_paywall_rgb(native_output, output, expected)
            raw = {"path": str(output), "sha256": normalized["sha256"],
                   "previousCopy": previous, **normalized,
                   "nativeSource": native_source,
                   "nativeOriginalPreserved": True}
        record = {"name": case_name, "device": device, "scenario": scenario, "testMethod": method,
                  "resultBundle": str(result_bundle), "log": str(xcode_log), "diagnostics": diagnostic,
                  "readyMarker": marker, "capture": raw, "passed": 1, "failed": 0, "skipped": 0}
        ledger.setdefault("nativeCases", []).append(record)
        save()
        print(f"Captured {fmt}/{output.name}; native test passed", flush=True)
        return record
    except BaseException:
        if process is not None and process.poll() is None:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
        if output_written and output.exists():
            # A failed UI test must not leave an apparently valid source image.
            # Any previous raw was copied into this run's private log folder.
            output.unlink()
        failure_png = save_failure_capture(device, case_dir, display, expected)
        if not diagnostic:
            diagnostic = export_test_diagnostics(result_bundle, case_dir, method)
        ledger.setdefault("failures", []).append({"name": case_name, "caseDirectory": str(case_dir),
                                                    "resultBundle": str(result_bundle), "xcodebuildLog": str(xcode_log),
                                                    "diagnostics": diagnostic, "nativeFailureCapture": failure_png,
                                                    "readyMarkerExists": ready.exists(), "capturedBeforeCleanup": True,
                                                    "failedAtUTC": utc_now()})
        save()
        raise
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)


def create_owned_simulator(name: str, device_type: str, runtime: str, fmt: str,
                           ledger: dict[str, Any], save: Any, capture_log: Path) -> str:
    udid = simctl("create", name, "com.apple.CoreSimulator.SimDeviceType." + device_type, runtime)
    record = {"name": name, "id": udid, "format": fmt, "deviceType": device_type,
              "runtime": runtime, "createdAtUTC": utc_now(), "deleted": False}
    ledger.setdefault("ownedSimulators", []).append(record)
    ledger["activeSimulator"] = record
    save()
    capture_log.parent.mkdir(parents=True, exist_ok=True)
    with capture_log.open("a", encoding="utf-8") as out:
        out.write(f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\t{name}\t{udid}\t{runtime}\n")
    os.chmod(capture_log, 0o600)
    return udid


def cleanup_owned(ledger: dict[str, Any], save: Any) -> None:
    active = ledger.get("activeSimulator")
    if not active:
        return
    udid = active["id"]
    errors: list[str] = []
    for action in ("shutdown", "delete"):
        result = command(["xcrun", "simctl", action, udid], timeout=90, check=False)
        message = result.stderr.lower()
        already_gone = "invalid device" in message or "no device" in message
        already_shutdown = action == "shutdown" and ("already shutdown" in message or "current state: shutdown" in message)
        if result.returncode and not already_gone and not already_shutdown:
            errors.append(f"simctl {action} exited {result.returncode}: {result.stderr.strip()[-600:]}")
    active["deleted"] = not errors
    active["deletedAtUTC"] = utc_now() if not errors else None
    active["cleanupErrors"] = errors
    ledger["activeSimulator"] = None
    save()
    if errors:
        raise RuntimeError("Owned simulator cleanup failed: " + "; ".join(errors))


def capture_classic(fmt: str, spec: tuple[str, tuple[int, int]], args: argparse.Namespace,
                    xctestrun: Path, app_path: Path, ledger: dict[str, Any], save: Any) -> None:
    device_type, size = spec
    runtime, runtime_version = select_runtime(device_type, args.sim_runtime)
    name = "Trust Capture " + fmt
    device = create_owned_simulator(name, device_type, runtime, fmt, ledger, save, args.capture_log)
    try:
        prepare_simulator(device)
        install_app(device, app_path)
        # Native tests capture the People and full consent screens through current UI paths.
        capture_native_case(device, fmt, "hero-live", NATIVE_ROUTES["hero-live"],
                           args.output_root / fmt / "map.png", size, None,
                           "portrait",
                           xctestrun, args.app_root, args.log_root, ledger, save)
        capture_native_case(device, fmt, "look-expanded", NATIVE_ROUTES["look-expanded"],
                           args.output_root / fmt / "look.png", size, None,
                           "portrait",
                           xctestrun, args.app_root, args.log_root, ledger, save)
        for route in STATIC_ROUTES:
            capture_static(device, fmt, args.output_root, size, route, ledger, save, None)
        if fmt == "iphone-69" and args.capture_phone:
            capture_static(device, fmt, args.output_root, size, "phone", ledger, save, None)
        if fmt == "iphone-69" and args.capture_paywall_review:
            capture_native_case(device, fmt, "paywall-real-catalog", NATIVE_ROUTES["paywall-real-catalog"],
                               args.paywall_output, size, None, "portrait", xctestrun, args.app_root,
                               args.log_root, ledger, save)
    finally:
        cleanup_owned(ledger, save)
    ledger.setdefault("runtimeSelections", []).append({"format": fmt, "deviceType": device_type,
                                                         "runtime": runtime, "version": runtime_version})
    save()


def capture_duo_formats(formats: list[str], helper: Path, args: argparse.Namespace,
                        xctestrun: Path, app_path: Path, ledger: dict[str, Any], save: Any) -> None:
    device_type = "iPhone-Duo"
    runtime, runtime_version = select_runtime(device_type, args.sim_runtime)
    name = "Trust Capture Duo"
    device = create_owned_simulator(name, device_type, runtime, "duo", ledger, save, args.capture_log)
    try:
        prepare_simulator(device)
        install_app(device, app_path)
        for fmt in formats:
            _, size, degrees, display = DUO_DEVICES[fmt]
            orientation = "landscapeLeft" if fmt == "duo-inner" else "portrait"
            set_hinge_posture(device, helper, degrees, ledger, save)
            capture_native_case(device, fmt, "hero-live", NATIVE_ROUTES["hero-live"],
                               args.output_root / fmt / "map.png", size, display,
                               orientation,
                               xctestrun, args.app_root, args.log_root, ledger, save)
            capture_native_case(device, fmt, "look-expanded", NATIVE_ROUTES["look-expanded"],
                               args.output_root / fmt / "look.png", size, display,
                               orientation,
                               xctestrun, args.app_root, args.log_root, ledger, save)
            for route in STATIC_ROUTES:
                capture_static(device, fmt, args.output_root, size, route, ledger, save, display)
    finally:
        cleanup_owned(ledger, save)
    ledger.setdefault("runtimeSelections", []).append({"format": "duo", "deviceType": device_type,
                                                         "runtime": runtime, "version": runtime_version})
    ledger["hingeHelper"] = {"path": str(helper), "sha256": HINGE_HELPER_SHA256}
    save()


def selected_formats(requested: str, helper_explicit: bool) -> tuple[list[str], list[str]]:
    classic = list(CLASSIC_DEVICES)
    if requested == "all":
        classics = classic
        duo = list(DUO_DEVICES) if helper_explicit else []
    elif requested in ("iphone", "iphone-69"):
        classics, duo = ["iphone-69"], []
    elif requested in ("ipad", "ipad-13"):
        classics, duo = ["ipad-13"], []
    elif requested in CLASSIC_DEVICES:
        classics, duo = [requested], []
    elif requested == "duo":
        classics, duo = [], list(DUO_DEVICES)
    elif requested in DUO_DEVICES:
        classics, duo = [], [requested]
    else:
        raise ValueError("TRUST_CAPTURE_DEVICES must be all, iphone-69, iphone-65, iphone-medium, ipad-13, duo, duo-outer, or duo-inner.")
    if duo and not helper_explicit:
        raise ValueError("Duo capture requires an explicitly provided TRUST_HINGE_HELPER.")
    return classics, duo


def main() -> int:
    for handled_signal in INTERRUPTION_SIGNALS:
        signal.signal(handled_signal, handle_capture_signal)
    parser = argparse.ArgumentParser(description="Capture native Trust App Store source screens from current UI.")
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--log-root", type=Path, required=True)
    parser.add_argument("--capture-log", type=Path, required=True)
    parser.add_argument("--devices", default="all")
    parser.add_argument("--xctestrun", type=Path)
    parser.add_argument("--hinge-helper", type=Path)
    parser.add_argument("--capture-phone", action="store_true")
    parser.add_argument("--capture-paywall-review", action="store_true")
    parser.add_argument("--paywall-output", type=Path, required=True)
    args = parser.parse_args()
    args.repo_root = args.repo_root.resolve()
    args.app_root = args.repo_root / "apps/trust-ios"
    args.output_root = args.output_root.resolve()
    args.log_root = args.log_root.resolve()
    args.derived_data = args.derived_data.resolve()
    args.capture_log = args.capture_log.resolve()
    args.paywall_output = args.paywall_output.resolve()
    args.sim_runtime = os.environ.get("TRUST_SIM_RUNTIME") or None
    helper = ensure_helper(args.hinge_helper) if args.hinge_helper else None
    classics, duo = selected_formats(args.devices, bool(helper))
    if args.capture_paywall_review and "iphone-69" not in classics:
        classics.insert(0, "iphone-69")
    if not classics and not duo:
        raise ValueError("No capture format selected.")
    if os.environ.get("TRUST_ALLOW_PARALLEL_SIMULATORS", "0") != "1":
        booted = command(["xcrun", "simctl", "list", "devices", "booted"], check=False).stdout
        if "(Booted)" in booted:
            raise RuntimeError("A simulator is already booted. Shut it down or set TRUST_ALLOW_PARALLEL_SIMULATORS=1 to preserve it.")
    products = args.derived_data / "Build/Products"
    xctestrun = find_xctestrun(products, args.xctestrun)
    app_path = products / "Debug-iphonesimulator/Trust.app"
    info_plist = app_path / "Info.plist"
    if not app_path.is_dir() or not info_plist.is_file():
        raise FileNotFoundError(f"Trust.RealServices simulator app not found at {app_path}; build-for-testing first.")
    with info_plist.open("rb") as source:
        if plistlib.load(source).get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("Built simulator app is not the normal Trust bundle.")
    args.output_root.mkdir(parents=True, exist_ok=True)
    args.log_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(args.log_root, 0o700)
    if (args.log_root / "capture-ledger.json").exists():
        raise FileExistsError(f"Capture log root already has a ledger: {args.log_root}")
    source_sha = command(["git", "-C", str(args.repo_root), "rev-parse", "HEAD"]).stdout.strip()
    source_status = command(["git", "-C", str(args.repo_root), "status", "--porcelain", "--untracked-files=all"]).stdout
    app_source_status = command(["git", "-C", str(args.repo_root), "status", "--porcelain", "--untracked-files=all", "--", "apps/trust-ios"]).stdout
    app_source_diff = command(["git", "-C", str(args.repo_root), "diff", "--binary", "HEAD", "--", "apps/trust-ios"]).stdout
    ledger: dict[str, Any] = {"status": "running", "startedAtUTC": utc_now(),
        "sourceGitSHA": source_sha, "sourceGitDirty": bool(source_status.strip()),
        "appSourceDirty": bool(app_source_status.strip()),
        "appSourceStatus": app_source_status.splitlines(),
        "appSourceWorkingDiffSHA256": hashlib.sha256(app_source_diff.encode("utf-8")).hexdigest(),
        "repoRoot": str(args.repo_root), "derivedData": str(args.derived_data),
        "xctestrun": str(xctestrun), "appPath": str(app_path), "outputRoot": str(args.output_root),
        "logRoot": str(args.log_root), "formats": classics + duo, "requestedDevices": args.devices,
        "trustCapturePhone": args.capture_phone, "capturePaywallReview": args.capture_paywall_review,
        "ownedSimulators": [], "activeSimulator": None, "rawCaptures": [], "nativeCases": [], "failures": []}
    ledger_path = args.log_root / "capture-ledger.json"

    def save() -> None:
        ledger["updatedAtUTC"] = utc_now()
        atomic_json(ledger_path, ledger)

    save()
    try:
        for fmt in classics:
            capture_classic(fmt, CLASSIC_DEVICES[fmt], args, xctestrun, app_path, ledger, save)
        if duo:
            capture_duo_formats(duo, helper, args, xctestrun, app_path, ledger, save)  # type: ignore[arg-type]
        ledger["status"] = "complete"
        ledger["completedAtUTC"] = utc_now()
        save()
        print(f"Capture complete. Raw screenshots: {args.output_root}; logs and ledger: {args.log_root}")
        return 0
    except BaseException as exc:
        ledger["status"] = "failed"
        ledger["failure"] = {"type": type(exc).__name__, "message": str(exc), "failedAtUTC": utc_now()}
        save()
        raise
    finally:
        if ledger.get("activeSimulator"):
            cleanup_owned(ledger, save)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Capture stopped: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
