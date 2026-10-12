# Trust cloud development

Prepared on 2026-10-11. Codex Cloud handles source edits and Linux checks; Xcode Cloud handles native iOS builds and simulator tests. A private Codex Cloud **draft** has been saved; it has not been published or tested in the cloud. Xcode Cloud is **not yet configured or verified**. The Mac is accessible. New security-sensitive access grants, legal agreements, publication, and distribution still require review before execution.

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

## First Xcode Cloud workflow to configure

Use the existing app record for bundle **`com.collapsetechnologies.trust`**, team **`3S529795M9`**. The signed-in Apple Account, role, current agreements, included compute balance, and existing Xcode Cloud configuration must be verified directly; repository settings establish none of them.

Proposed initial workflow **Trust validation**:

- Repository: `QuirinoC/trust`; project: `apps/trust-ios/Trust.xcodeproj`; shared scheme: **Trust**.
- First run: manual on `codex/cloud-development-setup` at the reviewed revision. After its result is reviewed, start builds on pull request creation/updates targeting `main`, for `codex/*` branches. This lets Codex sessions get an iOS build/test result on their PR. Do not enable default-branch release automation.
- Actions: simulator Build and Test, using the scheme's **Debug** test configuration. Age, demo, and test-keychain fixtures require DEBUG. No Archive action or TestFlight post-action in this first workflow.
- Start with one iPhone simulator. Choose an available Xcode version compatible with the linked DeclaredAgeRange and PermissionKit SDKs. Local isolated testing of the previously failing sharing-actions test passed on Xcode 27.0/iOS 26.5; GitHub's full CI on Xcode 26.6/iOS 26.5 failed that test while waiting for the pause menu to dismiss. This single comparison does not prove the cause; validate the full suite on the actual cloud version before relying on it. Record the actual Xcode version instead of assuming either is offered.
- Keep the existing standard TrustCore/UI suite. Opt-in local API tests need explicit loopback Development fixtures and intentionally skip without them. The separate GitHub CI lane continues to exercise its configured API UI cases.
- No custom secrets, exported signing keys, added distribution recipients, or automatic tester notifications.

