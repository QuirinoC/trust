#!/usr/bin/env python3
"""Validate Trust localization keys and format placeholders."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/TrustCore/TrustCopy.swift"
LOCALES = (
    "es.lproj",
    "ja.lproj",
    "zh-Hans.lproj",
    "de.lproj",
    "fr.lproj",
    "ko.lproj",
    "pt-BR.lproj",
)
ENTRY = re.compile(r'^\s*"([^"]+)"\s*=\s*"((?:\\.|[^"])*)";\s*$')
FORMAT = re.compile(r"%(?:[-+0-9$.]*)(?:hh|h|ll|l|q|L)?(?:@|[diouxXf])")
INFOPLIST_REQUIRED = (
    "CFBundleDisplayName",
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
    expected, defaults = source_keys()
    errors: list[str] = []

    for locale in LOCALES:
        path = ROOT / "Resources" / locale / "Localizable.strings"
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

    for locale in LOCALES:
        path = ROOT / "Resources" / locale / "InfoPlist.strings"
        try:
            entries = strings(path)
        except (OSError, ValueError) as error:
            errors.append(str(error))
            continue
        for key in INFOPLIST_REQUIRED:
            if not entries.get(key, "").strip():
                errors.append(f"{locale}: missing {key}")
        if entries.get("CFBundleDisplayName") != "Trust Circle":
            errors.append(f"{locale}: CFBundleDisplayName must stay Trust Circle")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"Validated {len(expected)} keys across {len(LOCALES)} locales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
