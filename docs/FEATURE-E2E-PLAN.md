# Cross-account feature validation

## Active snapshot — 26 October 2026

This plan records user-visible outcomes and the evidence that supports them. “Local pass” means a loopback Development build and fictional accounts; it does not establish production or physical-device behavior. Current aggregate evidence and result paths are in the [26 October evidence snapshot](evidence/2026-10-26-release-e2e/README.md).

### Story matrix

| User outcome | XCTest / check | Current evidence |
| --- | --- | --- |
| A returning person can correct a phone number, recover after cooldown, relaunch, and keep the verified account. | `testRequiredPhoneCorrectionsCooldownEditRelaunchAndReturningVerifiedAccount` | Local pass in the standalone PostgreSQL-backed UI sweep. |
| Late phone-send or verify responses do not expose the wrong code or Home after an edit. | `testLatePhoneResponsesAfterEditPreserveRetryWithoutOpeningCodeOrHome` | Local pass with fault proxy and fictional Development OTP; direct-API CI names this as a setup skip. |
| A person can choose a Home status and the previous notice retires only after the new choice succeeds. | `testManualHomeChoicesReachServerAndRetirePreviousNotice` | Local pass with held fault-proxy responses; direct-API CI names this as a setup skip. |
| An Apple age-exchange failure keeps onboarding closed and the person can retry through the transaction link. | `testAdultAgeGateAppleExchangeFailureCanRetryThroughTransactionLinkIntoOnboarding` | Local retry-fixture pass; not Apple Sign In or Apple age assurance. |
| Account requests stay closed until app-transaction registration succeeds, then recover after relaunch. | `testAppTransactionRetryKeepsRequestsClosedThenRecoversAcrossRelaunch` | Local transaction fixture and fault-proxy pass; not StoreKit verification. |
| Age or privacy holds suppress account, location, and push requests. | `testAgeAndPrivacyBlocksSuppressAccountLocationAndPushRequests` | Local fault-proxy request-counter pass. |
| Two people can accept a request and explicitly grant reciprocal presence visibility. | `testPairedRequestAcceptAndPresenceGrantRole` | Latest retry stopped at Bob's DOB gate before the story started; rerun with `TRUST_AGE_TEST_ADULT=0` and a fresh install. This lane needs two roles and a shared pair fixture. |
| A privacy-held person can delete the account after relaunch. | `testPrivacyHeldAccountCanDeleteAfterRelaunch` | Local pass in the standalone PostgreSQL-backed UI sweep. |
| The first device can set Home and publish its server ownership marker. | `testSameAccountHomeHandoffOwnerSetsHome` | Passed 1/0/0 in completed Home A/B/A lane; see `handoff-complete-48/`. |
| A first-use second device detects remote Home and can take over with a distinct marker. | `testSameAccountHomeHandoffFirstUseDeviceTakesOver` | Passed 1/0/0 in completed Home A/B/A lane; see `handoff-complete-48/`. |
| The previous owner detects takeover, clears Home, and reconciles after reconnect. | `testSameAccountHomeHandoffPreviousOwnerDetectsTakeoverAndClear` | Passed 1/0/0 in completed Home A/B/A lane; see `handoff-complete-48/`. |
| Sharing reflects a peer’s acceptance after refresh. | `testSharingTabRefreshShowsPeerAcceptedAfterInitialFetch` | Local pass in the standalone PostgreSQL-backed UI sweep. |
| Always sharing makes History available and Stop removes that access. | `testAlwaysSharedLocationHistoryRendersAndClearsAfterStop` | Local pass with the synthetic Development review-unlock fixture; not a purchase or entitlement proof. |
| A new person can complete onboarding, send and accept a request, then stop sharing. | `testRealOnboardingHandleRequestAcceptAndStopSharing` | Local pass with fictional accounts and Development OTP. |
| A stale Circle response cannot restore sharing after Stop and relaunch. | `testStopRemainsOffAcrossStaleCircleResponseAndRelaunch` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| A share-mode change waits for success and a failure preserves Pause state. | `testShareModeSelectionWaitsForSuccessAndPreservesPausedStateOnFailure` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| A removed person stays absent through stale reads and relaunch. | `testRemoveStaysAbsentAfterStaleCircleResponseAndRelaunch` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| Stop All is atomic on failure and can be retried after relaunch. | `testStopAllFailureDoesNotPartiallyStopAndRetryPersistsAfterRelaunch` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| A delayed Look response from an old relationship is discarded. | `testDelayedLookResponseIsDiscardedAfterReplacementRelationship` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| Delayed History cannot reappear after Stop, removal, and reconnect. | `testDelayedHistoryFixtureCannotReappearAfterStopRemoveAndReconnect` | Local pass with synthetic review entitlement fixture; not paid History verification. |
| History remains closed when consent refresh is offline. | `testDelayedHistoryFixtureStaysClosedWhenConsentRefreshIsOffline` | Local pass with synthetic review entitlement fixture; not paid History verification. |
| Look remains closed when consent refresh is offline. | `testDelayedLookStaysClosedWhenConsentRefreshIsOffline` | Local fault-proxy pass. |
| An offline peer removal reconciles after relaunch and reconnect. | `testOfflinePeerRemovalReconcilesAfterRelaunchAndReconnect` | Local fault-proxy pass. |
| A failed lookup can be retried, while a confirmed request survives a later lookup failure. | `testAddPersonCanRetrySameQueryAndConfirmedSendSurvivesFailedLookup` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| A failed acceptance preserves the named request and leaves other requests usable. | `testFailedAcceptKeepsNamedRequestAndOtherRequestsAvailableForRetry` | Local fault-proxy pass; direct-API CI names this as a setup skip. |
| A person can inspect multi-day Pause choices and explicitly resume only that person. | `testPauseShowsMultiDayEndAndExplicitResumeRestoresOnlyThatPerson` | Local pass in the standalone PostgreSQL-backed UI sweep. |
| At maximum text size, each Pause duration and Cancel remain reachable, and Cancel preserves Sealed sharing. | `testPauseChoicesAndCancelRemainReachableAtAccessibilityText` | Broad build-48 UI failure: the German native sheet did not scroll; no app callback occurred. A focused native-scroll helper passed before the first-open assertion was added. Build-49 standard-size Pause labels passed in six languages; 375 pt and accessibility-size coverage remain pending. |
| A staged profile picture and explicit discovery choice survive relaunch. | `testProfilePictureIsStagedAndDiscoveryStaysExplicitAcrossRelaunch` | Local pass in the standalone PostgreSQL-backed UI sweep. |
| A Look notification in foreground or background opens the matching Activity receipt. | `testRealSandboxAPNsForegroundAndBackgroundLookRoute` | Local APNs simulator pass, 1 passed / 0 skipped / 0 failed; two viewers produced distinct Look IDs and both taps opened the correct visible receipt. No `simctl push`. See the APNs captures and result bundle in the evidence snapshot. |
| A denied notification permission does not register a recipient and can be recovered through native Settings. | `testRealSandboxAPNsNotificationSettingsRecovery` | Build-49 run is in progress using the notification-specific Settings API route. The earlier native Settings navigation attempt failed; it is not a pass. |
| Notifications settings and legal footer remain readable and reachable at narrow width and large text. | `testNotificationPreferencesRemainReachableWithoutPrompting` | Build-48 375 pt pass in English and German XXL; action, status, and footer were visible, but the status bar was clipped. The build-49 source adds direct notification Settings routing; no updated 375 pt capture yet. |

