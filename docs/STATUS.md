# Trust readiness status — 2026-09-25

This page separates local verification from live-service observations. PR #4 merged the Together Lines website update to `main` at `50715c0`; API, iOS, and web CI passed. Cloudflare version `0b61e45a-0391-42e6-9e44-d3a473921469` is live, and the public landing, legal, SMS, invite, and Apple association routes returned 200. Xcode Organizer validated the optimized Trust 1.0 (24) archive for Collapse Technologies LLC and uploaded it for internal TestFlight on 2026-09-25. Apple processing and internal-group assignment are unverified because App Store Connect is signed out in Chrome. Build 23 was validated but not uploaded; build 22 is the previous uploaded build. Render deployment `dep-dar1gnm0tbcc73cingv0` remains the last verified API deploy and `/health/ready` returned `200 Healthy`. Physical TestFlight, screenshot/privacy ASC work, and the age-policy decision remain open.

## Current redesign (after build 21)

- Implemented a new Together Lines sign-in treatment and open-stroke app icon, compact Sharing rows, a clearer People empty state, and a simpler You screen with a My location detail. Home/Away/Hidden moved to Sharing. After the two build 22 feedback items, the You legal links are fixed at the bottom and the profile picker has a centered preview and horizontal carousel. Names are exposed to accessibility only. Full local Duo UI tests passed **4/4** and Swift core tests **26/26** after these changes; final closed-Duo screen was inspected. Far-end carousel behavior and open-Duo visual sign-off remain.
- Added optional profile pictures with **26 illustrated choices**, Photos/Camera selection, staged Save/Remove, authenticated image retrieval, metadata-stripped server storage, and automatic cleanup on replacement/account deletion. API preset allowlist changes are deployed with PR #2; local API tests passed **107/107** with local Postgres. The website now uses the same Together Lines direction as the app.
- Corrected a privacy gap: Home/Away was previously returned to connected people while their location mode was Off. The API now hides status for Off and active Pause; Sealed and Always can show it. The Sharing and privacy copy now describe this behavior.
- Refreshed the landing, Terms, Privacy, Support, SMS, 404, and invite presentation to match the app. The web suite passed **3/3**, and PR #4 API/iOS/web CI passed. Cloudflare deployed version `0b61e45a-0391-42e6-9e44-d3a473921469`; `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` all returned 200. Legal copy and Twilio paths were preserved.
- Reduced duplicate startup/foreground circle refreshes and added redacted circle-request diagnostics. The user's reported live Offline/Retry symptom is **not yet proven resolved**; the release build and authenticated production flow need retesting.
- Build 24 passed Xcode Organizer validation and was uploaded for internal TestFlight on 2026-09-25. Apple processing and tester-group assignment await App Store Connect sign-in. The 14 M6 screenshots still reflect build 22 and need recapture after Duo and carousel visual sign-off; they are not uploaded. Privacy answers remain pending in ASC, and the age policy remains unresolved.

## Current redesign handoff

### Done or verified

- Reviewed the earlier iOS screens against the design guide; the later redesign and profile-picture feature are described above.
- CircleView now keeps one NavigationStack while switching between compact and wide layouts. The map remains left and People/detail routes use the right pane when the available width is at least 760 points.
- MapScreen chooses its split from its actual width, so the Map route retains a useful canvas inside the Duo detail pane.
- After the feedback work, local Duo UI passed **4/4**, Swift core **26/26**, and API **107/107** with local Postgres. Independent code review found no issue. The final screen was seen in closed Duo; far-edge carousel and open-Duo appearance are not yet signed off.
- Sol's final read-only review found no actionable issue in the adaptive navigation, Map layout, or sharing confirmation flow.
- Build 24 is the latest uploaded build; Xcode Organizer shows validation succeeded and Uploaded to Apple. ASC processing and internal group assignment are unverified while Chrome is signed out. Build 23's archive passed Organizer validation but was not uploaded. Version 1.0's current ASC selection is unverified; nothing has been submitted for review.
- Build 20 remains processed and **Ready to Submit** in the IJ iPhone Juan group, with no install or device-session evidence recorded.
- The build 21 TestFlight “What to Test” note is saved in ASC for one internal tester. It covers phone sign-in, invite consent defaults, sharing modes, Look receipts, People/Map/You, sandbox Plus purchase/restore, and best-effort push observation; no test results are recorded.
- The simulator inventory contains only the retained Duo and iPhone 17 Pro devices; eleven unused generated simulators were removed. A manual Device Hub check confirmed Maya Chen remains selected after closing and reopening Duo: closed mode shows the compact person detail, while open mode restores map-left/person-detail-right. Duo is currently open and booted; open-Duo and far-edge carousel visual sign-off remain pending. The iPhone 17 Pro is shut down.

### Still in progress

- Build 24 is uploaded, but ASC processing/group assignment are unverified while Chrome is signed out. Verify internal TestFlight availability and install it on a physical device for the remaining checks.

### App Store and website update

