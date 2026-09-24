# Resume after the macOS/Xcode upgrade

Checkpoint: 2026-09-24. The release candidate is commit `0b5975f` in [PR #1](https://github.com/QuirinoC/trust/pull/1). The existing build 19 archive has exported successfully; App Store Connect upload is pending account authentication. Duo toolchain/device validation is a separate follow-up and is not a prerequisite for uploading the current release unless the release scope changes.

## Current state

- CI API and web jobs pass; the iOS job is still running/pending.
- `/tmp/trust-release19-checkpoint.log` reports **26 core tests and 4 iPhone 17 Pro UI tests passed**, with `TEST SUCCEEDED`. This checkpoint includes the final race/history fixes.
- Archive build completed successfully for `com.collapsetechnologies.trust` version 1.0 build 19. A persistent copy is at `~/Library/Developer/Xcode/Archives/2026-09-24/Trust-1.0-19.xcarchive`; the exported IPA is `~/Library/Developer/Xcode/Archives/2026-09-24/Trust-1.0-19-export/Trust.ipa`. IPA export succeeded offline; root verified production APS environment, `beta-reports-active`, `get-task-allow=false`, the `applinks:jointrust.app` entitlement, and team `3S529795M9`. It has **not** been uploaded to App Store Connect. Upload authentication remains blocked until the correct ASC account is available.
- macOS was 26.3 at this checkpoint. The macOS 26.7 download (`softwareupdate` task 48721) was running with automatic restart disabled; completion is unverified. The user plans to install Xcode 27.1 beta from the downloaded XIP; installation is also unverified. Apple lists iPhone Duo development as requiring Xcode 27.1 beta and macOS 26.6 or later: [Duo developer info](https://developer.apple.com/iphone-duo/) · [Xcode system requirements](https://developer.apple.com/support/xcode/).
- Keep Xcode 26.6 installed alongside the beta. TestFlight remains pending for upload/authentication and Apple processing. Use the beta for Duo-specific checks after it is installed; do not describe those checks as complete in advance.
- Production API origin remains `https://trust-api-u0ft.onrender.com`; the custom API hostname's TLS is unresolved. Production and Sandbox App Store Server Notification URLs and the published Phone Number privacy label were updated in ASC, but no signed server-notification end-to-end result is recorded.

## After reboot

1. Confirm macOS is at least 26.6 and Xcode 27.1 beta launches. In Xcode → Settings → Accounts, sign in to the Apple account needed for App Store Connect upload. Do not put credentials or signing material in this repo.
2. Confirm both the persistent archive at `~/Library/Developer/Xcode/Archives/2026-09-24/Trust-1.0-19.xcarchive` and exported IPA at `~/Library/Developer/Xcode/Archives/2026-09-24/Trust-1.0-19-export/Trust.ipa` exist. Offline export is complete; after ASC authentication is restored, upload through Organizer/Transporter and wait for Apple processing before calling the TestFlight gate complete.
3. Only the main iPhone 17 Pro simulator remains installed; Phone B and five other unused simulator devices were removed (six total). The iPad People portrait visual check passed before its simulator was removed. For Duo validation, run the passing test suite on the supported Xcode beta/macOS setup, build the intended target, and perform the planned simulator/device checks. Record actual outcomes in [STATUS.md](STATUS.md); simulator evidence does not count as physical-device push evidence.
4. For the local two-account API flow, restart only the local Postgres service and API. The Docker Compose named volume preserves local fixture data; **do not** run `docker compose down -v` or point these commands at production.

   ```bash
   cd apps/trust-api
   docker compose up postgres -d
   dotnet run --launch-profile TrustApi
   ```

   In another terminal, confirm `curl -fsS http://127.0.0.1:5088/health/ready` returns `Healthy`, then run `python3 apps/trust-api/scripts/e2e_two_account_http.py` from the repository root. That script uses the local Development API and Postgres only; it creates temporary test accounts/relationships and deletes one throwaway account, while leaving the other test rows in the local database. Local Development has development sign-in and review unlock for testing, with no production Twilio or APNs configuration. Never point the script at the live API.

5. Recheck the live service using read-only health endpoints, then continue the TestFlight process in [DEPLOYMENT.md](DEPLOYMENT.md). Do not change production review flags or service secrets as part of resume work.

## Release evidence

See [STATUS.md](STATUS.md) for test results, current deployed API/site versions, known TLS and notification-delivery limits, and remaining release gates.

## Explicit pause before Mac update

The user explicitly paused work to update macOS. Do not resume implementation, installation, deployment, or restart automatically. Resume only when the user asks after the update.

- All product changes are pushed in PR #1. Release source: `0b5975f`; handoff checkpoint: `679a054`. The working tree was clean before this pause note.
- The final local simulator suite and signed IPA export passed. Upload failed only because Xcode could not find an App Store Connect account for team `3S529795M9`. The user was asked to sign in under Xcode Settings → Apple Accounts. Browser ASC sign-in is already valid but does not supply Xcode credentials.
- Current TestFlight build 19 has not been uploaded or assigned to testers. Resume with account verification, upload, Apple processing, and assignment to the existing **iPhone Juan** internal group. Physical testing remains the user's chosen follow-up from TestFlight.
- The beta download is `/Users/juanquirino/Downloads/Xcode_27.1_beta.xip`; download completeness and installation remain unverified. macOS 26.7 was downloading through `softwareupdate --download` with no automatic install/restart. The user will handle installation. Do not assume the Mac or Xcode was upgraded: verify on resume.
- Six unused simulator devices were deleted at the user's request. Only **iPhone 17 Pro**, UDID `61DC2501-3A93-4123-A6D5-D3512AF07464`, remains. Duo is not installed yet. Test its outer/inner layouts and pose transitions after the supported beta/runtime is installed.
- GitHub Actions reran after the handoff commit; the latest run at pause was `36057777163` (pending). The preceding run had API and web passing, with iOS still pending. Inspect current results rather than assuming they passed.
- TestFlight marketing/privacy URLs now use jointrust.app and its privacy page; beta review notes were corrected for phone verification, explicit invites, and no production review bypass. The ASC privacy disclosure includes Phone Number for app functionality, linked to identity, not tracking.
- Implementation/model policy remains Luna for fixes, Sol for review, Astra for orchestration/design/testing. Sol's final targeted review found no remaining blocker in refresh, revocation, history freshness, invitation, or paywall changes.
