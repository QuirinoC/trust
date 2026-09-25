#!/usr/bin/env bash
# Capture Trust 1.0 App Store shots from the DEBUG fixture.
# Requires Xcode + iOS 26.5 runtime. Creates one temporary simulator at a time,
# deletes it afterward, and never uploads screenshots.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUNDLE="com.collapsetechnologies.trust"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
DERIVED="${ROOT}/build/DerivedDataM6"
APP="${DERIVED}/Build/Products/Debug-iphonesimulator/Trust.app"
# Capture People last so a fresh simulator has time to load Apple Maps tiles and
# finish first-boot notification banners before the home image is saved.
SHOTS=(look view share you map invite circle)

IPHONE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
IPAD_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
ACTIVE_SIM=""

cleanup_active() {
  if [[ -n "$ACTIVE_SIM" ]]; then
    xcrun simctl shutdown "$ACTIVE_SIM" >/dev/null 2>&1 || true
    xcrun simctl delete "$ACTIVE_SIM" >/dev/null 2>&1 || true
    ACTIVE_SIM=""
  fi
}
trap cleanup_active EXIT

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

capture_device() {
  local name="$1" type="$2" outdir="$3" udid
  udid="$(xcrun simctl create "$name" "$type" "$RUNTIME")"
  ACTIVE_SIM="$udid"
  echo "Capturing $name ($udid)" >&2
  prepare_sim "$udid"
  mkdir -p "$outdir"
  xcrun simctl install "$udid" "$APP"
  xcrun simctl privacy "$udid" grant location "$BUNDLE" || true
  xcrun simctl privacy "$udid" grant location-always "$BUNDLE" || true
  # First boot can show an Apple Intelligence banner while Maps downloads its
  # first tiles. Open the map once and let both settle before recording shots.
  SIMCTL_CHILD_TRUST_DEMO=1 SIMCTL_CHILD_TRUST_SCREENSHOT="circle" \
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" >/dev/null
  sleep 45
  for shot in "${SHOTS[@]}"; do
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    SIMCTL_CHILD_TRUST_DEMO=1 SIMCTL_CHILD_TRUST_SCREENSHOT="$shot" \
      xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" >/dev/null
    sleep 5
    xcrun simctl io "$udid" screenshot "${outdir}/${shot}.png"
    echo "  wrote ${outdir}/${shot}.png"
  done
  cleanup_active
}

cd "$ROOT"
if xcrun simctl list devices booted | grep -q '(Booted)'; then
  echo "Shut down the current simulator before capturing; this script uses one simulator at a time." >&2
  exit 1
fi
echo "Building Debug for Simulator…"
xcodebuild -project Trust.xcodeproj -scheme Trust \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED" \
  -quiet build

capture_device "Trust ASC 6.9" "$IPHONE_TYPE" "${ROOT}/AppStore/Screenshots/m6/iphone-69"
capture_device "Trust ASC 13" "$IPAD_TYPE" "${ROOT}/AppStore/Screenshots/m6/ipad-13"

echo "Done. Review AppStore/Screenshots/m6/ before uploading to ASC."
