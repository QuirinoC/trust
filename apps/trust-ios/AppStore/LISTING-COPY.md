# App Store listing copy

**App Store Connect draft updated 2026-09-29; not submitted for review.** The English (U.S.) name, subtitle, promotional text, description, keywords, and URLs below were applied and re-read through Apple’s API. Beta description was updated to match. Public release gates remain open.

## Proposed metadata

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

With Sealed sharing, you can confirm a Look to request the other person's latest available location snapshot. Trust records the check in Activity and requests a notification to the person sharing. Notification delivery is not guaranteed. Sealed does not provide location history.

Always is separate. While someone has chosen Always, selected connected people can view their location and eligible history. Pause or stop sharing at any time.

Find accounts by handle or, when phone discovery is enabled, by a complete phone number. Accepting a connection does not turn sharing on.

Trust Plus includes additional features. Review the in-app offer for current features, availability, price, and subscription terms.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy: https://jointrust.app/privacy
```

### Keywords (proposal, under 100 characters)

```text
location,sharing,privacy,activity,check,live,phone,friend,partner,snapshot
```

### Category and URLs

Reconfirm the primary and secondary categories, supported platforms, territory availability, and all App Store Connect URLs before submission. The current support, marketing, privacy, and terms URLs are:

- Support: https://jointrust.app/support
- Marketing: https://jointrust.app
- Privacy: https://jointrust.app/privacy
- Terms: https://jointrust.app/terms

## Release blockers

- **Live listing:** App Store Connect's 1.0 draft still selects build 27 and retains the earlier product name and other unverified listing metadata. Current English (U.S.) screenshots are uploaded in the iPhone 6.9, iPhone 6.5, and iPad 13 sets; this draft copy has not been copied into App Store Connect.
- **Build:** build 32 is the observed internal TestFlight build and includes the phone-verification skip; keep it internal and do not select it for public App Review. Build 34 is the current ordinary Trust export with the bypass disabled; its local archive and IPA have not been uploaded. Trust Family Auto is the sole remaining internal group and auto-receives all builds, so deploy and verify the reviewed backend before uploading. It remains a public-review candidate only after build-32 compatibility and release checks pass and the exact App Store Connect draft is updated.
- **Screenshots:** current images in `Screenshots/2026-09/{iphone-69,iphone-65,ipad-13}/` are uploaded to the matching English (U.S.) sets for version 1.0. Review storefront presentation and confirm visible content against the exact public-release build before submission.
- **Age assurance:** The normal app has no global birth-date screen. It uses Apple age and significant-update flows when Apple signals they apply on supported OS versions. Trust’s COPPA audience classification and jurisdiction-specific obligations remain unresolved; review the shipped product and launch markets with counsel before release. See [`docs/AGE-ASSURANCE.md`](../../../docs/AGE-ASSURANCE.md).
- **Privacy disclosures:** reconcile the live App Privacy answers, privacy manifest, client behavior, API storage/retention, phone verification, profile photos, and analytics. `REVIEW-READINESS.md` is a checklist, not evidence those answers are complete.
- **Subscription details:** verify the live Trust Plus products, territories, prices, eligibility, trial, and included features. The old draft's exact prices and feature bundle are intentionally omitted here.
- **Waitlist:** the website's current beta link opens an email draft; it is not a functioning waitlist. Do not label it a waitlist until there is a reviewed, working collection flow and a matching privacy disclosure.
- **Legal:** Terms and Privacy describe the Apple-signaled age-assurance flow and its current OS limitations. Confirm the legal pages, SMS consent, subscription terms, and App Store answers against current behavior before public release.

## Review notes to prepare after release checks

Use `REVIEW-READINESS.md` to prepare reviewer instructions from the exact public build. Keep the review path on normal production authentication, do not include seeded accounts or review-only bypasses, and describe notification delivery as best-effort. Verify every path and claim in App Store Connect before submission.
