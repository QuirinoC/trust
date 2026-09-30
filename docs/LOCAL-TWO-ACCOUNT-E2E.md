# Local two-account E2E evidence

This document records completed local interaction evidence and the safe way to rerun the simulator lane. It does not describe production behavior. Latest evidence is from 29 September 2026.

## Latest completed simulator evidence

The latest paired run passed **1/1 with no skips on each device**: Alice `/tmp/trust-pair-alice34-20260929.xcresult` on iPhone 17 Pro/iOS 26.5 and Bob `/tmp/trust-pair-bob34-20260929.xcresult` on Duo/iOS 27.1. Both apps performed the reciprocal Home/Away presence grants through their native UIs, including Bob's grant through Duo. The run also covered Development OTP onboarding, phone discovery/request/acceptance, removal and re-invite, Sealed Look with map and Activity receipt, Home/Away consent and movement, Home update/clear, Hidden suppression and its visible label on Duo, Stop, and fresh default-Off after re-add.

A separate History UI run, `/tmp/trust-history-current-source-20260929.xcresult`, passed **1/1** on iPhone 17 Pro/iOS 26.5. It displayed three synthetic visits for an Always-sharing peer, then removed the History view after the peer stopped sharing and the viewer refreshed. It used one app UI and an API-driven peer, not two simultaneous app UIs.

The paired and History lanes used an isolated ASP.NET Development API backed by Memory on `127.0.0.1:5089`, with the review seed disabled. The fixtures use reserved fictional 555-01xx numbers and Development OTP; no SMS was sent. No push devices were registered, so these runs do not establish APNs delivery, OS presentation, or tap behavior. They also do not establish physical-device SMS, background location, or StoreKit behavior.

The account-owned cache isolation fix is implemented and reviewed by Sol. Swift package tests pass **77/77** and the full API suite passes **183/183**. The paired results above are current-source evidence for the normal reciprocal-grant and relationship flow. The focused Stop/Remove/partial Stop All/delayed Look evidence below adds deterministic fault coverage; delayed History remains open.

The unsigned simulator `TrustAgeGateTests` suite passed **6/6** after DEBUG-only `TrustKeychain` test storage was enabled for `TRUST_AGE_TEST_MODE=1`; result: `/tmp/trust-agegate-keychain-fix-20260929.xcresult`. The release keychain path remains unchanged. That grant assertion was synchronized with the enabled UI action. Earlier failed harness attempts and the rate-limited five-case run are not counted as completed evidence.

## Completed focused fault cases

Sol independently verified each final xcresult: **1/1 passed, zero skips/failures** on iPhone 17 Pro/iOS 26.5 with Xcode 27.1 beta:

- Stop: `/tmp/trust-race-stop-final-20260929.xcresult`.
- Remove: `/tmp/trust-race-remove-final-20260929.xcresult`.
- Partial Stop All: `/tmp/trust-race-stopall-final5-20260929.xcresult`.
- Delayed Look: `/tmp/trust-race-look-guarded-20260929.xcresult`.

Each case used a fresh Development + Memory API with review seed disabled, fictional phones, and no StoreKit/review bypass. Stop/Remove wait for the app-applied mutation before releasing the captured old circle, inject a failed reconciliation read, and check independent server state plus same-account relaunch. Stop All arms its second-write failure before returning the first acknowledgement and verifies successful Off versus failed Sealed after relaunch. Look waits for response processing/sheet dismissal and the delayed-navigation interval before checking that the replaced relationship cannot restore a map.

The delayed-History case was removed from this patch: its available synthetic unlock fixture returns 503 with bypass disabled. It remains pending a legitimate paid entitlement. Earlier synthetic History UI evidence is not real StoreKit validation.

## Safe simulator setup

`TrustRealAPIFeatureTests` requires an explicit `TRUST_UI_TEST_BASE_URL` with HTTP loopback port 5089. Before creating an account or requesting a phone code, setup checks `/api/v1/local-test-capabilities` for `developmentOtpWithoutSms: true`, then validates the returned OTP. Single-UI test accounts are deleted in test cleanup; paired accounts are discarded when the isolated Memory API is stopped.

Start the isolated API with local-only settings:

```sh
ASPNETCORE_ENVIRONMENT=Development \
ASPNETCORE_URLS=http://127.0.0.1:5089 \
Trust__Store=memory \
Trust__SeedReviewCircle=false \
Auth__AllowDevelopmentSignIn=true \
Auth__SigningKey=development-signing-key-32bytes-min!! \
dotnet run --no-launch-profile --project apps/trust-api/TrustApi.csproj
```

Set `TRUST_UI_TEST_BASE_URL=http://127.0.0.1:5089` for the runner and each simulator. For paired runs, also set `TRUST_UI_PAIR_ROLE=alice` or `bob` and the same eight-hex `TRUST_UI_PAIR_ID` on the corresponding simulator. After reboot, reapply and verify simulator launchd variables with `launchctl getenv`. Stop the isolated API and clear every `TRUST_UI_*` simulator variable after the run. Never point these tests at a remote service or the existing local service on port 5088.

