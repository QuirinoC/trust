# Trust for iPhone and iPad

Native SwiftUI app for adult-peer location escrow. **Home is map + draggable People sheet** (People · Log · You). Location stays **Sealed** until someone **Looks** — a notify-first confirm, then one snapshot and a receipt push. People who share **Always / For a while** are **Available**: View without a sheet, every view logged, never a push. Screen inventory: `SCREENS.md`. Design history (list-first mocks superseded): `design-mocks/duo-gpt6/`.

The product backend is `apps/trust-api` (ASP.NET Core + Postgres). This app does not use an in-memory demo as the backend. Debug builds behave like Release (real Sign in with Apple, real — possibly empty — circle); the offline demo circle is opt-in only, via the DEBUG **See the app** button on Login or `TRUST_DEMO=1` in the scheme (`SIMCTL_CHILD_TRUST_DEMO=1` with `simctl launch`).

## Map provider

**MapKit** is the production map.

- Native, no vendor token, no extra billing, no third-party tracker on the home screen.
- Custom annotations: you (square + red rule `#E10600`), live people (black/white initials), sealed people as a lock chip — **never** a GPS dump for Until they look.
- iOS 18 is the deployment target; the map uses `MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)` for a quieter, editorial plate. Light only.

Google Maps is out (billing and tracking optics). **Mapbox / MapLibre** is the right later upgrade for a true black-and-white cartography skin; 1.0 is not blocked on a Mapbox token.

## Visual

**Masthead Paper** is the default: Didot for **Trust** (large lockup; Home Screen name is **Trust Circle**), Space Grotesk for **Collapse Technologies** (same as Pixelboard and the studio site; a step smaller than the previous system-folio mark), SF for UI, white paper, black ink, red `#E10600` as the only chromatic. Light only — Night Edition was removed for 1.0.

Login is paper only: wordmark, **Trust**, rule, Sign in with Apple, legal links. (The earlier Canvas atlas background was dropped in M0.) Design history: `design-mocks/duo-gpt6/` (list-first home superseded by Round 8 map+sheet).

## Open and run

1. Start the API (Postgres + Trust API):

   ```bash
   cd apps/trust-api
   docker compose up postgres -d
   dotnet run --launch-profile TrustApi
   ```

   The API listens on `http://0.0.0.0:5088`.

   | Build | API URL |
   | --- | --- |
   | Simulator Debug | `http://127.0.0.1:5088` |
   | Device Debug | Production `https://trust.collapsetechnologies.com`, unless you pass `TRUST_BASE_URL=http://<mac-lan-ip>:5088` to `xcodebuild` (loopback is the phone, not the Mac — the app remaps `127.0.0.1` on device). If the configured host is down, Debug probes `/health/live` and uses the first reachable candidate, or shows a real error instead of spinning forever. |
   | Release / Archive | `https://trust.collapsetechnologies.com` (set in `project.yml`; do not point Release at LAN) |

   Local HTTP is allowed via App Transport Security local networking (`NSAllowsLocalNetworking`). Do not hardcode a LAN IP in the project.

2. `cd apps/trust-ios && xcodegen generate`

## Localization

**1.0 ships English only.** English is the development language (`defaultValue` in `Sources/TrustCore/TrustCopy.swift`); `CFBundleLocalizations` lists only `en`. The seven non-EN `Resources/*.lproj` bundles (es, ja, zh-Hans, de, fr, ko, pt-BR) were removed in M0 so stale translations do not ship. Product names **Trust** and **Trust Circle** stay untranslated. Known API error codes are mapped on device; unknown server messages pass through.

If localization returns post-1.0: edit `Scripts/overlays/*.json`, run `python3 Scripts/emit_localizations.py` to regenerate the `.lproj` bundles, then `python3 Scripts/validate_localizations.py`, and add the locales back to `CFBundleLocalizations` in `project.yml`.

3. Open `Trust.xcodeproj` in Xcode (Xcode 16+ / iOS 18 deployment target; Universal iPhone + iPad — iPhone portrait only, iPad all orientations). Team `3S529795M9`.
4. The shared Run scheme attaches `Resources/Trust.storekit`.
5. Run on Simulator or device.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Trust.xcodeproj -scheme Trust \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Device Debug against your Mac API (API must be running, same Wi-Fi):

```bash
LAN=$(ipconfig getifaddr en0)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Trust.xcodeproj -scheme Trust \
    -destination 'id=<DEVICE_UDID>' -configuration Debug \
    DEVELOPMENT_TEAM=3S529795M9 TRUST_BASE_URL="http://$LAN:5088" \
    -derivedDataPath build/DerivedDataDevice build
```

Bundle ID: `com.collapsetechnologies.trust`.

## First-open and look flow

