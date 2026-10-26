# Release E2E evidence snapshot — 26 October 2026

This is a finite snapshot of the local checks reported for the Trust release work as of 26 October 2026. Build 48 is now archived and uploaded for internal TestFlight; build 49 is the current source-only candidate and is not archived or uploaded. This is not a release approval and does not mean every test target or external integration passed. Full simulator logs and `.xcresult` bundles remain on the test Mac under `/tmp/trust-e2e-20261025/`.

## Results recorded

| Area | Result | Scope and interpretation |
| --- | --- | --- |
| TestFlight build 48 | `VALID / APP_STORE_ELIGIBLE`; internal `IN_BETA_TESTING` | Checked at 2026-10-26 18:56:49 UTC. Delivery ID `d87680b0-aa68-44f3-b4be-66c3af8f58ff`; in `Trust Family Auto`. App Store draft remains manual with build 47 selected. Build 49 has not been archived or uploaded. |
| Trust API/PostgreSQL tests | 216/216 passed | Backend test suite with PostgreSQL. |
| Fictional-account HTTP scenarios | 41/41 passed | `apps/trust-api/scripts/e2e_two_account_http.py` against the isolated local API and a fresh runner-owned PostgreSQL database, using fictional Development accounts and OTP. It covers phone-consent/OTP ownership, invite and connection, privacy/sharing, locations/History/Look, Pause/Stop/remove, profile/input validation, and account deletion. Run log: `/tmp/trust-e2e-20261025/http-42-final/http.log`. This does not test carrier SMS or production accounts. |
| Broad standard build-48 UI attempt | 134 passed, 27 expected setup skips, 1 failure | The German Pause test failed because the native sheet did not scroll; no app callback occurred. A focused native-scroll rerun passed 1/0/0, but the later first-open assertion still needs current-source verification. Log/result: `/tmp/trust-e2e-20261025/standard-current-48.log`, `/tmp/trust-e2e-20261025/standard-current-48/standard-ui.xcresult`. |
| Build-49 Pause standard-language run | 1 passed / 0 skipped / 0 failed | Six shipped languages passed at standard text size using the concise visible title and full accessibility title. The 375 pt run is pending. Result: `pause-six-standard-49.xcresult`. |
| Frozen iOS build 48 standalone real-API cases | 23/23 passed individually, each 1 passed / 0 skipped / 0 failed | Fresh local Development API and PostgreSQL database per case, loopback proxy, synthetic Development review-unlock fixture enabled. The source-defined stories cover account setup and recovery, discovery and requests, sharing/Pause/Stop/remove, stale and offline reconciliation, Look/History access, profile edits and privacy restrictions. The serial Home A/B/A and paired two-device scenarios are tracked separately below. This is local API/UI evidence, not StoreKit evidence. |
| Privacy race regression cases | 4/4 passed after the fixes | They were observed red before the fix and green afterward: delayed History after Stop/remove/reconnect; History closed during offline consent refresh; Look closed during offline consent refresh; offline peer removal reconciled after relaunch/reconnect. Green case records are in `/tmp/trust-e2e-20261025/privacy-green-results.json`; per-case `.xcresult` bundles are under `/tmp/trust-e2e-20261025/privacy-green-{1..4}/`. |
| Real APNs notification and tap | 1 passed / 0 skipped / 0 failed | Against a fresh native PostgreSQL database on loopback port 5434. Two unique viewers generated two Look event IDs; actual system notifications were observed in foreground and background, and tapping opened the correct visible receipt. No `simctl push` was used. Result: `/tmp/trust-e2e-20261025/real-apns-48-final/RealPushAPNS.xcresult`. |
| APNs denied-permission recovery | Running; earlier attempt failed | Build-49 scenario checks that a denied installation is not registered as a recipient and that the notification-specific Settings route enables permission and refreshes status. The earlier test failed while navigating native Settings; it is not a pass. |
| Notifications UI at 375 pt, English and German XXL | 1 passed / 0 skipped / 0 failed | Current-source run; the complete notification action and status were visible and the German legal footer words were unfragmented. The status bar was clipped in the captured layout. Result: `/tmp/trust-e2e-20261025/you-narrow-footer-48.xcresult`. |
| Same-account Home A/B/A handoff | 3/3 phases passed, each 1/0/0 | Full completion evidence is under `handoff-complete-48/{case}/{case}.xcresult`. |
| Paired two-device lane | Not exercised; rerun pending | Retry stopped at Bob's DOB gate before the paired story began. Fixture `TRUST_AGE_TEST_ADULT=0` and a fresh-install rerun are pending; this is not a paired test result. |

Other checks recorded for this session: API web tests 3/3; localization validation 547 keys across five locales; TrustCore 103 passing tests. Fresh Python helper checks passed using `python3 -m unittest discover -s apps/trust-ios/Scripts/tests -p 'test_*.py' -v` (29/29) and `python3 -m unittest discover -s apps/trust-api/scripts/tests -p 'test_*.py' -v` (7/7). These describe separate runs, not a combined release gate.

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

The build-48 broad standard attempt failed only in the German Pause native-scroll interaction; no app callback occurred. Build-49 standard-size Pause coverage passed in six languages, with 375 pt verification pending. A/B/A is complete, with all three phases passing. The paired retry stopped at Bob's DOB gate before its story began; use the clean `ADULT=0` fixture and fresh install for a valid retry. Build-49 denied-permission APNs recovery is running; the earlier Settings-navigation failure is retained as provenance and is not a pass.

All API/UI cases used local Development services, fictional accounts and loopback endpoints. The enabled `StoreKit__AllowReviewUnlock` setting is a synthetic Development fixture, not an Apple purchase or entitlement verification. The HTTP fictional-account cases do not establish carrier SMS delivery.

This snapshot does **not** establish genuine Apple Sandbox in-app purchases or restores, Apple Sign In, carrier SMS, physical-device background location, TestFlight behavior, or production release readiness. The APNs result is limited to the simulator sandbox route exercised above. TestFlight in-app purchases use Apple’s IAP sandbox, while TestFlight push uses the production APNs environment; neither is evidenced by these local runs.

The full local-versus-Apple test boundary is documented in [SANDBOX.md](../../../apps/trust-ios/SANDBOX.md). The reusable orchestration guide is [LOCAL-TWO-ACCOUNT-E2E.md](../../LOCAL-TWO-ACCOUNT-E2E.md).
