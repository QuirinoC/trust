# App Store listing copy

**Listing copy last directly compared with App Store Connect on 2026-09-30; not submitted for App Review.** At 5:51:54 PM PDT on 2026-10-25, version 1.0 was **Prepare for Submission**, release was **Manual**, and build 47 was selected. Listing localization is English (U.S.) only and the privacy URL is correct; other listing metadata should be rechecked before public submission. The current availability snapshot shows only the United States available, with new territories disabled. The U.S. content statuses include `CANNOT_SELL` and `AVAILABLE_FOR_SALE_UNRELEASED_APP`; no cause is inferred. The snapshot is retained in the release evidence folder. All 18 panels in the [2026-10-25 screenshot set](Screenshots/2026-10-25/README.md) were visually passed, uploaded to the three existing groups, and verified complete in order. The copy, reviewer-access, privacy-attestation, physical-test, and legal gates remain open.

## Current English (U.S.) draft metadata

### Name (23 characters)

```text
Trust: Location Sharing
```

### Subtitle (29 characters)

```text
See who checked your location
```

### Promotional text

```text
Choose what each person can see. Review location checks recorded in Trust.
```

### Description

```text
Trust is a location-sharing app for friends and partners. Choose what each person can see and review location checks made in Trust.

Adding someone does not start sharing. After you connect, each person chooses whether to share. You can choose different settings.

With Sealed sharing, you can confirm a Look to request the other person's latest available location snapshot. Trust records the check in Activity and attempts to notify the person sharing. Notification delivery is not guaranteed. Sealed does not provide location history.

Always is separate. While someone has chosen Always, selected connected people can view their location and eligible history. Pause or stop sharing at any time.

Find accounts by handle or, when phone discovery is enabled, by a complete phone number. Accepting a connection does not turn sharing on.

Trust Plus includes additional features. Review the in-app offer for current features, availability, price, and subscription terms.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy: https://jointrust.app/privacy
```

### Keywords (under 100 characters)

```text
location,sharing,privacy,activity,check,live,phone,friend,partner,snapshot
```

### Category and URLs

Reconfirm the primary and secondary categories, supported platforms, and all App Store Connect URLs before submission. The current snapshot is U.S.-only; counsel still needs to classify the intended audience and launch markets before any territory change. The current support, marketing, privacy, and terms URLs are:

- Support: https://jointrust.app/support
- Marketing: https://jointrust.app
- Privacy: https://jointrust.app/privacy
- Terms: https://jointrust.app/terms

## Remaining release checks

- **Build:** regular version 1.0 (47), from committed source `c70756f` plus the build-number-only change, is `VALID / APP_STORE_ELIGIBLE` and selected on the version draft. It is in TestFlight internal state `IN_BETA_TESTING` and external state `READY_FOR_BETA_SUBMISSION`; the existing `Trust Family Auto` group contains it. Delivery/build ID: `94fc80d4-0796-491c-8596-b99fb8c283b7`. Public App Review has not been submitted. See [review readiness](REVIEW-READINESS.md) and [STATUS.md](../../../docs/STATUS.md) for artifact details.
- **Screenshots:** Astra passed the new 18-panel set in [Screenshots/2026-10-25/](Screenshots/2026-10-25/README.md); it is uploaded to the three existing groups, six complete images each in the correct order. The capture used the DEBUG fictional fixture and is not evidence about production accounts or locations. See its manifest and README for provenance and the ReleaseEvidence folder for the upload audit.
- **Privacy:** the 2 October App Store Connect inspection recorded a published label with nine types, including Contacts for Trust's stored account-to-account social graph; the app does not upload the phone address book. That inspection showed Photos or Videos, Other Diagnostic Data, and Other Data Types selected but not configured. Current privacy draft state is unknown. Reconcile the current preview against app/server behavior and manifest, then get the Account Holder's accuracy and legal-compliance attestation before publishing.
- **Subscriptions:** the 2026-10-25 snapshot showed monthly product `6806880712` and annual product `6806880974` as `READY_TO_SUBMIT`, not added for review. Customer-facing localization was English (U.S.) only. Recheck prices, trial, status, product copy/localizations, review resources, and app/IAP territories before submission; an earlier 2 October observation of different status and prices is historical.
- **Review and distribution:** the 2026-10-25 snapshot showed manual release and `Prepare for Submission`; `demoAccountRequired=false`, no demo login/password, and 994-character review notes. Verify reviewer access to connected and paid flows and refresh platform support, agreements, category, and availability settings. Current availability is U.S.-only with new territories disabled; investigate the `CANNOT_SELL` status alongside agreements without inferring its cause. Counsel's audience/market classification remains open. No App Review submission has been made.
- **Age assurance and legal:** the app uses Apple-signaled age and significant-update flows on supported OS versions. The App Store questionnaire now declares age-assurance use. Audience classification and launch-market obligations still need legal review; see [AGE-ASSURANCE.md](../../../docs/AGE-ASSURANCE.md). Confirm SMS consent and subscription terms against the shipped behavior.
- **Beta website:** the current beta link opens an email draft. It is not a waitlist or public App Store download link.

## Review notes to prepare after release checks

Use `REVIEW-READINESS.md` to prepare reviewer instructions from the exact public build. Keep the review path on normal production authentication, do not include seeded accounts or review-only bypasses, and describe notification delivery as best-effort. Verify every path and claim in App Store Connect before submission.
