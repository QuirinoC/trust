# iOS open work

This is an index, not a second release-status snapshot. Current local evidence and dated external observations live in [docs/STATUS.md](../../docs/STATUS.md). App Store Connect claims must be rechecked in App Store Connect before acting.

- Source build 30 is the current internal candidate. Commit and merge it, archive with the `Trust-Internal` scheme, validate the `TRUST_SKIP_PHONE_VERIFICATION=true` build setting, upload, process, and assign to the intended internal groups. Verify the tester sees that exact build.
- Refresh the App Store listing icon and replace its seven older screenshots after the new build is processed; keep the draft version unsubmitted.
- Reconcile the current Send code consent disclosure with Twilio campaign records and public SMS evidence.
- Complete physical two-account TestFlight checks, including SMS, location permissions/background behavior, APNs receipt, StoreKit purchase/restore, and account deletion. No physical APNs receipt has been verified yet.
- Complete remaining App Review metadata checks: privacy answers, age policy, reviewer access, agreements, availability, platform scope, and subscription review status.
- Resolve server-side Home-place removal before public release; the current client clears local Home state but does not clear the server's saved Home presence.
- Reproduce and resolve the first-login Offline/Retry report against the release API.
- Verify custom API hostname TLS before changing client configuration.

See [FEATURE-E2E-PLAN.md](../../docs/FEATURE-E2E-PLAN.md) for the test matrix, [REVIEW-READINESS.md](AppStore/REVIEW-READINESS.md) for the last App Store audit, and [PRODUCTION-READINESS.md](../../docs/PRODUCTION-READINESS.md) for post-beta work.
