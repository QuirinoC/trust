# iOS work index

Use [docs/STATUS.md](../../docs/STATUS.md) as the single dated source for current delivery, CI, App Store Connect, backend, and release blockers. Do not use older statements in this file as current evidence. The current behavior is documented in [DESIGN.md](../../docs/DESIGN.md); two-account coverage is in [FEATURE-E2E-PLAN.md](../../docs/FEATURE-E2E-PLAN.md).

## Current handoff — 30 September 2026

- Build 35 feedback (iPhone 16 Pro, iOS 27.0, 23-second uptime) shows “We can’t complete the required check.” App Store Connect has no crash-feedback entries.
- Build 36 fixes the Apple age-assurance call order, is distribution-signed, and is `VALID` in the internal Trust Family Auto group. ASC shows three invitations and no installs yet.
- Hosted CI run `36655526974` passed all jobs: API/Postgres 189/189, iOS 23 UI tests with 9 loopback-API cases skipped and zero failures, and website tests. The age-gate UI fixtures passed 6/6; they do not call Apple's live service.
- Install build 36 and retry the required check on the same physical iPhone. Then continue the outstanding physical two-account checks for SMS, background location, APNs, StoreKit, and account deletion.
- Public App Review remains blocked on reviewer access, App Privacy categories, subscription metadata/evidence, Paid Apps agreement, Send code campaign/HELP/STOP verification, age/audience legal review, and physical release-path evidence. See `REVIEW-READINESS.md` for the detailed gate list.
