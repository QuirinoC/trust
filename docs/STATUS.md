# Trust project status

Updated 2026-09-26. This is a dated evidence snapshot; recheck live service and App Store Connect state before relying on it.

## Current work

The working branch is `codex/phone-discovery`, based on `main` commit `e5039b5`. It adds automatic exact handle/full-phone lookup, an explicit default-off phone-discovery choice, consent-gated avatar previews, and a native share-sheet invite link for unmatched phone searches. Sending an invite link does not claim a text was sent, and accepting a connection leaves both sharing directions Off. Old HTML design mocks were removed; `DESIGN.md`, `SHARING-REDESIGN.md`, `SCREENS.md`, and the READMEs describe the current experience.

Astra reviewed the final Add Someone sheet and found no remaining high-impact visual issue. Sol's independent review found no actionable privacy or implementation issue in the native share-sheet callback or Duo dismissal fallback.

## Verified checks

- API suite: **132/132** passed, no skips.
- Swift package: **33/33** passed. Full stable iPhone 17 Pro Xcode suite: **41/41** passed, no skips (**33 core + 8 UI**).
- Real-API onboarding through phone lookup, invitation sharing, request acceptance, Off defaults, and stopping sharing: **1/1** passed on stable iOS 26.5 and **1/1** on iOS 27.1 beta Duo.
- Website tests: **3/3** passed. Localization validation: **470 keys across five translated locales**.
- The local Development API returns Healthy. Cloudflare Wrangler authentication and a website deploy dry run were verified.
- About **1.4 GB** of ignored old iOS build and archive artifacts were removed from `apps/trust-ios/build`. Only the actively used iPhone 17 Pro and Duo simulator devices remain.

On Duo’s iOS 27.1 beta, the system share sheet ignores the close-button tap from XCTest; swipe-down closes it and the rest of the real-API flow passes. The same control dismisses normally on stable iOS. Simulator checks do not establish physical SMS, Sign in with Apple, APNs delivery, background location, or TestFlight behavior.

## Release and service state

- The branch has not yet been committed, merged, or deployed. The production Render API and Cloudflare site still reflect the earlier merged release.
- App Store Connect is signed in through Safari. The iOS 1.0 listing is still **Prepare for Submission**, currently selects build **27**, and still displays the old red-ring listing icon. Builds **27** and **28** are processed; build 28 is in the `iPhone Juan` internal group. The current source build is **30** and has not been archived or uploaded. The 6.5-inch listing still has seven older screenshots. The source asset uses the current three-arc icon; refresh the listing from the reviewed internal build and replace the stale screenshots before submitting.
- The revised website SMS disclosure and privacy wording are present in this branch, but the live Twilio campaign record has not been independently verified. Do not claim carrier SMS consent language is registered until that check is complete.
- No end-to-end push notification delivery has been verified. APNs delivery is best effort; no successful server publish proves a notification reached a device.

## Remaining release work

Merge the reviewed branch; deploy and health-check the API and website; archive and upload source build 30 through the internal-only scheme; assign it to the intended internal testers; refresh the App Store listing icon and screenshots; and retire the superseded TestFlight builds after the replacement is available. Then run the physical two-account TestFlight checks for SMS, location/background behavior, notifications, account deletion, and StoreKit purchase/restore.

Before public release, resolve or explicitly accept the known Home-place issue: `clearHomePlace()` currently clears local device state without clearing the server's Home presence. Also reproduce the first-login Offline/Retry report against the release API, verify the custom API hostname's TLS before switching clients, and confirm the production Twilio campaign and public `/sms` evidence agree.

The current design is in [DESIGN.md](DESIGN.md), real-feature evidence and its limits are in [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md), and the deployment procedure is in [DEPLOYMENT.md](DEPLOYMENT.md). Broader scale requirements remain in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md).
