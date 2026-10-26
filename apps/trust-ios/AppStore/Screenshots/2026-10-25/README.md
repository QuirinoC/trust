# Trust App Store screenshot set — 25 October 2026

This set contains 18 composed panels across the 6.9-inch iPhone, 6.5-inch iPhone, and 13-inch iPad groups. The panels were captured from source base `c70756f390342f6fc859f75eed4cb2f23c0abecc` with build 47 metadata. Astra passed all raw iPhone captures, all six raw iPad captures, and all 18 final panels. The panels were uploaded to the existing App Store Connect groups; all three groups are `COMPLETE`, with six images each in `01-map`, `02-look`, `03-share`, `04-view`, `05-log`, `06-lookup` order. App Store Connect returned source MD5s and dimensions matching all 18 local composed files. The transfer initially failed during the iPad group upload; the upload was restored and retried, and final verification found no omissions. The final screenshot checksum/order audit and backup of prior ASC screenshots are in `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-10-25/Trust-1.0-47-ReleaseEvidence/`.

## Source and fixture limits

Fourteen raw Debug captures (seven routes per device) were made on disposable iPhone 17 Pro Max and iPad Pro 13-inch M5 simulators using iOS 26.5. The app used `TRUST_DEMO=1`, `TRUST_UI_TEST=1`, and the screenshot fixture. Contacts and location values are fictional. These images do not establish production account state, production privacy behavior, real device behavior, or customer location data. The local `raw/` directory is Git-ignored and may be absent from a fresh checkout. The original captures are retained in `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-10-25/Trust-1.0-47-ReleaseEvidence/raw-simulator-captures/`, with their hashes in `raw-capture-hashes.json` in the same evidence folder. Before running the builder from a fresh checkout, recapture into this set's `raw/` directory or restore the retained originals there. `manifest.json` lists each composed panel's dimensions and SHA-256, plus source, build, capture date, and fixture note.

The 18 final listing panels are:

- `iphone-69/`: six PNGs at **1320 × 2868**.
- `iphone-65/`: six PNGs at **1242 × 2688**, downsampled from the composed 6.9-inch iPhone panels.
- `ipad-13/`: six PNGs at **2064 × 2752**.

The iPhone raw set also contains the phone-consent route; it is not one of the six App Store listing panels.

## Reproduction commands

Run from `apps/trust-ios` after selecting the intended source checkout. The capture script builds the Debug simulator app, creates and deletes its own simulators, and writes raw screenshots to the requested output folder:

```sh
OUTPUT_ROOT="$PWD/AppStore/Screenshots/2026-10-25/raw" \
  ./AppStore/capture-app-store-screenshots.sh
```

To compose into a non-default dated folder, load the existing builder and point its `SET` at that folder before calling its `--device all` entry point:

```sh
python3 - <<'PY'
import importlib.util
from pathlib import Path
import sys

builder_path = Path("AppStore/build-store-screenshots.py")
spec = importlib.util.spec_from_file_location("store_screenshots", builder_path)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
builder.SET = Path("AppStore/Screenshots/2026-10-25")
sys.argv = [str(builder_path), "--device", "all"]
builder.main()
PY
```

The builder writes the 6.9-inch iPhone and iPad panels and derives the 6.5-inch group from the iPhone set. It does not upload images or confirm that the captures are visually acceptable. For a future refresh, review against [DESIGN.md](../../../../../docs/DESIGN.md), then upload and verify each App Store Connect screenshot group separately.
