# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Current evidence — 2026-09-30 3:43 PM PDT

App Store Connect shows internal group `Trust Family Auto` with three testers and Automatic for Xcode Builds enabled. Build 40 is available in the group with status `Testing`, and one tester is listed as installed on it. The last known feedback is build 35 on iPhone 16 Pro/iOS 27.0: “We can’t complete the required check.” Retry that flow on build 40 using the same phone.

The avatar, legal-page, test, and documentation changes are merged to `main` at `140b338af756a6b4c99e0f593a617763666415f6` by PR #16. PR CI [`36722169451`](https://github.com/QuirinoC/trust/actions/runs/36722169451) passed API, iOS simulator, and web jobs. Latest CI [`36784102036`](https://github.com/QuirinoC/trust/actions/runs/36784102036) passed all three jobs. Local validation passed iOS core tests 82/82 and the focused dark-appearance UI test 1/1.

Version 1.0 build 40 is configured in `project.yml` and the generated Xcode project. Stable Xcode 27.0 archived and exported `/tmp/Trust-1.0-40-AppStore.xcarchive` and `/tmp/Trust-1.0-40-AppStore-Export/Trust.ipa`. IPA SHA-256: `29b1d569fe15ef04a178a5587d883ed891c9f77c086aec6104e28286b54d5129`. Audit confirms production API, phone-verification bypass off, Apple Distribution team `3S529795M9`, production APNs, Declared Age Range entitlement, and `get-task-allow=false`. Xcode uploaded it on 2026-09-30; App Store Connect lists it as `Testing` in `Trust Family Auto`.

The published App Privacy label remains unchanged. Contacts and Photos or Videos are selected in the App Store Connect edit flow. The Photos or Videos wizard is configured as App Functionality, linked to identity, and not used for tracking; it is sitting at its final Publish step and has not been published. Contacts still needs its setup completed. Build 40's embedded privacy manifest declares Contacts and Photos or Videos as linked, used for App Functionality, and not tracked. Trust uploads and stores user-selected profile photos, so retain that category.

Render `trust-api` is live on commit `de977df9879429582b73776a66dd88e4d952dc52`; `/health/live` and `/health/ready` returned 200 at the app's configured host. PR #16 has no API or database change and needed no redeploy/migration. Cloudflare Worker `jointrust-web` version `70b84345-28e2-401a-94f1-f03f79a2f0c0` was deployed after the merge; live checks confirmed the current `/terms` and `/sms` disclaimer and date. `/privacy` and `/support` are reachable.

The English (U.S.) listing has build 40 selected, the current icon, revised notification language, name `Trust: Location Sharing`, subtitle `See who checked your location`, keywords, support URL, and marketing URL. The version uses Social Networking as its primary category and Lifestyle as secondary. Its release setting is manual. The current 6.5-inch screenshot set has six images; prior App Store Connect observations recorded six ordered screenshots for the iPhone 6.9-inch and iPad 13-inch groups as well. Recheck all images against the release build at storefront scale. App Review notes were saved with the legacy subscription product IDs removed and the plan described as Trust Plus. The current age rating is 4+; the previous 18+ override was cleared and the saved result verified after navigating away. Counsel still needs to classify the intended audience and launch territories. Subscription product review status, paid agreements, reviewer access, App Privacy publication, and territory/price availability still need final review. No public App Review submission has been made.

The age-gate simulator suite uses fixtures and does not call Apple's live service. Retest the required-check flow on the same iPhone 16 Pro using normal Apple sign-in, age assurance, and App Transaction registration. Twilio campaign alignment, physical notification/background-location behavior, purchase/restore, and the full reviewer journey still need evidence. See [project status](../../../docs/STATUS.md) and [two-account E2E evidence](../../../docs/LOCAL-TWO-ACCOUNT-E2E.md).

## Required before submission

- [x] Build the earlier version 1.0 (36) archive and App Store distribution export with stable Xcode 27.0; verify Apple Distribution team 3S529795M9, production APNs, `get-task-allow=false`, production API URL, and that the phone-verification bypass is disabled. Build 36 passed Apple validation/upload at that earlier checkpoint; it is historical evidence and is not the selected release build.
- [x] Increment to build 40 and archive/export the current release app source with `ExportOptions-AppStore.plist`; verify Apple Distribution signing, production APNs, Declared Age Range entitlement, `get-task-allow=false`, production API URL, and `TRUST_SKIP_PHONE_VERIFICATION=false`. See the audited build 40 archive and IPA paths above.
- [x] Merge the current source and deploy the backend. The active API is on `de977df`; `/health/ready` and current legal/SMS routes returned 200. The latest app-only change needs no API redeploy or migration.
- [ ] Recheck the full listing and availability configuration before submission. The current observation confirms the name, revised description, support/marketing/privacy URLs, current icon, build 40, screenshots, and manual release; verify subtitle, keywords, categories, age rating, reviewer access/instructions, territories, price, and platform support.
- [x] Verify six ordered screenshots in each App Store Connect iPhone 6.9-inch, iPhone 6.5-inch, and iPad 13-inch group. One 6.5-inch image matches the local source; visually recheck all six against the final release candidate before submission.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity, connection social graph, installation/device identifiers, and profile photos. Finish Contacts setup, review the exact resulting label, then publish it.
- [x] Clear the unsupported 18+ App Store rating override; verify the saved calculated 4+ rating. Runtime Apple age assurance remains conditional on Apple signals.
- [ ] Have counsel classify Trust's intended audience and validate COPPA and launch-territory obligations, then align Terms, Privacy, and territory availability. A 4+ App Store rating is not a legal audience classification.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Provide and verify an active demo account or a complete demo experience for App Review, with access to the connected-person and paid flows. Normal Apple sign-in instructions alone have not established that access. Keep development sign-in, seeded review data, and review-unlock flags disabled in production. Apple’s [review guidance, Before You Submit and 2.1](https://developer.apple.com/app-store/review/guidelines/) requires full access and describes approval for a demo mode when legal or security constraints prevent a demo account.
- [ ] Reconcile the shipped Send code disclosure with the registered Twilio campaign and public SMS evidence. Consent-event persistence and privacy disclosure are implemented/deployed; verify the campaign's current opt-in method and HELP/STOP behavior.
- [x] Upload audited build 40 and confirm it appears as Testing in `Trust Family Auto`.
- [ ] Retry build 35's required-check failure on the same iPhone using build 40, normal Apple sign-in, and registration.
- [ ] Verify the full reviewer journey without development or entitlement bypasses: onboarding, adding/accepting a person, consented sharing, Stop/remove, purchase/restore, and account deletion.

## Before manual public availability

Keep the release manual until physical TestFlight checks confirm background location, APNs permission/presentation/taps, offline reconnect, same-account second-device behavior, paid History/revocation, and subscription renewal/expiry/refund/restore. Confirm support and incident ownership, delivered alerts, backups/recovery, and a deliberate verification-SMS capacity limit. Resolve any observed privacy or entitlement defect before release.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [Current App Store copy draft](LISTING-COPY.md) — the English (U.S.) draft description now uses the qualified notification wording; version 1.0 remains unsubmitted
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
