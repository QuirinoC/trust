# Trust — Sandbox verification (M3 `m3-sandbox`)

Exit gate for the L2 matrix below. See the plan's "Sandbox / TestFlight / StoreKit testing
path" section for the full three-layer rationale (L1 Simulator / **L2 Sandbox** / L3
TestFlight) — this file only covers what you actually run and check off for L2.

**Primary setup:** physical iPhone + iPad, Debug build via the `Trust-Sandbox` scheme,
Apple's real Sandbox App Store, against the **Dev API** on local Postgres. Zero production
rows. Do not use the `Trust` scheme for this (it carries `Trust.storekit`, which intercepts
StoreKit locally and makes Sandbox purchases impossible on device, and the API will reject
its JWS as "certificate chain is not trusted").

---

## 1. One-time ASC setup (Juan — needs App Store Connect access)

1. **Sandbox testers** — App Store Connect → Users and Access → Sandbox → Testers. Create
   **two** testers, US storefront, default renewal rate:
   - Tester **A** → signed into iPhone only.
   - Tester **B** → signed into iPad only.
   - Never sign a sandbox tester into iCloud — Settings → Developer → Sandbox Apple Account
     only.
   - Between trial runs: same screen → **Clear Purchase History** / **Reset eligibility for
     introductory offers** on the tester, so the 7‑day trial can be exercised again.
