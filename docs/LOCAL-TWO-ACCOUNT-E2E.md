# Local iOS E2E guide and evidence

This guide covers the loopback-only iOS E2E runner and the current evidence snapshot. Local simulator runs validate the checked-in app against a disposable Development API; they are not production-service or physical-device acceptance.

## Current evidence snapshot — 26 October 2026

The source snapshot is release build 49, from source archive `2561ba8`.

| Lane | Result | Evidence |
| --- | --- | --- |
| Standard iOS UI | 135 passed, 27 named setup skips, 0 failed | `/tmp/trust-e2e-20261025/standard-final-49/standard-ui.xcresult` |
| Paired two-account UI | Alice 1/1 and Bob 1/1, no skips or failures; wrapper exit 0; controller completed | `/tmp/trust-e2e-20261025/paired-handshake-49/paired-two-account/{alice,bob}/paired-{alice,bob}.xcresult`; controller log alongside results |
| APNs notification Settings recovery | 1 passed, 0 skipped, 0 failed | `/tmp/trust-e2e-20261025/real-apns-switch-recovery-49/RealPushAPNS.xcresult` |
| APNs foreground/background delivery | 1 passed, 0 skipped, 0 failed; two viewer accounts produced distinct Look receipts and matching Activity routes | `/tmp/trust-e2e-20261025/real-apns-48-final/RealPushAPNS.xcresult` |

The paired controller uses explicit stages rather than short-lived UI polling. Bob acknowledges `first-home-ready`; the controller moves to Away and records `first-away-held`; Bob updates Home and acknowledges `second-home-ready`; after the second Away is observed by both accounts, the controller records `complete` and releases its route. The test clears Home only after that final stage.

The APNs recovery case uses the native Settings route and asserts that the actual **Allow Notifications** switch is on, the API acknowledges registration, and a real APNs Look appears and opens the matching Activity receipt. On this simulator, the switch’s native accessibility tap did not change its value, so the test used one bounded tap at the visible switch thumb after capturing the native UI state. This is an interaction recovery through the native Settings UI, not an injected permission grant.

Build 49 is available through TestFlight. That availability does not establish TestFlight push delivery, Apple In-App Purchase purchase/restore, or physical-device behavior. The APNs runs above use the development APNs environment on a simulator.

## Running the local E2E matrix

`apps/trust-ios/Scripts/run_release_e2e.py` builds the standard Trust scheme once, copies its `.xctestrun`, injects runner settings under the test target environment, then runs the requested lane. It supports `standard`, `real-api`, `fault-matrix`, `paired`, `handoff`, and `all`. `--lane real-api` requires `--case`; the paired and same-account handoff cases use their dedicated orchestrators.

API-backed lanes start a fresh Development API on `127.0.0.1:5090` and the race proxy on `127.0.0.1:5089`. They use Memory by default. PostgreSQL mode creates a unique disposable database for each API session; native `psql` mode is intended for a caller-supplied, isolated loopback PostgreSQL instance. The runner refuses remote hosts and fails if either service port is already occupied. It stops only its own child processes, clears only locations it set on the selected devices, and drops only databases it created.

Example full matrix with two already-created simulator UDIDs and a local PostgreSQL server:

```sh
cd apps/trust-ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TRUST_E2E_POSTGRES_CONNECTION='Host=127.0.0.1;Port=5433;Database=postgres;Username=<local-role>;Password=<local-password>'
python3 Scripts/run_release_e2e.py \
  --lane all \
  --alice-device '<alice-simulator-udid>' \
  --bob-device '<bob-simulator-udid>' \
  --store postgres \
  --postgres-direct \
  --allow-review-fixture
```

The PostgreSQL connection string must point to a dedicated local instance with permission to create and drop databases. The generated database is per runner-owned API session. Omit `--postgres-direct` only when explicitly using a local Docker container with `--postgres-container <container-name>` and a loopback port mapping validated by the runner.

The runner creates a unique output directory under `/tmp` by default. To keep evidence in a chosen location, pass a new or empty `--output` directory. To rerun a case without rebuilding, provide the saved run specification with `--skip-build --xctestrun <path>`. One-case reruns use `--lane real-api --case <case-name> --device <udid>`; paired and handoff lanes accept `--alice-device` and `--bob-device`.

`--allow-review-fixture` opts into a Development-only synthetic review entitlement for cases that need it. It is labeled in the run evidence and does not create an App Store transaction. Leave it off when running cases that do not need the fixture.

## Paired location behavior

The `paired` lane creates a fresh pair ID and launches Alice and Bob on separate simulators. The runner starts `trust_pair_location_controller.py`; it sets only the selected Bob simulator’s synthetic route and waits for the paired test’s acknowledged stages. The UI tests still verify both accounts’ Home/Away state and visible-sharing responses before each acknowledgement. Do not start a second controller for a runner-managed paired lane.

The `handoff` lane runs its three same-account phases serially against one local API identity and gives the two simulators distinct local Home coordinates. The runner restores/clears only locations it changed. For both lanes, use disposable or explicitly selected simulators and retain each `.xcresult` and controller log.

## Evidence boundaries

- Local `.storekit` files exercise Xcode’s StoreKit test configuration; they are not Apple Sandbox transactions.
- Development OTP and reserved fictional phone numbers bypass delivery for local tests. Twilio test credentials simulate supported API responses but do not deliver SMS to phones.
- `--allow-review-fixture` is a synthetic Development entitlement path, not StoreKit or App Review validation.
- The APNs simulator cases exercise Apple’s development APNs environment. TestFlight uses production APNs; the simulator results do not prove TestFlight or production push delivery.
- These runs do not establish Apple Sign In, carrier SMS, IAP purchase or restore, background location on a physical device, or end-to-end production readiness.

Older September and early-October run totals are historical snapshots and are superseded for current release validation by the table above.
