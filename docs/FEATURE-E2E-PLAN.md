# Real-feature test plan — 2026-09-25

This plan distinguishes screen checks from server behavior and physical delivery. The fixture UI tests use an offline fictional demo; they are useful for layout and interaction regressions, but they cannot prove that account creation, sharing, or notifications work with the service.

## 1. Local service contract

Run the Development API against local Postgres only. Use fresh per-run identities and delete test accounts at the end; never point destructive flows at production. Keep the existing API suite and two-account HTTP scenario as the fast gate, then add checks for:

- Account/session, handle and phone verification: new identity, duplicate handle and phone, wrong/expired code, consent gates in the app, and successful completion.
- Invite: no connection until code acceptance, both directions Off on acceptance, invalid/reused code, and no phone-number account enumeration.
- Sharing: Sealed Look returns one snapshot and a receipt; Always View shows only allowed live data; Pause blocks access and restores; Off immediately removes live access and stops location storage; Remove revokes the connection.
- Notifications: authenticated device registration/update/unregister, invalid token/environment handling, one best-effort publish for a confirmed Look, no push for View, and no claim of delivery from a successful API response.

Record request and response assertions, not just successful taps. Preserve the production guards that reject development sign-in and review unlock outside their intended environment.

## 2. Simulator with the real local API

`TrustRealAPIFeatureTests.testRealOnboardingInviteAndStopSharing` launches Debug with `TRUST_BASE_URL=http://127.0.0.1:5088` and `TRUST_STRICT_API=1`, without `TRUST_DEMO`. It creates two disposable identities, completes handle and phone consent/verification in the app using the Development OTP displayed by the app, joins the second identity's invite, checks both directions start Off, and verifies Sealed then Stop through the API response. The test deletes both accounts in teardown and skips when loopback health is unavailable so ordinary UI runs do not require the local service.

For the dedicated lane, make health a hard precondition before invoking Xcode:

```sh
curl --fail --silent --show-error http://127.0.0.1:5088/health/live >/dev/null || exit 2
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/trust-ios/Trust.xcodeproj -scheme Trust -configuration Debug -destination 'platform=iOS Simulator,id=C6495E9A-B165-46E1-97F9-0B92ABBDDC0D' -derivedDataPath /tmp/trust-avatar-derived-data -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO -only-testing:TrustUITests/TrustRealAPIFeatureTests/testRealOnboardingInviteAndStopSharing test
```

Evidence on 2026-09-25: the focused real API case passed on iPhone Duo, iOS 27.1, and the full `TrustUITests` suite passed **6/6** on that simulator with the local Development API healthy. The focused run showed Verify remained visible and hittable while the OTP keyboard was open. Logs and result bundles: `/tmp/trust-real-ui-focused-final2-20260925.log`, `/tmp/trust-real-ui-focused-final2-20260925.xcresult`, `/tmp/trust-real-ui-full-final-20260925.log`, and `/tmp/trust-real-ui-full-final-20260925.xcresult`.

This simulator evidence does not test physical Sign in with Apple, carrier SMS delivery, APNs delivery/display, background location behavior, or TestFlight. The local Development OTP was displayed in the app; no physical device or production service was used. Retain the fixture UI tests for rapid visual regression checks.

The Debug-only UI-test launch leaves the fresh account at the real Handle screen, while ordinary Development sign-in can still claim its test handle automatically. The Release sign-in path is unchanged. Simulator testing cannot prove Apple's actual Sign in with Apple sheet, carrier SMS delivery, APNs delivery, or background behavior on a physical iPhone.

## 3. Physical TestFlight acceptance

Once the newest reviewed build is processed and assigned to the internal group, use two separate device/account identities. Verify real Sign in with Apple, SMS consent and code delivery, invite and both-side Off defaults, each sharing mode, stopping/removing access, a Look while the recipient app is foreground/background, notification permission denial and recovery, banner/tap behavior, sign-out and deletion. Record build, OS, devices, account/test time, relevant API state, and whether a push was actually seen. Push remains best effort; a server publish attempt alone is not delivery proof.

### Notification checkpoint — 2026-09-25

- Two disposable Development identities connected through an invite. With one person sharing Sealed and a location uploaded, the other person's confirmed Look returned `200` and the subject's `GET /circle` contained the Look in `lookLog`. The identities were deleted after each run.
- Both existing simulators (iPhone Duo 27.1 and iPhone 17 Pro 26.5) launched the Debug app against loopback with strict API mode and separate development device IDs. The phone showed the connected peer, but retained older local app state; the Duo `simctl` screenshot was black. This run does **not** establish a clean two-screen Activity or notification UI pass.
- The Home notification publisher previously selected connected people with presence grants even while the subject's share was Off or Paused, and repeated Home posts retriggered the publisher. The API now checks the effective share before selecting each recipient and only publishes on a transition into Home. Home payloads also carry `home_arrival` instead of being mislabeled as `look`. Focused tests cover Off, Sealed, Paused, and repeat transitions. The API suite passed **113/113**; the corrected real-API Duo onboarding/stop-sharing UI case passed **1/1**.
- The local setup had no APNs credentials. A synthetic device registration and `simctl push` command succeeded, but the phone screenshot did not show a banner. Neither that command nor a successful Look response establishes Apple acceptance or delivery. Verify the permission prompt, APNs token registration, foreground/background notification presentation, tap navigation, and duplicate suppression with two physical TestFlight accounts. A Debug `TRUST_DEV_SESSION=1` startup returns before the ordinary notification-permission path; accepting an invite in the app still invokes that path.

## Exit criteria

The API suite and local two-account flow pass; the real-API simulator lane passes without production fallback; visual demo UI tests pass on a phone and Duo; and the physical matrix has explicit results or named blockers. A failure must identify the broken layer (UI, API contract, Apple delivery, or environment) before release readiness is claimed. See `docs/STATUS.md` for dated evidence and `docs/DEPLOYMENT.md` for release procedure.
