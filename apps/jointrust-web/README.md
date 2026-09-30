# jointrust.app

Public landing for **Trust** at [jointrust.app](https://jointrust.app).
The site follows the current product direction in `docs/DESIGN.md`. The landing page leads with the app's consent-first promise. Sharing is off until a person chooses a mode for each connection.

Privacy, terms, support, and the verification-text opt-in live on this host: `/privacy`, `/terms`, `/support`, `/sms`. Invitation links (`/i/:code`) and the Apple association file are served by the Worker; keep those routes intact when updating the design.

## Deploy

Direct upload is explicit and preserves dashboard-configured variables:

```bash
cd apps/jointrust-web
npm ci
npm test
npm run deploy
```

Deploy the updated privacy page with the API migration that starts recording the SMS consent events it describes.

Apex and `www` are Worker custom domains (proxied). `www` 301s to `https://jointrust.app`.
