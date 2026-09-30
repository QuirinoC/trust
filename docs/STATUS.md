# Trust project status

Updated 2026-09-30 3:15 AM PDT. This snapshot is based on the checked-out repository, GitHub Actions, Render CLI, Xcode archive/export, and public HTTP probes. App Store Connect could not be refreshed because macOS is locked; its information below is the last saved observation, not a live read.

## Current release decision

**Not ready to submit to public App Review yet.** The product source is merged to `main` at `f579005fb73fbc45b6d3551b5ab63fac7da240c6` (PR #14). PR CI [`36697551317`](https://github.com/QuirinoC/trust/actions/runs/36697551317) and post-merge CI [`36699341073`](https://github.com/QuirinoC/trust/actions/runs/36699341073) passed API, iOS, and web. The merged iOS change fixes empty-History letterboxing; local visual-regression, appearance, and language-picker UI tests passed. A release branch now contains the build-39 version bump and refreshed launch docs; its CI/merge remain pending.

The app project now specifies version 1.0 build 39 on the working release branch. The fresh archive `/tmp/Trust-1.0-39-AppStore-20260930.xcarchive` and IPA `/tmp/Trust-1.0-39-AppStore-Export-20260930/Trust.ipa` were built from current app source (`f579005` plus the build-number bump) using stable Xcode 27.0. The exported IPA SHA-256 is `7a621bc29b170f44409a6060943b878cb02a4de7b4255d7b67c91d0d3a5fa7d4`. Verification confirms Apple Distribution team `3S529795M9`, production APNs, Declared Age Range entitlement, production API URL, `get-task-allow=false`, and phone-verification bypass disabled. It has not been uploaded; first refresh App Store Connect to confirm build 39 is unused, and merge/CI must pass before upload. The earlier build-38 archive predates current `main` and must not replace this one. Stable Xcode 27.0 is installed; `xcode-select` currently points to Command Line Tools, so commands must set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The last saved App Store Connect observation recorded version 1.0 build 36 as `VALID` in internal group `Trust Family Auto`, with build 35 selected in the draft. The latest saved feedback is build 35 on an iPhone 16 Pro/iOS 27.0: “Uh,” 23 seconds of uptime, and a screenshot reading “We can’t complete the required check.” No newer feedback or crash report confirms resolution. App Store Connect still needs a live refresh; the previous API read returned `NOT_AUTHORIZED`. The required-check failure needs a normal physical retry on the same iPhone after the current build is processed. Simulator fixtures do not prove Apple's live age-assurance or App Transaction registration flow.

## Live services and database

- Render service `trust-api` is currently on live deployment `dep-daucmktg1s2s7383b15g`, commit `de977df9879429582b73776a66dd88e4d952dc52`. `/health/live` and `/health/ready` both returned HTTP 200 during this update. The API starts after its startup migrations, currently 001–021; a direct production migration-ledger read is still blocked by the database IP allowlist. The merged iOS History change does not change the API or schema, so it requires no API redeploy or new database migration.
- Render Postgres is available in Oregon on `basic_256mb`, 15 GB disk, with disk autoscaling off, no high availability, and no connection pool. This is the current beta configuration, **not demonstrated capacity for millions of users**. Measure workload and cost, add monitoring and recovery evidence, then scale deliberately before meaningful growth.
- `jointrust.app`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, and `/.well-known/apple-app-site-association` all returned HTTP 200. The deployed Cloudflare Worker is `jointrust-web`, version `f8382a78-2b17-45ba-8cad-1ec4d46dd800`; the revised Privacy, Terms, and Support pages are live. The homepage CTA opens an email draft for beta access; it is not a signup database, waitlist, or public App Store link.
- Migration 021 persists phone verification consent events. The registered Twilio campaign and its actual HELP/STOP flow have not been independently re-verified. Keep the existing 40 verification-SMS/day setting treated as a hard beta ceiling until provider limits, abuse controls, and spend alerts are deliberately reviewed.

## Feature and release evidence

- The paired iPhone 17 Pro + Duo simulator E2E from 29 September passed onboarding, reciprocal Home/Away grants, handle/phone discovery, connection request and acceptance, removal/re-add, Sealed Look/map/Activity, Home movement/update/clear, Hidden, Stop, and fresh default-Off. It used isolated Development services and fictional 555-01xx numbers; it did not send SMS or prove physical APNs delivery.
- Focused simulator fault tests covered delayed Circle responses and refresh failure across Stop, Remove, and partial Stop All, plus a delayed Look during remove/re-add. Each passed 1/1 with no skips. A paid-entitlement History race and same-account reconnect across physical devices remain unverified. See [two-account E2E evidence](LOCAL-TWO-ACCOUNT-E2E.md) and [the remaining interaction matrix](FEATURE-E2E-PLAN.md).
- PR #14 validation passed API, iOS, and web checks. The post-merge iOS job was still running in CI `36699341073` at this snapshot; its completion must be rechecked before release. The simulator UI checks do not replace physical TestFlight checks.
- Push notifications are best effort. APNs configuration is enabled, but no current physical TestFlight evidence verifies delivery, presentation, or taps. Do not promise guaranteed notification delivery.
- `docs/DESIGN.md` is the current design reference. `docs/PRODUCTION-READINESS.md` is the current launch and scale plan; older issue notes are historical unless repeated in the open gates below.

## Must close before App Review submission

1. Complete CI and merge the release branch containing build 39. The archive/export is already verified against the current app source with production signing and bypasses off; validate the merged tree against the recorded IPA hash.
2. Unlock the Mac, refresh App Store Connect, select the current build, and confirm it processes into `Trust Family Auto`. Re-read the draft, TestFlight feedback, and all metadata rather than relying on saved snapshots.
3. Retry the required-check flow on the same iPhone 16 Pro using normal Apple sign-in. Resolve or conclusively isolate any failure before submission.
4. Reconcile App Privacy (including Contacts and Photos/Videos), age rating and audience classification, subscription agreement/products/pricing/localizations/review assets, listing metadata/screenshots, supported territories, and manual release settings against current source and actual behavior.
5. Provide App Review a working account and concise test instructions for connection, consented sharing, Stop/remove, subscription purchase/restore, and account deletion. Keep production development sign-in, seeded circles, and review bypasses disabled.
6. Compare the shipped Send-code disclosure with the registered Twilio campaign and test the actual opt-in plus HELP/STOP behavior. Confirm support contact and beta email inbox ownership/monitoring.

These are active gates, not paperwork to mark complete from repository state. Apple's review decision and storefront propagation time are outside our control; a same-day public listing cannot be promised. See [Apple's submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app) and [publishing workflow](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store).

