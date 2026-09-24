# Trust readiness status — 2026-09-24

This page separates local verification from live-service observations. It does not claim that an iOS archive was uploaded or that APNs was verified on physical devices.

## Verified

- API: `dotnet test apps/trust-api/TrustApi.sln --no-restore` passed **103 tests** locally, including HTTP tests, two-account Postgres tests, sealed-history denial, phone lookup invite behavior, StoreKit disabled behavior, and concurrent Postgres SMS budget/OTP-attempt operations. Local Postgres runs on port `5433`.
- iOS: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apps/trust-ios` passed **26 core tests** on 2026-09-24. The final iPhone 17 Pro simulator run in `/tmp/trust-redesign-uitests-final.log` passed **4 UI tests** with zero failures; `xcodebuild` reported `TEST SUCCEEDED`. A full app Debug simulator build also passed locally. The hosted GitHub Actions job still needs a recorded run.
- Local simulator/API flow: against the local Development API, a bad phone OTP was rejected and the correct OTP completed verification. The explicit invite was accepted with both sharing directions Off; a Sealed Look returned a snapshot, and Always/View returned live location. This is local simulator evidence, not a production or physical-device test.
- Production Render: deployment `dep-daqocb8473hc73btvbmg`, commit `3a010ec`, is live on 2026-09-24. The linked `trust-api` service is configured for Production/Postgres. Read-only configuration inspection confirmed development sign-in, review circle seeding, and review unlock were disabled; StoreKit and APNs were enabled, and Twilio credentials were present. Secret values were not read into the report. The Twilio 2FA messaging campaign status was `VERIFIED` with use case `2FA`.
- Health check and release origin: `https://trust-api-u0ft.onrender.com/health/ready` returned healthy on 2026-09-24 after that deployment, and this is the configured release API origin while the custom hostname is unresolved. The custom hostname `trust.collapsetechnologies.com` is verified with Render and its CNAME now uses DNS-only mode, but HTTPS/TLS health is still failing/pending certificate provisioning; do not configure or describe it as healthy yet. The updated local two-account HTTP script passed **32 checks** against local API/Postgres on 2026-09-24.
- App Store Server Notifications V2: App Store Connect Production and Sandbox notification URLs were read-only verified as `https://trust-api-u0ft.onrender.com/api/v1/storekit/notifications` on 2026-09-24. This confirms the configured destination only; no signed notification delivery and processing result is recorded.
- Website: Cloudflare deployment commit `65fa48a`, version `7d90d280-a37f-42f4-b198-215e016069cd`, is live. On 2026-09-24, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/apple-app-site-association` each returned 200; API legal routes redirected successfully to canonical pages. `npm test` passed **3 route tests** locally; GitHub Actions now runs these tests when web files change. The hosted job still needs a recorded run. The URL checks confirm route responses, not a full visual or legal review.
- Backend safeguards now reject development sign-in config outside Development; disable StoreKit transaction verification when its feature flag is off; atomically reserve SMS budgets and advance/complete OTP challenges in Postgres; throttle phone send/verify routes; validate coordinates and cap location batches at 100; and return invites for both known and unknown phone numbers.

## Release blockers and limits

- **API custom hostname TLS:** Render verified the custom domain on 2026-09-24 and the CNAME was switched to DNS-only, but `https://trust.collapsetechnologies.com/health/ready` still fails TLS negotiation/pends certificate provisioning while the Render service URL passes. Recheck from an independent client; the iOS build must use an HTTPS hostname whose readiness endpoint succeeds before TestFlight distribution.
- **APNs delivery proof:** the live API has APNs configured, but notifications are best effort. There is no durable outbox or retry worker, and no physical-device delivery/display test is recorded. A successful API request is not delivery confirmation.
- **TestFlight:** no signed archive, App Store Connect upload, processed build, or physical iPhone verification is recorded here. Backend deployment is complete, but it does not establish app distribution readiness. Complete the release runbook and record the actual build/device outcome.
- **StoreKit production flow:** server verification is enabled, but a current end-to-end sandbox purchase/restore and server-notification test on the release build is not recorded.
- **Runtime maintenance:** the API targets .NET 9. Microsoft lists support ending 2026-11-10; plan a supported-runtime upgrade ahead of that date rather than expanding this hardening pass.

## Contract the clients should follow

- A confirmed `POST /api/v1/looks` from a connected viewer whose subject is Sealed returns exactly one current-location snapshot and records the Look event. It does not expose the sealed history endpoint.
- `GET /api/v1/people/{id}/history` requires the subject to share Always with that viewer. Sealed history returns `409 share_off`; the viewer's Plus entitlement controls the history window only after Always access is granted.
- Phone entry never reveals whether the number belongs to a Trust account and never connects accounts automatically. Both cases return an ordinary invite code; the recipient joins through the existing invite acceptance flow.
- Accepting an invite creates a connection. It does not enable sharing; each person chooses sharing for that peer.

## Next evidence to collect

Record the TestFlight build number, API hostname used by that build, two-account simulator results, physical iPhone push receipt result, StoreKit sandbox purchase/restore outcome, and whether the custom hostname passes HTTPS health checks. Keep secrets and signing material out of this file.
