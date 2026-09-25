# Trust release runbook

This runbook covers the API, canonical website, and iOS TestFlight build. As of 2026-09-24, API and website deployments are verified. iOS build 21 is the older pre-redesign TestFlight build; the redesign is on the current branch and not yet deployed. Source is now version 1.0 build 22, intended for internal TestFlight, and has not been archived or uploaded. The redesign's M6 iPhone/iPad screenshots were recaptured on 2026-09-24 and have not been uploaded to App Store Connect. Installed Xcode 27.1 beta can build internal TestFlight build 22; stable public Xcode 27 is required for App Review. Keep production secrets in their service secret stores; the names below are configuration keys only.

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
3. If needed, generate `apps/trust-ios/Trust.xcodeproj` from `project.yml` by running `xcodegen generate` in `apps/trust-ios`. The local redesign passed API tests 106/106, Swift core tests 26/26, Duo UI tests 4/4, and web tests 3/3. Build 21 is the older TestFlight build; current source version 1.0 build 22 is intended for internal TestFlight and can be archived with installed Xcode 27.1 beta. Deploy the reviewed API and website changes before testing the release app against production. Stable public Xcode 27 is required when preparing the App Review build.
4. Confirm the website's legal pages and `sms-opt-in.png` are present in `apps/jointrust-web/public`; use the repository's authenticated Wrangler setup for deployment.

## API deployment

The Render web service is `trust-api` (`srv-daabv1lg1s2s73co5gm0`), connected to `QuirinoC/trust` on `main`, with root directory `apps/trust-api` and Dockerfile `./Dockerfile`. Its existing database is `trust-postgres` (`dpg-daabu1e7bikc73808dt0-a`). The checked-in `render.yaml` is a blueprint definition, not a safe way to refresh existing production configuration: **do not Blueprint Sync it over the live service**, because secret-backed values are managed separately.

The current live deployment is `dep-daqocb8473hc73btvbmg`, commit `3a010ec` (2026-09-24). Deploy a later reviewed commit through the existing Render service's deployment controls. Before triggering another production deploy, confirm that the commit is the intended release and that Render still points to the existing service and database. Preserve the live values for `Auth__SigningKey`, `ConnectionStrings__Postgres`, `Apns__KeyId`, `Apns__PrivateKey`, and Twilio credentials. Keep `Auth__AllowDevelopmentSignIn`, `Trust__SeedReviewCircle`, and `StoreKit__AllowReviewUnlock` set to `false` in production. Stripe remains disabled.

After the deploy finishes, check `/health/live` and `/health/ready`. The Render service URL `https://trust-api-u0ft.onrender.com` returned healthy readiness after the current deployment on 2026-09-24, and is the configured release API origin. Render verified ownership of `trust.collapsetechnologies.com`; its CNAME points to the Render service in DNS-only mode, but TLS still fails/pends certificate provisioning. Do not report the custom host as healthy until HTTPS succeeds from an independent client. The live API configuration was read-only verified as Production/Postgres with development sign-in, review seeding, and review unlock disabled; StoreKit and APNs enabled; Twilio configured. The Twilio 2FA campaign is `VERIFIED`. No secret values were read or changed.

If readiness fails, stop the release and inspect Render logs and the database migration result. Use Render's deployment history to roll back to the last known healthy deployment, then verify both health endpoints. The previous audited deployment was commit `0d974744c6c11e530ecef0f918f568a6eaca765e`; confirm it remains healthy and available in Render before selecting it as a rollback target.

## Website deployment

The canonical site is the Cloudflare Worker in `apps/jointrust-web` with config `wrangler.jsonc`. The current live Cloudflare version is `5c1d221f-4e07-4adb-9b4d-9c1844de332b`, deployed from the working tree on 2026-09-24 with the corrected support copy. Deploy from the repository root after reviewing later site changes:

```bash
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

After a deployment, check `https://jointrust.app`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association`. On 2026-09-24 these paths all returned 200 on the live site, including the invite landing and AASA response. The API legal routes previously returned successful redirects to canonical website pages. If the Worker update fails verification, use Cloudflare's deployment/version history to restore the prior working version, then repeat the URL checks.

## Release order

1. Review the local redesign and complete the intended source changes; commit and push before preparing distribution.
2. Archive version 1.0 build 22 with installed Xcode 27.1 beta, validate and upload it for internal TestFlight, then complete physical-device checks. Build 21 remains the older uploaded TestFlight build.
3. Upload the recaptured M6 screenshots to ASC and verify the listing assets; reconcile privacy disclosures and remaining listing metadata.
4. Before App Review, install stable public Xcode 27 (27A266a), create a new compliant release archive/build, select it for version 1.0, and submit the app and subscription group together when all review blockers are resolved.
5. Deploy API or website changes only when their reviewed source is ready; verify the live health/routes after each deployment.

Build 21 is the older uploaded TestFlight build and is distinct from intended internal build 22. Neither the redesigned source nor its screenshots have been uploaded. Since stable Xcode 27 is required for App Review, build 22's beta-built archive is for internal testing; prepare a stable-Xcode release build for submission. See `docs/STATUS.md` and `apps/trust-ios/AppStore/REVIEW-READINESS.md` for current evidence and blockers.

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
