# TestFlight M4 physical-device checklist

> **Release status:** This checklist is a plan, not evidence of a completed release. The earlier M4 notes named build 18 and included stale instructions; that build is historical. `project.yml` now sets version 1.0 build **19**, the current local target. The canonical status page records that no signed archive, App Store Connect upload, processed build, or physical-device verification is recorded. See [docs/STATUS.md](../../docs/STATUS.md) and [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).

Use this only after the reviewed build is uploaded, processed, and assigned to the internal TestFlight group. Do not use a Debug install as TestFlight evidence. Keep production review flags disabled.

## Two-account sharing flow

- [ ] Install the assigned TestFlight build on two physical devices and sign in with two different dedicated tester accounts.
- [ ] Create an invitation on one account. On the second, review the invitation code and explicitly tap **Join**. Confirm membership is added with both directions Off.
- [ ] Set one direction to Until they look. Confirm the recipient sees a notify-first confirmation, then one current-location snapshot. Confirm the share remains Sealed afterward.
- [ ] Confirm the Sealed snapshot does not grant location history. If the API contract is exercised directly, confirm a Sealed history request is rejected.
- [ ] Check the sender for the Look receipt. Record whether it arrives and displays; an API success alone does not prove APNs delivery.
- [ ] Buy Plus through TestFlight sandbox IAP on the appropriate account, then enable Always. Confirm View opens without a Look confirmation, is recorded in Activity, and does not send a Look receipt.
- [ ] Confirm location history appears only while the subject shares Always. Switch that direction away from Always and confirm history is unavailable.
- [ ] Exercise Stop, Remove, and account deletion. Record actual account cleanup results.

## Device and store checks

- [ ] Verify SMS consent starts unchecked, must be selected before sending, and code resend and verification states are clear.
- [ ] Verify background location while Always is enabled and test Home/Away updates with a configured Home boundary.
- [ ] Test sandbox purchase and Restore on the TestFlight build; record the product outcome and any StoreKit errors.
- [ ] Check behavior on cellular/background use and note observed battery impact. Do not infer battery performance from simulator runs.
- [ ] Confirm production review-unlock and review-circle flags remain false.

Record the TestFlight build number, device/OS, API host, and results in [docs/STATUS.md](../../docs/STATUS.md). APNs is best effort and Trust makes no delivery guarantee. Do not submit the app for App Review as part of this internal test plan.
