# Trust test and sandbox boundaries

Trust has several test paths that use the word “sandbox” for different systems. The evidence from one path does not prove the others.

## Local UI and API test fixtures

The `Trust` and `Trust.LocalE2E` Xcode schemes attach [`Resources/Trust.storekit`](Resources/Trust.storekit) to the Run action. That is Xcode’s local StoreKit test environment: StoreKit uses the products and transaction behavior in the file without contacting the App Store. It is useful for checking purchase UI and local transaction handling, but it is not an Apple Sandbox purchase or an App Store signed transaction. [Apple: StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)

The release E2E runner starts the API with the Development environment and loopback-only API/proxy endpoints. Its default in-memory mode is disposable. Its optional PostgreSQL mode creates a fresh named database for each API session. These fixtures validate app/API behavior against this local service; they do not validate a production backend.

Several UI tests opt into the app’s DEBUG age-assurance fixture with `TRUST_AGE_TEST_MODE`. The runner can separately opt into `StoreKit__AllowReviewUnlock` for the Development API. That synthetic review-unlock behavior is fixture evidence only; it does not perform a StoreKit purchase, Apple age assurance, or App Store transaction verification. The runner writes this distinction to each case’s `evidence-mode.txt` when the fixture is enabled.

The local API OTP capability bypasses SMS delivery for tests. It does not show that a real phone received a text. Twilio’s test credentials can exercise supported API request validation and simulate SMS API responses without connecting to real phone numbers; they do not deliver messages and do not trigger message status callbacks. [Twilio: Test credentials](https://www.twilio.com/docs/iam/test-credentials)

## Apple In-App Purchase Sandbox

Apple’s App Store Sandbox uses configured App Store Connect products and Sandbox Apple Accounts. Transactions are simulated by Apple and do not incur charges. TestFlight also uses Apple’s Sandbox environment for in-app purchases. These paths exercise real StoreKit-to-App-Store test infrastructure and Apple-signed transaction data, unlike Xcode’s local `.storekit` file. [Apple: Testing In-App Purchases with Sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) · [Apple: Testing at all stages](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox)

The `Trust-Sandbox` scheme is configured without a local StoreKit configuration, so its purchase requests use the App Store path. The scheme is intended for a physical device and a developer-configured API URL. Keep credentials and real hostnames out of source control.

## Push notification evidence

Injected notifications and APNs notifications are different tests. A notification supplied through Simulator tooling or a test fixture can check app presentation and tap routing, but it does not show that the API registered a device token, authenticated to APNs, or delivered a remote notification.

The APNs development environment is Apple’s sandbox APNs endpoint. A development-signed app uses the `aps-environment` entitlement value `development`; prerelease distribution builds such as TestFlight use `production`. Apple also documents APNs delivery as best-effort, so a successful provider response does not guarantee that a person sees an alert. [Apple: APS Environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment) · [Apple: Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)

Some supported iOS Simulator and host configurations can register with the APNs development environment, while virtualized macOS hosts may fail to produce a token. Validate the actual host and runtime used by a push test. A genuine APNs test needs a registered token, a development entitlement, API provider credentials, and a successful notification route through APNs to the app. [Apple Developer Forums: Simulator APNs registration on a virtualized Mac](https://developer.apple.com/forums/thread/796868)

### Genuine APNs simulator lane

The Trust.RealServices scheme builds a separate UI-test target for genuine APNs checks. Build its Debug simulator products with an entitlement plist outside the checkout. The example below copies the repository plist and changes only aps-environment in the temporary copy:

```sh
cd apps/trust-ios
mkdir -p /tmp/trust-real-apns
python3 - <<'PY'
import plistlib
from pathlib import Path

source = Path("Trust.entitlements")
temporary = Path("/tmp/trust-real-apns/simulator-development.entitlements")
entitlements = plistlib.loads(source.read_bytes())
entitlements["aps-environment"] = "development"
temporary.write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML))
PY

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project Trust.xcodeproj \
  -scheme Trust.RealServices \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/trust-real-apns/DerivedData \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_ENTITLEMENTS=/tmp/trust-real-apns/simulator-development.entitlements
```

Select a fresh, booted iOS Simulator and pass its UDID to the runner. A fresh simulator matters because the test explicitly enables alerts and requires the system permission to be undecided at the start. Use an isolated local PostgreSQL instance with a role allowed to create and drop databases. For the native loopback database used on this host:

```sh
PRODUCTS=/tmp/trust-real-apns/DerivedData/Build/Products
XCTESTRUN="$(find "$PRODUCTS" -maxdepth 1 -name '*.xctestrun' -print -quit)"
python3 Scripts/run_real_push_e2e.py \
  --products "$PRODUCTS" \
  --xctestrun "$XCTESTRUN" \
  --device '<fresh-booted-simulator-UDID>' \
  --postgres-connection 'Host=127.0.0.1;Port=5434;Database=postgres;Username=trust;Password=trust' \
  --postgres-direct \
  --output /tmp/trust-real-apns-result
```

The runner requires the pre-signed Debug-iphonesimulator/Trust.app, verifies its code signature and its embedded development APNs entitlement/application identifier, then copies the app without re-signing it. It reads the five APNs provider settings from the configured Render service in memory and passes them only to the local API process; they are excluded from the proxy and Xcode test environment and are not written to logs or the xctestrun file. The runner uses a new generated PostgreSQL database, a local Development API, fictional +1-555-555-01xx accounts, and Development OTP with Twilio cleared. The test explicitly enables alerts, obtains an acknowledged sandbox device registration, sends two Looks from distinct fictional viewers, observes separate real APNs foreground/background notifications, taps each notification, and verifies each receipt appears in Activity. It does not use simctl push.

The --postgres-direct option uses native psql against a loopback Postgres server and drops only the database name generated by the runner. The port, role, and password above describe this host's isolated Postgres setup; use a separately isolated local database with equivalent permissions on other hosts. Never point the runner at a shared or production database.

This lane verifies one simulator/runtime, the local Development API, and APNs development delivery to the test simulator. It does not prove Apple Sign In, carrier SMS delivery, Apple In-App Purchase or restore, production APNs, TestFlight push, physical-device behavior, or production release readiness. A passed notification route is not a delivery guarantee.

TestFlight push uses the production APNs environment even though TestFlight in-app purchases use Apple’s Sandbox. Therefore a successful development APNs test does not establish TestFlight push delivery. Physical-device/TestFlight acceptance remains a separate release check.

## Evidence labels

When reporting a test result, name the path that actually ran:

- **Local StoreKit fixture:** Xcode `.storekit` configuration.
- **Development API fixture:** local API/proxy with synthetic OTP, age, or review-unlock controls.
- **Apple IAP Sandbox:** App Store Connect products and a Sandbox Apple Account, including a TestFlight purchase.
- **Injected notification:** local payload or app test fixture, without APNs delivery.
- **Development APNs:** provider request to APNs sandbox with a development-signed app token.
- **TestFlight push:** production APNs environment with the TestFlight app and its registered token.

Do not label one of these paths as proof of another.
