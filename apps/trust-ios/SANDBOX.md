# Trust test and sandbox boundaries

Trust has several test paths that use the word “sandbox.” Evidence from one path does not prove another.

## Local UI and API fixtures

The `Trust` and `Trust.LocalE2E` schemes use [`Resources/Trust.storekit`](Resources/Trust.storekit) for Xcode’s local StoreKit test configuration. That file exercises local purchase UI and transaction handling without contacting the App Store; it is not an Apple Sandbox transaction or an App Store signed transaction. [Apple: StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)

The release E2E runner starts a Development API and a loopback-only proxy. It uses Memory by default or creates a new disposable PostgreSQL database per API session when explicitly configured. These modes validate app/API behavior against local services, not a production backend. See [the local E2E guide](../../docs/LOCAL-TWO-ACCOUNT-E2E.md) for runner usage and current results.

Some historical UI tests retain the app’s DEBUG age-assurance fixture. Current RealServices setup goes directly to People for a fully seeded verified account and explicitly rejects the paused age/app-transaction screens; do not restore the old required birth-date entry from historical build-49 tests. The runner can also enable a Development-only synthetic review entitlement fixture with `--allow-review-fixture`. Both are labeled in the run evidence; neither performs Apple age assurance or an App Store transaction.

Local Development OTP and reserved fictional numbers bypass carrier delivery. Twilio test credentials can exercise supported API validation and simulate responses, but they do not send messages to real numbers or trigger message status callbacks. [Twilio: Test credentials](https://www.twilio.com/docs/iam/test-credentials)

## Apple In-App Purchase Sandbox

Apple’s App Store Sandbox uses App Store Connect products and Sandbox Apple Accounts. Transactions are simulated by Apple and do not incur charges. TestFlight also uses Apple’s Sandbox environment for in-app purchases. These paths use Apple’s transaction infrastructure, unlike Xcode’s local `.storekit` file. [Apple: Testing In-App Purchases with Sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) · [Apple: Testing at all stages](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)

Trust Staging build 51 is available through internal TestFlight. Availability alone is not evidence of a completed Sandbox purchase or restore. The `Trust-Sandbox` scheme has no local StoreKit configuration and is intended for an explicitly configured physical-device/API test. Keep credentials and real hostnames out of source control.

## Push notification evidence

Injected notifications can test app presentation and tap routing; they do not establish device-token registration or delivery through APNs. A successful APNs provider response also cannot guarantee that a person sees an alert. [Apple: APS Environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment) · [Apple: Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)

The simulator APNs suite has two genuine development-environment cases: foreground/background Look delivery and denied-permission Settings recovery. The release 49 recovery case passed **1/1, 0 skipped, 0 failed** on 26 October 2026. It used the native Settings route, verified the actual Allow Notifications switch value, waited for API registration acknowledgement, then checked the real APNs alert and matching Activity receipt. A native accessibility tap missed the switch thumb on this simulator; one bounded tap at its visible thumb completed the normal OS setting change. No permission-grant API or `simctl push` was used.

The separate foreground/background delivery case passed **1/1, 0 skipped, 0 failed**. Two fictional viewers generated distinct Look event IDs; the simulator received the corresponding foreground and background APNs alerts, and tapping each opened the matching Activity receipt. Current result bundles are recorded in [the local E2E guide](../../docs/LOCAL-TWO-ACCOUNT-E2E.md).

### Running the genuine APNs simulator lane

The `Trust.RealServices` scheme builds a separate UI-test target. The runner consumes an existing Debug simulator build, verifies its code signature and effective embedded `aps-environment=development` entitlement/application identifier against the expected team, then copies the products without re-signing them. Xcode can use its normal local simulator signature; the runner does not require a distribution certificate or reject every ad-hoc outer signature. Actual registration and Apple sandbox delivery must still pass. Keep these temporary simulator entitlements outside the checkout; Release signing and entitlements remain unchanged.

Create a temporary entitlement plist outside the checkout, changing only the APNs environment in a copy of the source entitlements, then build the dedicated scheme:

```sh
cd apps/trust-ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PREBUILT_DIR="$(mktemp -d /tmp/trust-real-apns-build.XXXXXX)"
python3 - "$PREBUILT_DIR/simulator-development.entitlements" <<'PY'
import plistlib
import sys
from pathlib import Path

entitlements = plistlib.loads(Path("Trust.entitlements").read_bytes())
entitlements["aps-environment"] = "development"
Path(sys.argv[1]).write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML))
PY

xcodebuild build-for-testing \
  -project Trust.xcodeproj \
  -scheme Trust.RealServices \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PREBUILT_DIR/DerivedData" \
  CODE_SIGN_ENTITLEMENTS="$PREBUILT_DIR/simulator-development.entitlements" \
  CODE_SIGNING_ALLOWED=YES
```

Choose a fresh, booted simulator for each case that needs an undecided notification permission. Set `TRUST_E2E_POSTGRES_CONNECTION` to an isolated local PostgreSQL server on a loopback address; the role must be allowed to create and drop databases. The runner uses `--postgres-direct` to create and drop only its own generated database.

```sh
PRODUCTS="$PREBUILT_DIR/DerivedData/Build/Products"
XCTESTRUN="$(find "$PRODUCTS" -maxdepth 1 -type f -name '*.xctestrun' -print -quit)"
python3 Scripts/run_real_push_e2e.py \
  --products "$PRODUCTS" \
  --xctestrun "$XCTESTRUN" \
  --device '<fresh-booted-simulator-UDID>' \
  --postgres-connection "$TRUST_E2E_POSTGRES_CONNECTION" \
  --postgres-direct
```

The default case is `testRealSandboxAPNsForegroundAndBackgroundLookRoute`. To run Settings recovery, pass `--case testRealSandboxAPNsNotificationSettingsRecovery` and use a fresh simulator. The runner reads the five APNs provider settings from the connected Render service into memory and passes them only to the local API process. They are excluded from the proxy and Xcode test environment and are not written into logs or the `.xctestrun`. The API uses Development OTP with Twilio cleared, fictional accounts, and the loopback proxy at `127.0.0.1:5089` forwarding to the Development API at `127.0.0.1:5090`.

The runner fails closed if those service ports are occupied. Its output directory is unique under `/tmp` by default; `--output <new-or-empty-directory>` can select another evidence location. Do not reuse or delete another run’s products as the input: set `PREBUILT_DIR` to the folder containing the exact build’s `Build/Products` and `.xctestrun`.

These results establish development APNs delivery to the tested simulator/runtime only. TestFlight uses the production APNs environment even though its in-app purchases use Apple’s Sandbox. The simulator tests do not prove TestFlight or production push delivery, Apple Sign In, carrier SMS, Apple IAP purchase/restore, physical-device behavior, or release readiness. Push delivery remains best-effort.

## Current-source simulator follow-up

On 2 November 2026, current-source genuine foreground/background APNs delivery and notification-denial Settings recovery each passed 1/0/0. A separate native CoreLocation case passed 1/0/0 after simulated movement reached the local API while Trust remained backgrounded. It requests native While Using/Always permission and selects Sealed explicitly; it does not use a direct fixture upload as evidence. Run it with the same signed-product runner and `--case testSimulatorBackgroundLocationReachesAPIWithoutForegrounding`. Its evidence is location-specific and does not claim APNs delivery.

The opt-in `SimulatorAppleServiceProbeTests` require `TRUST_SIMULATOR_APPLE_PROBE=1` and an explicitly installed Staging app (`TRUST_PROBE_APP_BUNDLE_IDENTIFIER=com.collapsetechnologies.trust.staging`). The test spec must point `UITargetAppPath` at that Staging build and contain no local StoreKit configuration. They observe service/account boundaries and cancellation only; they must not be counted as completed Apple authentication or purchases. The Staging catalog displayed actual monthly/annual plans; Apple sign-in required an Apple Account, and Restore reached a credential form. No credential was entered, purchase confirmed or positive entitlement claimed. The final fresh-device probes passed their observation/cancel checks. An earlier failed credential modal survived app relaunch, so isolated fresh simulator state matters.

The current service launcher does not require the paused age screen or manual handle choice for a seeded verified account. Do not restore the historical build-49 age/DOB steps. All follow-up devices and the temporary database/credential were removed. Detailed device/account mapping, failed attempts and durable evidence locations are in [the customer-experience report](../../docs/evidence/2026-11-01-customer-experience/DEVICE-ACCOUNT-REPORT.md).

## Evidence labels

- **Local StoreKit fixture:** Xcode `.storekit` configuration.
- **Development API fixture:** local API/proxy with synthetic OTP, age, or review-unlock controls.
- **Apple IAP Sandbox:** App Store Connect products and a Sandbox Apple Account, including a TestFlight purchase.
- **Injected notification:** local payload or app fixture without APNs delivery.
- **Development APNs:** provider request to APNs sandbox with a development-signed app token.
- **TestFlight push:** production APNs environment with the TestFlight app and its registered token.

Report only the path that actually ran; do not treat one as evidence for another.
