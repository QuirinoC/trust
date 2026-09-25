# Resume Trust project work

Checkpoint: 2026-09-24. macOS 26.7 and Xcode 27.1 beta 27A9269 are installed at /Applications/Xcode.app. The Trust app builds from apps/trust-ios/Trust.xcodeproj and scheme Trust; Package.swift is for the core library tests.

## Current verified state

- The redesigned iOS 27.1 Duo UI suite passed **4/4** via `xcodebuild` (`/tmp/trust-redesign-ui-full.log`), with **26/26** core tests in the same run. The API suite passed **106/106** with isolated Postgres, and the website `node --test` suite passed **3/3**. A focused compact-width pause test passed after the final layout fix (`/tmp/trust-redesign-compact-paused.log`).
- The current local redesign includes the Together Lines sign-in, compact Sharing rows and centered stop-sharing alert, adaptive People/map layout, simplified You screen, profile pictures, Home/Away privacy gate, and refreshed legal pages. The 14 M6 iPhone/iPad screenshots were recaptured from local build 22; they have not been uploaded to ASC. See [STATUS.md](STATUS.md) for remaining production verification.
- Current source is version 1.0 build **22** in `project.yml` and `Trust.xcodeproj`; it has not been archived or uploaded. The previous Release archive is `apps/trust-ios/build/archives/Trust-1.0-21.xcarchive`, signed by team `3S529795M9`. Organizer validation passed and upload completed at 8:45 PM Pacific. As of 8:50 PM Pacific, ASC TestFlight Build Uploads showed build **21**, the older pre-redesign app, **Ready to Submit** and automatically assigned to the existing internal iPhone Juan group. It has 0 installs, sessions, crashes, and feedback. Version 1.0 selects build 21; it remains Prepare for Submission and nothing has been submitted.
- Build 20 remains processed, Ready to Submit, and assigned to IJ iPhone Juan. Its earlier archive/export are `/tmp/Trust-1.0-20.xcarchive` and `/tmp/Trust-1.0-20-export/Trust.ipa` (upload UUID `96ca1915-82ec-4b9c-8974-53fe93400d57`).
- Manual Device Hub testing confirmed selected-person retention across Duo close/open; closed mode is compact and open mode restores map-left/person-detail-right.
- Production API origin for this build is https://trust-api-u0ft.onrender.com and passed readiness. TLS for trust.collapsetechnologies.com is still unresolved; do not switch the app to that host.
- App Store version 1.0 selects build 21, but ASC rejected adding it to App Review because it was built with Xcode 27.1 beta (27A9269). Beta Xcode can upload build 22 for **internal TestFlight**; public Xcode 27 (27A266a) is needed for a later App Review archive. The draft contains the Trust Plus group and both products (3 items), all Ready for Review; nothing has been submitted. The $0.00 Free base price is saved, availability is unset pending US-only or all-175-region choice, and Mac/Vision Pro compatibility is unverified. The Paid Apps agreement is unverified. The recaptured DEBUG offline-fixture screenshots passed QA but do not prove live account behavior. See [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md).
- Physical-device TestFlight, APNs delivery, and StoreKit purchase/restore results are not recorded. Upload build 22, then install that redesigned build from the internal iPhone Juan group.
- Website support correction is deployed as Cloudflare version `5c1d221f-4e07-4adb-9b4d-9c1844de332b`; live `/`, `/support`, `/privacy`, `/terms`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned **200**.

## Resume steps

1. Complete the release order in [DEPLOYMENT.md](DEPLOYMENT.md), including PR checks, the API/web rollout, and internal TestFlight build 22.
2. Install build 22 on the physical iPhone and record actual outcomes in [STATUS.md](STATUS.md), especially StoreKit sandbox purchase/restore and push receipt.

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
