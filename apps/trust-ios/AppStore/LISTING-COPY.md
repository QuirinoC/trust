# App Store listing copy

**Working draft — not approved for submission.** This copy follows the September 26, 2026 launch brief and describes the current app vocabulary. It is not a record of the live App Store Connect listing. The working name and subtitle are proposals; repo changes do not change App Store Connect.

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

- **Live listing:** the latest recorded App Store Connect state still has the earlier product name and old listing artwork. Verify current state directly; this draft has not been copied into App Store Connect.
- **Build:** build 31 is internal-only and includes the TestFlight phone-verification skip. Do not select it for public App Review.
- **Screenshots:** the six-screen set in `Screenshots/2026-09/` is proposed local artwork, not uploaded store content. Review at storefront size and against the exact public-release build before upload.
- **Age policy:** the earlier 18+ listing draft conflicts with the current Terms/Privacy language, which excludes children under 13 while permitting household use. Decide and align product, legal pages, recruitment, and App Store age answers before public release.
- **Privacy disclosures:** reconcile the live App Privacy answers, privacy manifest, client behavior, API storage/retention, phone verification, profile photos, and analytics. `REVIEW-READINESS.md` is a checklist, not evidence those answers are complete.
- **Subscription details:** verify the live Trust Plus products, territories, prices, eligibility, trial, and included features. The old draft's exact prices and feature bundle are intentionally omitted here.
- **Waitlist:** the website's current beta link opens an email draft; it is not a functioning waitlist. Do not label it a waitlist until there is a reviewed, working collection flow and a matching privacy disclosure.
- **Legal:** this copy refresh does not modify Terms, Privacy, SMS consent, age policy, or subscription terms.

## Review notes to prepare after release checks

Use `REVIEW-READINESS.md` to prepare reviewer instructions from the exact public build. Keep the review path on normal production authentication, do not include seeded accounts or review-only bypasses, and describe notification delivery as best-effort. Verify every path and claim in App Store Connect before submission.
