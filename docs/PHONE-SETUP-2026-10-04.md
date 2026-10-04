# Required phone setup and correction retries — 4 October 2026

## Implemented behavior

Authenticated setup follows the existing required age/AppTransaction/privacy checks, then handle, then verified phone, then the main app. Internal source no longer bypasses phone verification. No Later action can enter the app from phone setup. A server-verified returning account does not request another text. Historical uploaded build 45 remains unchanged and does not contain this work.

The first number and two distinct normalized corrections can send immediately within an account's hourly window. Revisiting a number or changing its formatting does not create grace. Grace bypasses only account pacing. Account 8/hour and 8/24h, destination 8/hour and 45/90/180-second pacing, configured-sender global 40/24h, five wrong-code attempts, ten-minute codes, and phone-send IP 5/minute remain in effect. After three distinct destinations, account pacing reaches three minutes; this is not an added hard hourly lock.

`PhoneSmsPolicy` supplies the same policy to Memory and PostgreSQL. Reservation, replacement challenge, and consent event commit together. Migration 022 adds a nullable bounded destination array to account hourly budgets. Existing NULL rows receive no correction grace until their current hour expires. Accepted reservations consume budgets even if provider delivery fails. Same-account concurrent corrections accept exactly three; concurrent sends to one number accept one. A stale wrong-code attempt cannot mutate a replacement challenge. Account deletion and phone writes share lifecycle lock ordering.

Success/error responses provide authoritative retry deadlines, server time, remaining distinct allowance, and account window/send-count ordering. `resendAfterSeconds` keeps its earlier pacing-only semantics. Middleware 429 responses provide limiter-derived retry metadata. The client separates account timing from each destination, merges delayed responses without regressing newer budget state, and guards challenge presentation and verification routing with account, age, and operation identity. Codes are never persisted. Account-scoped retry state and unexpired challenge identity survive relaunch; deletion, consent revocation, and acknowledged privacy hold remove private local retry state.

The phone cards retain the existing palette, explicit disclosed Send action, Privacy/Terms links, and accessibility identifiers. Send/Resend use a neutral disabled fill and countdown, with an exact local retry time. Edit stays available; Verify is independent of send cooldown. English and all five shipped translations include retry copy. Sharing and discovery retain their existing defaults and consent controls.

## Completed local checks

All local execution used `/Applications/Xcode.app/Contents/Developer`. Local logs/result-bundle root: `/tmp/trust-phone-setup-20261004`. Selected screenshots and sanitized cross-device evidence are retained in [docs/evidence/phone-setup-2026-10-04](evidence/phone-setup-2026-10-04/README.md).

| Check | Result | Evidence |
| --- | --- | --- |
| Full API suite with isolated PostgreSQL 16 on 5434 | 216 passed, 0 failed, 0 skipped | `api-tests.log`, `api-tests.trx` |
| Swift package suite | 103 passed, 0 failed | `swift-test.log` |
| Checked-in Xcode TrustCoreTests target | 103 passed, 0 failed | `core-xcode-final.log`, `core-xcode-final.xcresult` |
| Simulator build for testing | Passed | `ios-build.log` |
| Localization validation | 535 keys across five locales | `localization.log` |
| Pro final correction/setup UI | 1 passed, 0 skipped | `phone-ui-pro-final.xcresult` |
| Duo final correction/setup UI | 1 passed, 0 skipped | `phone-ui-duo-final.xcresult` |
| Held send/verify response after Edit | 1 passed, 0 skipped | `phone-ui-late-response.xcresult` |
| Disclosed Send action UI | 1 passed, 0 skipped | `phone-consent.xcresult` |
| Existing complete handle/phone/request/accept/Stop flow plus earlier correction UI | 2 passed, 0 skipped | `phone-ui-pro.xcresult` |

API tests cover three immediate destinations, exact fourth-send retry, normalization/revisits, per-destination protection across accounts, concurrent corrections and resends, PostgreSQL store-instance persistence, legacy windows, destination minimum across rollover, stale wrong-code identity, provider failures, existing cap/expiry/privacy suites, and real HTTP 429/503 retry contracts. Swift tests cover required routing, countdown boundaries, serialization, clock skew, account/destination separation, reordered responses, and hourly history reset without losing destination waits.

The final Pro and Duo scenarios type three numbers, then explicitly type a fourth and confirm its disabled countdown. They confirm no main tabs or Later action before verification, Edit reachability, Verify usability during cooldown, unexpired code-screen restoration without an OTP, and retry persistence after editing/relaunch. These scenarios complete the last challenge through the local API before checking a returning verified launch. The separate held-response scenario taps Verify in the UI and proves an edited screen stays in setup when that verification response arrives late. The existing complete onboarding case also verifies through the UI.

