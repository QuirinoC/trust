#!/usr/bin/env bash
# Build the real-services UI test bundle once, then capture current App Store source screens.
# This prepares raw screenshots only; it never uploads or submits them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED="${DERIVED:-/private/tmp/trust-appstore-screenshots-derived-data}"
OUTPUT_ROOT="${OUTPUT_ROOT:-${ROOT}/AppStore/Screenshots/2026-11-02/raw}"
CAPTURE_DEVICES="${TRUST_CAPTURE_DEVICES:-all}"
CAPTURE_LOG="${CAPTURE_LOG:-${OUTPUT_ROOT}/simulator-ids.tsv}"
RUN_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
LOG_ROOT="${TRUST_CAPTURE_LOG_ROOT:-${OUTPUT_ROOT}/capture-logs/${RUN_STAMP}}"
HINGE_HELPER="${TRUST_HINGE_HELPER:-}"
PAYWALL_OUTPUT="${TRUST_PAYWALL_REVIEW_OUTPUT:-${LOG_ROOT}/iap-review-current-paywall.png}"
DRIVER="${ROOT}/AppStore/capture-native-screenshots.py"
APP="${DERIVED}/Build/Products/Debug-iphonesimulator/Trust.app"

case "$CAPTURE_DEVICES" in
  all|iphone|iphone-69|iphone-65|iphone-medium|ipad|ipad-13|duo|duo-outer|duo-inner) ;;
  *)
    echo "TRUST_CAPTURE_DEVICES must be all, iphone, iphone-69, iphone-65, iphone-medium, ipad, ipad-13, duo, duo-outer, or duo-inner." >&2
    exit 1
    ;;
esac

if [[ "$CAPTURE_DEVICES" == "duo" || "$CAPTURE_DEVICES" == "duo-outer" || "$CAPTURE_DEVICES" == "duo-inner" ]] && [[ -z "$HINGE_HELPER" ]]; then
  echo "Duo capture requires an explicit TRUST_HINGE_HELPER path." >&2
  exit 1
fi
if [[ -n "$HINGE_HELPER" ]]; then
  if [[ ! -f "$HINGE_HELPER" ]]; then
    echo "TRUST_HINGE_HELPER does not point to a local file." >&2
    exit 1
  fi
  HELPER_SHA="$(shasum -a 256 "$HINGE_HELPER" | awk '{print $1}')"
  if [[ "$HELPER_SHA" != "1997bd4788c561596ad8616e1bf0a1cc71b10685d7807ff88a37b126d1124a84" ]]; then
    echo "The supplied hinge helper does not match the pinned SHA-256." >&2
    exit 1
  fi
fi

if [[ "${TRUST_ALLOW_PARALLEL_SIMULATORS:-0}" != "1" ]] && xcrun simctl list devices booted | grep -q '(Booted)'; then
  echo "Shut down the current simulator before capture, or set TRUST_ALLOW_PARALLEL_SIMULATORS=1 to preserve it." >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT" "$LOG_ROOT" "$(dirname "$CAPTURE_LOG")"
if [[ -e "${LOG_ROOT}/capture-ledger.json" ]]; then
  echo "Capture log root already has a ledger: ${LOG_ROOT}. Choose a fresh TRUST_CAPTURE_LOG_ROOT." >&2
  exit 1
fi

echo "Building Trust.RealServices for Simulator (build-for-testing)…"
if ! xcodebuild -project "${ROOT}/Trust.xcodeproj" -scheme Trust.RealServices \
    -destination "generic/platform=iOS Simulator" \
    -configuration Debug CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    -derivedDataPath "$DERIVED" build-for-testing >"${LOG_ROOT}/build-for-testing.log" 2>&1; then
  echo "Trust.RealServices build-for-testing failed; see ${LOG_ROOT}/build-for-testing.log." >&2
  tail -n 80 "${LOG_ROOT}/build-for-testing.log" >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "The normal Trust simulator app was not produced at ${APP}." >&2
  exit 1
fi
if [[ "${TRUST_CAPTURE_DEVICES:-all}" == "all" && -z "$HINGE_HELPER" ]]; then
  echo "Capturing the four classic formats. Duo formats are included only when the pinned helper is explicitly supplied." >&2
fi

ARGS=(
  --repo-root "$REPO_ROOT"
  --derived-data "$DERIVED"
  --output-root "$OUTPUT_ROOT"
  --log-root "$LOG_ROOT"
  --capture-log "$CAPTURE_LOG"
  --devices "$CAPTURE_DEVICES"
  --paywall-output "$PAYWALL_OUTPUT"
)
if [[ -n "$HINGE_HELPER" ]]; then
  ARGS+=(--hinge-helper "$HINGE_HELPER")
fi
if [[ "${TRUST_CAPTURE_PHONE:-0}" == "1" ]]; then
  ARGS+=(--capture-phone)
fi
if [[ "${TRUST_CAPTURE_PAYWALL_REVIEW:-0}" == "1" ]]; then
  ARGS+=(--capture-paywall-review)
fi
if [[ -n "${TRUST_XCTESTRUN:-}" ]]; then
  ARGS+=(--xctestrun "$TRUST_XCTESTRUN")
fi
python3 "$DRIVER" "${ARGS[@]}"
echo "Capture complete. Review ${OUTPUT_ROOT}/ and ${LOG_ROOT}/ before composing or uploading assets."
