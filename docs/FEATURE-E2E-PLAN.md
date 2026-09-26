# Real-feature test plan — 2026-09-26

This plan distinguishes UI and service behavior from physical-device behavior. Fixture UI tests use fictional demo data; the dedicated real-API test exercises disposable accounts against the local Development API.

## Local Development API

Run the API from the repository root in its own terminal. It uses the existing local Postgres configuration on port 5433. `Trust__SeedReviewCircle=false` prevents seeded members from consuming account seats used by the real-API test.

```sh
ASPNETCORE_ENVIRONMENT=Development ASPNETCORE_URLS=http://127.0.0.1:5088 Trust__SeedReviewCircle=false Auth__AllowDevelopmentSignIn=true dotnet run --no-launch-profile --project apps/trust-api/TrustApi.csproj
```

Before any simulator test, require a healthy local API:

```sh
curl --fail --silent --show-error http://127.0.0.1:5088/health/live >/dev/null || exit 2
```

The real-API UI test requires strict API mode and does not use demo fallback. Run one simulator at a time because the API and UI test lane use shared local resources. Require a nonzero test count and **zero skipped tests**; a skipped real-API test is not a pass.

## Real-API simulator lane

The current test is `TrustRealAPIFeatureTests.testRealOnboardingHandleRequestAcceptAndStopSharing`. It creates two disposable identities, completes handle and Development phone verification, searches an exact handle, sends a connection request, observes the reverse incoming request, accepts it, and verifies the new connection and Sealed/Off sharing behavior. The test deletes both accounts afterward. It uses `TRUST_BASE_URL=http://127.0.0.1:5088` and `TRUST_STRICT_API=1`; do not set `TRUST_DEMO`.

Use the Xcode installation that matches the simulator. The stable iPhone 17 Pro uses `/Applications/Xcode.app` and simulator `61DC2501-3A93-4123-A6D5-D3512AF07464`. The Duo uses `/Applications/Xcode-27.1-beta.app` and simulator `C6495E9A-B165-46E1-97F9-0B92ABBDDC0D`. Run one at a time.

After the API health check, run the focused case on the selected device:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/trust-ios/Trust.xcodeproj -scheme Trust -configuration Debug -destination 'platform=iOS Simulator,id=61DC2501-3A93-4123-A6D5-D3512AF07464' -derivedDataPath /tmp/trust-handle-request-derived-data -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO -only-testing:TrustUITests/TrustRealAPIFeatureTests/testRealOnboardingHandleRequestAcceptAndStopSharing test
```

For Duo, use `DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer` and destination `platform=iOS Simulator,id=C6495E9A-B165-46E1-97F9-0B92ABBDDC0D`. Keep the focused test selector and other arguments the same. To run the full suite instead, remove `-only-testing:TrustUITests/TrustRealAPIFeatureTests/testRealOnboardingHandleRequestAcceptAndStopSharing`.

## Current evidence

- API tests passed **125/125**.
- The full iOS scheme passed **37/37**, with no skips, on both the stable iPhone 17 Pro and the Duo simulator. The focused real-API case passed **1/1** on each simulator.
- Swift package tests passed **29/29**; website tests passed **3/3**; localization checks passed for **459 keys across 5 translated locales**.
- XCTest screenshots are in the ignored `test-results/sharing-2026-09-26` directory.

Simulator tests use Development identities and a local service. They do not verify physical Sign in with Apple, carrier SMS delivery, APNs token registration or notification delivery/display, background location behavior, or TestFlight behavior. No physical APNs delivery has been verified. A successful server publish attempt is not evidence that Apple delivered a notification.

## Physical TestFlight acceptance

When a reviewed build is available to internal testers, use two separate device/account identities. Record build, OS, devices, and test time. Verify real Sign in with Apple, SMS consent and code delivery, handle request acceptance and both-side Off defaults, sharing modes and revocation, background location, notification permission/token/banner/tap behavior, and StoreKit purchase/restore. Report delivery only when a notification was actually observed on device; delivery remains best effort.

See [STATUS.md](STATUS.md) for the dated project evidence and [DEPLOYMENT.md](DEPLOYMENT.md) for release procedures.
