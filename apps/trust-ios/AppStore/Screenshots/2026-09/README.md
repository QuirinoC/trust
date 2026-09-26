# Trust App Store screenshots — September 2026

This is the current draft asset set for the App Store listing. It follows a single-story sequence: a sealed snapshot, the confirmation step, person-by-person sharing choices, exact discovery, the activity record, the separate Always mode, and account controls.

## Upload assets

- `iphone-69/`: seven annotated 6.9-inch iPhone panels at **1320 × 2868**, RGB PNG.
- `ipad-13/`: the same story at **2064 × 2752**, RGB PNG for the 13-inch iPad listing.
- `raw/`: local-only direct simulator captures used as the screen layer. These are reproducible and ignored by Git; do not upload the unannotated source images.

The app UI is captured from the current source with the DEBUG-only, offline screenshot fixture. Names and locations are synthetic. The phone-search panel uses the fictional North American test number `+1 (202) 555-0134`; the result represents a verified account that opted into discovery. No real user account or location is included.

## Rebuild

From the repository root, run `apps/trust-ios/AppStore/capture-app-store-screenshots.sh`, then `python3 apps/trust-ios/AppStore/build-store-screenshots.py`. The capture script creates and removes its own simulators and never uploads assets. Pillow and the macOS Avenir Next / Helvetica Neue fonts are used for the annotation layer.

The final panels keep Trust’s paper, ink, and rust colors, use one short benefit headline and one explanatory annotation per image, and preserve a legible view of the current app screen. They borrow the feature-led sequence pattern from category leaders without reusing their artwork or visual identity. Confirm both device-size groups and the assigned image order in App Store Connect after upload; the draft listing remains separate from this local asset package.
