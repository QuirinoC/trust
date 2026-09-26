#!/usr/bin/env python3
"""Emit Trust Localizable.strings and InfoPlist.strings from TrustCopy defaults + overlays."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/TrustCore/TrustCopy.swift"
PROJECT = ROOT / "project.yml"
OVERLAY_DIR = Path(__file__).with_name("overlays")
LOCALES = ("zh-Hans", "ja", "de", "fr", "pt-BR")


def configured_locales() -> tuple[str, ...]:
    project = PROJECT.read_text(encoding="utf-8")
    block = re.search(r"CFBundleLocalizations:\s*\n((?:[ \t]+-[^\n]*\n)+)", project)
    shipped = set(
        re.findall(r"^[ \t]+-[ \t]+([^\s#]+)", block.group(1), re.MULTILINE)
    ) if block else set()
    return tuple(locale for locale in LOCALES if locale in shipped)


def defaults() -> dict[str, str]:
    source = SOURCE.read_text(encoding="utf-8")
    found = dict(
        re.findall(
            r'(?:value|format)\(\s*"([^"]+)"\s*,\s*defaultValue:\s*"([^"]*)"',
            source,
            re.DOTALL,
        )
    )
    if not found:
        raise SystemExit("no keys in TrustCopy.swift")
    return found


def escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def write_strings(path: Path, entries: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f'"{key}" = "{escape(entries[key])}";' for key in sorted(entries)]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    english = defaults()
    locales = configured_locales()
    if not locales:
        print("Trust ships English only; dormant translation overlays were not emitted.")
        return 0

    errors: list[str] = []
    overlays: dict[str, dict[str, str]] = {}
    for locale in locales:
        path = OVERLAY_DIR / f"{locale}.json"
        if not path.exists():
            errors.append(f"missing overlay {locale}")
            continue
        overlays[locale] = json.loads(path.read_text(encoding="utf-8"))
    for locale in locales:
        table = overlays.get(locale)
        if table is None:
            errors.append(f"missing overlay {locale}")
            continue
        missing = sorted(set(english) - set(table))
        extra = sorted(set(table) - set(english))
        if missing:
            errors.append(f"{locale}: missing {len(missing)} keys: {', '.join(missing[:20])}")
        if extra:
            errors.append(f"{locale}: extra keys: {', '.join(extra[:20])}")
        if missing or extra:
            continue
        write_strings(ROOT / "Resources" / f"{locale}.lproj" / "Localizable.strings", table)
        info = {
            "CFBundleDisplayName": "Trust",
            "NSCameraUsageDescription": table["camera_permission"],
            "NSLocationWhenInUseUsageDescription": table["location_when_in_use"],
            "NSLocationAlwaysAndWhenInUseUsageDescription": table["location_always"],
            "NSLocationAlwaysUsageDescription": table["location_always"],
            "PreciseEscrow": table["location_precise"],
        }
        write_strings(ROOT / "Resources" / f"{locale}.lproj" / "InfoPlist.strings", info)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Wrote {len(english)} keys for {len(LOCALES)} locales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
