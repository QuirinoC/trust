# Trust Circle 1.0 — App Store Connect paste (M6)

**Current prep record.** This is a working copy sheet, not a submission approval. App Store Connect is still in **Prepare for Submission** and the review-readiness blockers are tracked in [REVIEW-READINESS.md](REVIEW-READINESS.md). Production `Trust__SeedReviewCircle` and `StoreKit__AllowReviewUnlock` remain disabled; the review path must not depend on seeded partners or a review bypass.

**Current local checks:** API 106/106, Swift core 26/26, Duo UI 4/4, and web 3/3 passed for the redesign. M6 iPhone/iPad screenshots were refreshed from the final build 22 source on 2026-09-24; they have not been uploaded to ASC. The redesigned source is on this branch and not yet deployed. These checks do not establish App Review readiness.

**Current ASC blockers:** Attempting Add for Review rejected version 1.0 because selected build 21 was made with Xcode 27.1 beta (27A9269); Apple requires a release archive/build from stable public Xcode 27 (27A266a). Only the beta is installed at `/Applications/Xcode.app`. Current source is version 1.0 build 22, intended for internal TestFlight; it can be archived with the installed beta. The App Review draft contains the Trust Plus group, Plus Monthly, and Plus Annual; all three show **Ready for Review**, but none has been submitted. The app version could not join the draft. The $0.00 Free base price is saved with US as base territory and `AUTO_FREE` in 175 countries/regions; App Availability is unset pending the owner's US-only vs. all-175 choice. Apple silicon Mac and Apple Vision Pro availability are checked by default, but compatibility has not been verified. Paid Apps agreement status is unverified: the Business page returned a generic load error and a reload redirected to sign-in.

| | |
| --- | --- |
| Workspace | `collapse-tech` (`main`) |
| Bundle | `com.collapsetechnologies.trust` |
| Team | `3S529795M9` |
| ASC App ID | `6806879060` |
| IAP group | `22346972` |
| Version / build | ASC version 1.0 remains **Prepare for Submission** and currently selects build **21**, the older pre-redesign TestFlight build, **Ready to Submit** in the existing internal **iPhone Juan** group. Current local source is version 1.0 build **22**, intended for internal TestFlight; it has not been archived or uploaded. Nothing has been submitted. Archive the **`Trust`** scheme (Release), not `Trust-Sandbox`. |
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

ASC uniqueness: exact `Trust Circle` may already be taken. If the name field rejects, use `Trust Circle.` (trailing period). The installed app display name is **Trust** (`CFBundleDisplayName`). The App Store listing name may separately be **Trust Circle**.

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

A confirmed Look requests one current-location snapshot for the requester and leaves the relationship Sealed; it does not make location history available. People who choose Always or For a while can be viewed while that sharing mode is active, with views recorded in Activity.

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

Live pricing state: base price **$0.00 (Free)**, base territory **United States**, saved in ASC. The schedule displays `AUTO_FREE` in 175 countries/regions. App Availability remains unset; choose US-only or all 175 before submission. Apple silicon Mac and Apple Vision Pro availability are checked by default; compatibility is unverified and should be included in the launch-scope decision.

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

Live ASC currently declares **Name** and **Device ID**, but omits **Coarse Location**. Source review found Coarse Location is collected in Sealed and declared in the privacy manifest. Device ID appears only in DEBUG/unused Google helper code, not release Sign in with Apple. The server transiently reads the Apple identity token's email claim; ASC includes Email while the manifest omits it. Reconcile ASC answers, manifest, and shipped release behavior before submission; the list below is a draft, not a final determination. The account also requires a verified phone number. Drop **battery** (not an ASC data type; 1.0 does not show battery).

| Type | Linked to user | Used for tracking | Purpose | What it is |
| --- | --- | --- | --- | --- |
| **Precise Location** | Yes | No | App Functionality | Escrowed GPS while an outbound share ≠ Off. Revealed to a named peer only after a confirmed Look, or live while Always / For a while. |
| **Coarse Location** | Yes | No | App Functionality | Sealed tier uses hundred-meters / significant-change. Also used for “miles from you” on View / Map. Confirm its disclosure in ASC. |
| **User ID** | Yes | No | App Functionality | Sign in with Apple `sub` / account id, plus the unique handle. |
| **Name** | Yes | No | App Functionality | Apple full name, used as the account display name and sent to the API. |
| **Email** | Yes | No | App Functionality | Apple identity token email claim is read transiently by the server. Confirm the applicable disclosure and retention answers against implementation. |
| **Phone Number** | Yes | No | App Functionality | Required for account verification and SMS login/account security. |
| **Purchases** | Yes | No | App Functionality | Trust Plus StoreKit entitlement (`Purchase History` in the privacy manifest). |
| **Product Interaction** | Yes | No | App Functionality | Looks, views, and share-mode settings (view log). |