## Before turning on public availability

On the release candidate, exercise background location, notification permission/delivery/presentation/taps, offline reconnect, same-account second-device convergence, paid History and revocation, purchase/restore/renewal/expiry/refund, and deletion on physical devices. Verify backups and recovery, delivered service/spend alerts, an incident owner and support route, and a deliberate SMS capacity/spend ceiling. Keep release manual until privacy and entitlement defects are cleared.

Organic prelaunch material is drafted in `docs/PRODUCTION-READINESS.md` and `marketing/prelaunch/2026-09/README.md`. No campaign is confirmed published. A truthful prelaunch post can point to `jointrust.app` only after confirming the email inbox is monitored and stating that public download is not open. Do not buy install traffic until the public listing is live, conversion measurement is sound, and the owner has set a spend cap.

## Large-scale readiness

The current small Render database, single-instance beta deployment, missing measured load test, and open durability/monitoring/recovery work do not support a claim of million-user readiness. The multi-phase work in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md) covers protected/idempotent location ingestion, durable notification and billing outboxes, bounded/paged queries, distributed rate limits, capacity testing, database high availability, backup restore drills, observability, abuse response, and on-call ownership. A migration is **not** required for the merged History UI fix; future outbox/idempotency/paging work may require backward-compatible migrations and staged rollout.
