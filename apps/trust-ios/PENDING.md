# iOS open work

This is an index, not a second release-status snapshot. Current local evidence and dated external observations live in [docs/STATUS.md](../../docs/STATUS.md). App Store Connect claims must be rechecked in App Store Connect before acting.

- Build and verify working-tree changes; use a new build number for any upload.
- Reconcile the current Send code consent disclosure with Twilio campaign records and public SMS evidence.
- Complete physical two-account TestFlight checks, including SMS, location permissions/background behavior, APNs receipt, StoreKit purchase/restore, and account deletion.
- Refresh screenshots, privacy answers, age policy, reviewer access, agreements, availability, platform scope, and subscription review status in App Store Connect.
- Reproduce and resolve the first-login Offline/Retry report against the release API.
- Verify custom API hostname TLS before changing client configuration.

See [FEATURE-E2E-PLAN.md](../../docs/FEATURE-E2E-PLAN.md) for the test matrix, [REVIEW-READINESS.md](AppStore/REVIEW-READINESS.md) for the last App Store audit, and [PRODUCTION-READINESS.md](../../docs/PRODUCTION-READINESS.md) for post-beta work.
