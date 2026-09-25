# Trust for iOS

Trust is a native SwiftUI app for adults who choose to share location with each other. Its current visual system uses a porcelain canvas, white surfaces, navy text, blue actions, and teal positive states, with light and dark appearances. The main tabs are **People**, **Sharing**, **Activity**, and **You**. See [DESIGN.md](../../docs/DESIGN.md) for the current visual direction and [SCREENS.md](SCREENS.md) for the screen map.

A connection never starts sharing. An invitation recipient reviews the code and explicitly taps **Join** to accept; both directions remain Off until each person chooses a mode. A Look requires confirmation and returns one current-location snapshot. That share stays Sealed, and its location history is unavailable. Location history is available only while the person shares Always. Activity contains Look, View, and removal events, not a GPS trail.

## Build and run

The app targets iOS 18 and uses MapKit, Sign in with Apple, and StoreKit 2. Use Xcode 26 from this checkout:

```bash
cd apps/trust-ios
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Trust.xcodeproj -scheme Trust \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

For local API development, start the API and Postgres from `apps/trust-api`, then run the Debug app. The simulator uses the local API configuration. Release builds use the configured HTTPS API host; verify that host is healthy before distributing a build.

Core package tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path apps/trust-ios
```

## Current release state

`project.yml` currently sets version **1.0**, build **19**. Build 19 is the current local target; this README does not claim it has been archived, uploaded, processed, or installed from TestFlight. The canonical evidence and blockers are in [docs/STATUS.md](../../docs/STATUS.md); release steps are in [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md). The prior build 18 notes in [TESTFLIGHT-M4.md](TESTFLIGHT-M4.md) are historical.

The offline demo is opt-in in Debug (`See the app` or `TRUST_DEMO=1`). It uses fictional people and does not contact the service. A simulator result does not prove physical-device APNs delivery, background location behavior, or cellular battery use. APNs receipts are best effort; the app does not guarantee delivery.
