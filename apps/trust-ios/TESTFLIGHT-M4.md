# Trust — Internal TestFlight (M4)

L3 gate: **Release archive → Internal Testing**, production API + sandbox IAP, dedicated tester Apple IDs. Completes what L2 (`SANDBOX.md`) cannot: background location + battery off-Wi-Fi, **production** APNs, Delete account on real rows.

| | |
| --- | --- |
| Workspace | `collapse-tech` (`main`) |
| Bundle | `com.collapsetechnologies.trust` |
| Team | `3S529795M9` |
| ASC App ID | `6806879060` |
| Version / build | **1.0 (18)** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`) |
| Scheme to archive | **`Trust`** (Release). Do **not** archive `Trust-Sandbox` — that scheme is Debug / Dev API only. |
| API | `https://trust.collapsetechnologies.com` (Release `TRUST_BASE_URL` in `project.yml`) |
| IAP | Sandbox (free). Product IDs stay `com.collapsetechnologies.trust.circle.monthly` / `.annual` |
| Review flags | **Stay `false`.** Do not flip `Trust__SeedReviewCircle` / `StoreKit__AllowReviewUnlock` on production for M4. |

This file does not touch `apps/render.yaml` or live Render env.

---

## 0. What this build must prove

M4 exit (plan): **no P0/P1**, test accounts deleted, review flags still `false`.

| Case | Do | Expect |
| --- | --- | --- |
| **Two-device Look / receipt** | Dedicated Apple ID on iPhone (A) and iPad or second iPhone (B). A invites, B accepts (Off/Off). A sets **Until they look**. B **Looks**. | Notify-first confirm on B → **one snapshot** (not live) → **production APNs receipt** on A → both directions in View log. Share stays Sealed after. |
| **View (Available)** | A buys Plus (sandbox IAP) → sets **Always** toward B → B **Views**. | D1 opens with no Look sheet; event **logged**; **no push** on A. |
| **View log** | You → VIEW LOG (and the three-row preview) on **both** devices after Look and View. | Bidirectional: looks at you + your looks/views. Look has a receipt line; View is log-only. |
| **Battery, Sealed-only** | Both outbound **Until they look** (not Always). Always-allow location granted. Leave Wi-Fi, walk 15–20 min with the app backgrounded. | No blue Dynamic Island navigation pill while sharing. Sealed stack is coarse + significant-change (`LocationCoordinator` hundred-meters / 200 m filter). No unexpected GPS drain vs Available. Look from B still returns a recent snapshot. |
| **Prod APNs** | Same Look as above, devices on cellular. | Receipt lands on A. Release registers `environment: production` (`LookReceiptNotifier`). Confirm live Render `Apns__Enabled=true` (blueprint default is `false` — live env is source of truth). |
| **Sandbox IAP on TF** | On a TestFlight install (not the `Trust` Debug scheme — that attaches `Trust.storekit`). You → Plus → monthly or annual. Optional: Settings → Developer → Sandbox Apple Account if the tester Apple ID is a sandbox tester. | Products resolve; 7-day trial / buy succeeds with **no charge**; Sharing unlocks Always / For a while; seats 20. Restore after delete+reinstall, same SIWA. |
| **Delete account** | You → **Delete account** → confirm, on **both** tester IDs after the run. | Session cleared; `DELETE /account` 200; re-SIWA lands on Handle. Exercises Guideline 5.1.1(v) and removes prod rows. |
| **Review flags stay FALSE** | Paywall on TF. Render dashboard for `trust-api`. | **Unlock Plus for review** is **absent** (`PlusPaywall` only shows it when `allowsReviewUnlock` is true). New empty accounts are **not** seeded Alex/Jordan/Riley. `Trust__SeedReviewCircle` and `StoreKit__AllowReviewUnlock` remain `false`. Flip only in M6 review window. |

### Do not

- Do not flip production review flags to exercise Look/Plus. Use two real testers and sandbox IAP.
- Do not archive or distribute `Trust-Sandbox`.
- Do not use one Apple ID on both devices (same `sub` = same account; also defeats App Account Token).
- Do not use Juan's daily iCloud Apple ID as a tester. Dedicated IDs only; Delete after.
- Do not sign a sandbox tester into iCloud — Developer → Sandbox Apple Account only (IAP). SIWA uses the device's real Apple ID.
- Do not point Release `TRUST_BASE_URL` at LAN / Dev API.
- Do not submit 1.0 for App Review from this build (M6). Internal Testing only.

