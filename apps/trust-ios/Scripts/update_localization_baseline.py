#!/usr/bin/env python3
"""Accept reviewed English copy changes after every locale overlay is updated."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/TrustCore/TrustCopy.swift"
PROJECT = ROOT / "project.yml"
BASELINE = Path(__file__).with_name("localization_source_baseline.json")
OVERLAYS = Path(__file__).with_name("overlays")
LOCALES = ("zh-Hans", "ja", "de", "fr", "pt-BR")
FORMAT = re.compile(r"%(?:[-+0-9$.]*)(?:hh|h|ll|l|q|L)?(?:@|[diouxXf])")


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python3 update_localization_baseline.py <reviewed-key> [...]", file=sys.stderr)
        return 2

    source = SOURCE.read_text(encoding="utf-8")
    defaults = dict(re.findall(
        r'(?:value|format)\(\s*"([^"]+)"\s*,\s*defaultValue:\s*"([^"]*)"',
        source,
        re.DOTALL,
    ))
    try:
        baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Cannot read English baseline: {error}", file=sys.stderr)
        return 1

    project = PROJECT.read_text(encoding="utf-8")
    block = re.search(r"CFBundleLocalizations:\s*\n((?:[ \t]+-[^\n]*\n)+)", project)
    shipped = set(re.findall(r"^[ \t]+-[ \t]+([^\s#]+)", block.group(1), re.MULTILINE)) if block else set()
    locales = tuple(locale for locale in LOCALES if locale in shipped)

    requested = set(sys.argv[1:])
    unknown = requested - defaults.keys()
    if unknown:
        print(f"Unknown TrustCopy keys: {', '.join(sorted(unknown))}", file=sys.stderr)
        return 2

    errors: list[str] = []
    for locale in locales:
        path = OVERLAYS / f"{locale}.json"
        try:
            translated = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"{locale}: {error}")
            continue
        for key in sorted(requested):
            value = translated.get(key)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{locale}: {key!r} needs a reviewed translation before baseline refresh")
            elif sorted(FORMAT.findall(defaults[key])) != sorted(FORMAT.findall(value)):
                errors.append(f"{locale}: format placeholders differ for {key!r}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    for key in requested:
        baseline[key] = defaults[key]
    BASELINE.write_text(json.dumps(baseline, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Accepted {len(requested)} reviewed English source string(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
