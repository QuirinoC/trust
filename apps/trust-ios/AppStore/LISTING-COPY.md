# App Store listing copy

**App Store Connect listing last directly observed 2026-09-30 at 6:30 PM PDT; not submitted for review.** Version 1.0 remains **Prepare for Submission**, build 41 is selected, and manual release is selected. The English (U.S.) listing below matches the live name, subtitle, promotional text, description, keywords, support URL, marketing URL, and privacy URL. The current live page shows six screenshots in the 6.5-inch iPhone group; see [review readiness](REVIEW-READINESS.md) for the other previously checked screenshot groups. Core review and legal gates remain open.

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

Reconfirm the primary and secondary categories, supported platforms, territory availability, and all App Store Connect URLs before submission. The current support, marketing, privacy, and terms URLs are:

- Support: https://jointrust.app/support
- Marketing: https://jointrust.app
- Privacy: https://jointrust.app/privacy
- Terms: https://jointrust.app/terms

## Remaining release checks

- **Build:** Build 41 remains the last confirmed regular build selected on version 1.0. Internal build 42 was processed in `Trust Family Auto`; build 43 is **Testing** in that group, and App Store Connect lists Diana's iPhone 16 Pro Max as having installed it on 2 October. Her build-42 feedback (iOS 26.6.2) says “No me deja” and shows “We can’t complete the required check.” The owner reports build 43 still displays “Couldn’t verify this app”; a targeted fix and retest are required. Do not submit the internal target for public review.
- **Screenshots:** the current App Store Connect version page shows six ordered screenshots in the 6.5-inch iPhone group. A prior check also confirmed six screenshots in each iPhone 6.9-inch and iPad 13-inch group; recheck those groups and compare the complete set against the selected build before submission.
- **Privacy:** the published App Privacy label includes nine types, including Contacts for Trust's stored account-to-account social graph; the app does not upload the phone address book. App Store Connect currently warns that Photos or Videos, Other Diagnostic Data, and Other Data Types are selected but not set up, so they are not yet included in the product page. Finish and inspect all three declarations against app/server behavior and get the Account Holder's accuracy and legal-compliance attestation before publishing.
- **Subscriptions:** at 3:53 PM, Trust Plus and both products were `Ready for Review` and already added for review. U.S. prices were $7.99/month and $69.99/year with a seven-day trial shown across 175 selected subscription storefronts. Customer-facing localization was English (U.S.) only. The current product description says “Trust Plus: 20 seats, Always, map, year of log.” Revisit clarity and localization before broad international availability; app territory availability has not been rechecked.
- **Review and distribution:** the current version page still shows manual release and the `Prepare for Submission` status. The Sign-in required checkbox is off although an account is required; the review notes have no working demo credentials or connected test account. The last availability observation recorded US-only distribution with pre-order and automatic new territories disabled; recheck those settings. Verify paid agreements and physical purchase/restore before submission. No App Review submission has been made.
- **Age assurance and legal:** the app uses Apple-signaled age and significant-update flows on supported OS versions. The App Store questionnaire now declares age-assurance use. Audience classification and launch-market obligations still need legal review; see [AGE-ASSURANCE.md](../../../docs/AGE-ASSURANCE.md). Confirm SMS consent and subscription terms against the shipped behavior.
- **Beta website:** the current beta link opens an email draft. It is not a waitlist or public App Store download link.

## Review notes to prepare after release checks

Use `REVIEW-READINESS.md` to prepare reviewer instructions from the exact public build. Keep the review path on normal production authentication, do not include seeded accounts or review-only bypasses, and describe notification delivery as best-effort. Verify every path and claim in App Store Connect before submission.
