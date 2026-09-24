# Trust Circle 1.0 — App Store Connect paste (M6)

**Prep only.** Do not submit from this file. Do not flip production `Trust__SeedReviewCircle` or `StoreKit__AllowReviewUnlock` until the review window (step 8 in [Juan’s click-path](#juans-remaining-click-path)).

| | |
| --- | --- |
| Workspace | `collapse-tech` (`main`) |
| Bundle | `com.collapsetechnologies.trust` |
| Team | `3S529795M9` |
| ASC App ID | `6806879060` |
| IAP group | `22346972` |
| Version / build | **1.0 (18)** — archive the **`Trust`** scheme (Release). Do not archive `Trust-Sandbox`. Home IA is map + draggable People sheet (not list-first Circle). |
| API | `https://trust.collapsetechnologies.com` |
| English only | `CFBundleLocalizations` = `en` |
| Export compliance | `ITSAppUsesNonExemptEncryption` = **false** (HTTPS / standard encryption only) |

Related: [`TESTFLIGHT-M4.md`](../TESTFLIGHT-M4.md) · [`SANDBOX.md`](../SANDBOX.md)

---

## 1. Listing (App Information + Version)

Copy each field into App Store Connect.

### Name

```
Trust Circle
```

ASC uniqueness: exact `Trust Circle` may already be taken. If the name field rejects, use `Trust Circle.` (trailing period). Home Screen display name stays **Trust Circle** (`CFBundleDisplayName`).

### Subtitle (30)

```
Location without watching
```

### Promotional text (optional, 170)

```
Sealed until Look. Available when you choose. Adult-peer location escrow — not a live tracker.
```

### Description

```
Trust Circle holds your location in escrow for trusted adult peers. They cannot see it until they confirm a Look.

A Look is notify-first: one location snapshot — not a live feed — and you get a receipt. People who share Always or For a while are Available: View without a sheet, every view logged, never a push.

Join starts Off both ways. An invite is not permission. Presence is Home, Away, or Hidden — free, manual, and Hidden never reaches the circle.

Free includes up to 5 people, Off and Until they look, Look + receipt, View when someone is Available, a single map pin after a Look, and 30 days of view log.

Trust Plus is $7.99/month or $69.99/year, with a 7-day trial. Plus adds up to 20 people, Always and For a while, the circle map, and a year of view log with export. A paying member covers unpaid people on the edges they share. Looking is not paywalled. Family Sharing is off. No ads. We do not sell location.

Sign in with Apple. Delete your account in You → Delete account.
```

### Keywords (100 characters max)

```
location,privacy,share,circle,look,safety,find,trusted,escrow
```

(59 characters. Do not add `family` — 1.0 is adult peers, 18+.)

### Categories

| | |
| --- | --- |
| Primary | **Lifestyle** (`public.app-category.lifestyle`) |
| Secondary | **Social Networking** |

### URLs (`AppConfiguration`)

| Field | URL |
| --- | --- |
| Support | https://jointrust.app/support |
| Marketing | https://jointrust.app |
| Privacy Policy | https://jointrust.app/privacy |
| Terms (paywall / review) | https://jointrust.app/terms |

Copyright: `2026 Collapse Technologies`

Contact (review / IAP mismatch copy): `hello@collapsetechnologies.com`

---

## 2. Age rating — 18+

Set **18+**. This is an adult-peer location escrow. Precise location is shared only with a **named person the user invited**, and only after a **confirmed Look** (or while the user opted into Always / For a while).

### Questionnaire notes (do not use “unrestricted web” as the 18+ reason)

| Item | Answer / note |
| --- | --- |
| Unrestricted Web Access | **No.** No in-app browser, no arbitrary URLs. |
| User-generated content | No public feed. Circle membership is invite-only. |
| Age of users | Adults. Terms require 17+; listing is **18+**. |
| Kids / parental controls / family locator | **No.** Not a child tracker. No Family Sharing. |
| Gambling, alcohol, drugs, sexual content, violence, horror | None. |
| Frequent/intense mature themes | None as entertainment. The 18+ override is **precise location sharing among adults**, not mature media. |
| Made for Kids | **No.** |

Override reason (if ASC asks why 18+ when the questionnaire would land lower):

```
Trust Circle shares precise location with named adult peers the user invited. A Look is confirm-first and sends the subject a receipt. This is an adult product (18+), not a family or child locator. The app does not provide unrestricted web access.
```

---

## 3. App Privacy labels

**Data used to track you:** No  
**Tracking:** No (`NSPrivacyTracking` = false; no tracking domains; no ATT)

Republish the nutrition label to match 1.0. Declare **only** these types. Drop **Name** (identity is the `@handle`; we do not ask for a name) and **battery** (not an ASC data type; 1.0 does not show battery).

| Type | Linked to user | Used for tracking | Purpose | What it is |
| --- | --- | --- | --- | --- |
| **Precise Location** | Yes | No | App Functionality | Escrowed GPS while an outbound share ≠ Off. Revealed to a named peer only after a confirmed Look, or live while Always / For a while. |
| **Coarse Location** | Yes | No | App Functionality | Sealed tier uses hundred-meters / significant-change. Also used for “miles from you” on View / Map. |
| **User ID** | Yes | No | App Functionality | Sign in with Apple `sub` / account id, plus the unique handle. |
| **Purchases** | Yes | No | App Functionality | Trust Plus StoreKit entitlement (`Purchase History` in the privacy manifest). |
| **Product Interaction** | Yes | No | App Functionality | Looks, views, and share-mode settings (view log). |

**Not collected:** email (not required), phone, contacts, browsing history, search history, advertising data, Name (not asked), battery as a product field.

Do not sell location. No ads. Family Sharing off.

The shipped `Resources/PrivacyInfo.xcprivacy` matches this list.

---

## 4. Review notes (paste)

```
REVIEW ACCOUNT
Sign in with Apple on a fresh account. No demo password.

SEEDED CIRCLE (only while Trust__SeedReviewCircle is true on production)
A new empty account is seeded with three people so Look and View work on one device:
• Alex — Sealed (Until they look) both ways. Use Look.
• Jordan — Always both ways. Use View. No Look sheet, no push.
• Riley — For a while (timed Available), Hidden presence (chip withheld from Circle).
One prior Look (you → Alex) is already in You → View log.

LOOK vs VIEW
1. Circle → Alex → Look. The sheet leads with “Alex will be notified.” Confirm. You get one snapshot, not a live feed. Alex’s share stays Sealed. A receipt is sent (APNs). The event appears in both view logs as a Look.
2. Circle → Jordan → View. No confirm sheet. Live location while Jordan is Available. The view is logged. Jordan does not get a push.

BACKGROUND LOCATION
While Using is enough for Map / View “miles from you.”
Always is requested only after the first outbound share that is not Off (Sharing → Until they look / Always / For a while). Login does not ask for Always.
Background updates run only while Always is granted AND at least one outbound share ≠ Off. The blue Dynamic Island navigation pill stays off. Sealed uses coarse + significant-change. Available uses finer updates.
Purpose strings are in the binary (While Using / Always). We do not sell location.

UNLOCK PLUS FOR REVIEW
You → Trust Plus card → “Unlock Plus for review” (visible only while StoreKit__AllowReviewUnlock is true).
That grants Plus on the server: Always / For a while unlock, 20 seats, circle map, year of view log.
Looking, receipts, Home/Away/Hidden, Stop, Invite, and Delete are never paywalled.
If IAP metadata is already Ready to Submit, you can also use the real Plus monthly/annual ($7.99 / $69.99, 7-day trial) via Sandbox. Product IDs: com.collapsetechnologies.trust.circle.monthly and .annual. Family Sharing is off. Restore, Terms, and Privacy are on the paywall (Guideline 3.1.2).

DELETE ACCOUNT (5.1.1(v))
You → Delete account → confirm. Calls DELETE /account. Also described at https://jointrust.app/support

SUPPORT / PRIVACY / TERMS
https://jointrust.app/support
https://jointrust.app/privacy
https://jointrust.app/terms
```

---

## 5. IAP display rename checklist

Product **IDs stay unchanged.** Only display names / localizations change in ASC.

Subscription group **22346972**:

| Field | Set to | Do not change |
| --- | --- | --- |
| Group display name (en-US) | **Trust Plus** | Group ID `22346972` |
| Group reference name | Trust Plus | |
| Monthly product ID | | `com.collapsetechnologies.trust.circle.monthly` |
| Monthly display name (en-US) | **Plus Monthly** | |
| Monthly description | Trust Plus monthly. Up to 20 people, Always and For a while, full view log, circle map. | |
| Monthly price / intro | $7.99 / month · 7-day free trial · not family-shareable | |
| Annual product ID | | `com.collapsetechnologies.trust.circle.annual` |
| Annual display name (en-US) | **Plus Annual** | |
| Annual description | Trust Plus annual. Up to 20 people, Always and For a while, full view log, circle map. | |
| Annual price / intro | $69.99 / year · 7-day free trial · not family-shareable | |

ASC click-path: **Apps → Trust Circle → Subscriptions → [group] → Localization / Product localization.**

Local `Resources/Trust.storekit` already uses these display strings for the Simulator UX loop. After ASC save, optionally re-sync the StoreKit configuration (Xcode → New StoreKit Configuration → Sync with App Store Connect) so L1 matches ASC. IDs must still be the two `circle.*` products.

Both products must be **Ready to Submit** (localizations, price, review screenshot if ASC still asks) and the Paid Apps agreement **Active**, or `Product.products(for:)` is empty in review too.

**Submit the app version and the subscription group in the same submission.**

---

## 6. Screenshots — shot list

Required sizes: **iPhone 6.9"** (1320×2868 portrait) and **iPad 13"** (2064×2752 portrait). Optional 6.5" set is not required for 1.0 if 6.9" is present.

Use the DEBUG offline fixture (`See the app` or `TRUST_DEMO=1`). Do **not** upload the pre-M2 files in `AppStore/Screenshots/iphone-67-*`, `ipad-13-*.png`, or `asc-65/` — those are the old map-first UI.

Fixture (`DemoTrustService.startLeanDemo()`): Maya Sealed (Look), Leo Available (View), Jules timed, plus Inês / Eli / Noah Hidden. You are Alex Laurent, Free. View log has prior Look/View rows.

| # | Shot | `TRUST_SCREENSHOT` | What to show |
| --- | --- | --- | --- |
| 1 | **People** | `circle` | Map + draggable sheet. SHARED WITH YOU list. Maya **Look**, Leo **View**. No `+`, no counters. |
| 2 | **Look** | `look` | Confirm sheet on Maya: “Maya will be notified.” then one snapshot — not a live feed. |
| 3 | **View** | `view` | D1 on Leo: live, receipt/log line, muted one-pin map. No confirm sheet. |
| 4 | **Sharing** | `share` | Per-person Until / Always / For a while + Stop. Plus lock on Always / timed (Free fixture). |
| 5 | **You** | `you` | Presence triad, Plus card, view-log preview, Stop all / Sign out / Delete. |
| 6 | **Map** | `map` | Available + opened snapshots only. Sealed people are not pins. |
| 7 | **Invite** | `invite` | “I trust you with my location.” Code + share link. |

ASC allows fewer than 10 per locale. Upload **1–7 in that order** for iPhone 6.9" and again for iPad 13". iPad shots: portrait, readable width (list columns stay centered).

### Capture (sim + env)

Script (creates named sims if missing, builds Debug, sets 9:41 status bar, writes PNGs):

```bash
cd apps/trust-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash AppStore/capture-m6-screenshots.sh
```

Already captured (Debug fixture, 9:41 status bar on iPhone; iPad may still show the real weekday in the status bar — re-run `simctl status_bar override` if you want that tighter):

- `AppStore/Screenshots/m6/iphone-69/{circle,look,view,share,you,map,invite}.png` — 1320×2868
- `AppStore/Screenshots/m6/ipad-13/{circle,look,view,share,you,map,invite}.png` — 2064×2752

Spot-check before upload. First iPad launch can land on Login while `/health/live` probes; the script waits 6s. Grant location after install (`simctl privacy grant location` / `location-always`) so Map/View stay sheet-free.

Manual equivalent:

```bash
# Once per device (6.9" = iPhone 17 Pro Max; 13" = iPad Pro 13-inch M5)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl create "Trust ASC 6.9" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcrun simctl boot "$UDID"
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100
xcrun simctl privacy "$UDID" grant location com.collapsetechnologies.trust
xcrun simctl privacy "$UDID" grant location-always com.collapsetechnologies.trust

# Build + install (from apps/trust-ios)
xcodebuild -project Trust.xcodeproj -scheme Trust \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/DerivedDataM6 build
xcrun simctl install "$UDID" \
  build/DerivedDataM6/Build/Products/Debug-iphonesimulator/Trust.app

for shot in circle look view share you map invite; do
  xcrun simctl terminate "$UDID" com.collapsetechnologies.trust || true
  SIMCTL_CHILD_TRUST_DEMO=1 SIMCTL_CHILD_TRUST_SCREENSHOT=$shot \
    xcrun simctl launch "$UDID" com.collapsetechnologies.trust
  sleep 4
  xcrun simctl io "$UDID" screenshot "AppStore/Screenshots/m6/iphone-69/${shot}.png"
done
```

Repeat with an iPad Pro 13-inch simulator into `m6/ipad-13/`. Grant location before `map` / `view` so permission sheets do not cover the UI. `TRUST_SCREENSHOT` skips the notification prompt.

---

## 7. Submit order

1. Listing, age rating, privacy labels, screenshots, and IAP display names saved in ASC.
2. Archive **Trust** Release, upload build **6+** (Transporter / Organizer). Export compliance: **No** (non-exempt encryption).
3. Attach the build to version 1.0. Paste [review notes](#4-review-notes-paste).
4. On each Plus product: Ready to Submit. Select the subscription group on the app version.
5. **Submit the app and the subscription group together** (one review).
6. **Then** — and only then — flip production review flags (Render `trust-api`):
   - `Trust__SeedReviewCircle=true`
   - `StoreKit__AllowReviewUnlock=true`
7. After Approve or Reject, set both back to **`false`**. Leaving them on seeds Alex/Jordan/Riley into every new empty account and hands Plus to anyone who taps Unlock.

Do **not** flip those flags to take screenshots or to “test review.” Screenshots use the DEBUG fixture. TestFlight already proved the loop with flags off.

---

## Juan’s remaining click-path

Nothing below is done by this prep. Agent does not have ASC / Render production access and must not submit or flip flags.

1. **ASC → Trust Circle → App Information** — paste name, subtitle, support / marketing / privacy URLs, primary Lifestyle + secondary Social Networking, copyright, 18+ notes.
2. **ASC → 1.0 version** — paste description + keywords. Upload `AppStore/Screenshots/m6/iphone-69/` then `m6/ipad-13/` (Circle → Look → View → Sharing → You → Map → Invite). If `m6/` is empty, run `AppStore/capture-m6-screenshots.sh` or the simctl block above, then spot-check before upload. Discard `iphone-67-*` / old `ipad-13-*.png` / `asc-65/`.
3. **ASC → App Privacy** — republish: no tracking; Precise Location, Coarse Location, User ID, Purchases, Product Interaction; all linked, App Functionality; drop Name and battery.
4. **ASC → Subscriptions → group 22346972** — rename group **Trust Plus**; monthly **Plus Monthly**; annual **Plus Annual**. IDs unchanged. Confirm prices, 7-day trial, Family Sharing off, both **Ready to Submit**.
5. **Xcode Organizer** — archive `Trust` Release, distribute to App Store Connect (build 6+). Wait for processing.
6. **ASC → 1.0** — select the build. Paste [review notes](#4-review-notes-paste). Add the subscription group to the version.
7. **Submit for Review** — app + subscription group **together**.
8. **Render → trust-api env** — *after* submit, set `Trust__SeedReviewCircle=true` and `StoreKit__AllowReviewUnlock=true`. After the review decision, set both back to `false`.
9. Optional: re-sync `Trust.storekit` from ASC so Simulator strings match the renamed Plus group.
