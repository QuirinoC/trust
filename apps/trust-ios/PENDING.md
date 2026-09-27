# iOS open work

This is an index, not a second release-status snapshot. Current local evidence and dated external observations live in [docs/STATUS.md](../../docs/STATUS.md). App Store Connect claims must be rechecked in App Store Connect before acting.

- Build 32 is available for internal testing. It was archived from `codex/rebrand-launch-brief` with `Trust-Internal`, verified to include `TRUST_SKIP_PHONE_VERIFICATION=true`, processed by App Store Connect, and assigned to the existing `iPhone Juan` group. Verify that build 32 appears and installs on the physical phone.
- The September screenshot sets now contain six locally regenerated panels for iPhone 6.9-inch, iPhone 6.5-inch, and iPad 13-inch. Review them against the exact public build and upload only after approval; App Store Connect artwork remains unchanged. Keep the draft version unsubmitted.
- `codex/rebrand-launch-brief` contains a proposed English marketing/listing refresh. It has not been deployed. The website CTA is an email link, not a waitlist; implement a waitlist only with an approved collection and retention flow.
- Reconcile the current Send code consent disclosure with Twilio campaign records and public SMS evidence.
- Complete physical two-account TestFlight checks, including SMS, location permissions/background behavior, APNs receipt, StoreKit purchase/restore, and account deletion. No physical APNs receipt has been verified yet.
- Complete remaining App Review metadata checks: privacy answers, age policy, reviewer access, agreements, availability, platform scope, and subscription review status.
- Resolve server-side Home-place removal before public release; the current client clears local Home state but does not clear the server's saved Home presence.
- Reproduce and resolve the first-login Offline/Retry report against the release API.
- Verify custom API hostname TLS before changing client configuration.

See [FEATURE-E2E-PLAN.md](../../docs/FEATURE-E2E-PLAN.md) for the test matrix, [REVIEW-READINESS.md](AppStore/REVIEW-READINESS.md) for the last App Store audit, and [PRODUCTION-READINESS.md](../../docs/PRODUCTION-READINESS.md) for post-beta work.
