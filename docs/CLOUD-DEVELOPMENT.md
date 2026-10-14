# Trust cloud development

Prepared on 2026-10-11; updated 2026-10-14. Codex Cloud is intended for source edits and Linux checks; Xcode Cloud handles native iOS builds and simulator tests. The private Codex Cloud environment remains an unpublished, untested draft. Trust's workflow is configured and its build passed. Cloud and GitHub runs exposed two brittle UI-test checks; this update hardens those checks and locally verifies both affected tests. Pixelboard workflow setup is blocked in Xcode's repository-access step. Amber Capture's shared scheme is ready in draft PR #6, but its Xcode Cloud workflow is not configured yet.

## Repository setup

This cloud setup branch is based on `c70756f390342f6fc859f75eed4cb2f23c0abecc`. The earlier two-file age-gate fix at that revision was committed and pushed after Juan directly said **“Commit merge and push everything”** in this chat. The cloud setup is tracked separately in draft PR #17; merge to `main` remains separate from setup and testing.

On a disposable **Ubuntu 24.04** development environment, from the repository root:

```sh
bash scripts/cloud/setup.sh
bash scripts/cloud/check.sh
```

The setup installs .NET 9, Node 22, Python, and PostgreSQL 16. It needs root or noninteractive sudo inside the disposable environment. Do not run this Linux installation script on the release Mac. `check.sh` supplies its own temporary loopback PostgreSQL cluster and database to the API suite; it never uses the production database or the existing Docker Compose volume. It also runs the web tests and checks iOS source configuration and localization freshness. Native SwiftUI builds remain an Xcode responsibility.

No Apple, Render, Cloudflare, Twilio, production database, or customer credentials are needed for these development checks. Run setup and checks as the same operating-system user; NuGet restore records that user's package-cache paths. Run setup again after dependency or user changes. Report tests that skip their required external fixtures as skipped, not passing evidence.

## Codex Cloud environment to configure

The browser profile showed **Juan Quirino, Pro**. The existing Codex Cloud GitHub connection showed **QuirinoC** and already listed `QuirinoC/trust`. The environment draft is named **Trust development**, selects **`QuirinoC/trust` only**, and has **Only me** privacy. No new GitHub access grant was needed or accepted.

In Settings → Codex Cloud → Environments, **Get started** automatically opened the provider's [Set up trust](https://chatgpt.com/local/01a12ca6-8865-76f0-9429-85d8b4e0703e?hostId=local) onboarding chat. Its automatic turn was stopped immediately; the UI reported **You stopped after 0s**. Do not resume that turn blindly. The saved draft contains an install script that resolves the current Git checkout, fails if the unpublished setup files are absent, then runs `bash scripts/cloud/setup.sh` followed by `bash scripts/cloud/check.sh`. Startup guidance preserves the repository rules and approval boundaries. The UI confirmed **All changes saved**; **Publish** was not clicked. This is not a verified prepared cloud filesystem.

Before running setup, verify the actual VM is Ubuntu 24.04 x86_64, the install script's working directory is within the Trust checkout, and its revision contains the approved cloud setup files. Review the successful setup report before publishing. New tasks use the published environment; existing tasks retain their own files. These steps follow [official OpenAI documentation](https://learn.chatgpt.com/docs/environments/cloud-environments).

Suggested startup instructions for that environment:

> Work only in QuirinoC/trust. Read AGENTS.md and docs/DESIGN.md. Run bash scripts/cloud/check.sh for Linux validation. Native iOS verification runs through the reviewed Xcode Cloud workflow. Keep sharing consent and all account, age, phone, transaction, and privacy gates intact. Report skipped or unavailable checks accurately. Prepare changes on a codex/ branch and a draft PR when publication is specifically approved. Do not deploy services or upload/distribute TestFlight builds without the exact release approval.

The draft retains the provider's **Package managers** network preset, internet enabled, no additional domains, no network secrets, and no environment variables. These network settings were inspected and not changed. The Linux setup needs Ubuntu package mirrors (`archive.ubuntu.com`, `security.ubuntu.com`), Ubuntu's .NET backports PPA (`ppa.launchpadcontent.net`, with Launchpad/keyserver access during repository registration), NodeSource (`deb.nodesource.com`), NuGet (`api.nuget.org`), and npm (`registry.npmjs.org`). Review actual allowlist coverage and redirects before cloud execution; request any missing domain permission explicitly. Do not switch to unrestricted networking or add a production secret to make a development check pass. The existing GitHub connection's full original consent scopes were not re-inspected; no scopes were expanded.

