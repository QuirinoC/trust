# App Store screenshots

The current proposed set is in [`2026-09/`](2026-09/README.md). The `raw/` captures show current app UI from the DEBUG screenshot fixture; the final iPhone/iPad compositions use real captured screens with a headline and short explanation. This directory is only a local asset record. Uploading files and seeing them assigned to the draft version in App Store Connect is separate release evidence.

Use [`../capture-app-store-screenshots.sh`](../capture-app-store-screenshots.sh) to recapture the raw current UI. The script builds from source, creates and removes one simulator at a time, and does not upload anything. Set `TRUST_ALLOW_PARALLEL_SIMULATORS=1` only when another booted simulator should stay untouched. See [review readiness](../REVIEW-READINESS.md) for submission checks.
