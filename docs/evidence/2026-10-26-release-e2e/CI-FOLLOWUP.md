# Cloud CI follow-up — 26 October 2026

The checks for PR 18 head `80d1391662947a2c67f838b88526604d9ba7fceb` failed after the local release-49 runs completed. This follow-up changes UI-test helpers only; the production app source and uploaded build 49 remain unchanged.

## Observed failures

- GitHub iOS run `40388520259` failed the 375-point compact Sharing geometry test in Simplified Chinese. Its saved witness contains one valid sample: `visible=true`, `geometry=true`, the row is 327×50 points, and all four control targets are 44×44 points. The screenshot retains the compact name/modes/menu row. Remote accessibility reads consumed the eight-second sampling budget before a second stability sample could be taken.
- Xcode Cloud reported failures before the Pause menu item appeared in two tests, and an Appearance selection whose picker remained Light with the Dark option still visible in the native menu. These reports do not establish a product state or layout regression; the test contacts and their postconditions need reliable synchronization.

## Test changes

Menu triggers and selections now require stable, fully visible targets. Each action checks its actual result: a visible Pause sheet, the Remove confirmation, or the Appearance picker value. If a native tap leaves the original control visible and the result unchanged, one bounded element-centered contact is allowed; the same strict result is still required. Failed activation exits the current scenario instead of cascading into unrelated controls.

The geometry sampler retains the compactness, ordering, visibility, hittability, spacing, and target-size assertions. It removes redundant accessibility lookups and allows a 30-second budget for two matching visible samples. It does not accept the single-sample CI witness as a pass. Two ambiguous trailing-closure warnings in the native location-settings test helper were also resolved without changing behavior.

## Local verification

A fresh task-owned iPhone SE simulator on iOS 26.5 completed all six focused tests: **6 passed, 0 skipped, 0 failed**. Result: `/tmp/trust-ci-fix-20261026/menus-and-geometry.xcresult`.

- Appearance selection and persistence across relaunch.
- Language selection and persistence.
- Pause first-open visibility, every duration, and Cancel across six shipped languages at maximum text size.
- Pause, Resume, Off, and Remove as separate actions.
- Compact Sharing geometry across shipped locales at 375-point width.
- German extra-large row boundary.

The named Xcode build-for-testing and `git diff --check` completed successfully. These focused results do not assert that remote CI has passed; inspect the current PR head after the test-only fix is pushed. No release, entitlement, consent, or review gate was changed.
