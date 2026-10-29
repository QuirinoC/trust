# Device polish evidence — 28 October 2026

The current working source includes five device-polish changes:

- The Portuguese (Brazil) bottom tab uses the shorter “Compartilhar” label with an inset; the full screen heading remains unchanged.
- Picker loading, camera, error, and accessibility messages are localized.
- The picker scroll is clipped and its navigation background uses opaque palette paper, preventing content from showing through the toolbar.
- At accessibility text sizes, preference rows stack and use the available width so long values stay inside their cards.
- Avatar uploads, mutations, and cached images have account-bound guards, including a cache generation guard.

These working-source checks do not change the already uploaded TestFlight build 49. The [26 October device and account report](../2026-10-26-release-e2e/DEVICE-ACCOUNT-REPORT.md) records earlier release runs and their service boundaries.

## Completed checks

- **iPhone SE accessibility:** The focused check passed with **1 passed, 0 skipped, and 0 failed** in `/tmp/trust-polish-20261028-se-final-accessibility.xcresult`. Astra visually approved the scrolled picker and settings. This run preceded only the final fill-width modifier for wider screens.
- **iPhone 17 Pro, iOS 26.5:** The focused You, Activity, and picker test passed **1/0/0** in `/tmp/trust-polish-20261028-standard-r2.xcresult`; its normal-size toolbar screenshot was reviewed as clean. Notifications passed separately in the earlier mixed-result `/tmp/trust-polish-20261028-standard-final.xcresult` bundle.
- **Duo:** At a helper-confirmed 180-degree inner-display posture, map selection and You, Activity, and picker tests passed **2/0/0** in `/tmp/trust-polish-20261028-duo-inner.xcresult`. Outer-display Sharing German extra-extra-large and Add design checks passed **2/0/0** in `/tmp/trust-polish-20261028-duo-outer.xcresult`. A separate active-display capture test passed **1/0/0** in `/tmp/trust-polish-20261028-duo-visible.xcresult`; its review identified the German maximum-text preference layout issue addressed above.
- **Real API and PostgreSQL:** The profile picture story passed **1/0/0**, without the synthetic review fixture, in `/tmp/trust-polish-20261028-avatar-api/testProfilePictureIsStagedAndDiscoveryStaysExplicitAcrossRelaunch/testProfilePictureIsStagedAndDiscoveryStaysExplicitAcrossRelaunch.xcresult`. It covered preset staging, cancel, save, relaunch, and removal, plus explicit discovery and sharing state. It did not cover photo upload or delayed account-transition stress.
- **Build and package:** The current-source build completed (`/tmp/trust-polish-20261028-build-final.log`); later r3, r4, and final r7 builds also passed. Swift package tests passed **103 with 0 failures** (`/tmp/trust-polish-20261028-core.log`), localization validation passed for **560 source keys across five translations**, and the diff check was clean.

The delayed account-transition race was reviewed in source; no direct asynchronous dynamic fault test was run, and these checks do not establish that the race was reproduced.

The pre-fix SE baseline on committed product revision `5bd2124` passed **3/0/0** in `/tmp/trust-polish-20261028-se-baseline.xcresult`. Earlier picker attempts had test-harness failures involving a guessed German Cancel label, missing scrolling, and an invalid navigation-inset frame assumption; corrected focused tests passed. The mixed-result bundles are not full suite passes. Initial Duo inner attachments were black, so the later active-display captures were used for visual review.

## Final Duo accessibility review

The final Duo accessibility check passed **1 passed, 0 skipped, and 0 failed** in `/tmp/trust-polish-20261028-duo-final-accessibility.xcresult`. Astra approved the active-display captures in `/tmp/trust-polish-20261028-duo-final-captures/`: the full-width stacked German language value is complete, the picker toolbar is clean, and Activity has no overlap.

## Retained visual evidence

These fictional demo captures were visually reviewed: [SE Portuguese Sharing](screenshots/se-portuguese-sharing.png), [SE German picker](screenshots/se-german-picker.png), [Duo German Language](screenshots/duo-german-language.png), and [Duo German picker](screenshots/duo-german-picker.png). Result bundles and remaining captures under `/tmp` may be removed by system cleanup.
