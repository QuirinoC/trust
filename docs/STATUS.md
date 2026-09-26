# Trust project status

Updated 2026-09-26. This is a dated evidence snapshot, not a live dashboard.

## Current changes and evidence

- The handle-based connection-request milestone is implemented in the working tree on branch `codex/simple-handle-requests`; changes are uncommitted. A person can find an exact handle and send a request. The recipient accepts or declines; both sharing directions start Off. Request lists show incoming and sent requests. Verified phone ownership is required for connection discovery and requests. The phone-verification skip is limited to the internal preview build and does not satisfy the server's connection eligibility check.
- API tests passed **125/125**. Swift package tests passed **29/29**. Full Duo and stable iPhone 17 Pro simulator runs each passed **37/37** with no skips. The real-API onboarding, request, acceptance with both shares Off, and stop-sharing test passed again after review fixes on Duo and final layout polish on iPhone. Website tests passed **3/3**. Localization checks passed for **459 keys across 5 translated locales**.
- Luna implemented the change; Sol reviewed and rechecked account isolation, phone-verification return navigation, and legacy-invite request cleanup. Astra reviewed the five light-mode Duo screenshots without blocking issues. Five screenshots per device are saved locally under the ignored `test-results/sharing-2026-09-26/` directory. Dark appearance has interaction-test coverage; large text and dark-mode screenshots were not separately reviewed.
- iOS source is build **29**; its stable-Xcode archive is in progress and it has not been uploaded. Build **28** uploaded successfully but contains superseded UX and is not the intended replacement; its internal-group assignment is unverified.
- The deployed website invite page is still the old invite landing page, Worker version `8772afd0-4824-4a24-b148-99d14bbeea99`. Today's local privacy update has not been deployed. The last verified Render API deployment is `dep-dar1gnm0tbcc73cingv0`, commit `31db6cc` from 2026-09-25; current local API changes are not deployed.
- App Store Connect is signed out in Chrome and the Mac is locked, so the current processing and tester-group state is unverified. Release actions remain with the root task owner.
- No end-to-end push notification delivery has been verified. Do not claim that notifications are working; the app cannot guarantee delivery.
- English is the source locale, with Simplified Chinese, Japanese, German, French, and Brazilian Portuguese overlays. Website legal pages and App Store metadata remain English.

The current release design and screen intent live in [DESIGN.md](DESIGN.md). Broader production gaps remain tracked in [PRODUCTION-READINESS.md](PRODUCTION-READINESS.md). See [FEATURE-E2E-PLAN.md](FEATURE-E2E-PLAN.md) for test evidence and [DEPLOYMENT.md](DEPLOYMENT.md) for release procedures.
