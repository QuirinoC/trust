# App Store review readiness

This is a submission checklist, not a record of current App Store Connect state. Build assignment, metadata, agreements, and review status change outside the repository; verify them directly in App Store Connect before release actions. The last dated external observations are recorded in [project status](../../../docs/STATUS.md) and should be treated as unverified until checked again.

## Required before submission

- [ ] Create and validate a signed archive using stable public Xcode. Confirm the version, incremented build number, signing team, entitlements, and archive contents.
- [ ] Upload the reviewed build, wait for processing, select that exact build for the app version, and confirm submission state in App Store Connect.
- [ ] Complete listing name, subtitle, description, keywords, categories, support/marketing/privacy URLs, reviewer contact, release timing, territory availability, and platform compatibility.
- [ ] Capture and upload current listing screenshots from the release candidate; verify sizes, device frames, and visible content.
- [ ] Reconcile App Privacy answers and the privacy manifest against release code and server behavior, including location, phone, identity/email, and profile photos.
- [ ] Choose and align the age policy across the app, Terms, Privacy, listing, and age rating.
- [ ] Verify the Paid Apps agreement, subscription group/products, price, trial, localizations, review screenshots, purchase, and restore.
- [ ] Confirm reviewer sign-in works through the intended ordinary flow. Keep development sign-in, seeded review data, and review-unlock flags disabled in production.
- [ ] Reconcile the app's Send code consent with the registered Twilio campaign and public SMS evidence. Verify HELP/STOP handling and durable consent records.
- [ ] Finish physical two-account TestFlight checks for onboarding, invitations, sharing/revocation, background location, StoreKit, account deletion, and APNs presentation/tap behavior.

Notifications are best effort. An API response or APNs acceptance is not proof that a notification appeared on a device.

## Supporting records

- [Project status and dated evidence](../../../docs/STATUS.md)
- [App Store copy draft](LISTING-COPY.md) — unapproved; verify every claim before use
- [Two-account and notification test matrix](../../../docs/FEATURE-E2E-PLAN.md)
- [Deployment procedure](../../../docs/DEPLOYMENT.md)
