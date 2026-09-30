# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Current evidence — 2026-09-30

Stable Xcode 27.0 produced version 1.0 build 35 from the reviewed source. The archive is `/tmp/Trust-1.0-35-AppStore-20260929.xcarchive`; the App Store export is `/tmp/Trust-1.0-35-AppStore-Export-20260929/Trust.ipa`. The IPA is signed by Apple Distribution team `3S529795M9`, has production APNs and `get-task-allow=false`, and has phone-verification bypass disabled. Its production API URL is `https://trust-api-u0ft.onrender.com`. Apple validation and upload completed with no errors. App Store Connect reports build 35 as `VALID`, App Store eligible, and in internal beta testing in Trust Family Auto; the 1.0 draft selects 35. Older builds are expired. Public release timing is manual. The English (U.S.) name, subtitle, description, promotional text, keywords, and URLs were updated and re-read through Apple's API; categories, reviewer access, still need review. Availability is configured for the United States only, with pre-order and automatic new territories disabled; release remains manual. Its English (U.S.) iPhone 6.9, iPhone 6.5, and iPad 13 screenshot sets now contain six current images each, ordered 01–06 and confirmed `COMPLETE` at the target dimensions. The screenshot update did not submit the app for review. The remaining internal App Store group automatically receives all builds, so the reviewed backend must be deployed and protected routes verified before build upload. The reviewed backend is live and healthy. Public release remains NO-GO pending the remaining review gates. Swift tests passed 77/77 and API tests passed 183/183. See [the release decision](../../../docs/STATUS.md).

Build 35 includes the corrected Contacts and Device ID privacy declarations. The focused unsigned age-gate checks passed 6/6. Stop, Remove, partial Stop All, and guarded Look passed 1/1 each; delayed History remains open. Runtime CI run `36648913823` completed successfully in all three jobs. The later CI run `36652720704` passed API and website but failed iOS compilation; the local compile/test fix is ready for hosted rerun.

Physical feedback received `2026-09-30T00:39:03Z` confirms build 35 installed on iOS 27.0, but shows “We can’t complete the required check.” The latest feedback remains this same screenshot; no crash submission is present. It is a release blocker. The screenshot alone cannot distinguish Apple's on-device eligibility flow from authenticated App Transaction registration. The API receipt-field correction passed 14/14 focused and 189/189 full API tests and independent review. The follow-up iOS test-helper compilation fix passed locally on Xcode 27.0: 77 core and 23 UI tests, zero failures, with 9 API-backed UI tests skipped because the isolated loopback API was not running. Hosted CI rerun is pending. Check [STATUS.md](../../../docs/STATUS.md) for deployment and physical retest evidence. Do not treat successful upload or simulator fixtures as proof of normal Apple access.

## Required before submission

- [x] Build the current-source archive and App Store distribution export with stable Xcode 27.0; verify version 1.0 (35), Apple Distribution team 3S529795M9, production APNs, `get-task-allow=false`, production API URL, and that the phone-verification bypass is disabled. The local archive and exported IPA paths and signature evidence are recorded above.
- [x] Deploy backend and verify healthy/protected routes before upload; validate/upload build 35, confirm `VALID` and internal testing, and select it for the 1.0 draft. The sole remaining internal group, Trust Family Auto, auto-receives builds. No App Review submission has been made.
- [ ] Complete listing name, subtitle, description, keywords, categories, support/marketing/privacy URLs, reviewer contact, release timing, territory availability, and platform compatibility.
- [x] Upload current English (U.S.) screenshots to the iPhone 6.9, iPhone 6.5, and iPad 13 sets; verify six ordered `COMPLETE` assets at each target size. Recheck visible content against the exact selected release candidate before submission.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity, connection social graph, installation/device identifiers, and profile photos. Build 35 packages the Contacts and Device ID manifest additions; finish Contacts and Photos setup in App Store Connect.
- [ ] Choose and align the age policy across the app, Terms, Privacy, listing, and age rating.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Provide and verify an active demo account or a complete demo experience for App Review, with access to the connected-person and paid flows. Normal Apple sign-in instructions alone have not established that access. Keep development sign-in, seeded review data, and review-unlock flags disabled in production. Apple’s [review guidance, Before You Submit and 2.1](https://developer.apple.com/app-store/review/guidelines/) requires full access and describes approval for a demo mode when legal or security constraints prevent a demo account.
- [ ] Reconcile the app's Send code consent with the registered Twilio campaign and public SMS evidence. Verify HELP/STOP handling and durable consent records.
- [ ] Finish physical two-account TestFlight checks for onboarding, invitations, sharing/revocation, background location, StoreKit, account deletion, and APNs presentation/tap behavior.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [Current App Store copy draft](LISTING-COPY.md) — applied to the English (U.S.) draft; not submitted
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
