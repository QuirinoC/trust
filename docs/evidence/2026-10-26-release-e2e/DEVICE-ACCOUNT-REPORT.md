# Trust testing: devices, accounts, and scenarios

This report describes the release testing and iPhone Duo simulator sweep recorded on 26 October 2026. It separates the device and account used in each run from the services that were actually exercised. It is a snapshot of completed work, not a claim that every device or service has been tested.

## iPhone Duo simulator sweep

The Duo sweep used task-owned iPhone Duo simulators running iOS 27.1. These are simulated devices; no physical iPhone Duo was tested. The sweep tests a newer working-source snapshot, and does not alter the already uploaded TestFlight build 49.

- **PairAlice and PairBob — two Duo simulators.** Each fictional account ran as a separate app client against a fresh local Development API and disposable PostgreSQL database. On the final app source, both roles passed, with no skips or failures; the paired runner completed successfully and its location controller completed two Home-to-Away stages. The run used local Development phone codes, simulated locations, and a synthetic review-unlock fixture. It does not establish carrier SMS, actual travel, or a StoreKit purchase. An earlier paired run also passed, but preceded the final Add accessibility footer change. Changes after the final paired binary were limited to documentation and test evidence.
- **Fold and unfold — Duo simulator.** A focused test passed with no skips or failures while moving from closed to open on a person's View, closing and reopening to Map, and closing and reopening again. It checked that the same person remained selected, there was one map, and Sharing kept its single-row layout.
- **Half-open map — Duo simulator.** The focused map selection and context test passed with no skips or failures at the confirmed 90-degree half-open posture. This is one scenario, not a full half-open suite. Result: `/tmp/trust-duo-sweep-20261026/duo-half-map.xcresult`.
- **Pause at the largest text size — Duo simulator.** The focused six-language test passed with no skips or failures.
- **Add someone at the largest text size — Duo and iPhone SE (3rd generation) simulators.** The latest focused test passed on each device with no skips or failures. It covered English in light and dark appearances and German in light appearance. The SE runs iOS 26.5.

The final broad Duo suite completed with **135 passed, 28 skipped, and zero failed**. Twenty-seven skips required separate service setup; the remaining skip was an opt-in fold test, which passed in the separate focused fold/unfold run described above. Skips are not passes.

An earlier broad Duo attempt recorded 131 passes, 27 setup skips, and four failures. Later focused runs passed the separate Add, Invite, standard-size Pause, and largest-text Pause checks. The final broad rerun above supersedes that earlier attempt for the standard suite; focused results cover only their listed scenarios and configurations.

Result bundles: the final broad suite is at `/tmp/trust-duo-sweep-20261026/standard-final.xcresult`. Final paired roles are under `/tmp/trust-duo-sweep-20261026/paired-duo-final/paired-two-account/{alice,bob}/`, with the controller log alongside; the earlier paired roles are under `/tmp/trust-duo-sweep-20261026/paired-duo-postgres/paired-two-account/{alice,bob}/`. Fold/unfold is at `/tmp/trust-duo-sweep-20261026/transition-revision4.xcresult`; Pause at `/tmp/trust-duo-sweep-20261026/pause-revision5.xcresult`; and Add at `/tmp/trust-duo-sweep-20261026/add-duo-revision7.xcresult` and `/tmp/trust-duo-sweep-20261026/add-se-revision7.xcresult`. The earlier broad result is `/tmp/trust-duo-sweep-20261026/standard.xcresult`. Temporary results can be removed by system cleanup.

## iPad targeted checks

On an iPad Pro 11-inch (M5) simulator running iOS 26.5, the focused Look test passed in `/tmp/trust-duo-sweep-20261026/ipad-map-final.xcresult`. That same two-test run also had a map-context failure. A separate rerun of the map-context test passed, with one passed, no skips, and no failures, in `/tmp/trust-duo-sweep-20261026/ipad-map-rerun.xcresult`. These are targeted simulator checks, not a full iPad suite or physical-device validation.

## Earlier release devices and accounts

All iPhones in the earlier release runs below were **simulators running iOS 26.5**, not physical phones. Test accounts were fictional, disposable Development identities. The names below identify test roles; they are not customer accounts or Apple IDs.

