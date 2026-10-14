#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'setup: %s\n' "$*" >&2
  exit 1
}

SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

# Reject unsupported hosts before asking for elevated privileges.
[[ -r /etc/os-release ]] || fail "cannot identify the operating system; expected Ubuntu 24.04."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || \
  fail "unsupported operating system (${PRETTY_NAME:-unknown}); this setup supports Ubuntu 24.04 only."

SYSTEM_ONLY=0
if [[ "${1:-}" == "--root" ]]; then
  shift
  SYSTEM_ONLY=1
elif (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || fail "root privileges are required; install sudo or run this script as root."
  sudo -n -- bash "$SCRIPT_PATH" --root "$@" || fail "non-interactive sudo is unavailable; run as root or configure sudo before setup."
  set --
fi
(( $# == 0 )) || fail "unexpected arguments: $*"
if (( SYSTEM_ONLY )); then
  (( EUID == 0 )) || fail "could not obtain root privileges."
fi

if (( EUID == 0 )); then
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg software-properties-common

  # Ubuntu 24.04 carries .NET 9 in its official dotnet/backports PPA.
  add-apt-repository -y ppa:dotnet/backports

  # Use NodeSource's official Node.js 22 DEB setup for Ubuntu Noble.
  node_setup="$(mktemp)"
  trap 'rm -f "$node_setup"' EXIT
  curl -fsSL https://deb.nodesource.com/setup_22.x -o "$node_setup"
  bash "$node_setup"

  apt-get install -y --no-install-recommends \
    dotnet-sdk-9.0 nodejs python3 postgresql-16 postgresql-client-16 libpq-dev
fi

(( SYSTEM_ONLY == 0 )) || exit 0

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/env.sh"
dotnet_version="$(cd "$TRUST_CLOUD_REPO_ROOT" && dotnet --version)" || fail ".NET SDK could not be selected."
[[ "$dotnet_version" == 9.* ]] || fail "the selected .NET SDK must be version 9; found $dotnet_version."
[[ "$(node --version)" == v22.* ]] || fail "Node.js 22 was not found after installation."
python3 --version
[[ "$(initdb --version)" == *" 16."* ]] || fail "PostgreSQL 16 server tools were not found after installation."

printf '\n== Restore API packages ==\n'
(cd "$TRUST_CLOUD_REPO_ROOT" && dotnet restore apps/trust-api/TrustApi.sln)

printf '\n== Install web packages ==\n'
npm --prefix "$TRUST_CLOUD_REPO_ROOT/apps/jointrust-web" ci

cat <<'EOF'
Linux setup is ready. Run scripts/cloud/check.sh from any working directory.
Native iOS/Xcode checks run on Xcode Cloud; this Ubuntu setup does not install Swift or Xcode.
EOF