- Build 24 was uploaded to Apple for internal TestFlight; processing and internal group assignment are unverified. The last inspected App Store version 1.0 selected build 21. Stable public Xcode 27 (27A266a) is required for App Review. Screenshots and privacy answers remain pending in ASC; the browser is signed out, and nothing has been submitted. See [App Store review readiness](../apps/trust-ios/AppStore/REVIEW-READINESS.md).
- Cloudflare version `0b61e45a-0391-42e6-9e44-d3a473921469` is deployed. `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned 200; the Together Lines site matches the current app direction.
## Verified

- API: `dotnet test apps/trust-api/TrustApi.sln --no-restore` passed **103 tests** locally, including HTTP tests, two-account Postgres tests, sealed-history denial, phone lookup invite behavior, StoreKit disabled behavior, and concurrent Postgres SMS budget/OTP-attempt operations. Local Postgres runs on port `5433`.
- iOS: after the TestFlight feedback changes, local Duo UI passed 4/4 and Swift core 26/26. PR #2 fixed Remove by moving it into the parent alert; all API/iOS/web checks passed, including hosted iOS 26 core tests and 4 UI tests. Manual Device Hub testing confirmed selected-person retention across close/open. Duo is currently open and booted; open-Duo and far-edge carousel visual sign-off remain pending. iPhone 17 Pro is shut down.
- Build 20 history: `/tmp/Trust-1.0-20.xcarchive` and `/tmp/Trust-1.0-20-export/Trust.ipa` were signed by team `3S529795M9`. Organizer upload UUID `96ca1915-82ec-4b9c-8974-53fe93400d57` completed processing; build 20 is Ready to Submit and assigned to IJ iPhone Juan. Build 19 remains available in that group but predates the Duo changes.
- Uploaded build 21 history: its Xcode Release archive passed Organizer validation and upload; ASC marked it Ready to Submit and automatically assigned it to the existing internal iPhone Juan group. Version 1.0 currently selects build 21. This is the older pre-redesign TestFlight binary; nothing has been submitted.
- Local simulator/API flow: against the local Development API, a bad phone OTP was rejected and the correct OTP completed verification. The explicit invite was accepted with both sharing directions Off; a Sealed Look returned a snapshot, and Always/View returned live location. This is local simulator evidence, not a production or physical-device test.
- PR #1 merged to `main` at `8ebdc0f`; API, iOS, and web checks passed on the PR. PR #2 merged at `31db6cc`; all API/iOS/web checks passed, including hosted iOS 26 core and 4 UI tests. Render deployment `dep-dar1gnm0tbcc73cingv0` was verified live for PR #2’s merge commit. `/health/ready` returned `200 Healthy`; an unauthenticated avatar PUT returned `401`. The API preset allowlist changes are deployed.
- Health check and release origin: `https://trust-api-u0ft.onrender.com/health/ready` returned healthy on 2026-09-24 after that deployment, and this is the configured release API origin while the custom hostname is unresolved. The custom hostname `trust.collapsetechnologies.com` is verified with Render and its CNAME now uses DNS-only mode, but HTTPS/TLS health is still failing/pending certificate provisioning; do not configure or describe it as healthy yet. The updated local two-account HTTP script passed **32 checks** against local API/Postgres on 2026-09-24.
- App Store Server Notifications V2: App Store Connect Production and Sandbox notification URLs were read-only verified as `https://trust-api-u0ft.onrender.com/api/v1/storekit/notifications` on 2026-09-24. This confirms the configured destination only; no signed notification delivery and processing result is recorded.
- Website: Cloudflare version `0b61e45a-0391-42e6-9e44-d3a473921469` is live. `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` each returned 200. The landing and supporting pages use the app's Together Lines identity; live desktop and mobile layouts were inspected.
- Backend safeguards now reject development sign-in config outside Development; disable StoreKit transaction verification when its feature flag is off; atomically reserve SMS budgets and advance/complete OTP challenges in Postgres; throttle phone send/verify routes; validate coordinates and cap location batches at 100; and return invites for both known and unknown phone numbers.

## Release blockers and limits

- **API custom hostname TLS:** Render verified the custom domain on 2026-09-24 and its CNAME is in DNS-only mode, but HTTPS for trust.collapsetechnologies.com still fails or awaits certificate provisioning. The configured release origin, https://trust-api-u0ft.onrender.com, passes readiness and remains the origin for this build; keep the custom hostname out of client configuration until TLS is independently healthy.
- **APNs delivery proof:** the live API has APNs configured, but notifications are best effort. There is no durable outbox or retry worker, and no physical-device delivery/display test is recorded. A successful API request is not delivery confirmation.
- **TestFlight:** build 24 was validated and uploaded for internal testing; ASC processing and internal assignment are unverified while signed out. Physical iPhone verification remains outstanding.
- **Duo/release validation:** local UI suite passed 4/4 after the feedback work and independent review found no issue. The closed-Duo screen was reviewed; far-edge carousel and open-Duo visual sign-off remain. PR #2’s Remove-alert fix passed API/iOS/web checks, including hosted iOS 26 core and 4 UI tests.
- **StoreKit production flow:** server verification is enabled, but a current end-to-end sandbox purchase/restore and server-notification test on the release build is not recorded.
- **Runtime maintenance:** the API targets .NET 9. Microsoft lists support ending 2026-11-10; plan a supported-runtime upgrade ahead of that date rather than expanding this hardening pass.

## Contract the clients should follow

- A confirmed `POST /api/v1/looks` from a connected viewer whose subject is Sealed returns exactly one current-location snapshot and records the Look event. It does not expose the sealed history endpoint.
- `GET /api/v1/people/{id}/history` requires the subject to share Always with that viewer. Sealed history returns `409 share_off`; the viewer's Plus entitlement controls the history window only after Always access is granted.
- Phone entry never reveals whether the number belongs to a Trust account and never connects accounts automatically. Both cases return an ordinary invite code; the recipient joins through the existing invite acceptance flow.
- Accepting an invite creates a connection. It does not enable sharing; each person chooses sharing for that peer.

## Next evidence to collect

Open Duo and far-end carousel visual sign-off remain. Build 24 was validated and uploaded through Xcode Organizer; verify processing and internal-group assignment in ASC, then install it on the physical iPhone. Screenshots/privacy answers and the age-policy decision remain pending. Stable public Xcode 27 is required for App Review. Local tests do not establish physical push delivery or StoreKit sandbox purchase/restore.