A separate disposable synthetic identity was verified once through the Development API and launched on both simulators using the same development device identity. Both reached People directly. The account's SMS reservation count stayed one across both launches. Evidence: [sanitized reservation counts](evidence/phone-setup-2026-10-04/returning-devices-evidence.json), [Pro](evidence/phone-setup-2026-10-04/returning-verified-pro.png), and [Duo active display](evidence/phone-setup-2026-10-04/returning-verified-duo-active.png). Duo's default screenshot captured its inactive black display; the retained active-display screenshot uses supported `simctl io screenshot --display=1`.

## Visual review and limits

Astra execution and independent GPT-6.1 review found the accepted milestone satisfied. Retained final screenshots are indexed by the [Pro manifest](evidence/phone-setup-2026-10-04/pro/manifest.json) and [Duo manifest](evidence/phone-setup-2026-10-04/duo/manifest.json), each with four PNGs. Light code entry has blue usable Verify and gray Resend; dark entry/code states retain readable labels, the exact local retry time, and reachable Edit. Pro evidence includes the software keyboard. The scroll view keeps lower explanatory/legal content reachable when it exceeds the keyboard viewport.

No real carrier SMS, physical-device Apple authentication/AppTransaction, APNs, VoiceOver session, maximum Dynamic Type matrix, background clock-change behavior, or new TestFlight artifact was validated by these runs. The broad unrelated UI and web suites were not rerun locally. The standard and isolated CI lanes remain separate; the isolated lane now expects 15 cases, five passes and ten explicit setup-dependent skips when no paired/fault setup is configured. Skips are not passing evidence.

The disposable returning account and temporary token were deleted. Task-owned PostgreSQL 5434, Memory APIs 5089/5090, and the fault proxy were stopped. Duo returned to its initial shutdown state; Pro remains booted as it was initially. Logs, result bundles, screenshots, and the isolated PostgreSQL data directory remain in the evidence root.

No production data, deployed API, deployment credentials, review/release/age/privacy entitlement flags, or uploaded build changed. Release requires an independently authorized API deployment applying migration 022 and a new iOS build; the old server safely retains its older pacing but cannot provide the new correction allowance. Commit/push and final main CI are owned by the parent integration task.

## Pending physical-device validation

These steps remain unexecuted. Run them only after an authorized test environment has the matching API/migration 022 and a newly built iOS app containing this change. Historical build 45 cannot validate it. Use controlled accounts and destinations; carrier delivery testing requires an approved configured provider and phone numbers whose owners consent to those test texts.

1. On a fresh physical-device session, complete the normal Apple sign-in, AppTransaction, age, and privacy checks. Confirm failures keep access closed. Choose a valid handle and confirm phone setup opens immediately, with no Later action or main tabs; typing or keyboard submission alone must not request a text.
2. Tap the disclosed Send action for the first controlled number, then use Edit for two different controlled numbers. Confirm three distinct normalized destinations can send immediately when the other budgets permit. Formatting variants and returning to an earlier number must not create another allowance.
3. Enter a fourth distinct controlled destination. Confirm Send is gray and disabled, the countdown updates, and the exact device-local retry time agrees with the server deadline. Confirm resend for the challenged number is also disabled as required; Edit remains reachable. At the displayed deadline, a send should become available unless a newer server limit applies.
4. While Send/Resend is cooling down, enter the latest received code and tap Verify. Confirm valid verification reaches the main app; a wrong or expired code does not. Confirm sharing remains Off and phone discovery remains at its prior explicit consent setting.
5. Repeat setup with an unverified controlled account, then background and terminate the app during a cooldown. Relaunch and confirm the account retry deadline remains, an unexpired challenge can restore its code screen, and the code field does not contain a persisted OTP. Edit the number and relaunch again; confirm no grace reset. Check foreground/background timing and local timezone/clock-change behavior against a fresh server response.
6. Sign in to the already verified account on a second physical device, passing its ordinary Apple and required checks. Confirm it reaches the main app without another verification text. Confirm a different unverified account still requires phone setup and does not inherit the previous account's challenge or timers.
7. Inspect entry and code screens in system light/dark appearance, with the software keyboard open, larger and maximum Dynamic Type, and VoiceOver. Confirm number/code labels, Edit, Verify, countdown state, local retry time, disclosure, and Privacy/Terms remain understandable and reachable. Check compact screens and folded/open layouts where available.
8. Record actual Apple/AppTransaction and carrier-SMS outcomes separately from the synthetic local results. An API reservation or successful send response does not prove carrier delivery, and simulator success does not validate Apple's physical-device service. Keep the existing unresolved physical AppTransaction retry investigation separate; do not relax any gate to complete these checks.