**Not collected:** contacts, browsing history, search history, advertising data, battery as a product field. Email is not a separate stored account field; verify the final App Privacy answers against the shipped sign-in scopes and actual data handling before submitting.

Do not sell location. No ads. Family Sharing off.

The shipped `Resources/PrivacyInfo.xcprivacy` declares Name and Purchases among collected data types. Compare the final table to live ASC's current Name/Device ID selections and reconcile Coarse Location and Email before submission. See [review readiness](REVIEW-READINESS.md).

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
For a Sealed relationship, open the person's page and confirm Look. The app requests a notification for the recipient and returns one current-location snapshot to the requester. Push delivery is best-effort and not guaranteed. Sealed stays Sealed; it does not grant location history. History is available only while the person has chosen Always. When Always is enabled, View shows current location without the Look confirmation and records a receipt in Activity. API acceptance does not confirm device delivery.

PLUS AND ACCOUNT CONTROLS
Trust Plus is available through the in-app subscription purchase and Restore flow under You → See Plus → Restore Subscription; use the App Store sandbox for purchase testing. Monthly and annual review notes were corrected and saved in ASC to reflect this path and the current products and terms. The App Review draft contains the subscription group and both products, all **Ready for Review**. Nothing has been submitted. Account deletion is under You → Delete account.

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

Confirm each product's localization, price, and review screenshot if ASC still asks. Paid Apps agreement status is currently **unverified**: the Business page returned a generic load error and a reload redirected to sign-in; this does not establish whether the agreement is active. The App Review draft contains the group and both products; all three show **Ready for Review**, and none has been submitted.

**Submit the app version and the subscription group in the same submission.**

---

## 6. Screenshots — shot list

Required sizes: **iPhone 6.9"** (1320×2868 portrait) and **iPad 13"** (2064×2752 portrait). Optional 6.5" set is not required for 1.0 if 6.9" is present.

Use the DEBUG offline fixture (`See the app` or `TRUST_DEMO=1`). Do **not** upload the pre-M2 files in `AppStore/Screenshots/iphone-67-*`, `ipad-13-*.png`, or `asc-65/` — those are the old map-first UI.

Fixture (`DemoTrustService.startLeanDemo()`): five people. Maya Chen is Home with Sealed sharing and a Look action; Leo Park is Away, shares Always with you, and is Sealed in your direction; Jules Morgan is on Pause; Eli Brooks is Hidden; Noah Wilson is Off. This is a DEBUG offline fixture, not live account data.

| # | Shot | `TRUST_SCREENSHOT` | What to show |
| --- | --- | --- | --- |
| 1 | **People** | `circle` | People screen with map behind the sheet and five fixture rows: Maya (Home / Look), Leo (Away / View), Jules (Pause), Eli (Hidden), Noah (Off). |
| 2 | **Look** | `look` | Confirmation for one snapshot of Maya's current place; explains that Trust records the Look and a notification may be delivered. |
| 3 | **View** | `view` | Leo's detail screen shows Away, Always shared with you, Sealed in your direction, and the map with the location-view action. |
| 4 | **Sharing** | `share` | Five per-person sharing rows. Maya and Leo show Sealed selected; Always is locked for the Free fixture. Jules is paused, Eli Hidden, and Noah not sharing. |
| 5 | **You** | `you` | Your profile and Home/Away/Hidden controls, precise-location status, Plus card, account, sign-out, and delete controls. |
| 6 | **Map** | `map` | Map route with the Maya snapshot card and a count of one on map / four not shown. |
| 7 | **Invite** | `invite` | Invite screen with a phone number field, Create invite link action, and invite-code entry/join section. |

