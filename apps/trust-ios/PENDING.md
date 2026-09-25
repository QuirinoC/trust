# iOS release status

The dated project status is in [docs/STATUS.md](../../docs/STATUS.md). This page tracks only the iOS build and device checks.

**Current branch is newer than TestFlight build 21.** It contains the Together Lines sign-in/icon redesign, Sharing/People/You changes, profile pictures, the Home/Away privacy gate, and startup refresh changes. Source version is 1.0 build **22**, intended for internal TestFlight. The redesign has not been deployed, archived, or uploaded. The M6 iPhone/iPad screenshot sets were recaptured on 2026-09-24 and are not uploaded to App Store Connect. Local verification is API 106/106, Swift core 26/26, Duo UI 4/4, and web 3/3, recorded in [docs/STATUS.md](../../docs/STATUS.md); physical-device checks are pending.

## Verified

- The app uses the healthy release API origin, https://trust-api-u0ft.onrender.com. The optional custom hostname trust.collapsetechnologies.com still has unresolved TLS.
- The redesigned iOS 27.1 Duo UI suite passed **4/4** via `xcodebuild` on 2026-09-24; log: `/tmp/trust-redesign-ui-full.log`. Swift core tests passed **26/26**, API tests **106/106**, and website tests **3/3**.
- Sol's final read-only review found no actionable issue in adaptive navigation, Map layout, or the sharing confirmation flow.
- Build 21 is the older pre-redesign TestFlight build, **Ready to Submit** and assigned to the existing internal iPhone Juan group. Current local source is build **22**, intended for internal TestFlight; it is not archived or uploaded. Version 1.0 currently selects build 21; nothing has been submitted.
- Build 20 remains uploaded and processed, Ready to Submit, and assigned to the IJ iPhone Juan internal group. Build 19 predates the Duo changes.
- The build 21 TestFlight “What to Test” note is saved live in ASC for one internal tester. It covers phone sign-in, invite consent defaults, sharing modes, Look receipts, People/Map/You, TestFlight sandbox Plus purchase/restore, and best-effort push observation with device and steps. There are no test results yet.
- Xcode 27.1 beta 27A9269 and macOS 26.7 are installed. Duo UDID C6495E9A-B165-46E1-97F9-0B92ABBDDC0D and iPhone 17 Pro UDID 61DC2501-3A93-4123-A6D5-D3512AF07464 are the two retained simulators; eleven unused generated devices were removed. Both are shut down after screenshot capture.

## Build 20 TestFlight

- Version 1.0 build 20 was archived at /tmp/Trust-1.0-20.xcarchive and exported at /tmp/Trust-1.0-20-export/Trust.ipa.
- Xcode Organizer confirmed upload complete. App Store Connect upload UUID 96ca1915-82ec-4b9c-8974-53fe93400d57 is processing Complete and build 20 is Ready to Submit, assigned to the existing IJ iPhone Juan internal group.
- Build 20 is the earlier TestFlight build. Build 21 is Ready to Submit and assigned to the internal iPhone Juan group; install it there for physical checks.

## App Store review readiness

- Stable public Xcode 27 (27A266a) is required for App Review; installed Xcode 27.1 beta can be used to archive build 22 for internal TestFlight. The existing draft contains the Trust Plus group and both products, all Ready for Review; nothing has been submitted. Base price $0.00 Free is saved; availability, metadata, privacy disclosures, and physical checks remain open. The redesigned 14 M6 DEBUG offline-fixture screenshots were recaptured 2026-09-24 and are not uploaded. See [REVIEW-READINESS.md](AppStore/REVIEW-READINESS.md).
- Website support correction deployed on 2026-09-24 as Cloudflare version `5c1d221f-4e07-4adb-9b4d-9c1844de332b`. Live `/`, `/support`, `/privacy`, `/terms`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned **200**.

## Remaining device evidence

- Manual Device Hub testing confirmed that Maya Chen remains selected after Duo is closed and reopened; the closed view is compact, and the open view restores map-left/person-detail-right.
- On the physical TestFlight device, verify account/invite flows, sharing modes, sealed Look/history behavior, SMS consent and verification, StoreKit purchase/restore, background location, geofencing, and APNs receipt as applicable. Simulator results do not prove physical push delivery.
- Keep notifications described as best effort. No durable APNs outbox/retry worker or physical delivery result is recorded.

Deferred scope remains unchanged: widget, Google sign-in on iOS, promise UI, place-ping UI, gifting, SOS, chat, driving/crash detection, and battery percentage.
