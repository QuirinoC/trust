# Trust staging: purchase recovery operator continuation

**Status: implementation and local verification only.** No real customer case or positive in-app purchase recovery has been operated from this Mac. This record describes the source workflow; it does not establish that these changes are deployed to staging or production. Phone ownership conflicts are Support cases, not an automatic transfer of phone ownership or account data. The purchase procedure below applies only to a verified purchase-recovery request.

## Before operating

- Obtain the existing pending or blocked Support case and independently establish the appropriate ownership evidence and authorization. This code does not define the human evidence standard. Do not infer approval from a customer providing an identifier.
- Match exactly three values from the same case: **original transaction ID**, **old app account token** (UUID from the verified purchase), and **target Trust account ID** (UUID). The case's reference is useful for Support, but it is not one of the command's three arguments. Do not put actual customer identifiers or case data in this document, chat, shared logs, or source control.
- Run the operator on an authorized host that has the matching source and .NET 9 SDK, private network access to the correct staging PostgreSQL database, and outbound HTTPS access to the appropriate Apple App Store Server API. The staging database is private-only. Do not open an IP allowlist or make it public to run this command. A suitable private-network operator host and its access must be established and verified separately; this Mac has not performed a real case operation.
- Provide `ConnectionStrings__Postgres` only through a protected operator environment. The command requires a short-lived bearer token file via `TRUST_STOREKIT_BEARER_TOKEN_FILE`; it does not take the Apple private key. Keep the private key and bearer out of the API service, command arguments, ordinary logs, shell history, and this record. Use an operator-owned file with mode `0600`, a protected directory, and remove the short-lived bearer file after use. The CLI rejects group/other-accessible, missing, oversized, expired, or incorrectly bound bearer files.

## Apple operator credential

The existing Apple App Store Connect team API key is **223VMKVY8W**, team **3S529795M9**, issuer **10491755-3361-4bfa-8c64-8bb50b1a0be4**. It is an App Manager team API key, not a Sign in with Apple key. Its verified protected-storage reference, lifecycle and revocation instructions are in the `apple-appstoreconnect-223VMKVY8W` entry of [the credential inventory](/Users/juanquirino/.agents/operations/credential-inventory.json); check that entry before obtaining another credential. Apple does not let the private key be downloaded again. Do not create, rotate, or revoke a key merely to run this procedure.

Using the approved protected signing process on the operator host, mint an **ES256** App Store Server API JWT with that key and issuer, audience `appstoreconnect-v1`, and `bid` matching the actual app bundle. Set a fresh `iat` and short expiration: the CLI requires `iat` within the last five minutes (allowing 30 seconds of clock skew), expiration in the future and no more than ten minutes away, and token lifetime no longer than ten minutes. Put only the resulting bearer in the owner-only file; never copy the private key into the API service. For staging, set `StoreKit__BundleId` to the staging bundle `com.collapsetechnologies.trust.staging`; the source defaults to the production bundle if this setting is omitted. Ensure the verified case and Apple environment actually correspond to that bundle.

## Approval and outcome

From the repository on the authorized operator host, invoke the existing operator project with the case's three values, in this order:

```text
dotnet run --project apps/trust-api/TrustApi.Operations/TrustApi.Operations.csproj -- <originalTransactionId> <oldAppAccountToken> <targetAccountId>
```

The identifiers are arguments and can be visible to local process inspectors or shell history. Use a restricted operator session and protect the case record. Do not paste actual IDs, connection strings, bearer tokens, or private-key material into shared transcripts.

The command locks and finds the exact pending or blocked case, checks that the target account is not restricted, then queries Apple's **current** subscription status in the Sandbox or Production environment recorded on that case. It verifies Apple's signed transaction, exact original transaction ID, old app account token, product and environment, and requires active status, an unexpired transaction and no revocation. It rejects a purchase still owned by another active Trust account. Approval records the exact permitted purchase/account link; it **does not grant Plus**. The target must resubmit the verified purchase before the normal entitlement path can grant access. Nothing transfers automatically merely because a case was submitted.

If Apple's authority is unavailable or the stored environment is missing, the case is blocked for retry; restore the authority path or obtain a newly verified purchase as indicated and retry only after review. A mismatched, inactive, expired, revoked, or currently other-owned purchase is rejected. Inspect the recorded status and reason through authorized operator tooling; do not force an alias or entitlement to bypass a failure. Record the outcome and any unresolved action in the protected case record, not in public release notes.

## Evidence limits

Unit and mock tests and local operator checks exercise implementation paths; they are not proof of an actual Apple purchase, a real recovery, carrier SMS, or a successful production operation. The previously observed authenticated Sandbox dummy lookup returned 404, while an invalid bearer returned 401. Those responses show a limited authentication/negative lookup check, not a successful purchase or current-subscription validation. A positive recovery requires an actual eligible Sandbox or Production case, verified Apple response and an observed resubmission outcome. Record test environment, source revision, result and remaining blockers without exposing customer data or credentials.
