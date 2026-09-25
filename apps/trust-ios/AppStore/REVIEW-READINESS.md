# App Store review readiness — 1.0

**Status: not ready to submit.** This is an internal snapshot of the live App Store Connect audit and source review on 2026-09-24. Close the blockers below, then refresh this audit before submission.

**Redesign update:** Build 21 is the older pre-redesign TestFlight build. The current branch is now version 1.0 build 22, intended for internal TestFlight; it has not been deployed, archived, or uploaded. The redesigned M6 iPhone/iPad screenshots were recaptured on 2026-09-24 and have not been uploaded. Xcode 27.1 beta can build the internal TestFlight build; stable public Xcode 27 is required for App Review. App Privacy update for optional Photos/Videos, legal-page deployment if needed, and physical TestFlight tests remain. See [current status](../../../docs/STATUS.md).

## Live App Store Connect state

- Version 1.0 remains **Prepare for Submission** and selects build **21**, the older pre-redesign TestFlight build. It is **Ready to Submit**, assigned to the existing internal **iPhone Juan** group, with no recorded installs, sessions, crashes, or feedback. Build 22 is the local intended internal build and has not been uploaded. Nothing has been submitted.
- The build 21 TestFlight “What to Test” note is saved in ASC for one internal tester. It covers phone sign-in, invite consent defaults, Off/Sealed/Always/Pause, Look receipts, People/Map/You, Plus purchase and restore in the TestFlight sandbox, and best-effort push observation with device and steps. No tester results are recorded yet.
- The listing still has seven legacy **6.5-inch** screenshots. The redesigned M6 capture set has seven routes at each required size (iPhone 6.9-inch and iPad 13-inch), recaptured 2026-09-24. They use the DEBUG offline fixture and are not live account tests. The 14 screenshots have not been uploaded to ASC.
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
- The public support correction is deployed (Cloudflare version `5c1d221f-4e07-4adb-9b4d-9c1844de332b`). Live `/`, `/support`, `/privacy`, `/terms`, `/sms`, `/sms-opt-in.png`, `/i/ABC234`, and `/.well-known/apple-app-site-association` returned **200**. Support describes push as best-effort and includes You restore/delete guidance. These checks establish endpoint responses, not full flow behavior.
- Verification completed locally: redesigned Duo UI **4/4**, Swift core **26/26**, API **106/106**, and web **3/3**. The redesigned 14 listing screenshots were recaptured 2026-09-24 and are not uploaded. None of this establishes physical account use or App Review readiness.
- Physical-device push behavior has not been verified. Push delivery is best-effort; do not promise delivery in review notes or listing text.
- StoreKit purchase and restore have not been verified end to end.
- App Store Server Notification delivery and processing have not been verified end to end.
- Twilio **HELP** and **STOP** handling have not been verified.
- Review account onboarding depends on a reachable SMS number. The review path has no seeded partner circle or production review bypass; those flags must remain disabled.

## Closeout sequence

1. Archive source version 1.0 build 22 with installed Xcode 27.1 beta for internal TestFlight, upload it, then complete physical-device checks. Build 21 remains the older TestFlight build.
2. Upload the redesigned M6 screenshot sets already recaptured on 2026-09-24; verify the listing shows them.
3. Decide the display/listing name; fill in App Review phone and email; confirm automatic release, availability, and platform scope.
4. Reconcile App Privacy and the privacy manifest against release source and actual server handling, including Coarse Location, Device ID, Email, Photos/Videos, and other declared data types.
5. Install stable public Xcode 27 (27A266a), create and upload a compliant release build for App Review, select it for version 1.0, and add the app version to the existing three-item draft. Confirm Paid Apps agreement status when ASC is available. Nothing has been submitted.
6. Complete physical push, StoreKit purchase/restore, App Store Server Notification, and HELP/STOP checks as release evidence. Keep review instructions accurate about push being best-effort.

See [ASC-M6.md](ASC-M6.md) for listing copy, draft privacy language, review notes, screenshot routes, and the maintained capture command. That file is working material; this readiness record must be clear before submission.