1. Collapse Technologies, **Trust** (hero lockup; product name **Trust**; Home Screen / ASC display name may still read **Trust Circle**), Sign in with Apple (`apple.logo`, identity token → API). Terms of Service, Privacy, and Support sit in one row (`https://jointrust.app/…`). No extra legal line under the button.
2. After Apple, **Your handle** if a unique handle is not set yet. Handle is the identity (like `jordan` / `@jordan`). Completing it is required before the Circle. A display name from Apple is kept if it already exists — not asked here. After account delete, this returns.
3. **People** (home) is map + draggable sheet (build 15 / Round 8). Apple MapKit fills the top; the bottom sheet lists people under SHARED WITH YOU. Sealed rows show Home / Away (or “presence hidden”) and a **Look** pill; Available rows (Always toward you) show **View**. Recenter control sits above the sheet. **Do not ship list-first Circle** — that IA is obsolete.
4. **Look** confirm leads with the consequence — “Maya will be notified.” — then “one location snapshot — not a live feed”. The subject gets a remote receipt (APNs). No “don’t ask again.” Their share stays Sealed afterwards.
5. **View** (Available) opens D1 directly and logs a `view` (server dedupes within 30 min). No push.
6. **Sharing**: per person Until they look | Always | For a while (15m / 1h / 4h / 8h, overlays the current mode then seals) + Stop. Join default is **Off** both ways. Always / For a while are Plus; the server answers `402 pro_required` and the app opens the Plus sheet.
7. **You**: presence triad Home / Away / Hidden (free, manual, global; Hidden never reaches the circle), Plus card, view log (both directions), Stop all, Sign out, Delete.
8. Invite: “I trust you with my location.” `https://trust.collapsetechnologies.com/i/CODE` and `trust://invite/CODE`.

Development API seeds Alex / Jordan / Riley as **server accounts** so the map is usable on one device. That seed lives in Postgres, not in the iOS process.

## Free vs Circle vs covered partner

| | Free | Circle ($7.99/mo or $69.99/yr, 7-day trial) |
| --- | --- | --- |
| Escrow share, 1 trusted person, look, last 2 hours, quiet receipt, look log | Yes | Yes |
| Extra trusted people | No (1 seat) | Up to 6 |
| 24-hour history on an open look | No | Yes — “Include last 24 hours” |
| Place ping (got-home without opening the map) | No | Yes |
| Look-log retention | 30 days | 365 days + export |
| Ads / location sale | Never | Never |

**Looking is not paywalled.** If anyone in the circle has Circle, the unpaid people are covered. The app submits signed StoreKit transactions (`POST /api/v1/storekit/transactions`) with a server-issued App Account Token. Family Sharing is off. Stripe product `prod_trust_circle` is the web sponsor path when Stripe keys are set on the API. iOS never uses Stripe Checkout.

## Location

While Using is enough to use the map, Settings, and Look at someone else. Always is required once **your** location is in the product (Until they look / escrow, Always, or For a while) so Look still works when Trust Circle is closed.

The first Home asks for While Using. Always is requested when they turn on sharing (invite “I trust you with my location”, join, or a share-mode sheet) — not on login. Background updates and API ingest run only while sharing is on. If they keep While Using, escrow updates only while the app is open; Settings and a Home folio send them to iOS Settings for Always. Reduced accuracy requests precise location (`PreciseEscrow`). `UIBackgroundModes` includes `location`. The blue Dynamic Island navigation pill stays off. Trust is not a turn-by-turn app.

Purpose strings (Masthead voice, not Life360):

- **While Using:** Trust Circle uses your location while the app is open so you can see yourself on the map and look at people who share with you. Trust Circle does not sell your location.
- **Always:** Trust Circle holds your location in escrow, including in the background, so a trusted adult peer can find you if they look. They cannot see it until they confirm a look, and you are notified. Trust Circle does not sell your location.

## StoreKit

Products in `Resources/Trust.storekit` (local Run scheme only; archives use App Store Connect):

- `com.collapsetechnologies.trust.circle.monthly` — $7.99 / month, 7-day free trial, not family-shareable
- `com.collapsetechnologies.trust.circle.annual` — $69.99 / year, 7-day free trial, not family-shareable

**Unlock Circle for review** appears only when the server sets `StoreKit:AllowReviewUnlock`.

## App Store, TestFlight, Sandbox

Paste-ready 1.0 listing, privacy labels, review notes, IAP rename, screenshot shot list, and submit order:

- **M6 App Store Connect package:** [`AppStore/ASC-M6.md`](AppStore/ASC-M6.md)
- **M4 internal TestFlight:** [`TESTFLIGHT-M4.md`](TESTFLIGHT-M4.md)
- **M3 sandbox (L2):** [`SANDBOX.md`](SANDBOX.md)

Export compliance: `ITSAppUsesNonExemptEncryption` is false. Account deletion (5.1.1(v)): You → Delete account — also at https://jointrust.app/support

App Store screenshots for 1.0: `AppStore/Screenshots/m6/` (iPhone 6.9" + iPad 13"). Do not upload the pre-M2 `iphone-67-*` / `ipad-13-*.png` / `asc-65/` files. Capture: `bash AppStore/capture-m6-screenshots.sh` (see ASC-M6).

## Tests

Apple’s split: many fast unit tests, fewer integration tests, a short UI pass for the journeys a person actually does. Run them with the Trust scheme in Xcode (`DEVELOPER_DIR` must be Xcode.app, not Command Line Tools). Destination on this Mac is the iPhone 17 Pro simulator.

| Layer | Where | What it proves |
| --- | --- | --- |
| Unit | `TrustCoreTests` — rules, copy, handle, ingest buffer, vault | One function, no UI, no network. History is 24h free / 30 days Plus. Pause wires are 1h, 8h, 1 day, 2 days, 3 days. |
| Shadow | `TrustCoreTests` — `DemoTrustService` | The offline “See the app” fixture follows the same share, Look, View, and log rules as the server. It is not a second product. |
| Integration | `apps/trust-api` `TrustApi.Tests` and `scripts/e2e_two_account_http.py` | Two accounts against Postgres: Pause restores, Look is one snapshot, live pins need the viewer’s Plus. |
| Usage | `TrustUITests` | Launches the Debug app with `TRUST_DEMO=1` and `TRUST_UI_TEST=1` and walks People, a Look confirm, Sharing, Log, and You. |