---

## 1. Pre-archive smoke (agent / local)

From `apps/trust-ios`:

```bash
xcodegen generate

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Trust.xcodeproj -scheme Trust \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Trust.xcodeproj -scheme Trust \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO test \
    -only-testing:TrustCoreTests
```

If `iPhone 16` / `18.4` is missing, `xcrun simctl list devices available` and swap the destination. This machine’s available Simulator when smoked was `iPhone 17 Pro, OS=26.5`. Fail the archive if Debug or tests fail.

Confirm `project.yml` still has Release `TRUST_BASE_URL: https://trust.collapsetechnologies.com` and `CURRENT_PROJECT_VERSION: 6`.

---

## 2. Archive + upload (Juan)

Full Xcode + paid team. Codesign cannot run in this agent environment.

`ExportOptions.plist` uploads straight to App Store Connect. `ExportOptions-ipa.plist` writes an `.ipa` for Transporter. Both already set `method=app-store-connect`, `teamID=3S529795M9`, `signingStyle=automatic`, `manageAppVersionAndBuildNumber=false` (so ASC keeps build **6**).

### 2a. Generate + archive

```bash
cd /Users/juanquirino/dev/collapse-tech-trust-demo/apps/trust-ios
xcodegen generate

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Trust.xcodeproj -scheme Trust \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath build/Trust-1.0-6.xcarchive \
    DEVELOPMENT_TEAM=3S529795M9 \
    -allowProvisioningUpdates \
    archive
```

Expect `** ARCHIVE SUCCEEDED **`. Spot-check the archive Info.plist: `CFBundleShortVersionString` **1.0**, `CFBundleVersion` **6**, bundle `com.collapsetechnologies.trust`.

Xcode Organizer alternative: open `Trust.xcodeproj` → Product → Archive → Distribute App → App Store Connect.

### 2b. Upload via xcodebuild (no IPA)

Uses `ExportOptions.plist` (`destination` = `upload`). Xcode must already be signed into the `3S529795M9` Apple ID (Xcode → Settings → Accounts).

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -exportArchive \
    -archivePath build/Trust-1.0-6.xcarchive \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath build/Trust-1.0-6-upload \
    -allowProvisioningUpdates
```

### 2c. Export IPA + Transporter

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -exportArchive \
    -archivePath build/Trust-1.0-6.xcarchive \
    -exportOptionsPlist ExportOptions-ipa.plist \
    -exportPath build/Trust-1.0-6-ipa \
    -allowProvisioningUpdates
```

IPA path: `build/Trust-1.0-6-ipa/Trust.ipa`.

**Transporter.app (GUI):**

```bash
open -a Transporter build/Trust-1.0-6-ipa/Trust.ipa
```

Deliver with the same Apple ID that owns team `3S529795M9`.

**Transporter CLI** (app-specific password from appleid.apple.com → Sign-In and Security — never commit it):

```bash
# GUI binary, if Transporter.app is installed:
/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter \
  -m upload \
  -assetFile /Users/juanquirino/dev/collapse-tech-trust-demo/apps/trust-ios/build/Trust-1.0-6-ipa/Trust.ipa \
  -u <APPLE_ID_EMAIL> \
  -p <APP_SPECIFIC_PASSWORD>

# Or Xcode-bundled transporter (same flags):
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun iTMSTransporter -m upload \
    -assetFile /Users/juanquirino/dev/collapse-tech-trust-demo/apps/trust-ios/build/Trust-1.0-6-ipa/Trust.ipa \
    -u <APPLE_ID_EMAIL> \
    -p <APP_SPECIFIC_PASSWORD>
```

ASC listing: https://appstoreconnect.apple.com/apps/6806879060/distribution  
Wait until build **6** is **Ready to Test** (processing is usually 5–20 min). First upload of a new binary may ask export compliance — answer **No** (already `ITSAppUsesNonExemptEncryption = false`).

`build/` is local-only; do not commit archives or IPAs.

---

## 3. Internal Testing checklist (two devices)

Testers: **Juan + 1 helper**. Dedicated Apple IDs (not daily iCloud). Internal group does not need External Beta Review.

### Install

- [ ] Build **1.0 (6)** assigned to the Internal group; both devices install from TestFlight (not Xcode).
- [ ] Confirm no environment switcher; API is production (`usesProductionAPI`).
- [ ] Notifications allowed after first join. Always location granted when Sharing leaves Off.

### Two-device Look / receipt / View log

