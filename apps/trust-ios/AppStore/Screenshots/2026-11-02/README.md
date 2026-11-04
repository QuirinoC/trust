# App Store screenshot draft — 2 November 2026

Status — 3 November: all **36 current panels** are captured, composed and **accepted by Astra**, from frozen application source `faa306f85d4a24732f03b8420cf78b1a556846bf`. The [manifest](manifest.json) records exact final PNG and native-source hashes. All 24 phone/iPad panels are uploaded to the normal App Store draft and read back COMPLETE with exact source checksums, dimensions, sizes and order. The previous 18 assets were backed up before replacement. Both Duo formats are prepared locally; current App Store Connect upload groups are unavailable. This preparation does not submit or release either app.

## Storyboard

1. People — “Share your location. See who checks.”
2. Sharing — “Choose for each person.”
3. Look — “One check. One snapshot.”
4. Activity — “See checks made in Trust.”
5. Always — “Live sharing, by choice.”
6. Add — “Connect first. Share when ready.”

Each complete native screen sits inside its caption panel. Use only the DEBUG fictional fixture; never use customer or reviewer accounts. Do not paint over in-app data or add interface elements that are not in Trust. iPad captures must show the current full split layout and a single map.

## Capture and composition

From `apps/trust-ios`:

```sh
DERIVED="/private/tmp/trust-appstore-2026-11-02-derived" OUTPUT_ROOT="$PWD/AppStore/Screenshots/2026-11-02/raw" ./AppStore/capture-app-store-screenshots.sh
python3 AppStore/build-store-screenshots.py --set-dir 2026-11-02 --device iphone-69
python3 AppStore/build-store-screenshots.py --set-dir 2026-11-02 --device iphone-65
python3 AppStore/build-store-screenshots.py --set-dir 2026-11-02 --device iphone-medium
python3 AppStore/build-store-screenshots.py --set-dir 2026-11-02 --device ipad
```

The shell builds the `Trust.RealServices` scheme once with `build-for-testing`, then runs `capture-native-screenshots.py` against the resulting `Trust.RealServices_*.xctestrun`. That scheme installs the normal Trust bundle and uses the real StoreKit catalog; no local StoreKit catalog is configured. The People image (`map.png`) comes from the existing UI test navigating through Share → People, without granting this phone location permission. The driver does not pre-open the old circle route, so no extra snapshot or prior fixture state is injected before the actual People flow. The Look image (`look.png`) comes from the UI test after the complete consent text, heading, and fixed actions fit in the native sheet. The final Duo checks additionally require a fully visible Close followed by the complete heading and note above Look and Cancel; each posture passed 1/0/0. The viewport is re-resolved after expansion using an actual text ancestor, with a source-grounded ordering check when the accessibility tree exposes no sheet scroll ancestor. Sharing, Activity, View, and Add use their existing DEBUG screenshot routes. The capture code saves native pixels without painting over app UI.

The default `TRUST_CAPTURE_DEVICES=all` selects the four classic formats: `iphone-69`, `iphone-65`, `iphone-medium`, and `ipad-13`. Add an explicit `TRUST_HINGE_HELPER=/path/to/hinge_helper` whose SHA-256 matches the pinned helper (`1997bd4788c561596ad8616e1bf0a1cc71b10685d7807ff88a37b126d1124a84`) to include Duo outer and inner captures in `all`. Duo capture is unavailable without that helper; the script does not download or install it. The driver selects the newest available iOS runtime that advertises support for each device type. The current simulator set uses iOS 27.0 for the classic devices and 27.1 for iPhone Duo. `TRUST_SIM_RUNTIME` can pin a runtime, but it must support every selected device type.

The original selection and output variables remain available: `DERIVED`, `OUTPUT_ROOT`, `CAPTURE_LOG`, `TRUST_CAPTURE_DEVICES`, and `TRUST_ALLOW_PARALLEL_SIMULATORS`. `TRUST_CAPTURE_DEVICES` accepts `all`, `iphone`/`iphone-69`, `iphone-65`, `iphone-medium`, `ipad`/`ipad-13`, and the explicit `duo`, `duo-outer`, or `duo-inner` choices. Set `TRUST_CAPTURE_PHONE=1` to add the website phone-verification source on iPhone 6.9. Set `TRUST_CAPTURE_PAYWALL_REVIEW=1` to capture the actual catalog paywall for review; it only reads the monthly and annual offers and close control, and never taps Purchase, Restore, or Close. `TRUST_PAYWALL_REVIEW_OUTPUT` selects its separate output path. Captures are logs-only preparation and do not upload. Created simulator ownership, runtime, raw image hashes, source Git SHA, test results, `.xcresult` bundles, and test activity export (when available) are kept in the run log folder. A failed native case also records a device screenshot before the owned simulator is removed. Set `TRUST_CAPTURE_LOG_ROOT` to choose the log folder, or `TRUST_XCTESTRUN` to point to a specific generated test run.

The composer validates all six source images and exact dimensions before writing panels. Supported groups are `iphone-69` (1320×2868), `iphone-65` (1242×2688), `iphone-medium` (1206×2622), `ipad-13` (2064×2752), `duo-outer` (1398×2034), and `duo-inner` (2853×2007). Compose Duo with `python3 AppStore/build-store-screenshots.py --set-dir 2026-11-02 --device duo-outer` and `--device duo-inner`. Outer artwork uses a 300–330 px caption region, 64 px gutters, and a proportional complete screenshot below it. Inner artwork uses a shallow 250–280 px full-width caption band, 96 px gutters, and a proportional complete expanded screenshot below it; headline line breaks are removed when possible. The composer does not scale completed artwork or alter captured screenshot pixels.

## Review status and limitations

This capture workflow does not approve screenshots or update App Store Connect. Review screen content, captions, image dimensions and RGB format, text clipping, iPad split layout, and each current App Store Connect device group before any upload. The DEBUG fixture is illustrative and is not evidence of production account or location behavior. The superseded 25 October assets and failed-run diagnostics are retained as historical evidence. Active contact sheets use the `-final` suffix; earlier trial sheets are retained outside the active project to avoid restoring old designs.
