# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Current evidence — 2026-09-30 3:55 AM PDT

The last saved App Store Connect observation records build 36 as `VALID` in `Trust Family Auto` and build 35 selected in the 1.0 draft. The latest saved feedback is build 35 on iPhone 16 Pro/iOS 27.0: “We can’t complete the required check.” No newer report proves resolution. App Store Connect could not be refreshed while macOS was locked; the previous API read returned `NOT_AUTHORIZED`.

The app source is merged to `main` at `f579005fb73fbc45b6d3551b5ab63fac7da240c6`. PR CI [`36697551317`](https://github.com/QuirinoC/trust/actions/runs/36697551317) and post-merge CI [`36699341073`](https://github.com/QuirinoC/trust/actions/runs/36699341073) passed API, iOS, and web. The release branch configures version 1.0 build 39 and produced `/tmp/Trust-1.0-39-AppStore-Export-20260930/Trust.ipa`, SHA-256 `7a621bc29b170f44409a6060943b878cb02a4de7b4255d7b67c91d0d3a5fa7d4`. The exported IPA is Apple Distribution signed, uses production APNs and API, includes the Declared Age Range entitlement, has `get-task-allow=false`, and has phone-verification bypass disabled. This build-number/documentation branch still needs CI and merge. Confirm build 39 is unused in App Store Connect before upload. The previous build-38 archive predates the merged History-screen fix and must not be used as the current candidate.

Render `trust-api` is live on commit `de977df9879429582b73776a66dd88e4d952dc52`; `/health/live` and `/health/ready` returned 200. The merged app change has no API or database change and needs no redeploy/migration. Cloudflare Worker `jointrust-web` version `f8382a78-2b17-45ba-8cad-1ec4d46dd800` serves the current Privacy, Terms, and Support pages, all returning 200.

The English (U.S.) listing and an earlier screenshot set were applied in the last saved App Store Connect observation. The local annotated screenshot set has since been regenerated and reviewed; it has not been uploaded. Refresh and compare every field live; categories, reviewer access, App Privacy, age rating, agreements, subscription products and review resources, screenshots, and territories are not confirmed current. No public App Review submission has been made.

The age-gate simulator suite uses fixtures and does not call Apple's live service. Retest the required-check flow on the same iPhone 16 Pro using normal Apple sign-in, age assurance, and App Transaction registration. Twilio campaign alignment, physical notification/background-location behavior, purchase/restore, and the full reviewer journey still need evidence. See [project status](../../../docs/STATUS.md) and [two-account E2E evidence](../../../docs/LOCAL-TWO-ACCOUNT-E2E.md).

## Required before submission

- [x] Build the earlier version 1.0 (36) archive and App Store distribution export with stable Xcode 27.0; verify Apple Distribution team 3S529795M9, production APNs, `get-task-allow=false`, production API URL, and that the phone-verification bypass is disabled. The build-36 archive and IPA passed Apple validation/upload and are recorded as `VALID` in the last saved observation; current App Store Connect state still needs a live refresh.
- [x] Increment to build 39 and archive/export the current `main` app source with `ExportOptions-AppStore.plist`; verify Apple Distribution signing, production APNs, Declared Age Range entitlement, `get-task-allow=false`, production API URL, and `TRUST_SKIP_PHONE_VERIFICATION=false`. The project change still needs CI/merge, and App Store Connect must confirm 39 is unused.
- [x] Merge the current source and deploy the backend. The active API is on `de977df`; `/health/ready` and current legal/SMS routes returned 200. The latest app-only change needs no API redeploy or migration.
- [ ] Complete listing name, subtitle, description, keywords, categories, support/marketing/privacy URLs, reviewer contact, release timing, territory availability, and platform compatibility.
- [ ] Upload the regenerated English (U.S.) screenshots to the iPhone 6.9, iPhone 6.5, and iPad 13 sets; verify six ordered `COMPLETE` assets at each target size. Recheck visible content against the exact selected release candidate before submission.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity, connection social graph, installation/device identifiers, and profile photos. Build 36 retains the Contacts and Device ID manifest additions; finish Contacts and Photos setup in App Store Connect.
- [ ] Choose and align the age policy across the app, Terms, Privacy, listing, and age rating.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Provide and verify an active demo account or a complete demo experience for App Review, with access to the connected-person and paid flows. Normal Apple sign-in instructions alone have not established that access. Keep development sign-in, seeded review data, and review-unlock flags disabled in production. Apple’s [review guidance, Before You Submit and 2.1](https://developer.apple.com/app-store/review/guidelines/) requires full access and describes approval for a demo mode when legal or security constraints prevent a demo account.
- [ ] Reconcile the shipped Send code disclosure with the registered Twilio campaign and public SMS evidence. Consent-event persistence and privacy disclosure are implemented/deployed; verify the campaign's current opt-in method and HELP/STOP behavior.
- [ ] Refresh App Store Connect; confirm build 39 is available, upload the validated current-source build, wait for processing, confirm availability in Trust Family Auto, then retry build 35's required-check failure on the same iPhone through normal Apple sign-in and registration.
- [ ] Verify the full reviewer journey without development or entitlement bypasses: onboarding, adding/accepting a person, consented sharing, Stop/remove, purchase/restore, and account deletion.

## Before manual public availability

Keep the release manual until physical TestFlight checks confirm background location, APNs permission/presentation/taps, offline reconnect, same-account second-device behavior, paid History/revocation, and subscription renewal/expiry/refund/restore. Confirm support and incident ownership, delivered alerts, backups/recovery, and a deliberate verification-SMS capacity limit. Resolve any observed privacy or entitlement defect before release.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [Current App Store copy draft](LISTING-COPY.md) — applied to the English (U.S.) draft; not submitted
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
