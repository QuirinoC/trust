# App Store screenshot proposal — October 2026

This set is captured from the current Trust app source with the DEBUG screenshot fixture on iOS 26.5 simulators. The six annotated screens in each device group use real app captures: iPhone 6.9-inch, iPhone 6.5-inch, and iPad 13-inch. In the iPad wide People layout, opening View focuses the selected person and follows pin updates until the map is manually panned, so the live pin is visible.

The `raw/` directory is ignored by Git. It contains the unmodified `map`, `look`, `share`, `view`, `log`, and `lookup` app screens for both iPhone and iPad, plus the iPhone `phone` screen used by the public text-consent page. Recreate the complete set from `apps/trust-ios`:

```sh
TRUST_ALLOW_PARALLEL_SIMULATORS=1 ./AppStore/capture-app-store-screenshots.sh
python3 ./AppStore/build-store-screenshots.py --device all --website
```

To recapture one device group only, set `TRUST_CAPTURE_DEVICES=iphone` or `TRUST_CAPTURE_DEVICES=ipad` before running the capture script. The iPad status bar uses 24-hour time so its afternoon clock stays unambiguous; iPhone shows its compact 12-hour time.

Then use the matching builder command. An iPad-only capture has no iPhone raw files for rebuilding the iPhone groups or website images:

```sh
# After TRUST_CAPTURE_DEVICES=ipad
python3 ./AppStore/build-store-screenshots.py --device ipad

# After TRUST_CAPTURE_DEVICES=iphone
python3 ./AppStore/build-store-screenshots.py --device iphone --website
```

The builder checks that every required raw image exists, opens, and has the expected device dimensions before replacing any composed panels.

The website export writes optimized versions of the current map, look, sharing, and activity screens to `apps/jointrust-web/public/screenshots/` and replaces `apps/jointrust-web/public/sms-opt-in.png` with the current phone-consent screen. The iPhone/iPad listing art stays as PNG in this directory.

These are local assets. Nothing in this workflow uploads screenshots to App Store Connect.
