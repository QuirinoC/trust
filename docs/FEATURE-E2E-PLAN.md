# Cross-account feature validation

**Status: the local two-account simulator lifecycle plan is complete.** Treat the paired lifecycle, revocation, and listed fault cases as done; do not rerun them without a related code change or a specific regression. This is the current acceptance matrix, not a chronological work log. Detailed commands, result bundles, and safety boundaries are in [LOCAL-TWO-ACCOUNT-E2E.md](LOCAL-TWO-ACCOUNT-E2E.md); the next-agent queue is [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md).

## Completed locally

- Two simulator accounts completed onboarding, opted into phone discovery, found one another using fictional Development fixtures, sent and accepted a request, and removed and re-added the connection. A new connection returned to sharing Off in both directions.
- The pair exercised Sealed and Always sharing, reciprocal Home/Away presence grants, a Sealed Look with a map snapshot and matching Activity receipt, Home set and simulated movement, Home update and clear, Hidden suppression, Stop, and removal.
- Separate UI and API checks cover request cancellation, history loading and access removal after Stop, Stop All failure/retry, and delayed Circle/Look responses around revocation. The latest paired result passed 1/1 on both iPhone 17 Pro and iPhone Duo with zero skips or failures.
- The avatar light/dark backdrop regression passed locally and in CI. Latest CI [36820784316](https://github.com/QuirinoC/trust/actions/runs/36820784316) on docs/test handoff commit `06d7263` passed API/Postgres 202/202, web, TrustCore 82/82, and 20 iOS UI tests; 9 real-API UI tests skipped because the isolated service URL was absent. The first iOS attempt had one missed system-language Picker selection; retry attempt 2 passed. Local push API tests passed 14/14 with a mock APNs transport.

## Evidence limits

The paired tests used a loopback-only Development + Memory API and reserved fictional NANP `555-01xx` numbers. No carrier SMS, production API, physical background execution, StoreKit transaction, registered push token, Apple APNs delivery, notification presentation/tap, or physical second-device behavior was tested. The mock transport verifies API decisions and request construction only. Notifications are best effort.

The local real-API UI lane requires an explicit loopback HTTP URL on port `5089`; without it, those UI cases skip before account creation. Never point this harness at production or use its Development OTP on TestFlight. Use [LOCAL-TWO-ACCOUNT-E2E.md](LOCAL-TWO-ACCOUNT-E2E.md) for the current safe setup and cleanup.

## Remaining acceptance

- **History race:** hold a paid History response while Stop/remove/re-add occurs, then prove stale history cannot reappear. Use a legitimate sandbox-verified Plus entitlement; simulator review-unlock fixtures are not evidence of entitlement behavior. Include concurrent History screens.
- **Interruption and multi-device:** exercise offline → peer Stop/remove → app relaunch/reconnect; same-account use on a second physical device; and permission revocation while sharing. A source inspection found a specific Home conflict: each device keeps exact coordinates and its monitoring region in local Keychain, but the API stores one active Home place ID/current presence per account. Setting Home from a second device replaces the ID; the first device continues monitoring with a now-stale ID, so its later Home/Away events are rejected and the app does not reconcile the old monitor. Preserve the on-device coordinate privacy promise; settle and test a single-device handoff or a deliberate multi-device aggregate before broad release.
- **Notifications:** run physical TestFlight permission, token registration, foreground/background/terminated presentation, denial, and tap routing tests for Look and Home arrival. Decide whether request/acceptance needs a push; currently those changes appear after refresh, pull, or tab entry. A durable APNs outbox/retry worker is not implemented.
- **Real-device acceptance:** verify carrier SMS, Apple age assurance, background location, StoreKit purchase/restore/renewal/expiry/refund, and account deletion on the release candidate.
- **CI:** provision disposable isolated API and database services for the nine real-API UI tests currently skipped in CI; keep production credentials and user data out of that lane.

Age-assurance product and legal questions are tracked in [AGE-ASSURANCE.md](AGE-ASSURANCE.md). App Review and launch acceptance are in [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md). These are separate from the completed local two-account plan.
