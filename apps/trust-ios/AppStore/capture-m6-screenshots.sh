#!/usr/bin/env bash
# Capture Trust Circle 1.0 App Store shots from the DEBUG fixture.
# Requires Xcode + iOS 26.5 runtime. Does not upload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUNDLE="com.collapsetechnologies.trust"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
DERIVED="${ROOT}/build/DerivedDataM6"
APP="${DERIVED}/Build/Products/Debug-iphonesimulator/Trust.app"
SHOTS=(circle look view share you map invite)

IPHONE_NAME="Trust ASC 6.9"
IPAD_NAME="Trust ASC 13"
IPHONE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
IPAD_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"

find_or_create() {
  local name="$1" type="$2"
  local udid
  udid="$(xcrun simctl list devices available | grep -F "$name (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' | head -n 1)"
  if [[ -z "${udid}" ]]; then
    udid="$(xcrun simctl create "$name" "$type" "$RUNTIME")"
    echo "Created $name ($udid)" >&2
  fi
  printf '%s' "$udid"
}

prepare_sim() {
  local udid="$1"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --operatorName "" \
    --batteryState charged \
    --batteryLevel 100 || true
  xcrun simctl location "$udid" set 37.7749,-122.4194 || true
}

dismiss_location_alert() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Simulator" to activate
delay 0.3
tell application "System Events"
  if not (exists process "Simulator") then return
  tell process "Simulator"
    set btnNames to {"Allow While Using the App", "Allow Once", "Allow"}
    repeat with w in windows
      repeat with n in btnNames
        if exists button n of w then
          click button n of w
          return
        end if
      end repeat
    end repeat
  end tell
end tell
APPLESCRIPT
}

capture_device() {
  local udid="$1" outdir="$2"
  mkdir -p "$outdir"
  xcrun simctl install "$udid" "$APP"
  xcrun simctl privacy "$udid" grant location "$BUNDLE" || true
  xcrun simctl privacy "$udid" grant location-always "$BUNDLE" || true
  for shot in "${SHOTS[@]}"; do
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    SIMCTL_CHILD_TRUST_DEMO=1 SIMCTL_CHILD_TRUST_SCREENSHOT="$shot" \
      xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" >/dev/null
    sleep 6
    dismiss_location_alert
    xcrun simctl io "$udid" screenshot "${outdir}/${shot}.png"
    echo "  wrote ${outdir}/${shot}.png"
  done
}

cd "$ROOT"
echo "Building Debug for Simulator…"
xcodebuild -project Trust.xcodeproj -scheme Trust \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED" \
  build

IPHONE_UDID="$(find_or_create "$IPHONE_NAME" "$IPHONE_TYPE")"
IPAD_UDID="$(find_or_create "$IPAD_NAME" "$IPAD_TYPE")"

echo "iPhone 6.9  $IPHONE_UDID"
prepare_sim "$IPHONE_UDID"
capture_device "$IPHONE_UDID" "${ROOT}/AppStore/Screenshots/m6/iphone-69"

echo "iPad 13     $IPAD_UDID"
prepare_sim "$IPAD_UDID"
capture_device "$IPAD_UDID" "${ROOT}/AppStore/Screenshots/m6/ipad-13"

echo "Done. Review AppStore/Screenshots/m6/ before uploading to ASC."
