# Trust CI follow-up — 3 November 2026

The current PR 18 head `45845ba27265348bd160540e23c6a1163203a80b` failed [Trust CI run 41734835373](https://github.com/QuirinoC/trust/actions/runs/41734835373). Xcode selection, simulator creation/boot, runner tests and localization checks succeeded. This is not evidence that additional Apple credentials or Mac hardware are required.

## Confirmed failures and corrections

- **iOS job 126261222166:** `testLanguagePreferenceChangesCopyAndPersists` failed while waiting for the language picker after relaunch. Its failure hierarchy shows all four French tab labels, People selected and You unselected. The recorded 50 ms touch was inside You's bounds, but the app trace records no You callback. French persistence therefore worked; the exact reason the automated contact was dropped is unproven. The test now waits for stable visible/hittable tab geometry, sends one ordinary 100 ms contact, and requires You's selected state before scrolling/querying the preference. The exact French picker value and all French/English tab-label assertions remain. Failure evidence is attached at the navigation boundary; no retries or forced app state were introduced. The scroll helper avoids reading a missing element's frame.
- **API job 126261222711:** `OwnerEntitlementExpiryImmediatelyRevokesFreeRecipientsLiveViewAndHistory` expected `...9552108` but PostgreSQL returned `...9552100`. The fixture now removes sub-microsecond ticks before deriving expiry. PostgreSQL/Npgsql store microseconds while .NET timestamps represent 100 ns ticks. Exact expiry equality and all live-access, revocation and history assertions remain unchanged. See [PostgreSQL precision](https://www.postgresql.org/docs/current/datatype-datetime.html) and [Npgsql mapping](https://www.npgsql.org/doc/types/datetime.html).

The missing direct-API result bundle in the original iOS job was secondary: that phase was skipped after the earlier UI-test failure. It is not a separate setup diagnosis.

## Verification and limits

The affected PostgreSQL test passed 1/1 and the full API suite passed **258/258, zero skips**, using a task-owned disposable local PostgreSQL 16 cluster. Stdout and TRX are retained; the cluster was stopped and removed. Sol independently reviewed both test-only changes with no remaining actionable findings.

The iOS test build completed on the named Xcode 27.1 installation. Local runtime verification is **not passed**: the owned simulator could not install the app because the Mac ran out of disk space. The first attempt also hit linker errno 28. Both owned simulators were removed and the pre-existing device preserved. Only completed task Debug outputs and a verified duplicate artifact extraction were pruned; the original GitHub ZIP, exported failure attachments and all result/log evidence remain. Local runtime is iOS 26.5, while GitHub uses Xcode 26.6/iOS 26.6; the rerun on GitHub must establish the corrected runtime outcome.

These changes affect test code only. The released app source, staged API, signing, privacy gates, release flags and compact Sharing design are unchanged. No new TestFlight build or service deployment is needed for these test changes.

Protected evidence is under `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-11-03/Trust-1.0-52-ReleasePreparation/verification/ci-followup-20261103` (0700; private records 0600). The original artifact ZIP is 216,866,303 bytes, SHA-256 `baf599a62bc1a3cc644d835b73f630fc0d708578837611f9fa89379f7002b785`, matching GitHub's digest. Remote current-head checks remain pending until actually observed passing; no schedule was created.
