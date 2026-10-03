# Trust deployment runbook

This file documents deployment procedure only. It does not assert which deployment is live. Start with [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md), check [STATUS.md](STATUS.md), then verify the provider dashboard and live health/routes immediately before and after each release. Dated build and provider examples below are historical snapshots; refresh them before acting. Keep credentials in the provider's secret store; never add them to this repository.

## API — Render

The API service is configured by the repository-root `render.yaml`; the blueprint is descriptive and must not be synchronized over the existing service without reviewing every setting. Deploy a reviewed commit through the existing Render service. Preserve its database and secret-backed settings. In production, keep development sign-in, seeded review data, and review unlock disabled.

Treat the API and regular Trust app update as a controlled beta upgrade. Before scheduling it, review build/API compatibility and the latest migration evidence in [STATUS.md](STATUS.md), including the populated 013→020 upgrade against a local restore of the Render backup. That evidence validates migration execution and preserved table counts; it does not rehearse rollback.

Deploy and verify the reviewed API first, then upload the reviewed regular Trust build. The sole remaining group, `Trust Family Auto`, is internal and has `hasAccessToAllBuilds=true`, so uploads are automatically exposed to its testers; upload only when the exact candidate is ready for internal distribution. Duplicate groups were removed after a protected metadata backup and confirmation that their membership union matched the retained group. Verify API health, the migration ledger, and protected routes before upload. Internal build 42 is processed. Build 43 is archived at `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-10-02/Trust-Internal-1.0-43.xcarchive`; command-line export failed with an App Store Connect access error, but Xcode Organizer uploaded it through **TestFlight Internal Only**. Build 44 is archived at `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-10-02/Trust-Internal-1.0-44.xcarchive` and is **Testing** in `Trust Family Auto`. Build 45 is archived at `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-10-02/Trust-Internal-1.0-45.xcarchive`; Organizer uploaded it through the internal-only path at 11:30 AM PDT, and App Store Connect showed it **Testing** with three invites at 11:37 AM PDT. Build 45 contains the AppTransaction retry, cancellation, and authorization-guard fixes; the physical cause remains unconfirmed until Diana retries it. Never submit builds 42–45 for public review because the `Trust-Internal` target has the phone-verification test bypass. For API compatibility decisions, use the current installed-build inventory and [STATUS.md](STATUS.md), not the historical build-32 cutover note. Verify `/health/live`, `/health/ready`, the migration ledger/logs, and the required release routes before upload.

If readiness fails, stop the rollout and fail closed in maintenance while preparing a forward fix. Do not unconditionally roll back to legacy API code such as `c3401cf` after privacy holds or revocations have been recorded: that code may ignore the newer privacy records. A database restore is not a safe substitute for a code fix if it would discard newer privacy state. Before reopening access after any restore, reconcile privacy holds, blocked-account associations, revocation tombstones, and cleanup jobs with the restored account data. Preserve the newer restrictive state when records conflict, then verify health, routes, and enforcement before resuming the beta.

The app's configured production API URL is in `apps/trust-ios/Sources/TrustApp/AppConfiguration.swift`. Do not switch to a custom hostname until independent HTTPS checks pass.

## Website — Cloudflare Workers

The canonical website lives in `apps/jointrust-web`; deploy using `apps/jointrust-web/wrangler.jsonc` and the authenticated Wrangler account:

```sh
cd apps/jointrust-web
npm ci
npm test
npm run deploy
```

Verify the landing, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, invite route, and `/.well-known/apple-app-site-association` after deployment. Compare legal/SMS consent text with actual app behavior and the registered Twilio campaign; the updated campaign registration has not yet been verified.

## iOS archive and TestFlight

The current GitHub Actions workflow runs API, iOS simulator, and web checks only; it does not archive, sign, or upload App Store builds. No repository-level Actions secrets/variables or deployment environments are configured. TestFlight distribution therefore remains a manual App Store Connect step from an authenticated release workstation.