The frozen build-48 standalone run recorded 23/23 PostgreSQL-backed cases passing individually. The current Swift source inventory has 27 `TrustRealAPIFeatureTests` stories: the 23 standalone cases above plus the paired case and three serial Home handoff phases. All Home A/B/A phases passed 1/0/0. The paired retry stopped at Bob's DOB gate before the paired story; rerun with `ADULT=0` and a fresh install. The direct-API CI verifier accounts for the 27 source cases as 7 named passes, 17 named setup skips, and 3 serial handoff exclusions. A skip is not a pass. The broad build-48 standard attempt recorded 134 passes, 27 expected setup skips, and one German Pause failure because native sheet scrolling did not occur; no app callback was observed. Build-49 standard-size Pause coverage passed in six languages, with 375 pt coverage still pending.

### Verified aggregate results

- API/PostgreSQL suite: 216/216.
- TestFlight build 48: `VALID / APP_STORE_ELIGIBLE`, internal `IN_BETA_TESTING` in `Trust Family Auto`; build 49 source is not uploaded.
- Fictional-account HTTP scenarios: 41/41 against a fresh local PostgreSQL database; no carrier SMS.
- Standalone local real-API UI cases: 23/23 individually, one pass and no skips or failures per case; each used a fresh PostgreSQL database and loopback API/proxy. The synthetic Development review-unlock fixture is explicitly identified where used.
- Privacy regressions: 4/4 green after fixes: delayed History after Stop/remove/reconnect, History closed during offline consent refresh, Look closed during offline consent refresh, and offline peer removal after relaunch/reconnect.
- Real APNs simulator lane: 1/1, with actual foreground/background system notifications and tap routing to the correct Activity receipt.
- Build-49 Pause standard-language UI: 1/1 for six shipped languages; 375 pt rerun pending.
- TrustCore: 103; web: 3; localization validation: 547 keys. Fresh Python helper runs passed: 29/29 via `python3 -m unittest discover -s apps/trust-ios/Scripts/tests -p 'test_*.py' -v`, and 7/7 via `python3 -m unittest discover -s apps/trust-api/scripts/tests -p 'test_*.py' -v`.

