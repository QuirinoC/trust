# App Store listing copy

**App Store Connect draft updated 2026-09-29; not submitted for review.** The English (U.S.) name, subtitle, promotional text, description, keywords, and URLs below were applied and re-read through Apple’s API. Beta description was updated to match. Public release gates remain open.

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

With Sealed sharing, you can confirm a Look to request the other person's latest available location snapshot. Trust records the check in Activity and requests a notification to the person sharing. Notification delivery is not guaranteed. Sealed does not provide location history.

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

- **Build:** build 35 is the sole active TestFlight build, available in the automatic internal group and selected in the 1.0 draft. It uses normal phone verification. The backend is live on the reviewed source. Build 35 contains the reviewed Contacts and Device ID privacy manifest additions; Apple validated and processed it, and the draft selects it.
- **Screenshots:** six current English (U.S.) images are uploaded and complete in each iPhone 6.9, iPhone 6.5, and iPad 13 set. Confirm their visible content against the final selected candidate.
- **Privacy:** Coarse Location setup has been published. Contacts and Photos or Videos still need per-category setup and publication in App Store Connect. Email was removed because the app does not collect it. Recheck all answers against the final manifest and actual behavior.
- **Review and distribution:** the draft is US-only with pre-order and automatic new territories disabled; release stays manual. Usable reviewer access remains unresolved. Verify paid agreements and physical purchase/restore before submission. No App Review submission has been made.
- **Age assurance and legal:** the app uses Apple-signaled age and significant-update flows on supported OS versions. The App Store questionnaire now declares age-assurance use. Audience classification and launch-market obligations still need legal review; see [AGE-ASSURANCE.md](../../../docs/AGE-ASSURANCE.md). Confirm SMS consent and subscription terms against the shipped behavior.
- **Beta website:** the current beta link opens an email draft. It is not a waitlist or public App Store download link.

## Review notes to prepare after release checks

Use `REVIEW-READINESS.md` to prepare reviewer instructions from the exact public build. Keep the review path on normal production authentication, do not include seeded accounts or review-only bypasses, and describe notification delivery as best-effort. Verify every path and claim in App Store Connect before submission.
