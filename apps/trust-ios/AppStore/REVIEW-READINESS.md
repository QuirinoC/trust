# App Store review readiness — 1.0

**Status: not ready to submit.** This is an internal snapshot of the live App Store Connect audit and source review on 2026-09-24. Close the blockers below, then refresh this audit before submission.

**Redesign update:** PR #2 (`31db6cc`) merged the Remove-alert fix; API, iOS, and web checks passed, including hosted iOS 26 core tests and 4 UI tests. Render deployment `dep-dar1gnm0tbcc73cingv0` is live for merge commit `31db6cc`; `/health/ready` returned `200 Healthy`, and the API preset allowlist is deployed. Build 22 remains latest uploaded; ASC processing/group assignment are unverified. Build 24’s optimized archive and signature are verified, but `xcodebuild -exportArchive` validation is blocked pending Xcode App Store Connect access while the Mac is locked; build 24 is not uploaded. M6 screenshots need recapture after open-Duo and far-edge carousel visual sign-off. Privacy answers, age policy, and physical-device checks remain open. Stable public Xcode 27 is required for App Review. See [current status](../../../docs/STATUS.md).

## Live App Store Connect state

- Version 1.0 remains **Prepare for Submission** and selects build **21**, the older pre-redesign TestFlight build. Build 22 was uploaded through Organizer, but ASC processing and internal group assignment are unverified while the browser is signed out. Nothing has been submitted.
- The build 21 TestFlight “What to Test” note is saved in ASC for one internal tester. It covers phone sign-in, invite consent defaults, Off/Sealed/Always/Pause, Look receipts, People/Map/You, Plus purchase and restore in the TestFlight sandbox, and best-effort push observation with device and steps. No tester results are recorded yet.
- The listing still has seven legacy **6.5-inch** screenshots. The current M6 set has seven routes at each required size (iPhone 6.9-inch and iPad 13-inch) and reflects build 22. It uses the DEBUG offline fixture and is not live account testing. The 14 screenshots are not uploaded; recapture after visual sign-off on the build 24 feedback changes.
- The listing name is **Trust Circle** while the app display name is **Trust**. Confirm the intended customer-facing name and make the listing and app presentation consistent.
- App Review contact phone and email are empty. Populate both with monitored contact details.
- Release is set to **Automatic**. Confirm that this is the intended release setting when the version is submitted.
- A draft App Review submission contains three items: the Trust Plus subscription group, Plus Monthly, and Plus Annual. All three show **Ready for Review**. Nothing has been submitted. App version 1.0 could not be added because its selected beta-built build 21 was rejected; **Submit for Review** remains disabled. Both products' review notes were corrected and saved live in ASC, including the accurate You → See Plus → Restore Subscription path and current product/terms information.
- Attempting to add app version 1.0 failed: ASC explicitly rejects beta-built build 21 for App Review because it was made with Xcode 27.1 beta (27A9269). Apple requires a release archive/build made with stable public Xcode 27 (27A266a). Only the beta is installed at `/Applications/Xcode.app`. Build 22 can be beta-built for internal TestFlight; build 21 remains selected on version 1.0 and cannot be submitted for review.
- The app base price is saved as **$0.00 (Free)** with **US** as the base territory. ASC shows `AUTO_FREE` across 175 countries/regions. App Availability is unset; the release owner is choosing between US-only and all 175 regions. Apple silicon Mac and Apple Vision Pro availability are checked by default; compatibility has not been verified, so include those platform toggles in the launch-scope decision.
- Paid Apps agreement status is **unverified**: ASC's Business page returned a generic load error and a reload redirected to sign-in. This does not establish whether the agreement is active.
- Live App Privacy declares **Name** and **Device ID**, but omits **Coarse Location**. Source review found Coarse Location is collected in Sealed and declared in the privacy manifest. Device ID appears only in DEBUG/unused Google helper code, not release Sign in with Apple. The server transiently reads the Apple identity token email claim; live ASC includes **Email**, while the manifest omits it. Reconcile the privacy answers, manifest, and release behavior before submission; these observations do not determine the final declaration by themselves.

## Evidence and verification still needed

- Eight Duo UI captures are at `Screenshots/review-2026-09-24/duo/`. They show UI captured during a DEBUG offline-fixture run; they do not document actual live use, a production account, or a live two-account flow, and do not replace the App Store listing screenshots.
- Cloudflare version `387f20df-6ce6-46f0-bf55-5b32f1771e67` is deployed. `/`, `/privacy`, `/terms`, `/support`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned **200**. Live privacy photo content and support best-effort push wording were verified.
- PR #2 (`31db6cc`) merged the Remove-alert fix. API, iOS, and web checks passed, including hosted iOS 26 core and 4 UI tests. After the feedback changes, local verification is Duo UI **4/4**, Swift core **26/26**, and API **107/107** with local Postgres. Independent review found no issues; the closed-Duo view was checked, while open-Duo and far-end carousel visual sign-off remain. The 14 listing screenshots still reflect build 22 and are not uploaded; recapture after latest visual sign-off. None of this establishes physical account use or App Review readiness.
- Release-blocking content decision: live Terms/Privacy currently allow household use while excluding only children under 13, while the ASC draft says accounts are for adults 18+. Align the age policy, legal pages, and listing before submission. No legal-page edits are part of this checkpoint.
- Physical-device push behavior has not been verified. Push delivery is best-effort; do not promise delivery in review notes or listing text.
- StoreKit purchase and restore have not been verified end to end.
- App Store Server Notification delivery and processing have not been verified end to end.
- Twilio **HELP** and **STOP** handling have not been verified.
- Review account onboarding depends on a reachable SMS number. The review path has no seeded partner circle or production review bypass; those flags must remain disabled.

## Closeout sequence

1. Restore Xcode App Store Connect access, complete build 24 export validation and Organizer checks, and visually sign off open Duo and far-end carousel. Build 24’s optimized archive and code signature are verified; `xcodebuild -exportArchive` is blocked pending Xcode App Store Connect account access while the Mac is locked. Build 24 is not uploaded; build 22 remains latest uploaded with ASC processing/group unverified. Restore ASC sign-in to confirm its status.
2. Recapture M6 screenshots after sign-off on the latest picker changes, then upload the sets and verify the listing. Reconcile privacy answers, including optional Photos/Videos.
3. Decide the display/listing name; fill in App Review phone and email; confirm automatic release, availability, and platform scope.
4. Reconcile App Privacy and the privacy manifest against release source and actual server handling, including Coarse Location, Device ID, Email, Photos/Videos, and other declared data types.
5. Install stable public Xcode 27 (27A266a), create and upload a compliant release build for App Review, select it for version 1.0, and add the app version to the existing three-item draft. Confirm Paid Apps agreement status when ASC is available. Nothing has been submitted.
6. Resolve the age-policy mismatch between current legal pages (household use, under-13 exclusion) and the ASC draft (18+), then align legal and listing content. Complete physical push, StoreKit purchase/restore, App Store Server Notification, and HELP/STOP checks as release evidence. Keep review instructions accurate about push being best-effort.

See [ASC-M6.md](ASC-M6.md) for listing copy, draft privacy language, review notes, screenshot routes, and the maintained capture command. That file is working material; this readiness record must be clear before submission.
