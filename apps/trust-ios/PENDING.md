# iOS release work still pending

This is a short iOS-specific checklist. The canonical, dated release status is [docs/STATUS.md](../../docs/STATUS.md); do not infer completion from this list or from a simulator run.

## Before TestFlight

- The configured release API origin is `https://trust-api-u0ft.onrender.com` and passed readiness; the optional custom hostname `trust.collapsetechnologies.com` still has unresolved TLS and must not be used until independently verified.
- The local Debug simulator build and final iPhone 17 Pro UI suite have passed (4 UI tests; see [docs/STATUS.md](../../docs/STATUS.md)). Archive and upload the reviewed release build through the process in [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).
- Record the actual archive, upload, processing, and device results in `docs/STATUS.md`. The current local target is 1.0 build 19; no TestFlight upload is recorded there.

## Physical-device evidence

- With two separate tester accounts, create an invitation, explicitly accept it, and confirm both directions start Off.
- Confirm a Sealed Look produces one snapshot, leaves sharing Sealed, and does not expose location history. Confirm a Sealed-history request is rejected.
- Confirm Always enables View and location history, while View is recorded without a Look receipt.
- Verify SMS consent and code verification, account deletion, StoreKit sandbox purchase and restore, background location, and Home/Away geofence behavior on the intended devices.
- Check APNs receipt behavior on physical devices. Delivery is best effort; an API request is not proof of delivery or display.

Other deferred scope remains out of this release: widget, Google sign-in on iOS, promise UI, place-ping UI, gifting, SOS, chat, and driving/crash detection. Battery percentage is not displayed. See the root status and deployment docs for API, TLS, and production configuration details.