Apple's [workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference) requires initial setup in Xcode; later workflows can be managed in App Store Connect. Use the Developer Program's included allocation, currently [25 compute hours per month](https://developer.apple.com/xcode-cloud/get-started/). Verify the account's remaining balance before starting; no paid upgrade or purchase is authorized.

The executable hook `apps/trust-ios/ci_scripts/ci_post_clone.sh` sits beside the project and resolves the monorepo through `CI_PRIMARY_REPOSITORY_PATH`. It calls `Scripts/validate_cloud_build.py` to reject stale localizations and unexpected checked-in configuration. This follows Apple's [custom script location convention](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts). This source check does not inspect a signed archive, override provider workflow settings, or prove entitlement/signing readiness.

Local hook and validator checks:

```sh
CI_PRIMARY_REPOSITORY_PATH="$PWD" apps/trust-ios/ci_scripts/ci_post_clone.sh
python3 -m unittest discover -s apps/trust-ios/Scripts -p 'test_validate_cloud_build.py'
```

## Access and publication review

1. **Local UI access:** the earlier lock-state assessment was stale and incorrect. Xcode is open with `apps/trust-ios/Trust.xcodeproj` on branch `codex/cloud-development-setup`. The signed-in Apple account is on team **Collapse Technologies LLC** as **Admin**. The Xcode Cloud assistant has `Trust iOS` and that team selected; its repository screen shows `QuirinoC/trust` as **Not connected**. Clicking **Connect** opened App Store Connect in Safari. The page directs the user to link the Apple Account with GitHub, then install Apple's app for this repository only. GitHub is currently showing the **Authorize Xcode Cloud** consent for account `QuirinoC`; it says the app will verify the GitHub identity, see accessible resources, and act on the user's behalf. No authorization or repository installation has been accepted. The next action needs just-in-time approval. Inspect the following app installation screen and verify its scopes before installation.
2. **GitHub → Apple:** local GitHub CLI identifies `QuirinoC` with admin access to this public repository. The public [Xcode Cloud GitHub app](https://github.com/apps/xcode-cloud) currently declares `contents:read`, `metadata:read`, `pull_requests:read`, `checks:write`, and `statuses:write`, as verified by `gh api apps/xcode-cloud`. Install/select **only QuirinoC/trust**. Apple's account-linking consent may request additional user permissions; those must be read on the actual screen before approval. A read-only installed-app lookup returned HTTP 403 (“You must authenticate with an access token authorized to a GitHub App…”); this does not prove the app is absent, and no new token was created.
3. **GitHub → Codex Cloud:** the existing connection already exposes Trust to the intended profile. If later setup requests a new persistent connection, present the exact app identity, account, repository selection, and displayed permission scopes before granting it. Do not assume Apple's scopes apply to Codex.
4. **Repository publication:** draft PR #17 targets `main`; its head was `c023686` when the Xcode test failure was investigated. The branch contains no service deployment or release action. The GitHub iOS check failed one UI test on Xcode 26.6; the focused test passed locally on Xcode 27.0. Review the full-run result before merging. Merging into `main` is a separate action. Check deployment filters again before any main-branch publication.
5. **Environment/workflow activation:** review Codex's private environment publication, network policy, Apple's account-linking/install consent, any legal agreements, and the first manual simulator build. No credentials or signing keys should be pasted into chat; use the provider's secure UI if a credential is actually required.
6. **Distribution:** separately review any signing/credential creation and the exact archive/export/upload action before it can expose a build to testers. Do not enable distribution during the initial simulator workflow.

## Later TestFlight lane

Build 46 is already recorded as uploaded in the delivery notes, so verify App Store Connect's current build inventory and choose a unique build number before a future archive. Both current app targets require phone verification. Never restore the historical internal bypass.

Before upload, name the exact source revision, scheme, version/build number, bundle/team, export mode, and tester group. The dated runbook records **Trust Family Auto** with access to all builds and Automatic for Xcode Builds enabled; verify its current membership/settings. An upload may therefore make a build available and send tester notifications without a separate manual assignment. Treat upload and any distribution-capable archive workflow as an approval boundary. Confirm signing, production API URL, entitlements, and disabled bypasses in the resulting artifact. No App Store submission or public release is authorized.

## Provider evidence for the earlier push

At the 2026-10-11 read-only check, remote `main` was `c70756f390342f6fc859f75eed4cb2f23c0abecc`. [GitHub CI 38170737540](https://github.com/QuirinoC/trust/actions/runs/38170737540) was running; API and web jobs had passed. GitHub returned no deployments attached to this commit.

Render's live `trust-api` service (`srv-daabv1lg1s2s73co5gm0`) has automatic deploys from `main`, filtered to `apps/trust-api/**` and excluding API tests/README. Its latest deployment was `dep-db5s6ffavr4c73fdm8k0`, live on `96813cf`, started at 10:11 AM PDT on 11 October. No `c70756f` deploy appeared in the provider history. This is provider evidence; the root `render.yaml` alone would not establish the live filter or deployment state.

Cloudflare's `jointrust-web` deployment history likewise showed no new website deployment after the push. The newest entry was `cf256f4e-db1e-4cea-a014-c5ec921ed1b9`, created by Wrangler at 3:58 PM PDT on 5 October, with version `7c972d4a-bcb2-48df-8561-15e77ef5670d` serving 100% of traffic. No Render or Cloudflare mutation was performed for this check. Apple upload/distribution state was not refreshed in this work; no Apple upload was initiated.

Provider publication/activation and an actual Xcode Cloud result are still outstanding. Xcode Cloud setup is paused at GitHub's account-link authorization screen until the user approves it. Follow the just-in-time confirmation requirement before authorizing the Apple/Xcode Cloud app or installing it for the repository; verify the actual scopes before installation.

## Local validation evidence

Evidence is retained in the ignored `out/cloud-development-setup-20261011/` directory. Validation used an isolated copy of the repository in disposable Docker containers; no production database or existing project container was used.

- Ubuntu 24.04 **x86_64** setup completed with .NET SDK **9.0.121**, Node **22.23.3**, and PostgreSQL **16**. The complete check script passed both as root and as the ordinary `ubuntu` user (the latter launched from `/tmp`): **216 API tests passed, zero skipped**, **3 web tests passed**, and source/localization guards passed. Logs: `linux-amd64-setup.log`, `linux-amd64-check.log`, `linux-amd64-nonroot-check-restored.log`.
- An initial cross-user check incorrectly reused restore assets pointing to `/root/.nuget` and failed compilation. Restoring packages as the same ordinary user corrected the validation setup. No application source change was needed.
- Bounded checks confirmed that an earlier .NET 8 executable/incorrect `DOTNET_ROOT` are replaced by the installed .NET 9 path, dev HTTPS certificate generation is disabled, and occupied ports 5433–5435 fail before database creation with no temporary cluster left behind. Both completed full suites stopped their private PostgreSQL servers and removed their temporary data. Log: `linux-edge-checks.log`.
- The Xcode hook passed with the expected repository, project, and scheme; **9 validator mutation tests passed**. Shell syntax and `git diff --check` passed. The source guard tests include legal placements for target build settings and inherited xcconfig references.
- Actual Release iOS-device build settings resolved with named Xcode 27.0 to team `3S529795M9`, bundle `com.collapsetechnologies.trust`, production API `https://trust-api-u0ft.onrender.com`, and build 46. Both source phone-verification bypass flags are false. Evidence: `release-settings.json`. This was settings inspection, not an archive, signing check, or upload.
- The earlier app fix at `c70756f` passed **103 Swift core tests and 15 age-gate UI tests**, followed by a successful simulator build. Those are baseline app checks, separate from this script-only preparation. Evidence: `out/commit-validation-20261011/`.
- An isolated simulator run of `testPauseResumeOffAndRemoveAreSeparateActions` passed on Xcode **27.0** / iOS **26.5**. The GitHub PR's Xcode **26.6** run failed the same test at the pause-menu dismissal check; all other checks in that CI run passed. Recheck on Xcode Cloud before considering the UI lane healthy.
- **Limitation:** the separate Ubuntu 24.04 ARM64 Docker attempt exited with SIGILL (132) during .NET restore, including with an official Microsoft SDK diagnostic. Its cause remains unresolved. No workaround was shipped; only x86_64 is validated here. No Codex Cloud VM or Xcode Cloud build has passed yet.

Independent Sol review found no remaining runtime blocker after fixes; its final test-fixture placement correction was applied and the 9 guard tests rerun. A screenshot of the saved private draft is retained as `codex-cloud-draft.jpg`. The Codex Cloud environment remains a private, unpublished draft. Xcode Cloud is not connected or configured: the Apple account and team are present, but GitHub's authorization step and the repository app installation remain pending.
