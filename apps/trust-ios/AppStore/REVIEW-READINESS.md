# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Current evidence — 2026-09-30 6:22 AM PDT

Live App Store Connect confirms internal group `Trust Family Auto` has three testers and Automatic for Xcode Builds enabled. Builds 32 and 36 are listed; build 40 is not uploaded. The current Safari session is signed in, but Xcode reports no App Store Connect account for team `3S529795M9`, and the Mac locked before Organizer could be used. The last known feedback is build 35 on iPhone 16 Pro/iOS 27.0: “We can’t complete the required check.”

The committed base is `main` at `0d0c0530fc43e59efe31b5337153f00e0a8182ff` (PR #15). Current avatar, legal-page, test, and documentation changes are uncommitted on `codex/launch-readiness-today`. PR CI [`36706143943`](https://github.com/QuirinoC/trust/actions/runs/36706143943) and post-merge CI [`36710594550`](https://github.com/QuirinoC/trust/actions/runs/36710594550) passed all API, iOS, and web jobs; nine real-API UI tests skipped because CI has no isolated API base URL. Local validation after the avatar change passed iOS core tests 82/82 and the focused dark-appearance UI test 1/1.

Version 1.0 build 40 is configured in `project.yml` and the generated Xcode project. Stable Xcode 27.0 archived and exported `/tmp/Trust-1.0-40-AppStore.xcarchive` and `/tmp/Trust-1.0-40-AppStore-Export/Trust.ipa`. IPA SHA-256: `29b1d569fe15ef04a178a5587d883ed891c9f77c086aec6104e28286b54d5129`. Audit confirms production API, phone-verification bypass off, Apple Distribution team `3S529795M9`, production APNs, Declared Age Range entitlement, and `get-task-allow=false`. It is not uploaded.

App Privacy is published, but App Store Connect still flags Contacts and Photos or Videos as requiring setup. Both are selected among ten data types. Keep Contacts disclosed because its Apple definition includes the social graph and Trust stores connection relationships. Safari did not expose the two “Set Up” controls as actionable accessibility controls, so these declarations remain unfinished.

Render `trust-api` is live on commit `de977df9879429582b73776a66dd88e4d952dc52`; `/health/live` and `/health/ready` returned 200 at the app's configured host. The merged app change has no API or database change and needs no redeploy/migration. Cloudflare Worker `jointrust-web` version `faba17a1-c748-438e-86c7-17593f6f606b` serves Privacy, Terms, and Support, each returning 200 and matching the local source byte-for-byte.

The English (U.S.) listing and an earlier screenshot set were applied in the last saved App Store Connect observation. The local annotated screenshot set has since been regenerated and reviewed; it has not been uploaded. Refresh and compare every field live; categories, reviewer access, App Privacy, age rating, agreements, subscription products and review resources, screenshots, and territories are not confirmed current. No public App Review submission has been made.

The age-gate simulator suite uses fixtures and does not call Apple's live service. Retest the required-check flow on the same iPhone 16 Pro using normal Apple sign-in, age assurance, and App Transaction registration. Twilio campaign alignment, physical notification/background-location behavior, purchase/restore, and the full reviewer journey still need evidence. See [project status](../../../docs/STATUS.md) and [two-account E2E evidence](../../../docs/LOCAL-TWO-ACCOUNT-E2E.md).

## Required before submission

- [x] Build the earlier version 1.0 (36) archive and App Store distribution export with stable Xcode 27.0; verify Apple Distribution team 3S529795M9, production APNs, `get-task-allow=false`, production API URL, and that the phone-verification bypass is disabled. The build-36 archive and IPA passed Apple validation/upload and are recorded as `VALID` in the last saved observation; current App Store Connect state still needs a live refresh.
- [x] Increment to build 40 and archive/export the current release app source with `ExportOptions-AppStore.plist`; verify Apple Distribution signing, production APNs, Declared Age Range entitlement, `get-task-allow=false`, production API URL, and `TRUST_SKIP_PHONE_VERIFICATION=false`. See the audited build 40 archive and IPA paths above.
- [x] Merge the current source and deploy the backend. The active API is on `de977df`; `/health/ready` and current legal/SMS routes returned 200. The latest app-only change needs no API redeploy or migration.
- [ ] Complete listing name, subtitle, description, keywords, categories, support/marketing/privacy URLs, reviewer contact, release timing, territory availability, and platform compatibility.
- [ ] Upload the regenerated English (U.S.) screenshots to the iPhone 6.9, iPhone 6.5, and iPad 13 sets; verify six ordered `COMPLETE` assets at each target size. Recheck visible content against the exact selected release candidate before submission.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity, connection social graph, installation/device identifiers, and profile photos. Finish Contacts and Photos setup in App Store Connect; both are selected but still incomplete.
- [ ] Choose and align the age policy across the app, Terms, Privacy, listing, and age rating.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Provide and verify an active demo account or a complete demo experience for App Review, with access to the connected-person and paid flows. Normal Apple sign-in instructions alone have not established that access. Keep development sign-in, seeded review data, and review-unlock flags disabled in production. Apple’s [review guidance, Before You Submit and 2.1](https://developer.apple.com/app-store/review/guidelines/) requires full access and describes approval for a demo mode when legal or security constraints prevent a demo account.
- [ ] Reconcile the shipped Send code disclosure with the registered Twilio campaign and public SMS evidence. Consent-event persistence and privacy disclosure are implemented/deployed; verify the campaign's current opt-in method and HELP/STOP behavior.
- [ ] Sign into Xcode Organizer or Transporter with the Collapse Technologies account, upload audited build 40, wait for processing, and confirm it is available in `Trust Family Auto`; then retry build 35's required-check failure on the same iPhone through normal Apple sign-in and registration.
- [ ] Verify the full reviewer journey without development or entitlement bypasses: onboarding, adding/accepting a person, consented sharing, Stop/remove, purchase/restore, and account deletion.

## Before manual public availability

Keep the release manual until physical TestFlight checks confirm background location, APNs permission/presentation/taps, offline reconnect, same-account second-device behavior, paid History/revocation, and subscription renewal/expiry/refund/restore. Confirm support and incident ownership, delivered alerts, backups/recovery, and a deliberate verification-SMS capacity limit. Resolve any observed privacy or entitlement defect before release.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [Current App Store copy draft](LISTING-COPY.md) — most fields were previously applied to the English (U.S.) draft; the revised notification wording still needs App Store Connect application and verification; not submitted
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