### Open verification boundary

- Home A/B/A completed with all three phases passing 1/0/0. The paired retry stopped at Bob's DOB gate before the paired story ran; rerun with `TRUST_AGE_TEST_ADULT=0` and a fresh install.
- Finish build-49 Pause verification at 375 pt and the denied-permission APNs Settings-recovery scenario. The foreground/background delivery and tap-routing scenario is already a scoped simulator pass.
- History race behavior passed only with a synthetic Development entitlement fixture. Repeat with a legitimate Apple Sandbox verified Plus entitlement, including concurrent History screens, before treating paid History as validated.
- The APNs result demonstrates the simulator sandbox route only. TestFlight push uses production APNs. Physical background execution, terminated-state delivery, real TestFlight routing, token lifecycle, and delivery guarantees remain open; Notifications are best effort.
- Apple IAP purchase, restore, renewal, expiry, refund, Apple Sign In and age assurance, carrier SMS, account deletion on a release candidate, physical-device location, and production release readiness are not established by these local runs.
- Never point Development OTP, fixture entitlements, or this loopback harness at production. Follow [LOCAL-TWO-ACCOUNT-E2E.md](LOCAL-TWO-ACCOUNT-E2E.md) for safe orchestration and cleanup, and [SANDBOX.md](../apps/trust-ios/SANDBOX.md) for the local-versus-Apple boundary.

## Historical evidence — earlier milestones

The records below describe earlier runs. They provide traceability and must not override the active snapshot or be read as current acceptance.

### October 2026 design and two-account runs

- The October 10 presentation milestone updated six SwiftUI files and included 14 settled light/dark screenshots in `out/research/design-upgrades-2026-10-10`; compact Sharing rows were preserved. TrustCore passed 103 tests and localization covered 535 keys across five non-English languages. Targeted UI runs covered Sharing at 375 pt and German XXL, Add, appearance/language persistence, Invite/Activity/You, dark appearance, and map detents. Details: [verification.json](../out/research/design-upgrades-2026-10-10/verification.json). This is historical UI evidence.
- Required phone setup and correction retries passed focused Pro/Duo checks on 4 October. Details: [PHONE-SETUP-2026-10-04.md](PHONE-SETUP-2026-10-04.md).
- The 1 October Home A/B/A run completed with one Development + Memory API and synthetic locations. Its bundles were `/tmp/trust-home-handoff-A7.xcresult`, `/tmp/trust-home-handoff-B7.xcresult`, and `/tmp/trust-home-handoff-A8.xcresult`. The 25 October rerun completed only A set Home and B took over; disk exhaustion prevented the previous-owner phase. That incomplete attempt is superseded by the completed 26 October Home A/B/A lane in the active snapshot above.
- An earlier paired two-device acceptance passed on iPhone 17 Pro and iPhone Duo. A later build 48 attempt failed when an existing When-In-Use grant led to the Open Settings explainer. Native Settings automation was added; the current retry stopped at Bob's DOB gate before the paired story began, so a clean-fixture rerun is still pending.
- Historical CI runs include [37188923773](https://github.com/QuirinoC/trust/actions/runs/37188923773) and [36845697256](https://github.com/QuirinoC/trust/actions/runs/36845697256). Their branches, inventories, and counts differ from the current source. Run [36838051359](https://github.com/QuirinoC/trust/actions/runs/36838051359) executed zero iOS tests and is false-green evidence; it is not a pass.

### Older project and product records

Age-assurance product and legal questions remain in [AGE-ASSURANCE.md](AGE-ASSURANCE.md). App Review and launch acceptance remain in [REVIEW-READINESS.md](../apps/trust-ios/AppStore/REVIEW-READINESS.md). These records are separate from this finite current test snapshot.
