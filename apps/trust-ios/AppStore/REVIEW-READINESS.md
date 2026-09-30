# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Current evidence — 2026-09-30 12:24 AM PDT

Version 1.0 build 36 is the latest build recorded as uploaded and `VALID` in `Trust Family Auto`. The last saved App Store Connect draft selected build 35. The latest saved TestFlight feedback is build 35 on iPhone 16 Pro/iOS 27.0: “We can’t complete the required check.” No newer observation confirms this is resolved. App Store Connect cannot be refreshed while the Mac is locked. Build 37 is an older local archive/export that lacks current branch changes. The app project is now configured as version 1.0 build 38. Build 38 has been archived/exported at `/tmp/Trust-1.0-38-AppStore-20260930.xcarchive` and `/tmp/Trust-1.0-38-AppStore-Export-20260930/Trust.ipa` (SHA-256 `5f1bfbe486cab008506c6c17e851c54ca58dff95a495dac27cfbfc35b4cb8bfd`). Export verification confirms Apple Distribution team `3S529795M9`, production APNs, Declared Age Range entitlement, `get-task-allow=false`, production API, and phone-verification bypass `false`. It has not been uploaded.

Main CI [`36677893716`](https://github.com/QuirinoC/trust/actions/runs/36677893716) is green at `5c71d58a128f73a5d5409c0d57dc0211380ab602`. The unmerged branch passes API/Postgres 202/202, Swift 81/81, age-gate simulator UI 10/10 and a separate real-API Stop All failure/retry UI run 1/1 on iPhone 17 Pro/iOS 26.5, localization validation (518 keys/five locales), and website tests 3/3. It still needs PR CI, merge, and API deployment. No database migration is required for the current backend changes. Production `/health/ready` returned 200 on the existing API; Cloudflare Worker `jointrust-web` version `f8382a78-2b17-45ba-8cad-1ec4d46dd800` serves revised Privacy, Terms, and Support pages, each returning 200.

The English (U.S.) listing copy and screenshots were previously applied, with manual release and U.S.-only availability in the last saved state. Refresh all values live; categories, reviewer access, App Privacy, age rating, agreements, subscription details/review resources, and territories are not confirmed. No public App Review submission has been made.

The age-gate simulator suite uses fixtures and does not call Apple's live service. The latest saved physical feedback remains “We can’t complete the required check”; build 38 must be tested on the same iPhone 16 Pro through normal Apple age assurance and App Transaction registration. Twilio campaign alignment, physical notification/background-location behavior, purchase/restore, and the reviewer journey also need evidence. See [project status](../../../docs/STATUS.md) and [two-account E2E evidence](../../../docs/LOCAL-TWO-ACCOUNT-E2E.md).

## Required before submission

- [x] Build the earlier version 1.0 (36) archive and App Store distribution export with stable Xcode 27.0; verify Apple Distribution team 3S529795M9, production APNs, `get-task-allow=false`, production API URL, and that the phone-verification bypass is disabled. The build-36 archive and IPA passed Apple validation/upload and are recorded as `VALID`; build 38 is the current candidate and is tracked below.
- [x] Archive/export build 38 with `ExportOptions-AppStore.plist`; verify Apple Distribution signing, production APNs, Declared Age Range entitlement, `get-task-allow=false`, production API URL, and `TRUST_SKIP_PHONE_VERIFICATION=false`. Upload remains pending merge/CI and App Store Connect access.
- [ ] Merge the current branch, deploy the backend, and verify `/health/ready` plus legal/SMS routes before uploading build 38. No new schema migration is needed for this branch.
- [ ] Complete listing name, subtitle, description, keywords, categories, support/marketing/privacy URLs, reviewer contact, release timing, territory availability, and platform compatibility.
- [x] Upload current English (U.S.) screenshots to the iPhone 6.9, iPhone 6.5, and iPad 13 sets; verify six ordered `COMPLETE` assets at each target size. Recheck visible content against the exact selected release candidate before submission.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity, connection social graph, installation/device identifiers, and profile photos. Build 36 retains the Contacts and Device ID manifest additions; finish Contacts and Photos setup in App Store Connect.
- [ ] Choose and align the age policy across the app, Terms, Privacy, listing, and age rating.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Provide and verify an active demo account or a complete demo experience for App Review, with access to the connected-person and paid flows. Normal Apple sign-in instructions alone have not established that access. Keep development sign-in, seeded review data, and review-unlock flags disabled in production. Apple’s [review guidance, Before You Submit and 2.1](https://developer.apple.com/app-store/review/guidelines/) requires full access and describes approval for a demo mode when legal or security constraints prevent a demo account.
- [ ] Reconcile the shipped Send code disclosure with the registered Twilio campaign and public SMS evidence. Consent-event persistence and privacy disclosure are implemented/deployed; verify the campaign's current opt-in method and HELP/STOP behavior.
- [ ] Upload build 38, wait for Apple processing, confirm availability in Trust Family Auto, then retry build 35's required-check failure on the same iPhone through normal Apple sign-in and registration.
- [ ] Verify the full reviewer journey without development or entitlement bypasses: onboarding, adding/accepting a person, consented sharing, Stop/remove, purchase/restore, and account deletion.

## Before manual public availability

Keep the release manual until physical TestFlight checks confirm background location, APNs permission/presentation/taps, offline reconnect, same-account second-device behavior, paid History/revocation, and subscription renewal/expiry/refund/restore. Confirm support and incident ownership, delivered alerts, backups/recovery, and a deliberate verification-SMS capacity limit. Resolve any observed privacy or entitlement defect before release.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [Current App Store copy draft](LISTING-COPY.md) — applied to the English (U.S.) draft; not submitted
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
