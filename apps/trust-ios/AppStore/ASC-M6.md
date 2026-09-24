# Trust Circle 1.0 — App Store Connect paste (M6)

**Current prep record.** Do not submit from this file. Production `Trust__SeedReviewCircle` and `StoreKit__AllowReviewUnlock` remain disabled; the review path must not depend on seeded partners or a review bypass.

| | |
| --- | --- |
| Workspace | `collapse-tech` (`main`) |
| Bundle | `com.collapsetechnologies.trust` |
| Team | `3S529795M9` |
| ASC App ID | `6806879060` |
| IAP group | `22346972` |
| Version / build | **1.0 (19)** is the current local target; verify the selected build in App Store Connect before upload. Archive the **`Trust`** scheme (Release), not `Trust-Sandbox`. Home IA is map + draggable People sheet (not list-first Circle). |
| Release API | `https://trust-api-u0ft.onrender.com` (ready check passed; custom host TLS remains unresolved) |
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
Trust Circle lets adults share location by choice with trusted peers. Sharing starts Off in both directions after an invitation is accepted.

A confirmed Look returns one current-location snapshot to the requester and leaves the relationship Sealed; it does not make location history available. People who choose Always or For a while can be viewed while that sharing mode is active, with views recorded in Activity.

Join starts Off both ways. An invite is not permission. Presence is Home, Away, or Hidden — free, manual, and Hidden never reaches the circle.

Free includes up to 5 people, Off and Until they look, confirmed Looks with a single location snapshot, View when someone is Available, and 30 days of Activity history.

Trust Plus is $7.99/month or $69.99/year, with a 7-day trial. Plus adds up to 20 people, Always and For a while, the circle map, and a year of view log with export. A paying member covers unpaid people on the edges they share. Looking is not paywalled. Family Sharing is off. No ads. We do not sell location.

Sign in with Apple and verify your phone number to finish setup. Delete your account in You → Delete account.
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

Republish the nutrition label to match 1.0. Declare the collected types accurately; the account requires a verified phone number. Do not omit Phone from the App Privacy label. Drop **battery** (not an ASC data type; 1.0 does not show battery).

| Type | Linked to user | Used for tracking | Purpose | What it is |
| --- | --- | --- | --- | --- |
| **Precise Location** | Yes | No | App Functionality | Escrowed GPS while an outbound share ≠ Off. Revealed to a named peer only after a confirmed Look, or live while Always / For a while. |
| **Coarse Location** | Yes | No | App Functionality | Sealed tier uses hundred-meters / significant-change. Also used for “miles from you” on View / Map. |
| **User ID** | Yes | No | App Functionality | Sign in with Apple `sub` / account id, plus the unique handle. |
| **Phone Number** | Yes | No | App Functionality | Required for account verification and SMS login/account security. |
| **Purchases** | Yes | No | App Functionality | Trust Plus StoreKit entitlement (`Purchase History` in the privacy manifest). |
| **Product Interaction** | Yes | No | App Functionality | Looks, views, and share-mode settings (view log). |

**Not collected:** contacts, browsing history, search history, advertising data, battery as a product field. Email is not a separate stored account field; verify the final App Privacy answers against the shipped sign-in scopes and actual data handling before submitting.

Do not sell location. No ads. Family Sharing off.

The shipped `Resources/PrivacyInfo.xcprivacy` matches this list.

---

## 4. Review notes (paste)

```
REVIEW ACCOUNT
Sign in with Apple using a new account. Phone verification is required to finish
onboarding. Use a phone number you can receive an SMS at and enter the verification code.
There is no demo account, seeded partner circle, or review unlock bypass. Review flags
remain disabled in production.

INVITE AND CONSENT
Create an invite from the app, then accept it from a second account. Joining creates a
connection only; sharing starts Off in both directions. Each account chooses its own
sharing mode for the other person.

SEALED LOOK AND ALWAYS VIEW
For a Sealed relationship, open the person's page and confirm Look. The recipient is
notified and the requester receives one current-location snapshot. Sealed stays Sealed;
it does not grant location history. History is available only while the person has chosen
Always. When Always is enabled, View shows current location without the Look confirmation
and is recorded in Activity. Do not interpret API or push acceptance as confirmed device
delivery.

PLUS AND ACCOUNT CONTROLS
Trust Plus is available through the in-app subscription purchase and Restore flow; use the
App Store sandbox for purchase testing. Account deletion is under You → Delete account.

SUPPORT / MARKETING / PRIVACY / TERMS
https://jointrust.app
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
2. Archive the reviewed **Trust** Release build and upload it (Transporter / Organizer). Current local target is 1.0 build **19**; verify the selected build number before upload. Export compliance: **No** (non-exempt encryption).
3. Attach the build to version 1.0. Paste [review notes](#4-review-notes-paste).
4. On each Plus product: Ready to Submit. Select the subscription group on the app version.
5. **Submit the app and the subscription group together** (one review).
6. Keep production `Trust__SeedReviewCircle` and `StoreKit__AllowReviewUnlock` set to **`false`** through submission and review. The app review path is the actual unseeded onboarding and subscription flow; it has no seeded partner or review bypass.

---

## Juan’s remaining click-path

Use this as a checklist for the release owner. Never enable production seed or review-bypass flags for submission or review.

1. **ASC → Trust Circle → App Information** — paste name, subtitle, support / marketing / privacy URLs, primary Lifestyle + secondary Social Networking, copyright, 18+ notes.
2. **ASC → 1.0 version** — paste description + keywords. Upload `AppStore/Screenshots/m6/iphone-69/` then `m6/ipad-13/` (Circle → Look → View → Sharing → You → Map → Invite). If `m6/` is empty, run `AppStore/capture-m6-screenshots.sh` or the simctl block above, then spot-check before upload. Discard `iphone-67-*` / old `ipad-13-*.png` / `asc-65/`.
3. **ASC → App Privacy** — republish with no tracking and accurate collected data, including required Phone Number; use the table above as a draft and confirm it against the submitted binary and actual data handling. Drop battery as a product field.
4. **ASC → Subscriptions → group 22346972** — rename group **Trust Plus**; monthly **Plus Monthly**; annual **Plus Annual**. IDs unchanged. Confirm prices, 7-day trial, Family Sharing off, both **Ready to Submit**.
5. **Xcode Organizer** — archive `Trust` Release, distribute to App Store Connect. Verify version/build 1.0 and the chosen build number. Wait for processing.
6. **ASC → 1.0** — select the build. Paste [review notes](#4-review-notes-paste). Add the subscription group to the version.
7. **Submit for Review** — app + subscription group **together**.
8. Verify the Production and Sandbox App Store Server Notifications V2 URLs both use `https://trust-api-u0ft.onrender.com/api/v1/storekit/notifications`. This configuration is recorded as verified, but end-to-end signed notification delivery/processing is not.
9. Keep production review flags false. Optional: re-sync `Trust.storekit` from ASC so Simulator strings match the renamed Plus group.