## Trust Xcode Cloud workflow

Use the existing app record for bundle **`com.collapsetechnologies.trust`**, team **`3S529795M9`**. Xcode showed the Apple Account as an Admin on **Collapse Technologies LLC**. The actual Xcode Cloud usage balance is not available: the App Store Connect browser session expired during this work, so do not start more builds until the account usage page can be checked. No paid compute subscription or purchase was made.

Configured workflow **Trust validation**:

- Repository: `QuirinoC/trust`; project: `apps/trust-ios/Trust.xcodeproj`; shared scheme: **Trust**.
- Start conditions: pushes to `main`; pull requests from any source branch targeting `main`; manual start on any branch. Automatic builds cancel older queued or running builds of the same type on that branch.
- Actions: simulator Build and Test, using the shared **Trust** scheme. Test is required to pass. The build action targets **Any iOS Simulator**; tests use the recommended iPhones on the latest available simulator runtime. No Archive action, distribution, or TestFlight post-action is configured.
- Environment: **Latest Release** Xcode and macOS, no custom environment variables or secrets. The first build resolved to Xcode **27 (27A266a)** and macOS **Golden Gate 27 (26A428)**. Its Build action passed; its Test action completed with one precision-only failure: the measured 44-point People detent control was `43.99999999999997`. The PR-triggered build also passed and reported the same failure. The first build was manually started on `main` at `c70756f` (the setup branch selector offered only `main`).
- Xcode warned that the shared `Trust` scheme might exist only locally, even though `Trust.xcscheme` is tracked on both the setup branch and `main`. The cloud Build action completed successfully, confirming that the remote scheme was found.
- The Developer Program includes 25 compute hours per month, but the remaining balance could not be checked. Do not start optional or manual workflows until the balance is visible in App Store Connect or the Apple Developer app. A push to this active PR triggers its required validation automatically. Do not purchase or enable a paid compute plan.
- Keep the existing standard TrustCore/UI suite. Opt-in local API tests need explicit loopback Development fixtures and intentionally skip without them. The separate GitHub CI lane continues to exercise its configured API UI cases.
- No custom secrets, exported signing keys, added distribution recipients, or automatic tester notifications.

