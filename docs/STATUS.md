# Trust project status

Reconciled 2026-10-01 05:41 UTC (2026-09-30 10:41 PM PDT). This is the current evidence snapshot; provider state is last-known and must be refreshed before release actions. The actionable pickup list is [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md).

## Source and CI

- Reconciliation began from `main` and `origin/main` at `63476c8`; all PRs #1–#16 are merged and there were no open PRs. Stale `codex/*` refs correspond to merged PRs and are not work to merge.
- Latest CI: [36812181956](https://github.com/QuirinoC/trust/actions/runs/36812181956), on `c39bb81`, passed TrustCore 82/82, API/Postgres 202/202, web, and 20 iOS UI tests. Nine real-API UI tests skipped because CI lacked an isolated API URL. Local `PushDeviceApiTests` passed 14/14 with a mock APNs transport.
- Main has no app/API behavior changes after release-source checkpoint `637b809`; later commits were tests and documentation. Build 41's exact source revision is not pinned in the tracked release record. The current Send-code flow records disclosure version and Send/Resend action; [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md) says to rebuild before claiming that behavior is in the candidate. Verify binary/source correspondence and upload a new build if needed. This documentation update requires no API deployment or database migration.

## Last verified release and service state

- App Store Connect was last inspected 2026-09-30 6:39 PM PDT. Version 1.0 was `Prepare for Submission`, build 41 was processed, assigned to the sole internal group `Trust Family Auto`, and selected on the version draft. Manual release was selected. Three internal testers were listed. Refresh these facts before relying on them.
- The same inspection showed a prior required-check failure on the iPhone 16 Pro; build 41 still needs a same-device retry with normal Apple sign-in. The age-assurance simulator tests use fixtures and do not prove Apple's live age service.
- The published privacy label listed nine data types. Photos or Videos, Other Diagnostic Data, and Other Data Types were selected in the draft but remained unconfigured and unpublished. Completing and publishing those disclosures requires accurate answers and the Account Holder's legal/compliance attestation.
- App Review access was incomplete: the last-observed “Sign-in required” value was off despite account-only core use, and no verified reviewer account/test instructions covered the connected and paid flows. Counsel still needs to classify intended audience and launch territories; 4+ is a store rating, not a legal audience classification.
- Render `trust-api` was last confirmed healthy on deployment `dep-daucmktg1s2s7383b15g`, commit `de977df9879429582b73776a66dd88e4d952dc52`; live/readiness health returned 200. Migration 021 was included. Direct production migration-ledger inspection was blocked by the database IP allowlist.
- A read-only listing found 10 production accounts and no `Alpha` display name or handle; the owner identified `juanquirino` as the test target. Its previously empty phone fields now contain an owner-approved, temporary fictional `555-01xx` verified fixture for account discovery only; no SMS was sent. `juanito`'s existing real verified number was not changed. The temporary external database IP allowlist was restored to empty. Rollback instructions are in [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md).
- The public site and legal/SMS/support routes were last confirmed reachable. Cloudflare `jointrust-web` version `6bee1a5c-7e93-4031-8310-950a302c9ace` served the aligned privacy disclosure; invite-path invocation URL logging was disabled. Recheck live pages and dashboard retention before release.
- Render Postgres was Basic-256mb (15 GB disk), without high availability, disk autoscaling, or a recorded restore drill. Provider metrics had gaps, so actual utilization and capacity were unverified. This beta configuration is not evidence of million-user readiness.
- The registered Twilio campaign's current opt-in wording and HELP/STOP behavior were not independently verified against the app. Keep the existing 40 verification-SMS/day beta limit treated as a ceiling until spend and abuse controls are deliberately reviewed.

## Completed interaction evidence

The current-source paired iPhone 17 Pro + Duo simulator E2E passed 1/1 on each role. It covered onboarding, phone discovery/request/accept, reciprocal Home/Away grants, Sealed Look with map and Activity receipt, Home set/movement/update/clear, Hidden, Stop, remove/re-add, and default-Off. Focused simulator fault cases covered stale Circle reads, Stop, Remove, partial Stop All retry, and delayed Look during remove/re-add. The appearance regression checked the sleepy Fox backdrop in light and dark modes. Full test boundaries and result locations are in [LOCAL-TWO-ACCOUNT-E2E.md](LOCAL-TWO-ACCOUNT-E2E.md).

These runs used fictional numbers and an isolated Development + Memory API. They do not prove carrier SMS, physical background location, StoreKit transactions, a registered push device, Apple's APNs delivery, OS notification presentation/taps, or physical second-device behavior. See [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md) for the remaining interaction cases.

## Open work

Use [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md) as the single ordered action list. The main open groups are: same-device TestFlight age-assurance retry; App Store privacy, reviewer-access, subscription/listing and legal-audience gates; Twilio campaign verification; physical TestFlight acceptance; paid-History and offline/multi-device edge cases; nine CI UI tests that currently skip without an isolated API URL; and operational scale, monitoring, and recovery work.

The release is **not ready for public App Review or public availability** until its applicable gates are verified. The detailed App Store checklist is [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md); production and scale milestones are in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md). Notifications remain best effort; neither an API publish attempt nor APNs acceptance proves a device displayed a notification.
