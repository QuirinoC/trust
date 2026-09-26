# App Store listing and review copy — draft

This preserves useful draft copy from the retired App Store preparation notes. It is not evidence of current App Store Connect state and is not approved for submission. Verify all claims against the current app, legal pages, privacy manifest, and live App Store Connect fields before use. The 18+ age-policy text remains unresolved.

## 1. Listing (App Information + Version)

Copy each field into App Store Connect.

### Name

```
Trust: Close by Choice
```

App Information name was changed and saved as **Trust: Close by Choice**. The installed app display name remains **Trust** (`CFBundleDisplayName`). The version 1.0 header still shows the prior name until the next version takes effect.

### Subtitle (30)

```
Close by choice
```

### Promotional text (optional, 170)

```
Sealed until Look. Available when you choose. Adult-peer location escrow — not a live tracker.
```

### Description

```
Trust lets adults share location by choice with trusted peers. Sharing starts Off in both directions after an invitation is accepted.

A confirmed Look requests one current-location snapshot for the requester and leaves the relationship Sealed; it does not make location history available. People who choose Always can be viewed while that sharing mode is active, with views recorded in Activity.

Join starts Off both ways. An invite is not permission. Presence is Home, Away, or Hidden — free, manual, and Hidden never reaches the circle.

Free includes up to 5 people, Off and Sealed sharing, confirmed Looks with a single location snapshot, View when someone is Available, and 30 days of Activity history.

Trust Plus is $7.99/month or $69.99/year, with a 7-day trial. Plus adds up to 20 people, Always sharing, the circle map, and a year of view log with export. Looking is not paywalled. Family Sharing is off. No ads. We do not sell location.

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

## 2. Age rating — decision pending

The proposed listing is **18+**, but the live Terms and Privacy pages currently exclude only children under 13. Choose the product age policy before setting the listing rating. Precise location is shared only with a **named person the user invited**, and only after a **confirmed Look** (or while the user opted into Always).

### Questionnaire notes (do not use “unrestricted web” as the 18+ reason)

| Item | Answer / note |
| --- | --- |
| Unrestricted Web Access | **No.** No in-app browser, no arbitrary URLs. |
| User-generated content | No public feed. Circle membership is invite-only. |
| Age of users | **Unresolved:** live Terms/Privacy allow household use and exclude only children under 13; ASC draft proposes adults **18+**. Choose and align before submission. |
| Kids / parental controls / family locator | **No.** Not a child tracker. No Family Sharing. |
| Gambling, alcohol, drugs, sexual content, violence, horror | None. |
| Frequent/intense mature themes | None as entertainment. The 18+ override is **precise location sharing among adults**, not mature media. |
| Made for Kids | **No.** |

Override reason (if ASC asks why 18+ when the questionnaire would land lower):

```
Trust: Close by Choice shares precise location with named adult peers the user invited. A Look is confirm-first and sends the subject a receipt. This is an adult product (18+), not a family or child locator. The app does not provide unrestricted web access.
```

---

## 3. App Privacy labels

**Data used to track you:** No
**Tracking:** No (`NSPrivacyTracking` = false; no tracking domains; no ATT)

Live ASC currently declares **Name** and **Device ID**, but omits **Coarse Location**. Source review found Coarse Location is collected in Sealed and declared in the privacy manifest. Device ID appears only in DEBUG/unused Google helper code, not release Sign in with Apple. The server transiently reads the Apple identity token's email claim; ASC includes Email while the manifest omits it. Reconcile ASC answers, manifest, and shipped release behavior before submission; the list below is a draft, not a final determination. The account also requires a verified phone number. Battery is transmitted and stored with presence but is not shown in the 1.0 UI; reconcile its applicable App Privacy label.

| Type | Linked to user | Used for tracking | Purpose | What it is |
| --- | --- | --- | --- | --- |
| **Precise Location** | Yes | No | App Functionality | Escrowed GPS while Sealed or Always sharing is active. Revealed to a named peer only after a confirmed Look, or live while Always. |
| **Coarse Location** | Yes | No | App Functionality | Sealed tier uses hundred-meters / significant-change. Also used for “miles from you” on View / Map. Confirm its disclosure in ASC. |
| **User ID** | Yes | No | App Functionality | Sign in with Apple `sub` / account id, plus the unique handle. |
| **Name** | Yes | No | App Functionality | Apple full name, used as the account display name and sent to the API. |
| **Email** | Yes | No | App Functionality | Apple identity token email claim is read transiently by the server. Confirm the applicable disclosure and retention answers against implementation. |
| **Phone Number** | Yes | No | App Functionality | Required for account verification and SMS login/account security. |
| **Photos or Videos** | Yes | No | App Functionality | Optional profile photo selected by the user, uploaded for their account, and retrieved for display. |
| **Purchases** | Yes | No | App Functionality | Trust Plus StoreKit entitlement (`Purchase History` in the privacy manifest). |
| **Product Interaction** | Yes | No | App Functionality | Looks, views, and share-mode settings (view log). |

**Not collected:** contacts, browsing history, search history, and advertising data. Battery is transmitted and stored with presence but is not shown in the 1.0 UI; reconcile its applicable App Privacy label before submission. Email is not a separate stored account field; verify the final App Privacy answers against the shipped sign-in scopes and actual data handling before submitting.

Do not sell location. No ads. Family Sharing off.

**Age-policy blocker:** Current live Terms/Privacy allow household use and exclude only children under 13, while the ASC draft describes adults 18+. Resolve this decision and align legal pages and listing before submission.

The shipped `Resources/PrivacyInfo.xcprivacy` declares Name, Photos or Videos, and Purchases among collected data types. Compare the final table to live ASC's current Name/Device ID selections and reconcile Coarse Location, Email, and battery handling before submission. See [review readiness](REVIEW-READINESS.md).

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
