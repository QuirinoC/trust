# Trust release preparation — 3 November 2026

**Preparation delivered; public release remains held.** Both build-52 artifacts use frozen application source `faa306f85d4a24732f03b8420cf78b1a556846bf`. Later changes affect capture tooling, accepted assets and records. All 170 recorded binary-input hashes matched the freeze.

## Apps

- **Trust Staging 1.0 (52):** upload/build `6a97f245-3c40-4cac-81a6-651676b0cbf8` is `COMPLETE / VALID / INTERNAL_ONLY / IN_BETA_TESTING`. Existing group `b03d7b51-49a5-48f4-9899-08c54bf4470b` contains it; the same three approved tester IDs and roles were verified unchanged. English What to Test was read back.
- **Trust 1.0 (52):** signed, exported, strictly audited and Apple-validated, with `VERIFY SUCCEEDED`; **not uploaded**. Its task-owned empty awaiting-upload reservation was removed and absence verified. Normal 49 remains the latest uploaded eligible build, and the manual draft still selects 47. The new client requires a compatible production API/web rollout before upload or distribution.

Both artifacts retain the existing team, profiles, production APNs, privacy manifest, authentication and entitlement settings. Phone bypass is false. No production deployment, public App Review, automatic PR merge or cloud-validation wait occurred.

## App Store assets and metadata

Astra accepted all **36** caption-and-native-app panels using fictional data: three phone sizes, iPad, Duo outer and Duo inner. All 12 Duo panels were reviewed individually alongside critical full-resolution native captures. The compact `Name | Off | Sealed | Always | menu` row, complete Look explanation/actions and native OS framing are preserved. Each stricter Duo Look capture passed 1/0/0.

All **24 phone/iPad images** are uploaded to the normal draft in four supported groups, six each in `01-map, 02-share, 03-look, 04-log, 05-view, 06-lookup` order. Apple returned COMPLETE and matching source checksum, dimensions, file size and exact order for every image. All previous 18 assets were backed up before replacement. The **12 Duo images are prepared locally**; supported upload groups remain unavailable. See the [asset manifest](../../../../apps/trust-ios/AppStore/Screenshots/2026-11-02/manifest.json).

The current real-Apple-catalog [paywall review image](../../../../apps/trust-ios/AppStore/ReviewAssets/2026-11-03/README.md) was accepted. Apple rejected its subscription-review POST with `409 ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE`: `reviewScreenshot can not be modified`. Existing monthly and annual images remained COMPLETE with original IDs and checksums on readback. Customer-description edits are separately immutable; the existing truthful copy remains unchanged. No image deletion or review-state bypass was used to force an edit.

Developer and Paid Apps agreements are active following owner review and authentication. App Privacy has 12 published categories; the three corrected types are linked for functionality and not tracking. Normal listing metadata and subscription review notes were read back. The owner's intended launch is worldwide wherever Apple allows; actual territory configuration and provider/carrier coverage remain unchanged and unverified.

## Verification and remaining release gates

R12 GPS recovery, denied-location Recenter and phone pin cases each passed 1/0/0; phone variants included light/dark, maximum accessibility text and three map detents. Nine earlier native map cases, including five verified Duo postures, are a separate checkpoint. Earlier package checks passed 133/133 and localization covered 599 keys across five translations. This is scoped evidence, **not a new complete current-source standard UI all-pass claim**.

The denied-location case retained one Core Location responsiveness warning with an unusable 25-frame zero-address stack and no module attribution. No repository defect was confirmed or suppressed. See the [map evidence](../../../evidence/2026-11-03-map-recovery/README.md) and [device/account report](../../../evidence/2026-11-01-customer-experience/DEVICE-ACCOUNT-REPORT.md).

Before public release, follow the [rollout plan](../2026-11-02/PUBLIC-ROLLOUT-PLAN.md): establish recovery readiness, obtain authorization for the compatible production API/web rollout, verify actual worldwide service coverage and reviewer access, and resolve applicable Apple metadata locks. Genuine Apple sign-in, carrier SMS, completed purchase/server entitlement/restore, TestFlight production APNs and two physical phones remain unestablished by local fixtures. Use the [two-iPhone guide](../../../PHYSICAL-DEVICE-TEST.md); execution is not yet recorded. New unlinked accounts' app-transaction consent-notification coverage remains limited.

## Durable operational evidence

Signed archives and exports are under `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-11-03/`. Full protected evidence is at `Trust-1.0-52-ReleasePreparation/verification` (0700), with 3,223 retained files at the move, including passing/failed results, exact native raws, original-image backups, upload ledgers and helpers. `RETENTION.json` records critical hashes; the prior `/tmp/trust-release-prep-20261102-5rs8khss` path is only a compatibility symlink.

The staging delivery record is `/Users/juanquirino/.agents/secrets/trust-staging/apple-staging-build-52-upload.json`; credential and operational references remain in the existing protected inventory. No duplicate credentials were created. All nine task-owned capture simulators are absent, the pre-existing booted simulator was preserved, and only recorded task-owned compiler/index caches were removed.