Apple's [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference) requires initial setup in Xcode; later workflows can be managed in App Store Connect. Use the Developer Program's included allocation, currently [25 compute hours per month](https://developer.apple.com/xcode-cloud/get-started/). Check the account's remaining balance before any additional build; no paid upgrade or purchase is authorized.

Company scope is the three iOS apps listed for Collapse Technologies LLC: **Trust: Location Sharing** (`QuirinoC/trust`, shared scheme `Trust`), **Infinite Pixelboard** (`QuirinoC/collapse-tech`, project `apps/infinite-pixelboard-ios/InfinitePixelboard.xcodeproj`, shared scheme `InfinitePixelboard`), and **Amber Capture** (`QuirinoC/amber-sec`, project `src/AmberCapture/AmberCapture.xcodeproj`). Pixelboard's project and shared scheme are discoverable from the clean local `collapse-tech` checkout, and its `Package.resolved` pins public Google/Firebase packages. Xcode recognized `QuirinoC/collapse-tech` as connected but left **Next** disabled in the source-repository step; the page also listed the public package repositories as not connected. The App Store Connect browser session expired during this step. Apple documents that publicly accessible Swift packages need no separate Xcode Cloud setup, so don't expand GitHub permissions to these external repositories unless Xcode reports a private dependency and its exact required access. No Pixelboard workflow was saved or build started.

For Amber Capture, the original local checkout has extensive unrelated uncommitted work and is 37 commits behind `origin/main`; it was left untouched. A clean worktree from remote `main` now contains a shared `AmberCapture` scheme on branch `codex/amber-xcode-cloud-scheme`. `xcodebuild -list` recognizes it, build-for-testing succeeds, and draft PR [#6](https://github.com/QuirinoC/amber-sec/pull/6) has all GitHub checks passing. The Xcode Cloud workflow still needs to be configured after App Store Connect access is restored.

The executable hook `apps/trust-ios/ci_scripts/ci_post_clone.sh` sits beside the project and resolves the monorepo through `CI_PRIMARY_REPOSITORY_PATH`. It calls `Scripts/validate_cloud_build.py` to reject stale localizations and unexpected checked-in configuration. This follows Apple's [custom script location convention](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts). This source check does not inspect a signed archive, override provider workflow settings, or prove entitlement/signing readiness.

Local hook and validator checks:

```sh
CI_PRIMARY_REPOSITORY_PATH="$PWD" apps/trust-ios/ci_scripts/ci_post_clone.sh
python3 -m unittest discover -s apps/trust-ios/Scripts -p 'test_validate_cloud_build.py'
```

## Access and publication review

1. **Local UI access:** Xcode is signed in to team **Collapse Technologies LLC** as **Admin**. The Xcode Cloud assistant created the Trust workflow for `QuirinoC/trust`. App Store Connect lists three iOS apps for Collapse Technologies LLC: Trust: Location Sharing, Amber Capture, and Infinite Pixelboard. Their local project/repository mapping is Trust → `QuirinoC/trust`, Amber Capture → `QuirinoC/amber-sec`, and Infinite Pixelboard → the `apps/infinite-pixelboard-ios` project in `QuirinoC/collapse-tech`.
2. **GitHub → Apple:** the public [Xcode Cloud GitHub app](https://github.com/apps/xcode-cloud) has read access to code, metadata, and pull requests, plus write access to checks and commit statuses. With the user's approval, it is installed for **All repositories** owned by the personal account `QuirinoC`; this covers current and future repositories, while public repositories are read-only. GitHub's Installed GitHub Apps page confirmed installation ID `170905458` and those exact permissions. No Collapse Technologies GitHub organization exists in the account; the user's personal `QuirinoC` account owns the company repositories.
3. **GitHub → Codex Cloud:** the existing connection already exposes Trust to the intended profile. If later setup requests a new persistent connection, present the exact app identity, account, repository selection, and displayed permission scopes before granting it. Do not assume Apple's scopes apply to Codex.
4. **Repository publication:** draft PR #17 targets `main`. Its GitHub iOS job failed `testSharingCompactRowGeometryAtStandardTextAcrossShippedLocales` because the frame sampler returned one sample before its eight-second deadline; the attached recording showed the row in bounds. The Cloud test failed `testPeopleMapPinRemainsAboveListAtEveryDetent` because of subpoint rounding at the 44-point boundary. This update removes repeated hit-test queries while sampling, extends the deadline, keeps final control hit-test assertions, and allows 0.01 point for frame rounding. Both affected UI tests passed locally on Xcode 27 / iOS 26.5. Review the new PR checks before merging; merging into `main` remains separate. Check deployment filters again before any main-branch publication.
5. **Environment/workflow activation:** Codex's private development environment is still an unpublished draft with network policy and setup checks not yet exercised in that provider. Apple's Xcode Cloud GitHub installation and Trust workflow are configured. Check remaining compute before optional or manual builds; pushes to the active PR trigger required validation automatically. No credentials or signing keys should be pasted into chat; use the provider's secure UI if a credential is actually required.
6. **Distribution:** separately review any signing/credential creation and the exact archive/export/upload action before it can expose a build to testers. Do not enable distribution during the initial simulator workflow.

## Later TestFlight lane

Build 46 is already recorded as uploaded in the delivery notes, so verify App Store Connect's current build inventory and choose a unique build number before a future archive. Both current app targets require phone verification. Never restore the historical internal bypass.

Before upload, name the exact source revision, scheme, version/build number, bundle/team, export mode, and tester group. The dated runbook records **Trust Family Auto** with access to all builds and Automatic for Xcode Builds enabled; verify its current membership/settings. An upload may therefore make a build available and send tester notifications without a separate manual assignment. Treat upload and any distribution-capable archive workflow as an approval boundary. Confirm signing, production API URL, entitlements, and disabled bypasses in the resulting artifact. No App Store submission or public release is authorized.

## Provider evidence for the earlier push

At the 2026-10-11 read-only check, remote `main` was `c70756f390342f6fc859f75eed4cb2f23c0abecc`. [GitHub CI 38170737540](https://github.com/QuirinoC/trust/actions/runs/38170737540) was running; API and web jobs had passed. GitHub returned no deployments attached to this commit.

Render's live `trust-api` service (`srv-daabv1lg1s2s73co5gm0`) has automatic deploys from `main`, filtered to `apps/trust-api/**` and excluding API tests/README. Its latest deployment was `dep-db5s6ffavr4c73fdm8k0`, live on `96813cf`, started at 10:11 AM PDT on 11 October. No `c70756f` deploy appeared in the provider history. This is provider evidence; the root `render.yaml` alone would not establish the live filter or deployment state.

Cloudflare's `jointrust-web` deployment history likewise showed no new website deployment after the push. The newest entry was `cf256f4e-db1e-4cea-a014-c5ec921ed1b9`, created by Wrangler at 3:58 PM PDT on 5 October, with version `7c972d4a-bcb2-48df-8561-15e77ef5670d` serving 100% of traffic. No Render or Cloudflare mutation was performed for this check. Apple upload/distribution state was not refreshed in this work; no Apple upload was initiated.

The Xcode Cloud GitHub installation is verified for every repository owned by `QuirinoC`. Trust's workflow is saved; both Build actions passed, while the initial main and PR Test actions failed on the 44-point rounding assertion described above. A GitHub retry was launched on the earlier head; the PR update will trigger fresh checks against the hardened tests. Pixelboard remains blocked at Xcode's repository step. Amber's shared scheme is now available in draft PR #6 and its GitHub checks pass, but its Apple workflow remains unconfigured. App Store Connect's browser session ended at `authResult=FAILED`; sign in again to finish Pixelboard and Amber setup and to check remaining compute hours. No archive, upload, distribution, service deployment, or paid compute plan was enabled.

## Local validation evidence

Evidence is retained in the ignored `out/cloud-development-setup-20261011/` directory. Validation used an isolated copy of the repository in disposable Docker containers; no production database or existing project container was used.

- Ubuntu 24.04 **x86_64** setup completed with .NET SDK **9.0.121**, Node **22.23.3**, and PostgreSQL **16**. The complete check script passed both as root and as the ordinary `ubuntu` user (the latter launched from `/tmp`): **216 API tests passed, zero skipped**, **3 web tests passed**, and source/localization guards passed. Logs: `linux-amd64-setup.log`, `linux-amd64-check.log`, `linux-amd64-nonroot-check-restored.log`.
- An initial cross-user check incorrectly reused restore assets pointing to `/root/.nuget` and failed compilation. Restoring packages as the same ordinary user corrected the validation setup. No application source change was needed.
- Bounded checks confirmed that an earlier .NET 8 executable/incorrect `DOTNET_ROOT` are replaced by the installed .NET 9 path, dev HTTPS certificate generation is disabled, and occupied ports 5433–5435 fail before database creation with no temporary cluster left behind. Both completed full suites stopped their private PostgreSQL servers and removed their temporary data. Log: `linux-edge-checks.log`.
- The Xcode hook passed with the expected repository, project, and scheme; **9 validator mutation tests passed**. Shell syntax and `git diff --check` passed. The source guard tests include legal placements for target build settings and inherited xcconfig references.
- Actual Release iOS-device build settings resolved with named Xcode 27.0 to team `3S529795M9`, bundle `com.collapsetechnologies.trust`, production API `https://trust-api-u0ft.onrender.com`, and build 46. Both source phone-verification bypass flags are false. Evidence: `release-settings.json`. This was settings inspection, not an archive, signing check, or upload.
- The earlier app fix at `c70756f` passed **103 Swift core tests and 15 age-gate UI tests**, followed by a successful simulator build. Those are baseline app checks, separate from this cloud-setup and test-harness update. Evidence: `out/commit-validation-20261011/`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed **103 TrustCore tests**. A focused Xcode 27.0 / iOS 26.5 simulator run passed `testPeopleMapPinRemainsAboveListAtEveryDetent` and `testSharingCompactRowGeometryAtStandardTextAcrossShippedLocales` after the test-only fixes described above. Remote PR CI and Xcode Cloud checks against the updated branch are still required.
- **Limitation:** the separate Ubuntu 24.04 ARM64 Docker attempt exited with SIGILL (132) during .NET restore, including with an official Microsoft SDK diagnostic. Its cause remains unresolved. No workaround was shipped; only x86_64 is validated here. The Codex Cloud VM remains untested; Xcode Cloud's Build actions passed, but its initial Test actions failed on the UI-test assertions described above.

Independent Sol review found no remaining runtime blocker after fixes; its final test-fixture placement correction was applied and the 9 guard tests rerun. A screenshot of the saved private draft is retained as `codex-cloud-draft.jpg`. The Codex Cloud environment remains a private, unpublished draft. Xcode Cloud is configured for Trust only; Pixelboard and Amber workflows still need App Store Connect setup. The Apple account and team are present, GitHub OAuth is linked, and the Xcode Cloud GitHub app is installed for all `QuirinoC` repositories.
