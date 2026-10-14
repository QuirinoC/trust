#!/usr/bin/env bash
# Shared paths for the local Linux setup/check scripts. Source this file.

TRUST_CLOUD_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TRUST_CLOUD_REPO_ROOT="$(cd -- "$TRUST_CLOUD_SCRIPT_DIR/../.." && pwd)"
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false

DOTNET_EXECUTABLE=""
if [[ -x /usr/bin/dotnet ]]; then
  DOTNET_EXECUTABLE="$(readlink -f /usr/bin/dotnet)"
elif command -v dotnet >/dev/null 2>&1; then
  DOTNET_EXECUTABLE="$(readlink -f "$(command -v dotnet)")"
fi
if [[ -n "$DOTNET_EXECUTABLE" ]]; then
  export DOTNET_ROOT="$(dirname -- "$DOTNET_EXECUTABLE")"
  export PATH="$DOTNET_ROOT:$PATH"
fi

if [[ -d /usr/lib/postgresql/16/bin ]]; then
  TRUST_CLOUD_PG_BINDIR="/usr/lib/postgresql/16/bin"
  export PATH="$TRUST_CLOUD_PG_BINDIR:$PATH"
fi