1. Recheck the current release blockers and App Store Connect state. Do not infer build assignment or review status from old markdown snapshots.
2. Run the API and iOS checks required by [AGENTS.md](../AGENTS.md) for the changed components.
3. Generate the Xcode project from `apps/trust-ios/project.yml` with `xcodegen generate` if it is out of date.
4. For internal phone-verification testing only, archive the dedicated `Trust-Internal` target/scheme and export with [ExportOptions-Internal.plist](../apps/trust-ios/AppStore/ExportOptions-Internal.plist), which sets Apple's `testFlightInternalTestingOnly=true`. Confirm the resulting app's `TRUST_SKIP_PHONE_VERIFICATION` value is `true`. The app-only skip does not verify phone ownership on the server; internal builds must complete real verification before using handle discovery or connection requests. This archive must never be submitted for external TestFlight or App Store review. The regular `Trust` target embeds `false` and is the only release lane.
5. Export the regular `Trust` archive with [ExportOptions-AppStore.plist](../apps/trust-ios/AppStore/ExportOptions-AppStore.plist). It uses App Store Connect distribution, keeps the project build number unchanged, and explicitly leaves `testFlightInternalTestingOnly` off. Confirm the exported IPA is Apple Distribution signed, uses the production API, has `get-task-allow=false`, and has phone-verification bypass disabled. Validate before upload.
6. After confirming the backend is healthy, upload the exact reviewed regular Trust build and wait for App Store Connect processing. Build 41 was uploaded from authenticated Xcode 27.0 on 2026-09-30 at 4:38 PM PDT and remains the last confirmed processed regular build, selected in version 1.0 at the last draft check. Internal builds 42–45 were uploaded through Xcode's **TestFlight Internal Only** path; builds 44 and 45 are **Testing** in `Trust Family Auto`. Build 43 is **Testing** in that group and Diana's iPhone 16 Pro Max was listed as installed; the owner reports its transaction-verification error persisted. Build 45 was uploaded through Organizer's internal-only path at 11:30 AM PDT on 2 October and showed **Testing** with three invites at 11:37 AM PDT. The group has three internal testers and Automatic for Xcode Builds enabled. Builds 42–45 have the phone-verification test bypass enabled and must not be submitted for review; use the regular `Trust` scheme for release. Later build-42 feedback came from Diana's iPhone 16 Pro Max / iOS 26.6.2. Installation and sessions alone do not prove feature success. See [STATUS.md](STATUS.md) for current archive/export state. The live API was verified on deployment `dep-dauq0ke417fc73fj6acg`, commit `637b809e26fac5cb29dd8a17b963a4fe5d116b99`; readiness returned 200 during the build-43 attempt, and the production ledger previously listed migrations 001–021. Changes after release-source checkpoint `637b809` include client behavior, tests, and documentation; there is no API behavior change or migration.
7. Before public submission, reconcile listing copy, screenshots, privacy disclosures, age rating/legal pages, reviewer access, paid-app agreement, availability, platform support, and subscription metadata. At the 2026-09-30 6:30 PM PDT App Store Connect check, build 41 was selected on the version 1.0 draft, six screenshots were visible in the 6.5-inch iPhone group, and manual release was enabled. Photos or Videos, Other Diagnostic Data, and Other Data Types were selected but still unconfigured; the Account Holder must inspect and attest to the completed privacy answers before publishing. Sign-in required was unchecked despite account access being required, and no working reviewer credentials/connected test account were available. See [STATUS.md](STATUS.md) and [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md) for the latest evidence and gates.

## Production safeguards

- Keep production secrets in Render, Cloudflare, Apple, and Twilio account settings. Never put credentials in the repo or status notes.
- Do not enable development sign-in, seeded review circles, or review unlock in production.
- Do not treat API success or APNs acceptance as proof that a notification was displayed. APNs remains best effort; physical-device receipt must be observed.
- Do not deploy unreviewed working-tree changes. Record the commit, provider deployment ID, health check, and relevant public route checks in [STATUS.md](STATUS.md) after each verified release.
