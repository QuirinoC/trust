# jointrust.app

Public landing for **Trust** at [jointrust.app](https://jointrust.app).
The site follows the current product direction in `docs/DESIGN.md`. The landing page leads with the app's consent-first promise. Sharing is off until a person chooses a mode for each connection.

Privacy, terms, support, and the verification-text opt-in live on this host: `/privacy`, `/terms`, `/support`, `/sms`. Invitation links (`/i/:code`) and the Apple association file are served by the Worker; keep those routes intact when updating the design.

## Deploy

Direct upload — no git commit required:

```bash
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

Apex and `www` are Worker custom domains (proxied). `www` 301s to `https://jointrust.app`.
