# iOS release status

The dated project status is in [docs/STATUS.md](../../docs/STATUS.md). This page tracks only the iOS build and device checks.

Build 22 TestFlight feedback identified two UI issues: keep You legal links at the bottom, and center the profile preview with a horizontal strip of choices, no visible icon names, and Photos/Camera. Implemented locally with 26 illustrated options (20 new PNGs) and an API preset allowlist. Current source is build 24; its archive succeeded and codesign verified for team `3S529795M9`, but Organizer validation and upload have not happened. Build 23 was archive-validated but not uploaded; build 22 remains the latest uploaded build, with ASC processing/group unverified while signed out.

The Remove-alert fix moves Remove into the parent alert and is in open PR #2 (`50fec6b`); checks are pending. After the feedback changes, local Duo UI passed **4/4**, Swift core **26/26**, API **107/107** with local Postgres. Independent code review found no issues. Final screen was checked in closed Duo; far-end carousel and open-Duo visual sign-off remain. API preset allowlist changes are not deployed, and no new site changes are deployed. M6 screenshot/privacy ASC work, age-policy decision, and physical-device tests remain open.

## Verified

- The app uses the healthy release API origin, https://trust-api-u0ft.onrender.com. The optional custom hostname trust.collapsetechnologies.com still has unresolved TLS.
- After the TestFlight feedback changes, local Duo UI tests passed **4/4**, Swift core **26/26**, and API **107/107** with local Postgres.
- Sol's final read-only review found no actionable issue in adaptive navigation, Map layout, or the sharing confirmation flow.
- Build 22 is the latest uploaded build; ASC processing and internal group assignment are unverified. Build 23's archive was validated but not uploaded. Build 24's archive succeeded and codesign verified, but Organizer validation and upload are pending.
- Build 20 remains uploaded and processed, Ready to Submit, and assigned to the IJ iPhone Juan internal group. Build 19 predates the Duo changes.
- The build 21 TestFlight “What to Test” note is saved live in ASC for one internal tester. It covers phone sign-in, invite consent defaults, sharing modes, Look receipts, People/Map/You, TestFlight sandbox Plus purchase/restore, and best-effort push observation with device and steps. There are no test results yet.
- Xcode 27.1 beta 27A9269 and macOS 26.7 are installed. Duo UDID C6495E9A-B165-46E1-97F9-0B92ABBDDC0D and iPhone 17 Pro UDID 61DC2501-3A93-4123-A6D5-D3512AF07464 are the two retained simulators; eleven unused generated devices were removed. Duo is currently booted; iPhone 17 Pro is shut down.

## Build 20 TestFlight

- Version 1.0 build 20 was archived at /tmp/Trust-1.0-20.xcarchive and exported at /tmp/Trust-1.0-20-export/Trust.ipa.
- Xcode Organizer confirmed upload complete. App Store Connect upload UUID 96ca1915-82ec-4b9c-8974-53fe93400d57 is processing Complete and build 20 is Ready to Submit, assigned to the existing IJ iPhone Juan internal group.
- Build 20 is the earlier TestFlight build. Build 21 is Ready to Submit and assigned to the internal iPhone Juan group; install it there for physical checks.

## App Store review readiness

- Stable public Xcode 27 (27A266a) is required for App Review; Xcode 27.1 beta was used for the uploaded internal build. ASC is signed out, so screenshot upload and privacy answers remain pending. The 14 M6 DEBUG screenshots reflect build 22 and remain unuploaded; recapture the updated picker after visual sign-off. Age policy is unresolved between live legal pages (household use, under-13 exclusion) and the 18+ ASC draft. See [REVIEW-READINESS.md](AppStore/REVIEW-READINESS.md).
- Cloudflare version `387f20df-6ce6-46f0-bf55-5b32f1771e67` is deployed. `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned **200**. Photo privacy content and best-effort push support wording were verified.

## Remaining device evidence

- Manual Device Hub testing confirmed that Maya Chen remains selected after Duo is closed and reopened; the closed view is compact, and the open view restores map-left/person-detail-right.
- On the physical TestFlight device, verify account/invite flows, sharing modes, sealed Look/history behavior, SMS consent and verification, StoreKit purchase/restore, background location, geofencing, and APNs receipt as applicable. Simulator results do not prove physical push delivery.
- Keep notifications described as best effort. No durable APNs outbox/retry worker or physical delivery result is recorded.

Deferred scope remains unchanged: widget, Google sign-in on iOS, promise UI, place-ping UI, gifting, SOS, chat, driving/crash detection, and battery percentage.