2. **Paid Apps agreement** — App Store Connect → Business → Agreements, Tax, and Banking.
   Must be **Active**. If it lapses, `Product.products(for:)` returns empty in Sandbox too
   (looks like an app bug; it's the agreement).
3. **Subscriptions metadata** — App Store Connect → Trust Circle app → Subscriptions → both
   products (monthly, annual) at least **Ready to Submit** with complete metadata
   (localizations, price, review screenshot). Product IDs stay `com.collapsetechnologies.
   trust.circle.monthly` / `.annual` (plan decision 4 — IDs don't change even after the
   **Plus** display rename).
4. **App Store Server Notifications V2** — App Store Connect → App Information. Both the
   Production URL and Sandbox URL are currently configured as
   `https://trust-api-u0ft.onrender.com/api/v1/storekit/notifications` (read-only checked
   2026-09-24). The custom `trust.collapsetechnologies.com` host still has unresolved TLS;
   do not switch these URLs back until its HTTPS endpoint is independently healthy. This
   confirms configuration only; it is not proof that a signed Apple notification was
   delivered, accepted, or processed end to end. The app also submits signed transaction
   JWS on purchase/restore/renewal.
5. **Devices** — on the iPhone and iPad: Settings → Developer → Sandbox Apple Account → sign
   in tester A / B respectively.

**Blockers only Juan can clear:** steps 1–3 require App Store Connect access this agent does
not have. The `Trust-Sandbox` scheme, fail-loud Dev API guard, and matrix below are ready to
run as soon as the two testers exist and the Paid Apps agreement is active.

---

## 2. Run the Dev API (Postgres, port 5088)

```bash
cd apps/trust-api
docker compose up postgres -d
dotnet run --launch-profile TrustApi
```

- Binds `0.0.0.0:5088` (see `Properties/launchSettings.json`) so it's reachable over LAN /
  mDNS, not just loopback.
- `ASPNETCORE_ENVIRONMENT=Development` → `Trust:SeedReviewCircle`, `StoreKit:
  AllowReviewUnlock`, `Auth:AllowDevelopmentSignIn` all default `true` locally
  (`appsettings.Development.json`). **These must stay `false` in production** — see
  `apps/trust-api/README.md`. Nothing in this change touches production config
  (`apps/render.yaml`) or flips a review flag there.
- APNs receipts: set `Apns__KeyId` / `Apns__PrivateKey` env vars (or in
  `appsettings.Development.json`, gitignored) if you want push receipts during the Look
  test — iOS already registers with `environment: sandbox` in DEBUG
  (`LookReceiptNotifier.swift`), so `ApnsClient` routes to `api.sandbox.push.apple.com`
  automatically; no iOS change needed.
- Off-Wi-Fi (battery walk, M4): Tailscale on both Mac and phone, then use the Tailscale
  MagicDNS name instead of `.local` in step 3 below.

## 3. Run `Trust-Sandbox` on device

1. Find your Mac's mDNS name: **System Settings → General → Sharing → Local hostname**, or
   `scutil --get LocalHostName` (append `.local`).
2. Xcode → scheme selector → **Trust-Sandbox** → **Edit Scheme… → Run → Arguments →
   Environment Variables** → set `TRUST_BASE_URL` to `http://<that-name>.local:5088`
   (`project.yml` ships a `<mac-mdns-name>` placeholder — replace it there, or override
   per-machine in the scheme editor without touching `project.yml`).
3. Select the physical iPhone or iPad as the run destination (Sandbox purchases are
   **unsupported on Simulator** — Simulator is `.storekit`-only).
4. Build & run. StoreKit Configuration is **None** for this scheme, so purchases go to
   Apple's real Sandbox App Store using whichever tester is signed in under Settings →
   Developer → Sandbox Apple Account.
5. If the Dev API is down or unreachable at the configured host, the app **fails loud**: it
   shows the "can't reach `<host>`" notice / offline state instead of silently talking to
   production. This is enforced by `TRUST_STRICT_API=1` (baked into the scheme's env vars) —
   see `AppConfiguration.debugAPICandidates` / `remapLoopbackOnDevice` in
   `Sources/TrustApp/AppConfiguration.swift`. If you ever see the app respond with real data
   while the Dev API is stopped, that's a regression in that guard, not expected behavior.

## Do not

- Do not run this matrix with the `Trust` scheme.
- Do not flip `Trust__SeedReviewCircle` / `StoreKit__AllowReviewUnlock` on **production** —
  Render env only, review-window only (already called out for M6). This file does not touch
  `apps/render.yaml`.
- Do not sign a sandbox tester into iCloud, or use the same tester Apple ID on both devices
  for the two-device test (defeats the App Account Token check).
- Do not create a `.sandbox` bundle ID — isolation comes from `TRUST_BASE_URL`, not a second
  ASC record.

---

## 4. L2 matrix — check off against the Dev API

Server is truth for every row; if the app's UI disagrees with what the Dev API returns for
`GET /api/v1/circle`, that's the bug, not the checklist.

- [ ] **SIWA first run** — Sign in with Apple on device A → lands on Handle (A2). A
      `trust.accounts` row exists. Reset via device Settings → Apple Account → Sign-In &
      Security → Sign in with Apple → Trust → **Stop using**.
- [ ] **Trial buy (monthly)** — Paywall → Monthly. `subscription.isEligibleForIntroOffer` is
      true → 7‑day trial (~3 min accelerated in Sandbox) → `POST /storekit/transactions`
      returns 200 → coverage `isCovered = true` → Sharing unlocks Always / For a while →
      seat limit shows 20.
- [ ] **Renewals** — Wait through a couple of accelerated renewal cycles (~5 min each).
      `Transaction.updates` delivers; the app resubmits JWS; `expiresDate` advances;
      coverage stays true.
- [ ] **Expire / cancel** — Either let ~12 renewals lapse or Settings → Developer → Sandbox
      Apple Account → Manage → cancel the subscription. Coverage flips false; existing
      Always edges fall back to Until they look; if the circle had >5 members, no data is
      lost but new invites are blocked (downgrade rule, M1 rule 5).
- [ ] **Restore** — Delete the app, reinstall, sign back in with the same SIWA identity,
      tap Restore. `AppStore.sync()` resubmits JWS → 200 → Plus is back with no new charge.
- [ ] **App Account Token lock** — On device B, sign into the **same sandbox tester** but a
      **different** SIWA identity, then Restore. StoreKit returns the subscription, but the
      token doesn't match B's `appAccountToken` → app shows "linked to another account" and
      refuses to move ownership. A keeps Plus.
- [ ] **Covered partner** — A is Plus, B is free and connected to A. `GET /circle` for B
      shows `coverage.isCovered = true`, `sponsorName = A`. B can set Always toward A only
      (per-edge coverage, plan decision 7 if implemented; account-wide otherwise — confirm
      current server behavior against M1 rule 5).
- [ ] **Plan switch** — Manage Subscriptions → switch monthly → annual. Same
      `originalTransactionId`, new `productId` accepted server-side; `activeProductID`
      flips in the app.
- [ ] **Refund** — Trigger a Sandbox refund (Manage Subscriptions, or Manage Transactions in
      the L1 Simulator loop). `revocationDate` is set → coverage flips false on the next
      submit or notification.
- [ ] **Review unlock** — With Dev API `StoreKit__AllowReviewUnlock=true` (default locally),
      "Unlock Plus for review" is visible and `POST /circle/entitlement` grants access. Flip
      the env var to `false` and confirm the button disappears (this is the production
      default — don't leave it `true` anywhere but the Dev API / review window).
- [ ] **Two-device Look / View** — A invites, B accepts (both start Off/Off). A sets Until
      they look → B Looks → notify-first confirm on A → one snapshot on B → sandbox APNs
      receipt lands on A → both directions show up in the view log. Then A sets Always → B
      Views (no sheet) → logged, no push.

---

## 5. `Trust.storekit` vs ASC — status

The local `Trust.storekit` (L1 Simulator only) now says **Trust Plus** / "Plus Monthly" /
"Plus Annual" to match the app's current copy (`TrustCopy.swift`, `PlusPaywall.swift`) and
the 5/20-seat, Always/For-a-while/view-log feature set — it previously still said "Trust
Circle" and "24-hour history, place pings", which predates the M1 migration.

This is a **hand edit for L1 Simulator UX only**. It is not a real ASC sync. Once Juan does
the ASC subscription-group display rename to "Trust Plus" (tracked in M6, "IAP group rename
display to Trust Plus"), replace this file for real: Xcode → File → New → StoreKit
Configuration File → **"Sync this file with an app in App Store Connect"**, picking the
`Trust Circle` app record / `22346972` group. That sync needs App Store Connect access this
agent doesn't have — flagging as a Juan follow-up, not doing it now.

---

## Files touched by this pass

- `apps/trust-ios/project.yml` — added the `Trust-Sandbox` scheme (top-level `schemes:` —
  StoreKit Configuration **None**, `TRUST_STRICT_API=1`, placeholder `TRUST_BASE_URL`).
- `apps/trust-ios/Sources/TrustApp/AppConfiguration.swift` — `TRUST_STRICT_API=1` makes
  `debugAPICandidates` / `remapLoopbackOnDevice` refuse the production fallback, so a down
  Dev API fails loud instead of silently resolving to a production API host.
- `apps/trust-ios/Resources/Trust.storekit` — copy only (Plus naming/features) for the L1
  loop; product IDs unchanged.
- `apps/trust-ios/Trust.xcodeproj/**` — regenerated via `xcodegen generate` (adds the
  `Trust-Sandbox.xcscheme`, no other target/source changes from this pass).

Nothing here edits product UI, flips a production review flag, or touches `apps/render.yaml`.
Left uncommitted per instructions.
