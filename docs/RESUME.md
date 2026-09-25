# Resume Trust project work

Checkpoint: 2026-09-24. macOS 26.7 and Xcode 27.1 beta 27A9269 are installed at /Applications/Xcode.app. The Trust app builds from apps/trust-ios/Trust.xcodeproj and scheme Trust; Package.swift is for the core library tests. PR #2 merged to `main` at `31db6cc`.

## Current verified state

- After the TestFlight feedback changes, local Duo UI passed **4/4**, Swift core **26/26**, and API **107/107** with local Postgres. Independent code review found no issue. The final screen was seen in closed Duo; far-end carousel behavior and open-Duo visual sign-off remain.
- Build 22 feedback asked that You legal links stay at the bottom and the profile picker show a centered image, horizontal carousel, 20 more icons, no visible icon names, and Photos/Camera. These changes are implemented locally with 26 total illustrated options (20 new PNGs) and an API preset allowlist. Build 24's optimized archive succeeded and codesign verified; `xcodebuild -exportArchive` validation is blocked pending Xcode App Store Connect account access while the Mac is locked. Build 24 is not uploaded. Build 23 passed archive validation but was not uploaded. Build 22 is the latest uploaded build, with ASC processing/group assignment unverified while signed out.
- PR #1's API, iOS, and web CI checks passed. PR #2 (`31db6cc`) merged the Remove-alert fix; API/iOS/web checks passed, including hosted iOS 26 core and 4 UI tests. The API preset allowlist is deployed; no new website changes are deployed.
- Render deployment `dep-dar1gnm0tbcc73cingv0` was verified live for merge commit `31db6cc`; `/health/ready` returned `200 Healthy`. An unauthenticated avatar PUT returned `401`. Cloudflare version `387f20df-6ce6-46f0-bf55-5b32f1771e67` is deployed; `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned 200. Privacy photo content and support best-effort push wording were verified.
- The latest uploaded TestFlight build remains 22; ASC processing and group assignment are unverified. Build 24’s optimized archive and code signature are verified, but `xcodebuild -exportArchive` is blocked pending Xcode App Store Connect account access while the Mac is locked; build 24 is not uploaded. Build 21 is the pre-redesign build. Version 1.0 submission remains pending. Screenshot upload and privacy answers await ASC access. Resolve the age-policy mismatch: live Terms/Privacy allow household use excluding under-13s, while the ASC draft says 18+.
- Build 20 remains processed, Ready to Submit, and assigned to IJ iPhone Juan. Its earlier archive/export are `/tmp/Trust-1.0-20.xcarchive` and `/tmp/Trust-1.0-20-export/Trust.ipa` (upload UUID `96ca1915-82ec-4b9c-8974-53fe93400d57`).
- Manual Device Hub testing confirmed selected-person retention across Duo close/open; closed mode is compact and open mode restores map-left/person-detail-right. Duo is currently open and booted; open-Duo and far-edge carousel visual sign-off remain pending. iPhone 17 Pro is shut down.
- Production API origin for this build is https://trust-api-u0ft.onrender.com and passed readiness. TLS for trust.collapsetechnologies.com is still unresolved; do not switch the app to that host.
- App Store version 1.0 selects build 21, but ASC rejected adding it to App Review because it was built with Xcode 27.1 beta (27A9269). Beta Xcode can upload build 22 for **internal TestFlight**; public Xcode 27 (27A266a) is needed for a later App Review archive. The draft contains the Trust Plus group and both products (3 items), all Ready for Review; nothing has been submitted. The $0.00 Free base price is saved, availability is unset pending US-only or all-175-region choice, and Mac/Vision Pro compatibility is unverified. The Paid Apps agreement is unverified. The recaptured DEBUG offline-fixture screenshots passed QA but do not prove live account behavior. See [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md).
- Physical-device TestFlight, APNs delivery, and StoreKit purchase/restore results are not recorded. Confirm build 22 processing/group assignment in ASC; restore Xcode account access to validate and upload build 24 after visual sign-off, then install the available updated build for physical checks.

## Resume steps

1. Finish open-Duo and far-edge carousel visual sign-off. Restore Xcode App Store Connect access to complete build 24 export validation and Organizer checks.
2. Validate and upload build 24 through Organizer. Restore ASC browser sign-in to verify processing/group status, then handle screenshot upload and privacy answers.
3. Install the available redesigned build on the physical iPhone and record outcomes in [STATUS.md](STATUS.md), especially StoreKit sandbox purchase/restore and push receipt.

## Local API restart

For the local two-account API flow, restart only the local Postgres service and API; the Docker Compose named volume preserves fixtures. Do not run `docker compose down -v` or point these commands at production.

```bash
cd apps/trust-api
docker compose up postgres -d
dotnet run --launch-profile TrustApi
```

In another terminal, confirm `curl -fsS http://127.0.0.1:5088/health/ready` returns `Healthy`, then run `python3 apps/trust-api/scripts/e2e_two_account_http.py` from the repository root. The script uses local Development API and Postgres only. It creates temporary accounts/relationships, deletes one throwaway account, and leaves other test rows in the local database.

## Deferred product scope

Previously listed ideas remain deferred pending user clarification: widget, Google sign-in on iOS, promise UI, place-ping UI, gifting, SOS, chat, driving/crash detection, and battery percentage. Do not fold these into the current Duo adaptive implementation without that clarification.
