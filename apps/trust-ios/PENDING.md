# iOS open work

This is an index, not a second release-status snapshot. Current local evidence and dated external observations live in [docs/STATUS.md](../../docs/STATUS.md). App Store Connect claims must be rechecked in App Store Connect before acting.

Current gate (29 September 2026): the local build 33 App Store export is distribution-signed but not uploaded; it requires an API route that production does not have yet. Do not treat it as a usable TestFlight build. The full API suite passes 178/178 against isolated PostgreSQL 16 with migrations 001–020. See the release decision in [project status](../../docs/STATUS.md) for the compatibility, migration, age-policy, notification, physical-device, and listing blockers.

- App Store Connect check on 27 September 2026: `alpha.collapse@proton.me` is in the `Trust Family Auto` internal group, and App Store Connect reports build 32 installed on that tester's iPhone 13. Build 32's internal-only `TRUST_SKIP_PHONE_VERIFICATION` skips the iOS phone-entry step; it does not set `phone_verified_at` in the production API. Production sharing and connection actions still require a real SMS-verified number. Do not seed or mark a fabricated phone as verified in production; use a real number for TestFlight or a local Development API fixture for fake-number testing.
- The September screenshot sets now contain six locally regenerated panels for iPhone 6.9-inch, iPhone 6.5-inch, and iPad 13-inch. Review them against the exact public build and upload only after approval; App Store Connect artwork remains unchanged. Keep the draft version unsubmitted.
- `codex/rebrand-launch-brief` contains a proposed English marketing/listing refresh. It has not been deployed. The website CTA is an email link, not a waitlist; implement a waitlist only with an approved collection and retention flow.
- Reconcile the current Send code consent disclosure with Twilio campaign records and public SMS evidence.
- Complete physical two-account TestFlight checks, including SMS, location permissions/background behavior, APNs receipt, StoreKit purchase/restore, and account deletion. No physical APNs receipt has been verified yet.
- Complete remaining App Review metadata checks: privacy answers, age policy, reviewer access, agreements, availability, platform scope, and subscription review status.
- Home-place removal is implemented through the server contract and covered by API regression tests; the paired simulator record also covers set/update/clear. Physical TestFlight verification remains open ([feature evidence](../../docs/FEATURE-E2E-PLAN.md)).
- Reproduce and resolve the first-login Offline/Retry report against the release API.
- Verify custom API hostname TLS before changing client configuration.

See [FEATURE-E2E-PLAN.md](../../docs/FEATURE-E2E-PLAN.md) for the test matrix, [REVIEW-READINESS.md](AppStore/REVIEW-READINESS.md) for the last App Store audit, and [PRODUCTION-READINESS.md](../../docs/PRODUCTION-READINESS.md) for post-beta work.
