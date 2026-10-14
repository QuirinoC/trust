#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

fail() {
  printf 'check: %s\n' "$*" >&2
  exit 1
}

for command_name in dotnet node npm python3 initdb pg_ctl createdb pg_isready; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing $command_name; run scripts/cloud/setup.sh first."
done
[[ "$(node --version)" == v22.* ]] || fail "Node.js 22 is required; found $(node --version)."
dotnet_version="$(cd "$TRUST_CLOUD_REPO_ROOT" && dotnet --version)" || fail ".NET SDK could not be selected."
[[ "$dotnet_version" == 9.* ]] || fail "the selected .NET SDK must be version 9; found $dotnet_version."
[[ "$(initdb --version)" == *" 16."* ]] || fail "PostgreSQL 16 server tools are required."

PG_OWNER="$(id -un)"
if (( EUID == 0 )); then
  id postgres >/dev/null 2>&1 || fail "the postgres service account is missing; run setup.sh first."
  command -v runuser >/dev/null 2>&1 || fail "runuser is required to start an isolated PostgreSQL cluster as the postgres account."
  PG_OWNER=postgres
fi

PG_TMP="$(mktemp -d /tmp/trust-cloud-postgres.XXXXXX)"
PGDATA="$PG_TMP/data"
PG_LOG="$PG_TMP/postgres.log"
PG_START_ATTEMPTED=0

if (( EUID == 0 )); then
  chown postgres:postgres "$PG_TMP"
fi

run_pg() {
  if (( EUID == 0 )); then
    runuser -u "$PG_OWNER" -- "$@"
  else
    "$@"
  fi
}

cleanup() {
  local original_status=$?
  trap - EXIT
  if (( PG_START_ATTEMPTED )); then
    if run_pg pg_ctl -D "$PGDATA" -m immediate -w stop >/dev/null 2>&1; then
      rm -rf -- "$PG_TMP"
    else
      printf 'check: could not confirm the isolated PostgreSQL cluster stopped; preserving %s\n' "$PG_TMP" >&2
      (( original_status != 0 )) || original_status=1
    fi
  else
    rm -rf -- "$PG_TMP"
  fi
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

port="$(python3 - <<'PY'
import socket
import sys

for candidate in (5433, 5434, 5435):
    probe = socket.socket()
    try:
        probe.bind(("127.0.0.1", candidate))
    except OSError:
        continue
    else:
        print(candidate)
        sys.exit(0)
    finally:
        probe.close()

sys.exit("check: all supported isolated PostgreSQL ports (5433-5435) are busy.")
PY
)" || fail "could not select an available isolated PostgreSQL port."
mkdir -p "$PGDATA"
if (( EUID == 0 )); then
  chown postgres:postgres "$PGDATA"
fi
run_pg initdb -D "$PGDATA" --username=postgres --no-locale --encoding=UTF8 --auth-local=trust --auth-host=trust >/dev/null
PG_START_ATTEMPTED=1
run_pg pg_ctl -D "$PGDATA" -l "$PG_LOG" -o "-h 127.0.0.1 -p $port -c listen_addresses=127.0.0.1 -c unix_socket_directories=$PG_TMP" -w start
pg_isready -h 127.0.0.1 -p "$port" -U postgres -d postgres >/dev/null || fail "isolated PostgreSQL did not become ready."

database="trust_cloud_${$}_$(date +%s)"
run_pg createdb -h 127.0.0.1 -p "$port" -U postgres "$database"
test_connection="Host=127.0.0.1;Port=$port;Database=$database;Username=postgres;Password=;Pooling=false"

printf '\n== Trust API tests (isolated PostgreSQL on 127.0.0.1:%s / %s) ==\n' "$port" "$database"
(
  cd "$TRUST_CLOUD_REPO_ROOT/apps/trust-api"
  env -u 'ConnectionStrings:Postgres' -u DATABASE_URL \
    ConnectionStrings__Postgres="$test_connection" \
  dotnet test TrustApi.sln --no-restore --nologo
)

printf '\n== JoinTrust web tests ==\n'
npm --prefix "$TRUST_CLOUD_REPO_ROOT/apps/jointrust-web" test

printf '\n== Localization freshness and validation ==\n'
python3 "$TRUST_CLOUD_REPO_ROOT/apps/trust-ios/Scripts/validate_cloud_build.py"

printf '\nAll Linux checks passed.\n'
