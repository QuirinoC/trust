# Trust API

ASP.NET Core 9 API with Postgres persistence. Coordinates are stored as plaintext in Postgres. Authorization controls who can read them; the current implementation does not provide end-to-end encryption.

## Local development

Requires .NET 9 and Docker:

```bash
docker compose up postgres -d
dotnet test TrustApi.sln
dotnet run --launch-profile TrustApi
```

The API listens on `http://127.0.0.1:5088`. Local Postgres uses host port `5433`. The API applies checked-in migrations at startup. In-memory storage is restricted to Development and tests; its data does not survive a restart.

For the local two-account HTTP flow, keep the API running and run:

```bash
python3 scripts/e2e_two_account_http.py
```

This script writes test records and uses local Postgres for a few assertions. Never set its base URL to a production service.

## Location consent and history

- A new invite acceptance creates a connection with sharing Off on both sides. Joining does not grant location access.
- In Sealed (`untilTheyLook`), `POST /api/v1/looks` requires `confirmed: true`, returns one current location snapshot, and records a Look event. It does not open a persistent session or return a trail.
- Sealed sharing does not grant access to `GET /api/v1/people/{id}/history`; it returns `409 share_off`.
- Only Always grants ongoing live visibility and history. The viewer's own Circle entitlement sets the history window: 24 hours on free, 30 days on Plus.
- Always reads use `POST /api/v1/views`; they do not send a Look receipt. A sealed Look and Always View are distinct logged actions.
- Pause and Off stop reads. Location ingest rejects non-finite/out-of-range coordinates and batches larger than 100 points.

## Invite and phone behavior

`POST /api/v1/people/phone` always creates an ordinary invite. Its response does not reveal whether a submitted number is already verified by a Trust account. The recipient accepts through `POST /api/v1/invites/accept`; no SMS is sent by phone lookup.

Phone verification uses `POST /api/v1/me/phone/send` and `/verify`. Development may return a verification code when SMS is unconfigured. Production does not bypass verification. Postgres serializes hourly/daily SMS budget reservations and challenge attempts across API instances; per-IP route throttles add an extra request limit. The configured limits are eight sends per account per hour/day, eight per phone per hour, and 40 globally per day.

## Key endpoints

| Endpoint | Purpose |
| --- | --- |
| `POST /api/v1/session/apple` | Verify Sign in with Apple identity token |
| `POST /api/v1/session/google` | Verify Google identity token |
| `POST /api/v1/session/development` | Development-only session endpoint |
| `GET /api/v1/circle` | Circle members and currently permitted presence/location |
| `POST /api/v1/invites` and `/invites/accept` | Create and accept an invite |
| `POST /api/v1/looks` | Confirmed sealed snapshot and Look event |
| `POST /api/v1/views` | Always read and View event |
| `GET /api/v1/people/{id}/history` | Always-only historical trail |
| `POST /api/v1/storekit/transactions` | Verify a signed StoreKit transaction when enabled |
| `POST /api/v1/push/devices` | Register an APNs device token |
| `DELETE /api/v1/account` | Delete the signed-in account |

`/Privacy`, `/Terms`, and `/Support` redirect to the canonical pages on `https://jointrust.app`.

## Production operations

Production uses Render and Postgres. Keep `Auth__AllowDevelopmentSignIn`, `Trust__SeedReviewCircle`, and `StoreKit__AllowReviewUnlock` disabled outside App Review. Do not Blueprint Sync `render.yaml` over the existing service because the live instance has secret-backed settings. The APNs publisher is currently best-effort: there is no durable outbox/retry worker, so successful requests do not prove physical delivery.

See the repository's `docs/DEPLOYMENT.md` for release steps and `docs/STATUS.md` for verified state and blockers.
