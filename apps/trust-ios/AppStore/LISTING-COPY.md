# App Store listing copy

**Working listing draft; not submitted for App Review.** Listing metadata and availability must be rechecked in App Store Connect before submission. Astra accepted all 36 panels in the [2 November set](Screenshots/2026-11-02/manifest.json); all 24 phone/iPad images are uploaded to the normal draft and verified COMPLETE. Reviewer access, physical testing, coverage and release checks remain open.

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

Always is separate and requires Trust Plus for the person sharing. While someone has chosen Always, connected recipients can view that authorized live location without Plus; recipients need Plus only to share Always themselves. Pause or stop sharing at any time.

Trust assigns a handle after phone verification. Find accounts by handle or, when a person has enabled phone discovery, by their complete phone number. Accepting a connection does not turn sharing on.

Trust Plus includes additional features. Review the in-app offer for current features, availability, price, and subscription terms.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy: https://jointrust.app/privacy
```

### Keywords (under 100 characters)

```text
location,sharing,privacy,activity,check,live,phone,friend,partner,snapshot
```

### Category and URLs

Reconfirm the primary and secondary categories, supported platforms, and all App Store Connect URLs before submission. Worldwide launch wherever Apple allows is intended; actual territory settings have not been changed and provider coverage remains unverified. The current support, marketing, privacy, and terms URLs are:

- Support: https://jointrust.app/support
- Marketing: https://jointrust.app
- Privacy: https://jointrust.app/privacy
- Terms: https://jointrust.app/terms

## Remaining release checks

- **Build:** Normal 1.0 build 47 remains selected; build 49 is the latest verified uploaded normal build. Normal 52 from frozen `faa306f` was signed and Apple-validated but remains held without upload until compatible production rollout is explicitly authorized and verified. Staging 52 is `VALID / INTERNAL_ONLY / IN_BETA_TESTING` for the same three testers with unchanged roles. Public App Review has not been submitted. See [review readiness](REVIEW-READINESS.md).
- **Screenshots:** Astra accepted all 36 composed panels, including all 12 Duo panels individually and critical native raws; both strict Duo Look checks passed 1/0/0. All 24 phone/iPad images are uploaded to the normal draft and verified COMPLETE with matching checksums, dimensions, sizes and order; the previous 18 images were backed up before replacement. Duo panels remain local because upload groups are unavailable. The fictional fixture does not establish production behavior. See the [manifest](Screenshots/2026-11-02/manifest.json).
- **Privacy:** App Privacy shows 12 categories Published; the three formerly missing types are linked for app functionality and not tracking. Review disclosures against app and server behavior before submission. Contacts describes Trust's stored account-to-account graph, not upload of the phone address book.
- **Subscriptions:** The accepted [real-catalog paywall review image](ReviewAssets/2026-11-03/README.md) is prepared. Apple's screenshot POST returned `409 ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE` (`reviewScreenshot can not be modified`); both old monthly and annual resources remained `COMPLETE`, with IDs and checksums unchanged on readback. No deletion or state bypass occurred. Customer-description updates separately returned `409 FIELD_UNMODIFIABLE` and remain unchanged. Recheck prices, offers, localizations, review resources and territories before submission.
- **Review and distribution:** The normal draft remains manual and `PREPARE_FOR_SUBMISSION`. Verify reviewer access to connected and paid flows and recheck platform support, category, agreements and availability before submission. The Developer agreement was accepted and Paid Apps Schedules 2 and 3 are Active through 20 August 2027. Worldwide availability is intended; actual territory settings remain unchanged and provider coverage is unverified. Investigate the historical `CANNOT_SELL` status without inferring its cause. No App Review submission has been made.
- **Onboarding and launch obligations:** Signup uses genuine Sign in with Apple and server-verified phone verification before account completion. Missing handles are assigned automatically after verification; Apple age-range and app-transaction onboarding setup remain paused. Review the actual audience and launch-market obligations, SMS consent and subscription terms against shipped behavior. See [AGE-ASSURANCE.md](../../../docs/AGE-ASSURANCE.md).
- **Beta website:** the current beta link opens an email draft. It is not a waitlist or public App Store download link.

## Review notes to prepare after release checks

Use `REVIEW-READINESS.md` to prepare reviewer instructions from the exact public build. Keep the review path on normal production authentication, do not include seeded accounts or review-only bypasses, and describe notification delivery as best-effort. Verify every path and claim in App Store Connect before submission.
