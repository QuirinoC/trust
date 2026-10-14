#!/usr/bin/env python3
"""Validate checked-in Trust inputs before an Xcode Cloud build starts.

This is a source and project configuration guard. It does not build, sign, or
inspect an archive.
"""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]
TRUST_BASE_URL = "https://trust-api-u0ft.onrender.com"
DEBUG_BASE_URL = "http://127.0.0.1:5088"
BUNDLE_ID = "com.collapsetechnologies.trust"
TEAM_ID = "3S529795M9"
LOCALES = ("zh-Hans", "ja", "de", "fr", "pt-BR")


def _locales(root: Path) -> tuple[str, ...]:
    project = (root / "project.yml").read_text(encoding="utf-8")
    block = re.search(r"CFBundleLocalizations:\s*\n((?:[ \t]+-[^\n]*\n)+)", project)
    shipped = set(
        re.findall(r"^[ \t]+-[ \t]+([^\s#]+)", block.group(1), re.MULTILINE)
    ) if block else set()
    return tuple(locale for locale in LOCALES if locale in shipped)


def _localization_defaults(root: Path) -> dict[str, str]:
    source = (root / "Sources/TrustCore/TrustCopy.swift").read_text(encoding="utf-8")
    return dict(
        re.findall(
            r'(?:value|format)\(\s*"([^"]+)"\s*,\s*defaultValue:\s*"([^"]*)"',
            source,
            re.DOTALL,
        )
    )


def _render_strings(entries: dict[str, str]) -> str:
    def escape(value: str) -> str:
        return (
            value.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\t", "\\t")
        )

    return "\n".join(f'"{key}" = "{escape(entries[key])}";' for key in sorted(entries)) + "\n"


def localization_freshness_errors(root: Path) -> list[str]:
    """Compare emitted files byte-for-byte without rewriting the checkout."""
    locales = _locales(root)
    if not locales:
        return []

    english = _localization_defaults(root)
    if not english:
        return ["TrustCopy.swift contains no localization defaults"]

    errors: list[str] = []
    overlay_dir = root / "Scripts/overlays"
    for locale in locales:
        overlay_path = overlay_dir / f"{locale}.json"
        try:
            overlay = json.loads(overlay_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"{overlay_path}: missing or invalid overlay ({error})")
            continue

        if set(overlay) != set(english):
            errors.append(f"{locale}: overlay keys differ from TrustCopy.swift")
            continue

        generated = {
            "Localizable.strings": _render_strings(overlay),
            "InfoPlist.strings": _render_strings(
                {
                    "CFBundleDisplayName": "Trust",
                    "NSCameraUsageDescription": overlay["camera_permission"],
                    "NSLocationWhenInUseUsageDescription": overlay["location_when_in_use"],
                    "NSLocationAlwaysAndWhenInUseUsageDescription": overlay["location_always"],
                    "NSLocationAlwaysUsageDescription": overlay["location_always"],
                    "PreciseEscrow": overlay["location_precise"],
                }
            ),
        }
        for name, expected in generated.items():
            path = root / "Resources" / f"{locale}.lproj" / name
            try:
                actual = path.read_text(encoding="utf-8")
            except OSError as error:
                errors.append(f"{path}: missing generated localization ({error})")
                continue
            if actual != expected:
                errors.append(
                    f"{path}: stale generated localization; run Scripts/emit_localizations.py and review the diff"
                )
    return errors


def _configuration_blocks(project: str, list_name: str) -> list[tuple[str, str]]:
    config_list = re.search(
        rf'([A-F0-9]{{24}}) /\* Build configuration list for {re.escape(list_name)} \*/\s*=\s*\{{\s*'
        r"isa = XCConfigurationList;\s*buildConfigurations = \((.*?)\);",
        project,
        re.DOTALL,
    )
    if not config_list:
        return []

    blocks: list[tuple[str, str]] = []
    for identifier in re.findall(r"[A-F0-9]{24}", config_list.group(2)):
        match = re.search(
            rf"{identifier} /\* (Debug|Release) \*/\s*=\s*\{{(.*?)\n\t\t\}};",
            project,
            re.DOTALL,
        )
        if match:
            blocks.append((match.group(1), match.group(2)))
    return blocks


