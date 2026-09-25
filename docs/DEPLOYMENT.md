# Trust release runbook

This runbook covers the API, canonical website, and iOS TestFlight build. PR #4 merged the website alignment to `main` at `50715c0`; API, iOS, and web checks passed. Render deployment `dep-dar1gnm0tbcc73cingv0` remains the last verified API deployment; `/health/ready` returned `200 Healthy`, and the preset allowlist is deployed. Cloudflare version `0b61e45a-0391-42e6-9e44-d3a473921469` is live with the Together Lines site, and the documented public routes returned 200. Build 24’s optimized archive passed Xcode Organizer validation for team `3S529795M9` and uploaded for internal TestFlight on 2026-09-25. ASC processing and group assignment are unverified while Chrome is signed out. M6 screenshots, privacy answers, age-policy choice, physical-device checks, and carousel visual sign-off remain open. Stable public Xcode 27 is required for App Review. Keep production secrets in their service secret stores; the names below are configuration keys only.

## Before a release

1. Review `docs/STATUS.md` and resolve any blocker that affects the planned release.
2. Run the API suite and local two-account flow from the repository root:

   ```bash
   cd apps/trust-api
   docker compose up postgres -d
   dotnet test TrustApi.sln
   dotnet run --launch-profile TrustApi
   ```

   In another terminal, run `python3 apps/trust-api/scripts/e2e_two_account_http.py`. It creates temporary accounts in the local database and mutates test rows; do not point it at production.
3. If needed, generate `apps/trust-ios/Trust.xcodeproj` from `project.yml` by running `xcodegen generate` in `apps/trust-ios`. Build 24 was validated and uploaded for internal TestFlight; verify ASC processing and tester-group availability before physical-device checks. Stable public Xcode 27 is required for the App Review build.
4. Confirm the website's legal pages and `sms-opt-in.png` are present in `apps/jointrust-web/public`; use the repository's authenticated Wrangler setup for deployment.

## API deployment

The Render web service is `trust-api` (`srv-daabv1lg1s2s73co5gm0`), connected to `QuirinoC/trust` on `main`, with root directory `apps/trust-api` and Dockerfile `./Dockerfile`. Its existing database is `trust-postgres` (`dpg-daabu1e7bikc73808dt0-a`). The checked-in `render.yaml` is a blueprint definition, not a safe way to refresh existing production configuration: **do not Blueprint Sync it over the live service**, because secret-backed values are managed separately.

The last verified deployment was `dep-dar1gnm0tbcc73cingv0`, for merged commit `31db6cc`. `/health/ready` returned `200 Healthy`; the API preset allowlist is deployed. Deploy a later reviewed commit through the existing Render service's deployment controls. Before triggering another production deploy, confirm that the commit is intended and Render still points to the existing service and database. Preserve live secret-backed settings; keep `Auth__AllowDevelopmentSignIn`, `Trust__SeedReviewCircle`, and `StoreKit__AllowReviewUnlock` set to `false` in production. Stripe remains disabled. An unauthenticated avatar PUT returned `401`, confirming the endpoint rejects unauthenticated writes.

After the deploy finishes, check `/health/live` and `/health/ready`. The Render service URL `https://trust-api-u0ft.onrender.com` returned healthy readiness after the current deployment on 2026-09-24, and is the configured release API origin. Render verified ownership of `trust.collapsetechnologies.com`; its CNAME points to the Render service in DNS-only mode, but TLS still fails/pends certificate provisioning. Do not report the custom host as healthy until HTTPS succeeds from an independent client. The live API configuration was read-only verified as Production/Postgres with development sign-in, review seeding, and review unlock disabled; StoreKit and APNs enabled; Twilio configured. The Twilio 2FA campaign is `VERIFIED`. No secret values were read or changed.

If readiness fails, stop the release and inspect Render logs and the database migration result. Use Render's deployment history to roll back to the last known healthy deployment, then verify both health endpoints. The previous audited deployment was commit `0d974744c6c11e530ecef0f918f568a6eaca765e`; confirm it remains healthy and available in Render before selecting it as a rollback target.

