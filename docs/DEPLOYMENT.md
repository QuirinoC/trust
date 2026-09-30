# Trust deployment runbook

This file documents deployment procedure only. It does not assert which deployment is live. Check [STATUS.md](STATUS.md), then verify the provider dashboard and live health/routes immediately before and after each release. Keep credentials in the provider's secret store; never add them to this repository.

## API — Render

The API service is configured by the repository-root `render.yaml`; the blueprint is descriptive and must not be synchronized over the existing service without reviewing every setting. Deploy a reviewed commit through the existing Render service. Preserve its database and secret-backed settings. In production, keep development sign-in, seeded review data, and review unlock disabled.

Treat the API and regular Trust app update as a controlled beta upgrade. Before scheduling it, review build/API compatibility and the latest migration evidence in [STATUS.md](STATUS.md), including the populated 013→020 upgrade against a local restore of the Render backup. That evidence validates migration execution and preserved table counts; it does not rehearse rollback.

Deploy and verify the reviewed API first, then upload the reviewed regular Trust build. The sole remaining group, Trust Family Auto, is internal and has `hasAccessToAllBuilds=true`, so an upload would automatically expose the build; it cannot safely be uploaded early and left unassigned. Duplicate groups iPhone Juan, Trust Internal Testers, and Family Test were removed after a protected metadata backup and confirmation that their membership union matched the retained group. Verify the API health, migration ledger, and protected routes before upload. Do not use the `Trust-Internal` build for public review; build 32's phone-verification bypass keeps it internal-only. During the API cutover, build 32 clients may use only privacy-reducing HTTP operations that have been verified, such as Off, Remove, and Delete. Keep reads and share-enabling or Pause writes gated until clients move to the compatible build. Verify `/health/live`, `/health/ready`, the migration ledger/logs, and the required release routes before the upload that automatically exposes the build to Trust Family Auto.

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
6. After confirming the backend is healthy, upload the exact reviewed regular Trust build and wait for App Store Connect processing. Build 40 was uploaded from authenticated Xcode 27.0 on 2026-09-30 at 2:49 PM PDT and appears as `Testing` in `Trust Family Auto`; the upload-history pane still showed Processing at the last refresh. The group automatically receives Xcode builds. Confirm installation and exercise the exact flow under investigation; installation and sessions alone do not prove feature success. Do not use build 39. See [STATUS.md](STATUS.md) for build 40's SHA-256 and signing checks. The live API deploy is `de977df`, its readiness endpoint returned 200, and its startup migration sequence is 001–021; the app-only avatar change requires no backend deploy or schema change.
7. Before public submission, reconcile listing copy, screenshots, privacy disclosures, age rating/legal pages, reviewer access, paid-app agreement, availability, platform support, and subscription metadata. The current App Store draft has build 40 and six screenshots per display group; privacy-label additions are still an unpublished draft.

## Production safeguards

- Keep production secrets in Render, Cloudflare, Apple, and Twilio account settings. Never put credentials in the repo or status notes.
- Do not enable development sign-in, seeded review circles, or review unlock in production.
- Do not treat API success or APNs acceptance as proof that a notification was displayed. APNs remains best effort; physical-device receipt must be observed.
- Do not deploy unreviewed working-tree changes. Record the commit, provider deployment ID, health check, and relevant public route checks in [STATUS.md](STATUS.md) after each verified release.