ASC allows fewer than 10 per locale. Upload **1–7 in that order** for iPhone 6.9" and again for iPad 13". iPad shots: portrait, readable width (list columns stay centered).

### Capture (sim + env)

Script (builds Debug, creates and deletes one temporary simulator at a time, sets 9:41 status bar, writes PNGs):

```bash
cd apps/trust-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash AppStore/capture-m6-screenshots.sh
```

The current tracked M6 capture sets were refreshed from the final build 22 source on 2026-09-24. The seven-route iPhone 6.9-inch and iPad 13-inch sets are **not uploaded to ASC**. These are DEBUG offline-fixture screenshots, not live account testing.

- `AppStore/Screenshots/m6/iphone-69/{circle,look,view,share,you,map,invite}.png` — 1320×2868
- `AppStore/Screenshots/m6/ipad-13/{circle,look,view,share,you,map,invite}.png` — 2064×2752

The capture script builds once, then creates one temporary simulator at a time, captures iPhone 6.9-inch (iPhone 17 Pro Max) and iPad 13-inch (iPad Pro 13-inch M5), and deletes each simulator when done. It refuses to run while any simulator is booted; it does not reuse old/manual leftover simulators. It grants location and writes seven routes per device. The current 14 images have passed visual review; they are ready for ASC upload.

The script is the maintained capture path. It owns temporary simulator creation and cleanup; keep its one-simulator-at-a-time behavior and the two device sizes above. It grants location and `TRUST_SCREENSHOT` skips the notification prompt.

---

## 7. Current release state

Build 21 is selected on version 1.0 and remains the older internal TestFlight build. The current local source is build 22, intended for internal TestFlight with installed Xcode 27.1 beta; it has not been archived or uploaded. For App Review, ASC requires a new release archive/build from stable public Xcode 27 (27A266a). The M6 screenshots were refreshed from build 22 and are pending ASC upload. The draft already contains the Trust Plus group, Plus Monthly, and Plus Annual, all **Ready for Review**; none has been submitted. The $0.00 Free base price is saved; App Availability is unset pending the owner's US-only or all-175-region choice. Mac and Vision Pro availability are checked by default, but compatibility is unverified. Paid Apps agreement status is unverified because ASC's Business page failed to load and then redirected to sign-in. Keep production `Trust__SeedReviewCircle` and `StoreKit__AllowReviewUnlock` set to **`false`**.

---

## Juan’s remaining click-path

Use this checklist for the remaining ASC work. Never enable production seed or review-bypass flags for submission or review.

1. **ASC → Trust Circle → App Information** — paste name, subtitle, support / marketing / privacy URLs, primary Lifestyle + secondary Social Networking, copyright, 18+ notes.
2. **ASC → 1.0 version** — paste description + keywords. Upload the refreshed build 22 seven-route sets from `m6/iphone-69/` and `m6/ipad-13/`, in this order: People → Look → View → Sharing → You → Map → Invite. These are DEBUG offline-fixture screenshots, not live account tests. Discard `iphone-67-*` / old `ipad-13-*.png` / `asc-65/`.
3. **ASC → App Privacy** — republish with no tracking and accurate collected data, including required Phone Number; use the table above as a draft and confirm it against the submitted binary and actual data handling. Drop battery as a product field.
4. **ASC → TestFlight** — build 21 is the older pre-redesign build. Archive and upload local build 22 with installed Xcode 27.1 beta for internal testing, then install it for physical-device checks.
5. **Xcode / ASC → 1.0** — after stable Xcode 27 (27A266a) is available, make and upload a release build for App Review, then select it on version 1.0. ASC rejected beta-built build 21 for App Review.
6. **ASC → App Review draft** — choose App Availability (US-only or all 175 regions; currently unset), then add version 1.0 to the draft containing the Trust Plus group and both products. Paste [review notes](#4-review-notes-paste). Confirm Paid Apps agreement status when ASC is available; it is currently unverified. Nothing has been submitted.
7. Verify the Production and Sandbox App Store Server Notifications V2 URLs both use `https://trust-api-u0ft.onrender.com/api/v1/storekit/notifications`. This configuration is recorded as verified, but end-to-end signed notification delivery/processing is not.
8. Keep production review flags false. Optional: re-sync `Trust.storekit` from ASC so Simulator strings match the renamed Plus group.
