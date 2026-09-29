# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Current evidence — 2026-09-29

Stable Xcode 27.0 produced version 1.0 build 34 from the current source. The archive is `/tmp/Trust-1.0-34-AppStore-20260929.xcarchive`; the App Store export is `/tmp/Trust-1.0-34-AppStore-Export-20260929/Trust.ipa`. The IPA is signed by Apple Distribution team `3S529795M9`, has production APNs and `get-task-allow=false`, and has phone-verification bypass disabled. Its production API URL is `https://trust-api-u0ft.onrender.com`. It has not been uploaded. App Store Connect's 1.0 draft still selects build 27. The English (U.S.) name, subtitle, description, promotional text, keywords, and URLs were updated and re-read through Apple's API; categories, reviewer access, and release settings still need review. Its English (U.S.) iPhone 6.9, iPhone 6.5, and iPad 13 screenshot sets now contain six current images each, ordered 01–06 and confirmed `COMPLETE` at the target dimensions. No build selection or submission state was changed. The remaining internal App Store group automatically receives all builds, so the reviewed backend must be deployed and protected routes verified before build upload. Public release remains NO-GO pending that and the remaining review gates. Swift tests passed 77/77 and API tests passed 183/183. See [the release decision](../../../docs/STATUS.md).

## Required before submission

- [x] Build the current-source archive and App Store distribution export with stable Xcode 27.0; verify version 1.0 (34), Apple Distribution team 3S529795M9, production APNs, `get-task-allow=false`, production API URL, and that the phone-verification bypass is disabled. The local archive and exported IPA paths and signature evidence are recorded above.
- [ ] After backend deployment and protected-route verification, upload the reviewed build, wait for processing, select that exact build for the app version, and confirm submission state in App Store Connect. The sole remaining internal group, Trust Family Auto, auto-receives every uploaded build.
- [ ] Complete listing name, subtitle, description, keywords, categories, support/marketing/privacy URLs, reviewer contact, release timing, territory availability, and platform compatibility.
- [x] Upload current English (U.S.) screenshots to the iPhone 6.9, iPhone 6.5, and iPad 13 sets; verify six ordered `COMPLETE` assets at each target size. Recheck visible content against the exact selected release candidate before submission.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity/email, and profile photos.
- [ ] Choose and align the age policy across the app, Terms, Privacy, listing, and age rating.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Confirm reviewer sign-in works through the intended ordinary flow. Keep development sign-in, seeded review data, and review-unlock flags disabled in production.
- [ ] Reconcile the app's Send code consent with the registered Twilio campaign and public SMS evidence. Verify HELP/STOP handling and durable consent records.
- [ ] Finish physical two-account TestFlight checks for onboarding, invitations, sharing/revocation, background location, StoreKit, account deletion, and APNs presentation/tap behavior.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [App Store copy draft](LISTING-COPY.md) — unapproved; verify every claim before use
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
