#!/usr/bin/env python3
"""Validate Trust localization keys and format placeholders."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/TrustCore/TrustCopy.swift"
PROJECT = ROOT / "project.yml"
LOCALES = (
    "zh-Hans.lproj",
    "ja.lproj",
    "de.lproj",
    "fr.lproj",
    "pt-BR.lproj",
)
ENTRY = re.compile(r'^\s*"([^"]+)"\s*=\s*"((?:\\.|[^"])*)";\s*$')
FORMAT = re.compile(r"%(?:[-+0-9$.]*)(?:hh|h|ll|l|q|L)?(?:@|[diouxXf])")
INFOPLIST_REQUIRED = (
    "CFBundleDisplayName",
    "NSCameraUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription",
    "PreciseEscrow",
)


def source_keys() -> tuple[set[str], dict[str, str]]:
    source = SOURCE.read_text(encoding="utf-8")
    keys = set(re.findall(r'(?:value|format)\(\s*"([^"]+)"', source))
    defaults = dict(
        re.findall(
            r'(?:value|format)\(\s*"([^"]+)"\s*,\s*defaultValue:\s*"([^"]*)"',
            source,
            re.DOTALL,
        )
    )
    return keys, defaults


def strings(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        match = ENTRY.match(line)
        if not match:
            raise ValueError(f"{path}:{line_number}: invalid .strings entry")
        key, value = match.groups()
        if key in result:
            raise ValueError(f"{path}:{line_number}: duplicate key {key!r}")
        result[key] = value
    return result


def main() -> int:
    project = PROJECT.read_text(encoding="utf-8")
    localization_block = re.search(
        r"CFBundleLocalizations:\s*\n((?:[ \t]+-[^\n]*\n)+)",
        project,
    )
    shipped_locales = set(
        re.findall(r"^[ \t]+-[ \t]+([^\s#]+)", localization_block.group(1), re.MULTILINE)
    ) if localization_block else set()
    active_locales = {locale.removesuffix(".lproj") for locale in LOCALES} & shipped_locales
    if not active_locales:
        print("Trust ships English only; dormant translation overlays are not emitted or validated.")
        return 0

    expected, defaults = source_keys()
    errors: list[str] = []

    for locale in sorted(active_locales):
        path = ROOT / "Resources" / f"{locale}.lproj" / "Localizable.strings"
        try:
            actual = strings(path)
        except (OSError, ValueError) as error:
            errors.append(str(error))
            continue

        missing = expected - actual.keys()
        extra = actual.keys() - expected
        if missing:
            errors.append(f"{locale}: missing keys: {', '.join(sorted(missing))}")
        if extra:
            errors.append(f"{locale}: unexpected keys: {', '.join(sorted(extra))}")

        for key, default in defaults.items():
            if key not in actual:
                continue
            if sorted(FORMAT.findall(default)) != sorted(FORMAT.findall(actual[key])):
                errors.append(f"{locale}: format placeholders differ for {key!r}")
            if not actual[key].strip():
                errors.append(f"{locale}: empty translation for {key!r}")

        consent = actual.get("phone_consent_details", "")
        for command in ("STOP", "HELP"):
            if command not in consent:
                errors.append(f"{locale}: phone_consent_details must preserve the Twilio {command} command")

    for locale in sorted(active_locales):
        path = ROOT / "Resources" / f"{locale}.lproj" / "InfoPlist.strings"
        try:
            entries = strings(path)
        except (OSError, ValueError) as error:
            errors.append(str(error))
            continue
        for key in INFOPLIST_REQUIRED:
            if not entries.get(key, "").strip():
                errors.append(f"{locale}: missing {key}")
        if entries.get("CFBundleDisplayName") != "Trust":
            errors.append(f"{locale}: CFBundleDisplayName must stay Trust")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"Validated {len(expected)} keys across {len(active_locales)} shipped locales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
