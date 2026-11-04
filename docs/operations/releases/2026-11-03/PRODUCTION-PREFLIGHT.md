# Production preflight — 3 November 2026

This records read-only provider and public-site observations after delivery of Staging 52 and the accepted App Store assets. **Production deployment, database recovery and public submission have not been performed.** Physical two-iPhone acceptance is deferred at the owner's request. The normal build-52 upload remains held.

## Current production resources

- Render API `srv-daabv1lg1s2s73co5gm0` (`trust-api`) serves deployment `dep-db5s6ffavr4c73fdm8k0`, source `96813cf8ed1ef330601ccbeeac89e37137546c4e`, completed 11 October. Its configured branch is `main` and auto-deploy is enabled; a later merge can therefore have deployment consequences. No branch or auto-deploy setting was changed.
- A targeted read of only `ConnectionStrings__Postgres`, parsed in memory, matched the database name and internal host identifier to `dpg-daabu1e7bikc73808dt0-a` (`trust-postgres`). The value was neither printed nor saved. This proves configured identity, not a live database connection or migration ledger.
- That Postgres instance is available in Oregon, PostgreSQL 16, Basic 256 MB, 15 GB; HA and storage autoscaling are off and its external IP allowlist is empty. Point-in-time recovery reports AVAILABLE, beginning `2026-10-31T14:38:41Z`; no logical exports are listed. Workspace retention tier, off-provider backups, usable recovery access and an executed restore drill remain unverified.
- Cloudflare `jointrust-web` serves version `7c972d4a-bcb2-48df-8561-15e77ef5670d` at 100%, deployment `cf256f4e-db1e-4cea-a014-c5ec921ed1b9`. Its source commit remains unverified. Apex and `www` custom domains and workers.dev are enabled; previews are disabled. The existing Wrangler OAuth refresh succeeded without new scopes or a duplicate credential.

## Website compatibility

The live [privacy](https://jointrust.app/privacy) and [support](https://jointrust.app/support) pages still describe choosing a handle, while the candidate assigns it automatically and allows later editing. Live policy and support copy also differ on country suggestion, recovery, age setup and some Plus details. The source candidate is unchanged from the staged web source `e4cdf72`; production provenance cannot be inferred from that equivalence.

The optional `/api/region` endpoint returns 404 in production. The client correctly retains its United States/+1 default and permits manual selection on non-success responses. AASA and a synthetic invite route passed their public checks; the SMS page and opt-in image match the candidate. These observations do not establish carrier delivery or production campaign configuration.

The TestFlight install-and-reopen path remains appropriate before public availability. Switching invitations to a public download is a launch-time action requiring a verified live App Store URL; do not invent or switch that link prematurely.

## Confirmed migration compatibility issue

The original migration 023 made `phone_challenges.challenge_id` mandatory without a default. The deployed `96813cf` writer omits that column. Old instances serving during migration, or a binary-only rollback, would fail phone-challenge writes. The reviewed fix installs `gen_random_uuid()` as the default inside migration 023 before the backfill and NOT NULL commit; append-only migration 030 repairs already-migrated databases without rewriting existing IDs. The actual `96813cf` INSERT/ON CONFLICT SQL passed at the 023 boundary and current schema; historical-029 repair and explicit current-writer ID preservation passed. The targeted regression passed 1/1 and the required full API suite passed 258/258 on task-owned local PostgreSQL 16.15, with fake data only. The cluster was stopped and removed. Test output was streamed; no raw log/TRX was retained, and the protected summary states that evidence limit. Sol found no remaining issues. The old `e4cdf72` deployment request is superseded and must not be executed; the existing Staging API now serves exact candidate `b3817229bdfa0c66810fb6afb5354b1b7739deab` under deployment `dep-dbl6afou01pc73a03i60`, live at 22:51:40 UTC. Both health endpoints returned 200 and an invalid Apple identity token returned 401 `invalid_apple_token`. Startup-before-serving plus readiness establishes successful service startup; no direct database migration-ledger query was performed. The iOS application source/build remains unchanged.

Migrations use a migration-process advisory lock and separate transactions per file. Normal API writers do not acquire that advisory lock. A later migration failure can leave an applied prefix; backfills, constraint validation and nonconcurrent indexes can block traffic. Migration 029 intentionally blocks recovery requests with unknown environments; preserve that verification rule. These migrations do not update customer handles or privacy-hold tables or delete customer rows.

## Recovery rehearsal preparation

Protected API request drafts describe recovery into a separate temporary environment and deployment by exact commit. They are **not execution-ready** until destination isolation, validation access, recovery point, cost and cleanup are concrete and approved. The existing unsafe-source deployment draft is explicitly superseded.

Render recovery creates another billable instance; omitting the destination environment defaults to production. It copies the source external allowlist, which alone does not isolate same-region internal access. Use a separate environment with verified network isolation, preserve an empty external allowlist, and never connect the production API to the rehearsal copy. Do not create a restore, new environment or paid resource as a read-only check. See [recovery API](https://api-docs.render.com/reference/recover-postgres), [environment API](https://api-docs.render.com/reference/create-environment), [backup/recovery documentation](https://render.com/docs/postgresql-backups) and [private networking](https://render.com/docs/postgresql-creating-connecting).

The smallest paid Postgres compute tier is listed at $6/month; storage and other applicable charges are additional, and the instance remains billable until deletion. This is a pricing reference, not a guaranteed rehearsal total. Confirm the actual plan, duration and approved budget before creation. See [current pricing](https://render.com/pricing) and [plan identifiers](https://render.com/docs/compute-plans).

After an approved rehearsal proves restoration and migration compatibility, obtain the separate production-rollout authorization and follow the [rollout plan](../2026-11-02/PUBLIC-ROLLOUT-PLAN.md). API binary rollback does not reverse schema or recovery-state changes. Do not upload normal 52 or submit App Review until the compatible production services and remaining customer/reviewer evidence are established.

## Protected evidence

Raw provider responses, public-page snapshots, redacted binding results, OAuth expiry/hash metadata and request drafts are retained under `/Users/juanquirino/Library/Developer/Xcode/Archives/2026-11-03/Trust-1.0-52-ReleasePreparation/verification/production-readiness-20261103` (0700; files 0600). Provider-managed secrets remain in Render and existing CLI credential storage; inventory references were updated without secret values or duplicates.