- **PairAlice — iPhone 17 Pro simulator, build 49.** Completed onboarding with a Development account and opted into phone discovery. Sent PairBob a connection request, chose sharing and Home/Away permissions, checked recipient visibility, removed and reconnected the relationship.
- **PairBob — iPhone SE (3rd generation) simulator, build 49.** Ran alongside PairAlice on a separate simulator and account. Accepted the request, chose sharing and Home/Away permissions, performed a Sealed Look, and exercised Home/Away transitions and the subsequent relationship lifecycle.
- **HomeHandoff — the same Development identity on an iPhone 17 Pro and an iPhone SE (3rd generation), build 48.** This is a separate, serial same-account test: the 17 Pro set Home, the SE detected that monitoring was on another device and took it over, and the 17 Pro detected the takeover and cleared Home. Each of the three phases passed. The shared Development identity does not validate signing into an Apple account on two physical devices.
- **PushMain — iPhone 17 Pro simulator, build 48.** The app ran as this fictional recipient for real Apple development-environment notification checks. Two other fictional accounts, PushPeer and PushView, generated separate Looks through the local test API; they did not run as two additional phone clients. Foreground and background alerts appeared and each opened its matching Activity receipt.
- **RecoveryMain — iPhone SE (3rd generation) simulator, build 49.** A fictional RecoveryPeer account generated a Look through the local test API. The recipient denied notifications, opened native Settings, enabled them, returned to the app, registered for notifications, received a real Apple development-environment push, and opened its matching Activity receipt.
- **Other Development test identities — iPhone 17 Pro simulator, build 48.** Twenty-three separately run local-API user scenarios each passed without a skip. Accounts and data were isolated per case. The scenarios cover onboarding and recovery, discovery and requests, mode changes, Pause/Resume/Stop/remove, profile and privacy settings, offline or stale responses, and Look/History access.
- **Standard UI test fixtures — iPhone 17 Pro simulator, build 49.** The broad UI suite reported 135 passed, 27 expected setup skips, and zero failures. These fixtures are distinct from the paired accounts above. The skipped tests were not counted as passes: 23 corresponding standalone cases were run separately on build 48, three Home handoff phases were run separately on build 48, and the paired two-role story was run separately on build 49.

Build-49 Pause checks also passed on both simulator models in all six shipped languages, including the narrow SE layout. After a cloud test-helper timing correction, six focused UI checks passed on a fresh iPhone SE simulator: appearance, language, Pause accessibility and actions, the compact Sharing row across locales, and its German extra-large boundary. These results validate test-helper changes; the app in TestFlight build 49 was not changed by that correction.

## What the two-person scenario covered

The paired run completed on build 49 with Alice and Bob each reporting one passed test, no skips, and no failures. It exercised:

1. Each person's onboarding, an explicit discovery choice, verified fictional phone entry, request by phone, and acceptance on the other simulator.
2. Explicit directional Home/Away grants and Sealed sharing. Bob's UI performed a Look, saw its location snapshot on the map, and saw the corresponding Activity receipt.
3. Bob set Home, the simulator followed a controlled location route, and both accounts observed Home and Away. Bob updated Home and repeated the Home-to-Away transition before clearing it. Alice separately selected Home, Away, and Hidden, with Bob's recipient view checked for each choice.
4. Stop, removal from both accounts, a new request and acceptance, and a fresh connection that started with sharing Off.

This story used two simultaneously running app clients and an isolated local Development API backed by a fresh disposable PostgreSQL database. Location was supplied by a simulator route, the phone code was a local Development code, and the enabled review-unlock fixture was synthetic. It did not exercise real mobile-network travel, carrier SMS, Apple Sign In, or a StoreKit purchase.

## Other checks and service boundaries

- **API and storage:** 216 API/PostgreSQL tests passed on the build-49 source. Separately, 41 fictional-account HTTP scenarios passed against an isolated local Development API and PostgreSQL; these are server tests rather than additional phone tests.
- **Privacy races:** Four regression scenarios passed after fixes. They cover delayed History after Stop/removal/reconnection, History and Look while consent refresh is offline, and reconciliation of an offline peer removal.
- **Apple notifications:** The two APNs runs above used genuine Apple **development-environment** delivery to simulators. They did not use simulated notification injection. The test API and accounts were local. TestFlight uses production APNs, so these runs do not demonstrate TestFlight or production push delivery, and delivery is not guaranteed.
- **Purchases:** The synthetic review-unlock fixture is not an Apple purchase or restore. Local StoreKit configuration, where used, is also not an Apple sandbox purchase.
- **Not established by these runs:** Apple Sign In, carrier SMS delivery, genuine Apple sandbox purchases or restores, physical-device background location, physical-device two-phone operation, TestFlight behavior on a phone, and overall public-release readiness.

## Evidence

The [release E2E snapshot](README.md) contains result counts, screenshots, and retained result-bundle paths. The [local two-account guide](../../LOCAL-TWO-ACCOUNT-E2E.md) describes the paired controller and test-service boundaries. The [cloud CI follow-up](CI-FOLLOWUP.md) records the later test-helper changes and focused simulator results; current remote check status must be checked separately.

The paired role bundles are under `/tmp/trust-e2e-20261025/paired-handshake-49/paired-two-account/`, the completed handoff bundles under `/tmp/trust-e2e-20261025/handoff-complete-48/`, and the two APNs bundles under `/tmp/trust-e2e-20261025/real-apns-48-final/` and `/tmp/trust-e2e-20261025/real-apns-switch-recovery-49/`. These local paths may no longer exist if temporary files are cleaned up.