## Website deployment

The canonical site is the Cloudflare Worker in `apps/jointrust-web` with config `wrangler.jsonc`. The current live Cloudflare version is `0b61e45a-0391-42e6-9e44-d3a473921469`, merged in PR #4. Its `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` routes all returned 200. The live privacy page includes the photo information and support describes push as best-effort. Deploy from the repository root after reviewing later site changes:

```bash
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

After a deployment, check `https://jointrust.app`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association`. All returned 200 for the current version. The app-configured `jointrust.app/privacy`, `/terms`, and `/support` URLs also returned 200. If the Worker update fails verification, use Cloudflare's deployment/version history to restore the prior working version, then repeat the URL checks.

## Release order

1. Visually sign off the open Duo and far end of the profile carousel on build 24.
2. Build 24 was validated and uploaded for internal TestFlight. Restore ASC browser access to verify processing/group status, then install it for physical-device checks.
3. Upload the refreshed M6 screenshots to ASC and verify the listing assets; reconcile privacy disclosures and the age-policy conflict with the live legal pages.
4. Before App Review, install stable public Xcode 27 (27A266a), create a compliant release archive/build, select it for version 1.0, and submit the app and subscription group together when all review blockers are resolved.
5. Deploy API or website changes only when their reviewed source is ready; verify the live health/routes after each deployment.

Build 24 is the latest uploaded TestFlight build; ASC processing and group assignment remain unverified. Screenshots, privacy answers, and age-policy alignment remain pending in ASC, whose browser session is signed out. Since stable Xcode 27 is required for App Review, prepare a stable-Xcode release build for submission. See `docs/STATUS.md` and `apps/trust-ios/AppStore/REVIEW-READINESS.md` for current evidence and blockers.

## TestFlight upload

1. In Xcode, select the `Trust` scheme and an iOS device destination, then create an Archive for the reviewed commit.
2. In Organizer, confirm the bundle identifier is `com.collapsetechnologies.trust`, the version/build number is intended, and the archive is signed by the configured Apple distribution identity.
3. Validate the archive and upload it to App Store Connect. Do not paste signing credentials, API keys, or provisioning material into the repository or task notes.
4. Wait for Apple processing, assign the build to the internal TestFlight group, and install it on a physical iPhone.
5. Verify sign-in, invite creation and acceptance across two accounts, both sides' sharing controls, sealed history rejection, confirmed Look and recipient receipt, Always and View, pause/stop, account deletion, and SMS verification if testing real SMS is explicitly intended. Confirm the client uses an API hostname whose HTTPS health check succeeds.
6. Record the build number and actual device results in `docs/STATUS.md`. A simulator run does not count as physical APNs verification.

APNs sending currently works as a best-effort request from the API. There is no durable notification outbox or retry worker. A successful API request does not prove Apple delivered or displayed a receipt; verify this on a physical device before claiming end-to-end receipt delivery.

## Configuration keys

Use the service dashboard to manage values. This list intentionally contains no values:

- API: `ConnectionStrings__Postgres`, `Auth__SigningKey`, `Auth__AllowDevelopmentSignIn`, `Trust__SeedReviewCircle`, `StoreKit__Enabled`, `StoreKit__AllowReviewUnlock`, `Apns__Enabled`, `Apns__TeamId`, `Apns__KeyId`, `Apns__PrivateKey`, `Twilio__AccountSid`, `Twilio__AuthToken`, `Twilio__FromNumber`, `Twilio__MessagingServiceSid`.
- iOS: App Store Connect distribution signing and provisioning configured in Xcode.
- Website: the existing authenticated Wrangler account for the `jointrust.app` Worker.

The Twilio 2FA campaign was read-only verified as `VERIFIED` with use case `2FA` on 2026-09-24. Do not edit its registration as part of a routine release.
