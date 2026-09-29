# Trust project status

Updated 2026-09-29. This is a dated evidence snapshot; verify live service and App Store Connect state before relying on it.

## Current release evidence

Stable Xcode 27.0 produced version 1.0 build 34 from the current source. The local archive is `/tmp/Trust-1.0-34-AppStore-20260929.xcarchive`; the exported App Store IPA is `/tmp/Trust-1.0-34-AppStore-Export-20260929/Trust.ipa`. The export is signed by Apple Distribution team `3S529795M9`, has production APNs and `get-task-allow=false`, and has phone-verification bypass disabled. Its production API URL is `https://trust-api-u0ft.onrender.com`. It has not been uploaded. App Store Connect still has a draft selecting build 27. Its English (U.S.) name is now `Trust: Location Sharing`, with current subtitle, qualified description, keywords, URLs, and matching beta description verified through Apple’s API. Its English (U.S.) iPhone 6.9, iPhone 6.5, and iPad 13 screenshot sets now contain six current images each, ordered 01–06 and confirmed `COMPLETE` at target dimensions; no build selection or submission state was changed.

The paired UI run passed 1/1 with no skips on both devices: Alice `/tmp/trust-pair-alice34-20260929.xcresult` and Bob `/tmp/trust-pair-bob34-20260929.xcresult`. It exercised reciprocal Home/Away presence grants through both native UIs, including Duo, plus onboarding, invitation/acceptance, Home and movement updates/clear, Hidden, Stop, remove/re-add, and fresh default-Off state. Swift tests passed 77/77 and API tests passed 183/183. The account-owned cache isolation fix has been reviewed by Sol.

## Production and release decision

**Public release remains NO-GO.** The last recorded production observation was Render commit `c3401cf` (26 September): `/health/ready` was healthy and unauthenticated `PUT /api/v1/age-assurance/app-transaction` returned 404. Recheck before acting; migrations 014–020 and corresponding API routes were not deployed in that observation. The full API suite passed 183/183 locally. A synthetic 013→020 migration rehearsal and a twice-applied migration on a private local restore of the Render backup reached ledger 001–020 with all 20 pre-existing business-table row counts unchanged. Rollback and build-32 client compatibility remain unverified; no live production database write was made.

The one remaining App Store group, Trust Family Auto, is internal and has `hasAccessToAllBuilds=true`; all three testers remain in it. Duplicate groups iPhone Juan, Trust Internal Testers, and Family Test were removed after a protected metadata backup and verification that their combined membership matched the retained group. Deploy the reviewed backend, verify health, migration state, and protected routes, and only then upload build 34; upload automatically exposes it to Trust Family Auto. No upload or deployment is claimed here. Build 32 remains internal-only; it has the phone-verification bypass and its exact Off/Remove/Delete compatibility is limited to the documented API behavior, without build-32 UI proof.

## Remaining release work

- Deterministically test delayed stale reads, failed post-mutation refresh, Stop/Remove/partial Stop All through relaunch, and delayed Look/History while the peer stops, removes, and re-adds.
- Complete physical-device checks for SMS, background location, APNs permission/token/presentation/taps, StoreKit purchase/restore/expiry/refund, and account deletion. Apple Sandbox behavior and first-login Offline/Retry handling also need evidence.
- Verify production API deployment and build compatibility before upload; then verify App Store Connect build processing/assignment and reconcile listing metadata, uploaded screenshots, privacy/age answers, agreements, reviewer access, and legal claims against the exact binary.
- Resolve audience classification and launch-market age requirements with counsel. Keep the public no-go until these release gates have evidence.

Both simulator lanes used isolated Development + Memory API on loopback port 5089, reserved fictional 555-01xx numbers, and Development OTP. No SMS was sent, and no simulator push registration proves APNs delivery. The website and public marketing changes are not evidence of deployment. Do not claim public availability or purchase app-install traffic before the release gates pass.

The design direction and palette are in [DESIGN.md](DESIGN.md). The detailed local interaction evidence is in [LOCAL-TWO-ACCOUNT-E2E.md](LOCAL-TWO-ACCOUNT-E2E.md), and the verification plan is in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md).
