# Trust deployment runbook

This file documents deployment procedure only. It does not assert which deployment is live. Check [STATUS.md](STATUS.md), then verify the provider dashboard and live health/routes immediately before and after each release. Keep credentials in the provider's secret store; never add them to this repository.

## API — Render

The API service is configured in `apps/trust-api/render.yaml`; the blueprint is descriptive and must not be synchronized over the existing service without reviewing every setting. Deploy a reviewed commit through the existing Render service. Preserve its database and secret-backed settings. In production, keep development sign-in, seeded review data, and review unlock disabled.

After deployment, verify `/health/live` and `/health/ready`, inspect migration and application logs, and exercise the intended release API path. If readiness fails, stop rollout and use Render deployment history to restore a known-good deployment. Verify both health endpoints after rollback.

The app's configured production API URL is in `apps/trust-ios/Sources/TrustApp/AppConfiguration.swift`. Do not switch to a custom hostname until independent HTTPS checks pass.

## Website — Cloudflare Workers

The canonical website lives in `apps/jointrust-web`; deploy using `apps/jointrust-web/wrangler.jsonc` and the authenticated Wrangler account:

```sh
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

Verify the landing, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, invite route, and `/.well-known/apple-app-site-association` after deployment. Compare legal/SMS consent text with actual app behavior and the registered Twilio campaign.

## iOS archive and TestFlight

1. Recheck the current release blockers and App Store Connect state. Do not infer build assignment or review status from old markdown snapshots.
2. Run the API and iOS checks required by [AGENTS.md](../AGENTS.md) for the changed components.
3. Generate the Xcode project from `apps/trust-ios/project.yml` with `xcodegen generate` if it is out of date.
4. Archive the `Trust` scheme with stable public Xcode for App Review. Use the sandbox scheme and appropriate toolchain only for the intended sandbox testing lane.
5. In Organizer, confirm bundle ID, marketing version, incremented build number, signing team, entitlements, and archive contents. Validate before upload.
6. Upload, wait for processing, then verify the processed build and group assignment in App Store Connect. Install that exact build on physical devices and record actual results. An archive or successful upload alone does not prove installation or feature delivery.
7. Before public submission, reconcile listing copy, screenshots, privacy disclosures, age rating/legal pages, reviewer access, paid-app agreement, availability, platform support, and subscription metadata.

## Production safeguards

- Keep production secrets in Render, Cloudflare, Apple, and Twilio account settings. Never put credentials in the repo or status notes.
- Do not enable development sign-in, seeded review circles, or review unlock in production.
- Do not treat API success or APNs acceptance as proof that a notification was displayed. APNs remains best effort; physical-device receipt must be observed.
- Do not deploy unreviewed working-tree changes. Record the commit, provider deployment ID, health check, and relevant public route checks in [STATUS.md](STATUS.md) after each verified release.
