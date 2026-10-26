# Trust test and sandbox boundaries

Trust has several test paths that use the word “sandbox.” Evidence from one path does not prove another.

## Local UI and API fixtures

The `Trust` and `Trust.LocalE2E` schemes use [`Resources/Trust.storekit`](Resources/Trust.storekit) for Xcode’s local StoreKit test configuration. That file exercises local purchase UI and transaction handling without contacting the App Store; it is not an Apple Sandbox transaction or an App Store signed transaction. [Apple: StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)

The release E2E runner starts a Development API and a loopback-only proxy. It uses Memory by default or creates a new disposable PostgreSQL database per API session when explicitly configured. These modes validate app/API behavior against local services, not a production backend. See [the local E2E guide](../../docs/LOCAL-TWO-ACCOUNT-E2E.md) for runner usage and current results.

Several UI tests use the app’s DEBUG age-assurance fixture. The runner can also enable a Development-only synthetic review entitlement fixture with `--allow-review-fixture`. Both are labeled in the run evidence; neither performs Apple age assurance or an App Store transaction.

Local Development OTP and reserved fictional numbers bypass carrier delivery. Twilio test credentials can exercise supported API validation and simulate responses, but they do not send messages to real numbers or trigger message status callbacks. [Twilio: Test credentials](https://www.twilio.com/docs/iam/test-credentials)

## Apple In-App Purchase Sandbox

Apple’s App Store Sandbox uses App Store Connect products and Sandbox Apple Accounts. Transactions are simulated by Apple and do not incur charges. TestFlight also uses Apple’s Sandbox environment for in-app purchases. These paths use Apple’s transaction infrastructure, unlike Xcode’s local `.storekit` file. [Apple: Testing In-App Purchases with Sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) · [Apple: Testing at all stages](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)

Build 49 is available through TestFlight. That availability alone is not evidence of a completed Sandbox purchase or restore. The `Trust-Sandbox` scheme has no local StoreKit configuration and is intended for an explicitly configured physical-device/API test. Keep credentials and real hostnames out of source control.

## Push notification evidence

Injected notifications can test app presentation and tap routing; they do not establish device-token registration or delivery through APNs. A successful APNs provider response also cannot guarantee that a person sees an alert. [Apple: APS Environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment) · [Apple: Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)

The simulator APNs suite has two genuine development-environment cases: foreground/background Look delivery and denied-permission Settings recovery. The release 49 recovery case passed **1/1, 0 skipped, 0 failed** on 26 October 2026. It used the native Settings route, verified the actual Allow Notifications switch value, waited for API registration acknowledgement, then checked the real APNs alert and matching Activity receipt. A native accessibility tap missed the switch thumb on this simulator; one bounded tap at its visible thumb completed the normal OS setting change. No permission-grant API or `simctl push` was used.

The separate foreground/background delivery case passed **1/1, 0 skipped, 0 failed**. Two fictional viewers generated distinct Look event IDs; the simulator received the corresponding foreground and background APNs alerts, and tapping each opened the matching Activity receipt. Current result bundles are recorded in [the local E2E guide](../../docs/LOCAL-TWO-ACCOUNT-E2E.md).

### Running the genuine APNs simulator lane

The `Trust.RealServices` scheme builds a separate UI-test target. The runner consumes an existing signed Debug simulator build, verifies its signature and embedded `aps-environment=development` entitlement/application identifier, then copies the products without re-signing them. Use a valid development signing setup on the host; ad-hoc signed app products are rejected.

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

## Evidence labels

- **Local StoreKit fixture:** Xcode `.storekit` configuration.
- **Development API fixture:** local API/proxy with synthetic OTP, age, or review-unlock controls.
- **Apple IAP Sandbox:** App Store Connect products and a Sandbox Apple Account, including a TestFlight purchase.
- **Injected notification:** local payload or app fixture without APNs delivery.
- **Development APNs:** provider request to APNs sandbox with a development-signed app token.
- **TestFlight push:** production APNs environment with the TestFlight app and its registered token.

Report only the path that actually ran; do not treat one as evidence for another.
