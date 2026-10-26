# Release E2E evidence snapshot — 26 October 2026

This is a finite snapshot of the local checks reported for the Trust release work as of 26 October 2026. It is not a release approval and does not mean every test target or external integration passed. Full simulator logs and `.xcresult` bundles remain on the test Mac under `/tmp/trust-e2e-20261025/`.

## Results recorded

| Area | Result | Scope and interpretation |
| --- | --- | --- |
| Trust API/PostgreSQL tests | 216/216 passed | Backend test suite with PostgreSQL. |
| Fictional-account HTTP scenarios | 41/41 passed | `apps/trust-api/scripts/e2e_two_account_http.py` against the isolated local API and a fresh runner-owned PostgreSQL database, using fictional Development accounts and OTP. It covers phone-consent/OTP ownership, invite and connection, privacy/sharing, locations/History/Look, Pause/Stop/remove, profile/input validation, and account deletion. Run log: `/tmp/trust-e2e-20261025/http-42-final/http.log`. This does not test carrier SMS or production accounts. |
| Latest broad standard UI attempt | 134 passed, 27 expected setup skips, 1 failure | The only failure was the Pause accessibility test’s scroll helper; it did not move the sheet content. A focused rerun using native Pause scroll-view swipes passed 1/0/0 at `/tmp/trust-e2e-20261025/pause-native-scroll-48.xcresult`. A further first-open visibility assertion was then added and awaits rebuild/retest. Broad rerun is pending. Log/result: `/tmp/trust-e2e-20261025/standard-current-48.log`, `/tmp/trust-e2e-20261025/standard-current-48/standard-ui.xcresult`. |
| Frozen iOS build 48 standalone real-API cases | 23/23 passed individually, each 1 passed / 0 skipped / 0 failed | Fresh local Development API and PostgreSQL database per case, loopback proxy, synthetic Development review-unlock fixture enabled. The source-defined stories cover account setup and recovery, discovery and requests, sharing/Pause/Stop/remove, stale and offline reconciliation, Look/History access, profile edits and privacy restrictions. The serial Home A/B/A and paired two-device scenarios are tracked separately below. This is local API/UI evidence, not StoreKit evidence. |
| Privacy race regression cases | 4/4 passed after the fixes | They were observed red before the fix and green afterward: delayed History after Stop/remove/reconnect; History closed during offline consent refresh; Look closed during offline consent refresh; offline peer removal reconciled after relaunch/reconnect. Green case records are in `/tmp/trust-e2e-20261025/privacy-green-results.json`; per-case `.xcresult` bundles are under `/tmp/trust-e2e-20261025/privacy-green-{1..4}/`. |
| Real APNs notification and tap | 1 passed / 0 skipped / 0 failed | Against a fresh native PostgreSQL database on loopback port 5434. Two unique viewers generated two Look event IDs; actual system notifications were observed in foreground and background, and tapping opened the correct visible receipt. No `simctl push` was used. Result: `/tmp/trust-e2e-20261025/real-apns-48-final/RealPushAPNS.xcresult`. |
| APNs denied-permission recovery | Pending | A separate scenario now checks that a denied installation is not registered as a recipient and that native Settings recovery refreshes permission status. No result bundle yet. |
| Notifications UI at 375 pt, English and German XXL | 1 passed / 0 skipped / 0 failed | Current-source run; the complete notification action and status were visible and the German legal footer words were unfragmented. The status bar was clipped in the captured layout. Result: `/tmp/trust-e2e-20261025/you-narrow-footer-48.xcresult`. |
| Same-account Home A/B/A handoff in the latest attempt | Incomplete: first 2 phases passed; third was not run | OwnerSetsHome and FirstUseDeviceTakesOver each passed 1/0/0 after native Settings → Privacy & Security → Location Services recovery. The previous-owner phase could not start because the test Mac ran out of disk while creating its log; this is not a test failure and does not complete A/B/A. Evidence: `/tmp/trust-e2e-20261025/handoff-system-privacy-48.log` and the two per-phase result bundles under `/tmp/trust-e2e-20261025/handoff-system-privacy-48/`. A full A/B/A rerun is pending after disk recovery. |
| Paired two-device lane | Pending current-source rerun | The earlier attempt failed after Alice reached the Always explainer with an existing When-In-Use authorization and explicit **Open Settings** action; Bob was interrupted. The helper now opens native Settings, selects Location → Always, verifies Always on return, then restores the original tab. The current-source result is pending. Failure evidence: `/tmp/trust-e2e-20261025/paired-48/paired-two-account/alice/xcodebuild.log` (failure at line 512; the Open Settings sheet is shown at lines 425–429), Alice’s `.xcresult` at `/tmp/trust-e2e-20261025/paired-48/paired-two-account/alice/paired-alice.xcresult`, and run summary `/tmp/trust-e2e-20261025/paired-48.log`. |
| APNs denied-permission Settings recovery | Pending | A separate UI story now covers denial, confirming the device is not registered as an APNs recipient while denied, native Settings recovery, and refreshed allowed status. It has not yet produced a result bundle. |

