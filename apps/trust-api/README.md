# Trust API

ASP.NET Core 9 + Postgres backend for Trust. Location is held in escrow. Coordinates are never returned for sealed people. A Look requires an explicit confirm, writes an append-only receipt, and unlocks live location plus a short trail.

This is the product backend. The iOS app talks to it. **Postgres is the real store.** In-memory is an explicit Development/test fallback (`Trust:Store=memory`) and is refused outside Development. History in memory dies with the process.

## Location history

Postgres holds users, share modes, **time-series location points**, and look receipts. Coordinates are appended on ingest; Look reads the stored window. An API restart does not clear trails when Postgres is the store.

Until end-to-end encryption exists, location points are **plaintext on the server**. We do not sell location. Other clients still do not receive live GPS for sealed people until a confirmed Look, which then releases live plus the window below.

### Where it lives

| Table | What it stores |
| --- | --- |
| `trust.accounts` | Sign-in identity, unique handle, optional display name, optional verified E.164 phone, Circle entitlement |
| `trust.phone_challenges` | Hashed SMS OTP in flight (not the plaintext code) |
| `trust.invites` | Pending/consumed invite codes |
| `trust.memberships` | Circle pairs |
| `trust.shares` | Until they look / Always / For a while (timer) |
| `trust.location_points` | Append-only GPS time series (`account_id`, `recorded_at`, lat/long) |
| `trust.look_events` | Append-only Look receipts (who, when, window hours — **no coordinates**) |
| `trust.active_looks` | Open Look sessions |
| `trust.presence` | Last active / battery / got-home / check-in — **no coordinates** |

Schema is applied on boot from `Infrastructure/Postgres/Migrations/*.sql`.

### Retention

| Data | Free | Circle |
| --- | --- | --- |
| Look trail released to a viewer | Last **2 hours** | Optional extend to last **24 hours** |
| GPS kept on the server | **26 hours**, then pruned (covers the 24h grant; not a 30-day dossier) | Same GPS window |
| Look log (receipts, not GPS) | **30 days** | **365 days** + export |
| Empty circle / revoke last person | GPS for that account is deleted | Same |
| Account delete | Location, looks, memberships removed | Same |

Ingest (`POST /api/v1/location`) appends one point or a `points` array while the account is sharing (at least one trusted person). Older-than-retention rows are pruned on ingest. Background Always on iOS keeps appending while sharing is on.

### Honesty

Plaintext GPS on our database is a current limitation, not a feature. Do not treat escrow as client-only sealed storage. The product promise is authorization (sealed until Look) and short retention, not encryption-at-rest yet.

## Map

Maps are **not** rendered here. The iOS client uses **MapKit** (see `apps/trust-ios/README.md`). This API only stores and authorizes location.

## Run locally

Postgres on host port **5433** (avoids colliding with other stacks):

```bash
cd apps/trust-api
docker compose up postgres -d
dotnet run --launch-profile TrustApi
```

