# Trust App Store screenshots — September 2026

This is a proposed asset set for the App Store listing. It shows the current interface in this order: location sharing and checks, one snapshot, per-person sharing choices, separate live sharing, the Activity record, and connection setup.

## Upload assets

- `iphone-69/`: six annotated 6.9-inch iPhone panels at **1320 × 2868**, RGB PNG.
- `iphone-65/`: the same six panels at **1242 × 2688**, RGB PNG for the 6.5-inch listing group.
- `ipad-13/`: the same six panels at **2064 × 2752**, RGB PNG for the 13-inch iPad listing.
- `raw/`: local-only direct simulator captures used as the screen layer. These are reproducible and ignored by Git; do not upload the unannotated source images.

The app UI is captured from the current source with the DEBUG-only, offline screenshot fixture. Names and locations are synthetic. The phone-search panel uses the fictional North American test number `+1 (202) 555-0134`; the result represents a verified account that opted into discovery. No real user account or location is included.

## Rebuild

From the repository root, run `apps/trust-ios/AppStore/capture-app-store-screenshots.sh`, then `python3 apps/trust-ios/AppStore/build-store-screenshots.py`. The capture script sets Light appearance, creates and removes its own simulators, and never uploads assets. Pillow and the macOS Avenir Next / Helvetica Neue fonts are used for the annotation layer. The builder exports both supported iPhone listing sizes from the same captured screens and design.

The proposed panels use Trust’s porcelain, navy, blue, and teal palette. Each has one headline, one short explanation, and a large capture of the current app UI. The layout removes the old campaign slogan, category label, and decorative proof badge. Review the images at storefront scale and against the submitted build before uploading; this local asset package does not update App Store Connect.