def _yaml_target_block(source: str, target_name: str) -> str | None:
    match = re.search(
        rf"(?ms)^  {re.escape(target_name)}:\s*\n(.*?)(?=^  [A-Za-z_][A-Za-z0-9_-]*:\s*$|\Z)",
        source,
    )
    return match.group(1) if match else None


def _scheme_buildable_is_trust(reference: ET.Element | None) -> bool:
    return bool(
        reference is not None
        and reference.get("BlueprintName") == "Trust"
        and reference.get("BuildableName") == "Trust.app"
        and reference.get("ReferencedContainer") == "container:Trust.xcodeproj"
    )


def project_configuration_errors(root: Path) -> list[str]:
    errors: list[str] = []
    source = (root / "project.yml").read_text(encoding="utf-8")
    project_path = root / "Trust.xcodeproj/project.pbxproj"
    project = project_path.read_text(encoding="utf-8")
    scheme_path = root / "Trust.xcodeproj/xcshareddata/xcschemes/Trust.xcscheme"
    scheme = scheme_path.read_text(encoding="utf-8")

    source_expectations = {
        "name: Trust": "project name",
        f"PRODUCT_BUNDLE_IDENTIFIER: {BUNDLE_ID}": "bundle identifier",
        "PRODUCT_NAME: Trust": "product name",
        f"DEVELOPMENT_TEAM: {TEAM_ID}": "development team",
        f"TRUST_BASE_URL: {TRUST_BASE_URL}": "production API URL",
        f"TRUST_BASE_URL: {DEBUG_BASE_URL}": "Debug API URL",
    }
    for expected, label in source_expectations.items():
        if expected not in source:
            errors.append(f"project.yml is missing the expected {label}")

    info_plists = {"Trust": "Info.plist", "TrustInternal": "Internal-Info.plist"}
    for target_name, plist_name in info_plists.items():
        target_source = _yaml_target_block(source, target_name)
        if target_source is None:
            errors.append(f"project.yml is missing the {target_name} app target")
        else:
            phone_flag = re.search(
                r"(?m)^\s+TRUST_SKIP_PHONE_VERIFICATION:\s*(\S+)\s*$", target_source
            )
            if not phone_flag or phone_flag.group(1).lower() not in {"false", "no"}:
                errors.append(
                    f"project.yml {target_name} target must keep phone-verification bypass disabled"
                )
            if not re.search(rf"(?m)^\s+path:\s*{re.escape(plist_name)}\s*$", target_source):
                errors.append(f"project.yml {target_name} target must generate {plist_name}")

        path = root / plist_name
        try:
            with path.open("rb") as plist_file:
                plist = plistlib.load(plist_file)
        except (OSError, plistlib.InvalidFileException) as error:
            errors.append(f"{plist_name} is missing or invalid ({error})")
            continue
        if plist.get("TRUST_SKIP_PHONE_VERIFICATION") is not False:
            errors.append(f"{plist_name} must keep phone-verification bypass disabled")

    try:
        scheme_root = ET.fromstring(scheme)
    except ET.ParseError as error:
        scheme_root = None
        errors.append(f"shared Trust scheme is invalid XML ({error})")
    if scheme_root is not None:
        build_entries = scheme_root.findall("./BuildAction/BuildActionEntries/BuildActionEntry")
        build_refs = [entry.find("./BuildableReference") for entry in build_entries]
        if len(build_refs) != 1 or not _scheme_buildable_is_trust(build_refs[0]):
            errors.append("shared Trust scheme BuildAction must build the Trust.app product")
        elif build_entries[0].get("buildForArchiving") != "YES":
            errors.append("shared Trust scheme BuildAction must include Trust.app for archiving")

        test_action = scheme_root.find("./TestAction")
        if test_action is None or test_action.get("buildConfiguration") != "Debug":
            errors.append("shared Trust scheme TestAction must use Debug configuration")
        elif not _scheme_buildable_is_trust(test_action.find("./MacroExpansion/BuildableReference")):
            errors.append("shared Trust scheme TestAction must expand the Trust.app product")

        archive_action = scheme_root.find("./ArchiveAction")
        if archive_action is None or archive_action.get("buildConfiguration") != "Release":
            errors.append("shared Trust scheme ArchiveAction must use Release configuration")

    if re.search(r"\bINFOPLIST_KEY_TRUST_SKIP_PHONE_VERIFICATION\b", source + "\n" + project):
        errors.append(
            "INFOPLIST_KEY_TRUST_SKIP_PHONE_VERIFICATION overrides are unsupported; keep the checked-in Info plists authoritative"
        )

    blocks = _configuration_blocks(project, 'PBXNativeTarget "Trust"')
    by_name = {name: block for name, block in blocks}
    if set(by_name) != {"Debug", "Release"}:
        errors.append("checked-in Xcode project must contain Debug and Release configurations for Trust")
    else:
        for config in ("Debug", "Release"):
            block = by_name[config]
            required = {
                f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};': "bundle identifier",
                "PRODUCT_NAME = Trust;": "product name",
                f"DEVELOPMENT_TEAM = {TEAM_ID};": "development team",
                "INFOPLIST_FILE = Info.plist;": "app Info.plist",
            }
            for expected, label in required.items():
                if expected not in block:
                    errors.append(f"Xcode {config} configuration has an unexpected {label}")
            if re.search(r"\bbaseConfigurationReference\s*=", block):
                errors.append(
                    f"Xcode {config} Trust target configuration uses baseConfigurationReference; Cloud validator cannot resolve xcconfig overrides"
                )
            if re.search(r"\bTRUST_BASE_URL\s*=", block):
                errors.append(
                    f"Xcode {config} Trust target overrides TRUST_BASE_URL; keep it in the project configuration"
                )

    internal_blocks = _configuration_blocks(project, 'PBXNativeTarget "TrustInternal"')
    internal_by_name = {name: block for name, block in internal_blocks}
    if set(internal_by_name) != {"Debug", "Release"}:
        errors.append("checked-in Xcode project must contain Debug and Release configurations for TrustInternal")
    else:
        for config, block in internal_by_name.items():
            required = {
                f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};': "bundle identifier",
                "PRODUCT_NAME = Trust;": "product name",
                f"DEVELOPMENT_TEAM = {TEAM_ID};": "development team",
            }
            for expected, label in required.items():
                if expected not in block:
                    errors.append(f"Xcode {config} TrustInternal configuration has an unexpected {label}")
            if not re.search(r'INFOPLIST_FILE = "?Internal-Info\.plist"?;', block):
                errors.append(f"Xcode {config} TrustInternal configuration has an unexpected Internal-Info.plist")
            if re.search(r"\bbaseConfigurationReference\s*=", block):
                errors.append(
                    f"Xcode {config} TrustInternal configuration uses baseConfigurationReference; Cloud validator cannot resolve xcconfig overrides"
                )
            if re.search(r"\bTRUST_BASE_URL\s*=", block):
                errors.append(
                    f"Xcode {config} TrustInternal target overrides TRUST_BASE_URL; keep it in the project configuration"
                )

    project_blocks = _configuration_blocks(project, 'PBXProject "Trust"')
    project_by_name = {name: block for name, block in project_blocks}
    if set(project_by_name) != {"Debug", "Release"}:
        errors.append("checked-in Xcode project must contain Debug and Release project configurations")
    else:
        for config, expected_url in (("Debug", DEBUG_BASE_URL), ("Release", TRUST_BASE_URL)):
            if f'TRUST_BASE_URL = "{expected_url}";' not in project_by_name[config]:
                errors.append(f"Xcode {config} project configuration has an unexpected API URL")
            if re.search(r"\bbaseConfigurationReference\s*=", project_by_name[config]):
                errors.append(
                    f"Xcode {config} project configuration uses baseConfigurationReference; Cloud validator cannot resolve xcconfig overrides"
                )

    if "/* Begin PBXNativeTarget section */" not in project or not re.search(
        r"/\* Trust \*/\s*=\s*\{\s*isa = PBXNativeTarget;", project
    ):
        errors.append("checked-in Xcode project must contain the Trust application target")
    return errors


def validate(root: Path) -> list[str]:
    errors = project_configuration_errors(root)
    errors.extend(localization_freshness_errors(root))
    validator = root / "Scripts/validate_localizations.py"
    completed = subprocess.run(
        [sys.executable, str(validator)],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        details = (completed.stderr or completed.stdout).strip()
        errors.append("localization structure validation failed" + (f":\n{details}" if details else ""))
    return errors


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else IOS_ROOT
    errors = validate(root)
    if errors:
        print("Trust Cloud pre-build validation failed:", file=sys.stderr)
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1
    print("Trust Cloud pre-build validation passed (source, project, and localization checks only).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
