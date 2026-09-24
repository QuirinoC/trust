# jointrust.app

Public landing for **Trust** at [jointrust.app](https://jointrust.app).
Paper page matching the app: Bodoni italic for **Trust**, Space Grotesk for Collapse Technologies, system UI for the rest. No map drawing behind the name.

Privacy, terms, support, and the verification-text opt-in live on this host: `/privacy`, `/terms`, `/support`, `/sms`.

## Deploy

Direct upload — no git commit required:

```bash
npx wrangler deploy --config apps/jointrust-web/wrangler.jsonc
```

Apex and `www` are Worker custom domains (proxied). `www` 301s to `https://jointrust.app`.
