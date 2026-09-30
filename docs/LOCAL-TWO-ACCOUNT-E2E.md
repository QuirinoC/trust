# Local two-account E2E evidence

This document records completed local interaction evidence and the safe way to rerun the simulator lane. The latest local interaction evidence is from 29 September 2026; current merged API and deployment evidence elsewhere in this document is later and is tracked in [STATUS.md](STATUS.md). This document does not describe production behavior.

## Latest completed simulator evidence

At the 2026-09-29 source checkpoint, the paired run passed **1/1 with no skips on each device**: Alice `/tmp/trust-pair-alice34-20260929.xcresult` on iPhone 17 Pro/iOS 26.5 and Bob `/tmp/trust-pair-bob34-20260929.xcresult` on Duo/iOS 27.1. Both apps performed the reciprocal Home/Away presence grants through their native UIs, including Bob's grant through Duo. The run also covered Development OTP onboarding, phone discovery/request/acceptance, removal and re-invite, Sealed Look with map and Activity receipt, Home/Away consent and movement, Home update/clear, Hidden suppression and its visible label on Duo, Stop, and fresh default-Off after re-add.

A separate History UI run, `/tmp/trust-history-current-source-20260929.xcresult`, passed **1/1** on iPhone 17 Pro/iOS 26.5. It displayed three synthetic visits for an Always-sharing peer, then removed the History view after the peer stopped sharing and the viewer refreshed. It used one app UI and an API-driven peer, not two simultaneous app UIs.

The paired and History lanes used an isolated ASP.NET Development API backed by Memory on `127.0.0.1:5089`, with the review seed disabled. The fixtures use reserved fictional 555-01xx numbers and Development OTP; no SMS was sent. No push devices were registered, so these runs do not establish APNs delivery, OS presentation, or tap behavior. They also do not establish physical-device SMS, background location, or StoreKit behavior.

At that same 2026-09-29 source checkpoint, Swift package tests passed **77/77**, the API suite passed **183/183**, and the paired results above exercised the normal reciprocal-grant and relationship flow. These are checkpoint results, not the current merged-source test count. Current merged-source evidence is recorded in [STATUS.md](STATUS.md): API/Postgres suite **192/192** and [GitHub main CI run 36667903930](https://github.com/QuirinoC/trust/actions/runs/36667903930). The focused Stop/Remove/partial Stop All/delayed Look evidence below adds deterministic fault coverage; delayed History remains open.

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

At the 2026-09-29 source checkpoint, the full API suite passed **183/183** against an isolated local PostgreSQL 16 server. Its `PostgresMigrationUpgradeTests` rehearsal initialized the exact embedded migrations 001–013 and ledger, inserted synthetic pre-upgrade accounts, accepted memberships, Sealed/Always/live-Pause shares, presence grant and Home state, a pending request, location, and StoreKit subscription, then ran the actual migrator twice. It verified preserved rows, zero-default share and presence revisions, the complete 001–020 ledger, and a generated Home transition ID that is nonempty and stable across the second application. It then used `PostgresTrustStore` to Stop a share and Revoke the membership. The test creates and drops only its own temporary database and refuses non-loopback hosts or ports outside 5433–5435; the configured role needs `CREATEDB`. Migration 021 is covered by the later current-suite and deployment evidence in [STATUS.md](STATUS.md).

This synthetic rehearsal verifies the populated local schema path and rerunnable migrations through 020 at the 2026-09-29 checkpoint. Separately, a Render backup export completed at 15:35 PDT on 29 September was downloaded and privately retained outside the repository, then restored into isolated local PostgreSQL 16 at `127.0.0.1:5435` as `trust_production_restore_20260929`. Against that restored copy, the actual `PostgresMigrator.ApplyAsync` completed twice. The ledger contained all 20 migrations, the row counts of all 20 pre-existing business tables were unchanged, and `public` still had zero tables. No customer row values were inspected or printed and no live production database was written. This gives production-backup migration evidence without creating a new staging platform. It does not test rollback. Migration 021 is covered by the later current-suite and deployment evidence in [STATUS.md](STATUS.md). Build 32's exact privacy-reducing HTTP compatibility (Off, Remove, Delete) has test evidence, but there is no build-32 UI proof; all older App Store builds have expired, so retrieving an old build for a new UI run is not a release gate.

## Separate TestFlight and live-service evidence — 2026-09-29

The paired simulator results above came from local current-source UI tests and the isolated Development + Memory API, not from a TestFlight installation. At the App Store Connect observation recorded during this test run, version 1.0 was `PREPARE_FOR_SUBMISSION` with manual release and build 35 selected. Build 35 was `VALID`, `APP_STORE_ELIGIBLE`, and `IN_BETA_TESTING` in the sole internal Trust Family Auto group with all three testers; automatic notification and all-build access were enabled. Build 35 validation/upload had completed, and older builds were expired at that point. Physical feedback at `2026-09-30T00:39:03Z` confirms installation on iOS 27.0 but shows a blocking required-check error; normal Apple access remains unverified. Later App Store Connect evidence, including build 36, is recorded in [STATUS.md](STATUS.md); the current live state could not be refreshed while the Mac was locked.

At the Render observation recorded during this test run, API commit `f5e235d148fcf5068ec25a583af5231fbf209516` was live in deployment `dep-dau5sgm0tbcc738oskug` at `2026-09-30T00:57:31Z`. It corrected App Transaction validation to use Apple's `receiptType` and `receiptCreationDate`; the focused verifier suite passed 14/14 and the historical full API suite passed 189/189 with isolated PostgreSQL. `/health/live` and `/health/ready` returned 200; an unauthenticated App Transaction registration request returned 401. At that time the service startup awaited migrations 001–020 and the production ledger was not queried directly. This deployment was superseded by `c7c57b6481ade20c214e0ae40dcebab22829ab38`, which includes migration 021; current deploy evidence is in [STATUS.md](STATUS.md). These observations do not prove an authenticated production transaction or resolve the reported screen without physical retry, and do not change the local-only scope of the interaction tests.

## Remaining verification

- Delay History with a legitimate paid entitlement across Stop/remove/re-add; cover offline/reconnect, same-account second devices, and concurrent History screens. The focused Look replacement race is completed above.
- Verify carrier SMS, background location, APNs permission/token/presentation/tap, StoreKit purchase/restore/expiry/refund, and account deletion on physical TestFlight devices.
- Build-32 app-UI compatibility remains unverified because the build has expired. Existing HTTP tests cover its privacy-reducing Off, Remove, and Delete operations; they do not establish old-client UI behavior, and a new expired-build download is not a release gate.