API: [http://127.0.0.1:5088](http://127.0.0.1:5088)  
Health: `/health/live`, `/health/ready`  
Privacy / ToS: `/Privacy`, `/Terms`

Or run API + Postgres together:

```bash
docker compose up --build
```

On first boot the API applies `Infrastructure/Postgres/Migrations/*.sql`.

If Docker is down, Development can use a **process-local** store. Location history will not survive API restart:

```bash
Trust__Store=memory ASPNETCORE_ENVIRONMENT=Development \
  Auth__SigningKey='development-signing-key-32bytes-min!!' \
  Auth__AllowDevelopmentSignIn=true Trust__SeedReviewCircle=true \
  StoreKit__AllowReviewUnlock=true \
  dotnet run --urls http://0.0.0.0:5088
```

Durable product data needs Postgres via compose.

Development (`ASPNETCORE_ENVIRONMENT=Development`):

- `Auth:AllowDevelopmentSignIn=true` — `POST /api/v1/session/google` without an ID token, and `POST /api/v1/session/development`, issue a real session JWT.
- `Trust:SeedReviewCircle=true` — first sign-in seeds Alex (sealed), Jordan (Always), Riley (For a while) as **database accounts** with escrowed trails. Not an iOS mock.
- `StoreKit:AllowReviewUnlock=true` — Settings → Unlock Circle for review grants Circle on the server.

**App Review only:** Production `apps/render.yaml` defaults both to `false`. While Apple is reviewing, set Render env `Trust__SeedReviewCircle=true` and `StoreKit__AllowReviewUnlock=true`, then set them back to `false` after approval so real users are not seeded demo people.

Production must set `Auth:SigningKey` (32+ bytes). Do not ship the Development key.

## Auth

| Endpoint | What it does |
| --- | --- |
| `POST /api/v1/session/apple` | Verifies Apple `identityToken` against Apple JWKS (8s HTTP timeout, 12s overall), audience `com.collapsetechnologies.trust`. Apple directory timeouts return **503** instead of hanging. |
| `POST /api/v1/session/google` | Verifies Google `idToken` when `Google:ClientIds` is set. If not, Development may mint a session. |
| `POST /api/v1/session/development` | Development only. |

All other `/api/v1/*` routes require `Authorization: Bearer <session JWT>`.

## Product API

- `GET /api/v1/circle` — members, live coords only for Always / For a while / open Look. Battery presence is omitted when sealed. Home/Away chips only when a presence grant exists (no coordinates). Looks older than ~30 minutes are closed by a background sweep.
- `GET /api/v1/handles/available?handle=` — whether a handle is valid, not reserved, and free.
- `PUT /api/v1/me/handle` `{ handle }` — claim unique handle (onboarding).
- `POST /api/v1/me/phone/send` `{ phone }` and `POST /api/v1/me/phone/verify` `{ phone, code }` — verify the signed-in account’s phone. Development returns `developmentCode` when Twilio is unset. Production returns `otp_not_configured` and does not claim a text was sent.
- `POST /api/v1/people/phone` `{ phone }` — if that number is already verified, connect the account (no SMS). If it is not, create an invite and return the code. No invite text is sent. A Look does not send SMS. Verification texts are capped at 8 per hour and 8 per day for each account, 8 per hour for each number, and 40 per day for the whole service.
- `PATCH /api/v1/me` — optional display name.
- `PUT /api/v1/people/{id}/presence-grant` `{ enabled }` — subject-only: trustee may see Home/Away.
- `PUT /api/v1/me/home` `{ placeId, label }` — register Home place **without coordinates** (coords stay on device).
- `POST /api/v1/me/home/presence` `{ state: home|away|unknown }` — device posts geofence transitions.
- `POST /api/v1/promises` `{ trusteeId, deadlineAt }` — “back home by” promise (subject-only).
- `POST /api/v1/location` — append point(s) only while sharing (Until they look / Always / For a while). Optional `points` array for a batch. Prunes GPS older than 26 hours. No-op (and clears GPS) if the circle is empty.
- `POST /api/v1/looks` `{ subjectId, confirmed: true }` — unlock **live + last 2 hours from stored points**, append look log. Re-opening an active Look does not send another receipt.
- `POST /api/v1/looks/close`, `POST /api/v1/looks/{subjectId}/extend` — extend is Circle (24h); updates the look-log row and sends a quiet extend receipt.
- `PATCH /api/v1/people/{id}/share` `{ resting, timed }` — Until they look / Always / For a while (reverts). Timed `home` is a fixed 4-hour window (“For 4 hours”).
- `POST /api/v1/invites`, `POST /api/v1/invites/accept` — copy: “I trust you with my location.”
- `POST /api/v1/presence/check-in`, `POST /api/v1/presence/place-ping` — legacy; unused by iOS 1.0 UI.
- `POST /api/v1/circle/entitlement` — review unlock when allowed, or a signed transaction.
- `GET /api/v1/storekit/account-token`, `POST /api/v1/storekit/transactions` — StoreKit JWS, App Account Token, ownership lock.
- `POST /api/v1/storekit/notifications` — App Store Server Notifications V2.
- `POST /api/v1/push/devices` — APNs token for look receipts on the looked-at phone.
- `DELETE /api/v1/account` — App Store 5.1.1(v) account deletion.
- `POST /api/v1/stripe/checkout` — web Circle for Stripe product `prod_trust_circle` when keys are set.

Production host: Render service `trust-api`, custom domain `trust.collapsetechnologies.com`. Legal URLs also live on the studio site at `https://collapsetechnologies.com/trust`.

## Secrets (do not invent)

| Secret | Needed for | Local |
| --- | --- | --- |
| Postgres | Product store | docker compose (`trust` / `trust`) |
| `Auth:SigningKey` | Session JWTs | Development default in `appsettings.Development.json` |
| Apple JWKS | Sign in with Apple | No private key; bundle ID audience |
| `Google:ClientIds` | Production Google | Optional; iOS Google Sign-In client ID not in repo |
| `StoreKit:Enabled` + Apple Root CA G3 (embedded) | Verify App Store JWS | On in production |
| `StoreKit:AllowReviewUnlock` | Settings → Unlock Circle for review | Development / first App Review |
| `Apns:KeyId` + `Apns:PrivateKey` | Look receipts on the subject’s phone | User-supplied Auth Key; do not invent |
| `Twilio__AccountSid`, `Twilio__AuthToken`, and `Twilio__FromNumber` or `Twilio__MessagingServiceSid` | Verification SMS only | Optional locally. Development returns the code in the API response if unset. Production does not claim a text was sent. Do not commit secrets. |
| Stripe `SecretKey`, price IDs | Web checkout | Optional; iOS Circle is StoreKit |
| Mapbox | Not used | MapKit on iOS |

## Tests

```bash
dotnet test
```

Engine tests use the in-memory store. HTTP tests host the API with `Trust:Store=memory`. `PostgresHistoryTests` talks to local docker Postgres on port 5433 when it is up, and skips if it is not.
