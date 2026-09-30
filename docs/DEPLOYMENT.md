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
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

Verify the landing, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, invite route, and `/.well-known/apple-app-site-association` after deployment. Compare legal/SMS consent text with actual app behavior and the registered Twilio campaign; the updated campaign registration has not yet been verified.

## iOS archive and TestFlight

1. Recheck the current release blockers and App Store Connect state. Do not infer build assignment or review status from old markdown snapshots.
2. Run the API and iOS checks required by [AGENTS.md](../AGENTS.md) for the changed components.
3. Generate the Xcode project from `apps/trust-ios/project.yml` with `xcodegen generate` if it is out of date.
4. For internal phone-verification testing only, archive the dedicated `Trust-Internal` target/scheme and export with [ExportOptions-Internal.plist](../apps/trust-ios/AppStore/ExportOptions-Internal.plist), which sets Apple's `testFlightInternalTestingOnly=true`. Confirm the resulting app's `TRUST_SKIP_PHONE_VERIFICATION` value is `true`. The app-only skip does not verify phone ownership on the server; internal builds must complete real verification before using handle discovery or connection requests. This archive must never be submitted for external TestFlight or App Store review. The regular `Trust` target embeds `false` and is the only release lane.
5. In Organizer, confirm bundle ID, marketing version, incremented build number, signing team, entitlements, and archive contents. Validate before upload.
6. Only after the reviewed backend is deployed and health, migration state, and protected routes are verified, upload the exact reviewed regular Trust build and wait for App Store Connect processing. As of 30 September 2026, build 36 is `VALID` and available in Trust Family Auto; ASC records Diana's iPhone 12/iOS 26.6 install with 11 sessions. No build-36 feedback or crash is recorded. Because the group automatically receives all builds, perform each upload only after the API is ready. Verify the exact flow under investigation on the installed build; installation and sessions alone do not prove feature success.
7. Before public submission, reconcile listing copy, screenshots, privacy disclosures, age rating/legal pages, reviewer access, paid-app agreement, availability, platform support, and subscription metadata.

## Production safeguards

- Keep production secrets in Render, Cloudflare, Apple, and Twilio account settings. Never put credentials in the repo or status notes.
- Do not enable development sign-in, seeded review circles, or review unlock in production.
- Do not treat API success or APNs acceptance as proof that a notification was displayed. APNs remains best effort; physical-device receipt must be observed.
- Do not deploy unreviewed working-tree changes. Record the commit, provider deployment ID, health check, and relevant public route checks in [STATUS.md](STATUS.md) after each verified release.