The deterministic stale-read UI regression uses the loopback-only proxy in `apps/trust-api/scripts/trust_ui_race_proxy.py`. From the repository root, start the Development + Memory API in the first process:

```sh
ASPNETCORE_ENVIRONMENT=Development \
ASPNETCORE_URLS=http://127.0.0.1:5090 \
Trust__Store=memory \
Trust__SeedReviewCircle=false \
Auth__AllowDevelopmentSignIn=true \
Auth__SigningKey=development-signing-key-32bytes-min!! \
dotnet run --no-launch-profile --project apps/trust-api/TrustApi.csproj
```

Start the proxy in a second process:

```sh
python3 apps/trust-api/scripts/trust_ui_race_proxy.py
```

The proxy listens only on `127.0.0.1:5089`, forwards only to its fixed `127.0.0.1:5090` upstream, and does not log request paths or bodies. Set `TRUST_UI_TEST_BASE_URL=http://127.0.0.1:5089` on the simulator and in the `TrustUITests.EnvironmentVariables` section of the `.xctestrun` file; do not put it in `TestingEnvironmentVariables`. Do not also bind the API directly to port 5089 in this mode. Run one focused case per fresh API/proxy process to isolate rate limits and faults. Keep StoreKit/review bypass flags off. Teardown releases held reads and resets fault state; still stop both processes after each case and clear simulator `TRUST_UI_*` launchd variables.

## PostgreSQL migration rehearsal

The full API suite passed **183/183** on 29 September against an isolated local PostgreSQL 16 server. The suite includes `PostgresMigrationUpgradeTests`: it initializes the exact embedded migrations 001–013 and ledger, inserts synthetic pre-upgrade accounts, accepted memberships, Sealed/Always/live-Pause shares, presence grant and Home state, a pending request, location, and StoreKit subscription, then runs the actual migrator twice. It verifies preserved rows, zero-default share and presence revisions, the complete 001–020 ledger, and a generated Home transition ID that is nonempty and stable across the second application. It then uses `PostgresTrustStore` to Stop a share and Revoke the membership. The test creates and drops only its own temporary database and refuses non-loopback hosts or ports outside 5433–5435; the configured role needs `CREATEDB`.

This synthetic rehearsal verifies the populated local schema path and rerunnable migrations. Separately, a Render backup export completed at 15:35 PDT on 29 September was downloaded and privately retained outside the repository, then restored into isolated local PostgreSQL 16 at `127.0.0.1:5435` as `trust_production_restore_20260929`. Against that restored copy, the actual `PostgresMigrator.ApplyAsync` completed twice. The ledger contains all 20 migrations, the row counts of all 20 pre-existing business tables were unchanged, and `public` still has zero tables. No customer row values were inspected or printed and no live production database was written. This gives production-backup migration evidence without creating a new staging platform. It does not test rollback. Build 32's exact privacy-reducing HTTP compatibility (Off, Remove, Delete) has test evidence, but there is no build-32 UI proof; all older App Store builds have expired, so retrieving an old build for a new UI run is not a release gate.

## Separate TestFlight and live-service evidence — 2026-09-29

The paired simulator results above came from local current-source UI tests and the isolated Development + Memory API, not from a TestFlight installation. App Store Connect now reports version 1.0 as `PREPARE_FOR_SUBMISSION` with manual release and build 35 selected. Build 35 is `VALID`, `APP_STORE_ELIGIBLE`, and `IN_BETA_TESTING` in the sole internal Trust Family Auto group with all three testers; automatic notification and all-build access are enabled. Build 35 validation/upload completed, and every older build is expired. Physical feedback at `2026-09-30T00:39:03Z` confirms installation on iOS 27.0 but shows a blocking required-check error; normal Apple access remains unverified.

The live Render API is commit `f7eb05fa9ec16ba0049d333fe5761ce210eeb76c`, deployment `dep-dau4df2vcj2c73eg4v1g` at 23:17 UTC. `/health/live` and `/health/ready` returned 200; an unauthenticated App Transaction registration request returned 401. The current service starts only after its migration runner has applied migrations 001–020, but the production ledger was not queried directly. These observations do not prove an authenticated production transaction or change the local-only scope of the interaction tests.

## Remaining verification

- Delay History with a legitimate paid entitlement across Stop/remove/re-add; cover offline/reconnect, same-account second devices, and concurrent History screens. The focused Look replacement race is completed above.
- Verify carrier SMS, background location, APNs permission/token/presentation/tap, StoreKit purchase/restore/expiry/refund, and account deletion on physical TestFlight devices.
- Build-32 app-UI compatibility remains unverified because the build has expired. Existing HTTP tests cover its privacy-reducing Off, Remove, and Delete operations; they do not establish old-client UI behavior, and a new expired-build download is not a release gate.