- [ ] A (iPhone) SIWA → Handle if needed. B (iPad) SIWA on a **different** dedicated ID → Handle.
- [ ] A Invite → copy link / share. B joins. Both start **Off / Off**.
- [ ] A Sharing → B → **Until they look**. Always location. Dynamic Island does not show a navigation arrow when backgrounded.
- [ ] B Circle → **Look** → confirm (“they will be notified” / one snapshot). One pin on D1. Not a live feed. A's share stays Sealed.
- [ ] **Production APNs receipt** arrives on A (banner + lock screen). If missing: Render `Apns__Enabled`, device token registered after SIWA, not a Debug/sandbox token.
- [ ] You → VIEW LOG on **both**: the Look appears in both directions (looks at you / your looks).
- [ ] A buys **Plus** via TF sandbox IAP (monthly is enough). Sharing unlocks Always / For a while. **Unlock Plus for review is not visible.**
- [ ] A sets **Always** toward B. B **Views** (no sheet). Logged on both. **No** receipt push on A.
- [ ] You → VIEW LOG again: View row present, no push implied.

### Battery, Sealed-only, off-Wi-Fi

- [ ] A sets B back to **Until they look** (or Stop Always). Both outbound Sealed-only — no Available edges.
- [ ] Leave Wi-Fi. Cellular on. Background Trust 15–20 min (walk). Blue indicator on.
- [ ] Battery drop is ordinary (significant-change / ~100 m), not Available-tier (`kCLLocationAccuracyBest` / 25 m).
- [ ] B Looks again off-Wi-Fi: snapshot is recent; **prod APNs** receipt still lands on A.

### Delete + cleanup

- [ ] You → **Delete account** on **B**, then **A**. Confirm re-SIWA is a new Handle (or Stop using Apple → Trust first if the same Apple ID is reused).
- [ ] Confirm production Postgres has no leftover tester rows you care about (or accept Delete as the wipe).
- [ ] Render dashboard: `Trust__SeedReviewCircle=false`, `StoreKit__AllowReviewUnlock=false`. Do not “fix” a missing Unlock button by flipping these.
- [ ] Remove the Internal build from daily phones when the run is done.

---

## 4. ASC / console blockers only Juan can clear

This agent cannot sign, upload, or click App Store Connect / Render. Nothing below is a code change.

1. **Apple ID session** — Xcode Settings → Accounts signed into team `3S529795M9`; Distribution cert + App Store provisioning for `com.collapsetechnologies.trust`. App-specific password if using Transporter CLI.
2. **Archive + upload** — run §2 (or Organizer). Wait for build **6** to finish processing. Answer export compliance if ASC prompts.
3. **Internal Testing group** — ASC → TestFlight → Internal. Group = Juan + 1 helper. Assign build **1.0 (6)**. Internal testers must be Users on the team (Users and Access), not External.
4. **Dedicated tester Apple IDs** — two IDs that are **not** daily iCloud. Invite those as Internal testers. Same ID on both devices collapses SIWA `sub` and the token-lock case.
5. **Paid Apps agreement** — Business → Agreements, Tax, and Banking = **Active**. If it lapsed, TF sandbox IAP returns empty products (looks like an app bug).
6. **Subscriptions still Ready to Submit** — group `22346972`, monthly `6806880712`, annual `6806880974`. Metadata complete. Display rename to **Trust Plus** is **M6**, not a blocker for M4 IAP if products already resolve.
7. **Live production APNs** — Render `trust-api`: confirm `Apns__Enabled=true` and KeyId/PrivateKey present. Blueprint still defaults `Apns__Enabled=false`; do **not** re-sync the blueprint over live secrets. Without this, Look receipts fail on TF.
8. **Review flags stay false** — Render: `Trust__SeedReviewCircle=false`, `StoreKit__AllowReviewUnlock=false`. Confirm after any env edit. Do not turn them on for M4.
9. **Do not Add for Review / Submit** — listing may still show Add for Review enabled (older handoff). M4 is Internal TF only. App + subscription submit is M6.

Optional (not M4-blocking if IAP already works): ASC → App Information → App Store Server Notifications V2 Production URL `https://trust.collapsetechnologies.com/api/v1/storekit/notifications`. Client-submitted JWS already drives entitlement.

---

## Related

- L2 device sandbox vs Dev API: `SANDBOX.md`
- Screen inventory: `SCREENS.md`
- Plan M4 exit: Internal TF clean, accounts deleted, review flags false. M5 (external TF) skip if this is green.
