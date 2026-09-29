# Local two-account E2E evidence

This document records completed local interaction evidence and the safe way to rerun the simulator lane. It does not describe production behavior. Latest evidence is from 29 September 2026.

## Latest completed simulator evidence

The latest paired run passed **1/1 with no skips on each device**: Alice `/tmp/trust-pair-alice34-20260929.xcresult` on iPhone 17 Pro/iOS 26.5 and Bob `/tmp/trust-pair-bob34-20260929.xcresult` on Duo/iOS 27.1. Both apps performed the reciprocal Home/Away presence grants through their native UIs, including Bob's grant through Duo. The run also covered Development OTP onboarding, phone discovery/request/acceptance, removal and re-invite, Sealed Look with map and Activity receipt, Home/Away consent and movement, Home update/clear, Hidden suppression and its visible label on Duo, Stop, and fresh default-Off after re-add.

A separate History UI run, `/tmp/trust-history-current-source-20260929.xcresult`, passed **1/1** on iPhone 17 Pro/iOS 26.5. It displayed three synthetic visits for an Always-sharing peer, then removed the History view after the peer stopped sharing and the viewer refreshed. It used one app UI and an API-driven peer, not two simultaneous app UIs.

The paired and History lanes used an isolated ASP.NET Development API backed by Memory on `127.0.0.1:5089`, with the review seed disabled. The fixtures use reserved fictional 555-01xx numbers and Development OTP; no SMS was sent. No push devices were registered, so these runs do not establish APNs delivery, OS presentation, or tap behavior. They also do not establish physical-device SMS, background location, or StoreKit behavior.

The account-owned cache isolation fix is implemented and reviewed by Sol. Swift package tests pass **77/77** and the full API suite passes **183/183**. The paired results above are current-source evidence for the normal reciprocal-grant and relationship flow. Deterministic delayed-read/race/relaunch coverage remains open.

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

## PostgreSQL migration rehearsal

The full API suite passed **183/183** on 29 September against an isolated local PostgreSQL 16 server. The suite includes `PostgresMigrationUpgradeTests`: it initializes the exact embedded migrations 001–013 and ledger, inserts synthetic pre-upgrade accounts, accepted memberships, Sealed/Always/live-Pause shares, presence grant and Home state, a pending request, location, and StoreKit subscription, then runs the actual migrator twice. It verifies preserved rows, zero-default share and presence revisions, the complete 001–020 ledger, and a generated Home transition ID that is nonempty and stable across the second application. It then uses `PostgresTrustStore` to Stop a share and Revoke the membership. The test creates and drops only its own temporary database and refuses non-loopback hosts or ports outside 5433–5435; the configured role needs `CREATEDB`.

This synthetic rehearsal verifies the populated local schema path and rerunnable migrations. Separately, a Render backup export completed at 15:35 PDT on 29 September was downloaded and privately retained outside the repository, then restored into isolated local PostgreSQL 16 at `127.0.0.1:5435` as `trust_production_restore_20260929`. Against that restored copy, the actual `PostgresMigrator.ApplyAsync` completed twice. The ledger contains all 20 migrations, the row counts of all 20 pre-existing business tables were unchanged, and `public` still has zero tables. No customer row values were inspected or printed and no live production database was written. This gives production-backup migration evidence without creating a new staging platform. It does not test rollback or build-32 UI/client compatibility.

## Remaining verification

- Deterministically inject a delayed old circle response plus failed post-mutation refresh; verify Stop, Remove, and partial Stop All after relaunch.
- Delay Look/History while the peer stops, removes, and re-adds with the viewer screen open; cover offline/relaunch/reconnect and concurrent History screens.
- Verify carrier SMS, background location, APNs permission/token/presentation/tap, StoreKit purchase/restore/expiry/refund, and account deletion on physical TestFlight devices.
- Test old build 32 against the planned backend rollout. The local schema rehearsal does not establish old-client compatibility.
