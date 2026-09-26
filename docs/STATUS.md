# Trust project status

Updated 2026-09-25. This is a dated evidence snapshot, not a live dashboard. App Store Connect, Render, Cloudflare, and physical-device state must be checked in those services before a release action. Older build numbers in other notes are historical and must not be treated as current.

## Verified in this workspace

- The current source target is version **1.0**, build **27** (`apps/trust-ios/project.yml`). Working-tree changes after the last recorded upload have not been included in a new archive or TestFlight build.
- The notification changes in this working tree prevent Home notifications while the subject's effective share mode is Off or Paused, send arrival notifications only when state transitions into Home, and carry the actual notification kind in the APNs payload.
- Local API tests passed **113/113**. The focused real-API Duo onboarding/invite/stop-sharing UI test passed **1/1**. The complete Swift package suite passed **29/29**, and the current iOS app target built successfully for the Duo simulator.
- The full iPhone Duo Xcode scheme passed **36/36** on Xcode 27.1 beta (29 unit and 7 UI tests). It is simulator evidence; physical-device and APNs-delivery behavior remain unverified.
- The app is configured for English plus five additional locales: Simplified Chinese, Japanese, German, French, and Brazilian Portuguese. All 411 current in-app copy keys and camera/location purpose strings have first-pass translations; structural/placeholder validation passes. Push notifications remain English for compatibility with current TestFlight builds. Native-speaker review is still required, and website legal pages and App Store metadata are not yet localized. See [LOCALIZATION.md](LOCALIZATION.md).
- Two disposable local Development accounts connected, enabled Sealed sharing, uploaded a location, and completed a confirmed Look. The recipient's server `lookLog` contained the Look. Test accounts were deleted.
- Both retained simulators launched the Debug app against loopback. The iPhone 17 Pro screenshot showed stale simulator state; the Duo `simctl` screenshot was black. This is not a clean two-simulator UI pass.
- A local `simctl push` command was accepted, but no banner appeared in the phone screenshot. No local APNs credentials were configured. This does not prove APNs delivery.
- The project has one current UI source of truth in [DESIGN.md](DESIGN.md). Production scale and operational work is tracked separately in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md).

## Last recorded external observations — recheck before acting

These observations were recorded on 2026-09-25 in earlier App Store Connect and service inspections. They have **not** been revalidated in this status update.

- App Store Connect: stable-Xcode build **27** was reported as processed and Ready to Submit for external TestFlight. The same inspection said the external Family Test group had no build assigned and no Beta App Review submission had been made. Reopen App Store Connect to confirm the current build, group assignment, invitation state, and review state.
- App Store Connect: version 1.0 review submission, screenshots, privacy answers, age policy, reviewer sign-in path, paid-app agreement, availability, and platform scope were still open or unverified. See [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md), which is a dated audit and also requires a fresh ASC check.
- Render: the last recorded API deployment was `dep-dar1gnm0tbcc73cingv0`; its readiness endpoint returned healthy. The last record says the custom API hostname TLS was unresolved. Check Render and HTTPS live before deploying or changing app configuration.
- Cloudflare: the last recorded site version was `0b61e45a-0391-42e6-9e44-d3a473921469`, with the public legal, support, SMS, invite, and Apple association routes returning 200. Verify the live site after any new deployment.

## Remaining work

- Build and test the current working-tree changes, increment the build number, then upload only after the phone/SMS consent disclosure and Twilio campaign evidence are reconciled.
- Complete physical two-account TestFlight checks: onboarding and SMS, invite acceptance, sharing modes and revocation, background location, APNs permission/token/banner/tap behavior, and StoreKit purchase/restore.
- Recapture current App Store listing screenshots and complete the privacy, age-policy, reviewer-access, agreement, availability, and platform decisions using live App Store Connect state.
- Retest the reported first-login Offline/Retry issue against the release API.
- Mitigate account enumeration from the pre-SMS phone availability check with stronger per-account/phone abuse controls or an equivalent design before public release.
- Resolve custom API hostname TLS before configuring clients to use it.
- Before public launch, close production-readiness gaps: durable/retryable notification receipts, purchase reconciliation, offline location queue protection and idempotency, monitoring/alert drills, backup restore drills, abuse support, load testing, and the .NET runtime upgrade.

The detailed simulator and physical evidence matrix is in [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md). Release procedures are in [DEPLOYMENT.md](DEPLOYMENT.md); those procedures do not imply that a recorded deployment is still live.
