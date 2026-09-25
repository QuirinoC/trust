# Trust

Trust is a location sharing service for people who choose each other. It has three applications: an iOS client, an ASP.NET Core API with Postgres, and the public site at [jointrust.app](https://jointrust.app).

## Repository map

| Path | Purpose |
| --- | --- |
| `apps/trust-ios` | SwiftUI client, shared domain code, and iOS tests |
| `apps/trust-api` | ASP.NET Core 9 API, Postgres migrations, HTTP and service tests |
| `apps/jointrust-web` | Public landing page, privacy, terms, support, and SMS opt-in |
| `docs/DEPLOYMENT.md` | Safe API, website, and TestFlight release steps |
| `docs/STATUS.md` | Verified readiness, known gaps, and release blockers |

## Run the API locally

With Docker and .NET 9 installed:

```bash
cd apps/trust-api
docker compose up postgres -d
dotnet test TrustApi.sln
dotnet run --launch-profile TrustApi
```

The API listens on `http://127.0.0.1:5088`; Postgres is exposed on port `5433`. Development settings enable development sign-in and seed review accounts. Those flags are rejected at startup in other environments. For an HTTP two-account consent run after the API starts:

```bash
python3 apps/trust-api/scripts/e2e_two_account_http.py
```

The script exercises invite acceptance, Sealed and Always sharing, confirmed Looks, denied Sealed history, pause/stop, presence, deletion, and input validation against the local API and database.

## Build the iOS client

Use Xcode with the `Trust` scheme. If needed, run `xcodegen generate` from `apps/trust-ios`, then run the `Trust` scheme's tests on an available iOS Simulator. See [the iOS README](apps/trust-ios/README.md) and [release runbook](docs/DEPLOYMENT.md) for archive steps. App Store Connect upload requires the configured Apple signing account.

## Public site

The public pages and canonical legal URLs are served from Cloudflare at `https://jointrust.app`. The API's `/Privacy`, `/Terms`, and `/Support` routes permanently redirect there. Deployment and rollback notes are in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## Current release state

The API is deployed and its configured release origin `https://trust-api-u0ft.onrender.com` passed readiness. Production service readiness and the remaining TestFlight checks are tracked in [docs/STATUS.md](docs/STATUS.md). The custom hostname currently has unresolved TLS; use the Render service URL until DNS/TLS is independently verified.