Other checks recorded for this session: API web tests 3/3; localization validation 546 keys; TrustCore 103 passing tests. Fresh Python helper checks passed using `python3 -m unittest discover -s apps/trust-ios/Scripts/tests -p 'test_*.py' -v` (29/29) and `python3 -m unittest discover -s apps/trust-api/scripts/tests -p 'test_*.py' -v` (7/7). These describe separate runs, not a combined release gate.

## Screenshots

These eight simulator captures are representative UI evidence. The people and places are fictional. The first two illustrate reachable pause durations and the Home/Away disclosure; the next two show the current-source Notifications UI at 375 pt in English and German XXL. The four APNs captures belong to the passing simulator sandbox lane and show foreground/background presentation and Activity routing; they do not establish TestFlight or physical-device delivery.

![Pause duration choices](screenshots/pause-options-build-48.png)

![Home and Away disclosure](screenshots/home-away-disclosure-build-48.png)

![You notifications at 375 points](screenshots/you-notifications-english-375.png)

![You notifications at German XXL text size](screenshots/you-notifications-german-xxxl.png)

![Foreground APNs banner](screenshots/apns-foreground-banner.png)

![Foreground notification tap opened Activity](screenshots/apns-foreground-tap-activity.png)

![Background APNs banner](screenshots/apns-background-banner.png)

![Background notification tap opened Activity](screenshots/apns-background-tap-activity.png)

## Source and run limits

The broad standard attempt above failed only in its Pause scroll helper; a focused native-scroll rerun passed, followed by a new first-open visibility assertion that still needs a focused rebuild. The latest A/B/A attempt passed its first two phases, then disk exhaustion prevented phase three from starting. Paired two-device and broad standard reruns remain pending. Earlier permission-helper failures are retained above for provenance; do not count them as current passes.

All API/UI cases used local Development services, fictional accounts and loopback endpoints. The enabled `StoreKit__AllowReviewUnlock` setting is a synthetic Development fixture, not an Apple purchase or entitlement verification. The HTTP fictional-account cases do not establish carrier SMS delivery.

This snapshot does **not** establish genuine Apple Sandbox in-app purchases or restores, Apple Sign In, carrier SMS, physical-device background location, TestFlight behavior, or production release readiness. The APNs result is limited to the simulator sandbox route exercised above. TestFlight in-app purchases use Apple’s IAP sandbox, while TestFlight push uses the production APNs environment; neither is evidenced by these local runs.

The full local-versus-Apple test boundary is documented in [SANDBOX.md](../../../apps/trust-ios/SANDBOX.md). The reusable orchestration guide is [LOCAL-TWO-ACCOUNT-E2E.md](../../LOCAL-TWO-ACCOUNT-E2E.md).
