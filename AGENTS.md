# Trust repository guidance

## Product and design
- Follow `docs/DESIGN.md` for the current visual direction and screen intent. Keep consent explicit, privacy language accurate, and sharing off until a person chooses a mode.
- Preserve the existing route identifiers, accessibility identifiers, and API contracts unless the task specifically changes them.
- Keep system light and dark appearances readable. Use `TrustPalette.paper` and shared Trust components for iOS UI.

## Model workflow
- **Astra:** plan the scope and agree on a visual milestone before broad implementation; review the finished screens against that milestone.
- **Luna:** implement the approved work, fix issues found during review, update docs, and run requested checks.
- **Sol:** perform routine independent code review and report actionable findings.
- Keep changes within the assigned files when work is split across agents. Do not commit unless asked. Preserve unrelated user changes.

## Checks
- iOS package checks: `cd apps/trust-ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- Simulator builds and UI automation require the named Xcode installation and a booted simulator. Do not start a shared build while another agent owns the build or simulator run.
- API checks: run the repository's `apps/trust-api/TrustApi.Tests` suite when API files change.
- Report checks that could not run and why; do not claim a check passed unless it completed.

## Release and privacy
- Never add source-controlled deployment secrets, signing credentials, or customer data.
- Do not flip review, release, or entitlement flags to bypass validation.
- Verify privacy statements against actual app behavior. The app does not guarantee push notification delivery; use qualified language.
