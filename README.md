# Trust

Location escrow for adult peers: **Trust Circle** (iOS) + API + [jointrust.app](https://jointrust.app).

Split from [QuirinoC/collapse-tech](https://github.com/QuirinoC/collapse-tech) at `f9569af`.

## Layout

| Path | Purpose |
| --- | --- |
| `apps/trust-ios` | SwiftUI + MapKit client (Trust Circle) |
| `apps/trust-api` | ASP.NET Core + Postgres API |
| `apps/jointrust-web` | Marketing + legal at jointrust.app |

Canonical legal/marketing URLs: `https://jointrust.app` (`/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`).

Production API: `https://trust.collapsetechnologies.com` (Render `trust-api`).

## Local development

```bash
cd apps/trust-api
docker compose up postgres -d
dotnet run --launch-profile TrustApi
```

```bash
cd apps/trust-ios && xcodegen generate
# Run the Trust scheme. Simulator Debug → http://127.0.0.1:5088
```

```bash
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

## Render

Blueprint: root `render.yaml` (trust-api only). **Do not** blueprint-sync over live secrets. Keep `Trust__SeedReviewCircle` and `StoreKit__AllowReviewUnlock` **false** except during App Review.
