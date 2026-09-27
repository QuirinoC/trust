# Trust project status

Updated 2026-09-26. This is a dated evidence snapshot; verify live service and App Store Connect state before relying on it.

## Current source

The checked-out branch is `main` at `c3401cf` (`Consent-aware discovery and App Store screenshots`, already on `origin/main`). There was no outstanding feature branch to merge. This working change restores the approved blue light palette, aligns the App Store screenshot artwork and capture script to it, removes the iPad Simulator resize affordance from the prepared artwork, and advances the iOS build number to 31.

The current design direction and actual palette tokens are in [DESIGN.md](DESIGN.md). The app icon redesign remains paused.

## Verification evidence

- Swift package tests: **33/33 passed**.
- Stable iPhone 17 Pro Xcode UI suite: **41/41 passed** (33 core + 8 UI).
- API suite: **132/132 passed**.
- Website tests: **3/3 passed**; localization validation found **470 keys across five translated locales**.
- Real-API onboarding, phone lookup, invite sharing, request acceptance, default-Off sharing, and stopping sharing passed once on stable iOS 26.5 and once on iOS 27.1 beta Duo.
- Local development API health, Cloudflare Wrangler authentication, and a website deploy dry run were verified.
- App Store screenshot assets were regenerated for iPhone 6.9-inch, iPhone 6.5-inch, and iPad 13-inch sets. The capture script explicitly uses Light appearance. The assets are local; they have not been uploaded to the App Store listing.
- Build 31 was archived with the `Trust-Internal` scheme, checked to contain `TRUST_SKIP_PHONE_VERIFICATION=true`, and uploaded successfully to App Store Connect using the internal-only export configuration. At the last check, App Store Connect reported that the package was processing. Assignment to an internal group and tester visibility are not yet verified.

On Duo's iOS 27.1 beta, XCTest could not close the system share sheet with its close-button tap; a swipe-down closed it and the rest of the real-API flow passed. Simulator checks do not establish physical SMS, Sign in with Apple, APNs delivery, background location, or TestFlight behavior.

## Release state

- The current branch contains the latest merged app work plus the pending palette, screenshot, and build-number changes. Commit and push those changes to `main`.
- Build 31 is uploaded for internal TestFlight and was processing at last observation. Complete processing verification and assign it to the intended existing internal group; confirm the tester can see build 31 before calling TestFlight delivery complete.
- App Store listing artwork is not updated. The refreshed screenshot sets are staged locally, and the current listing icon/screenshots still need an App Store Connect review and update.
- The production Render API and Cloudflare site were previously observed on an earlier release; deploy and health-check current server/site changes separately.
- Reconcile the Send code disclosure with Twilio campaign records and public SMS evidence. Do not claim carrier SMS consent language is registered until verified.
- Push delivery has not been end-to-end verified. APNs delivery is best effort; a successful server publish does not prove delivery to a device.

## Remaining product and release work

Complete physical two-account TestFlight checks for SMS, background location, notification receipt, StoreKit purchase/restore, and account deletion. Reproduce the first-login Offline/Retry report against the release API, verify custom API hostname TLS before changing clients, and resolve server-side Home-place removal before public release (`clearHomePlace()` currently clears local device state without clearing the server's saved Home presence). Complete App Review metadata and agreement checks before public submission.

The current visual direction and screen intent live in [DESIGN.md](DESIGN.md); feature evidence and limits are in [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md); deployment procedure is in [DEPLOYMENT.md](DEPLOYMENT.md); broader scale requirements remain in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md).
