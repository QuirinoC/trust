# Trust age assurance

Updated 30 September 2026. This is the current implementation record and open product gate. It is not legal advice or a claim of compliance in every jurisdiction.

## Product rule

Trust does not impose a blanket 13+ age gate just because other family-location apps do. Age checks and consent steps should be added only when Apple or an applicable law requires them. That is a product direction, not a legal conclusion. Trust's intended audience classification and any child-account policy remain unresolved and need counsel review before public release.

For the planned U.S.-only launch, FTC guidance says COPPA applies to child-directed online services collecting children's personal information and to general-audience services when they have actual knowledge that they are collecting personal information from a child under 13. The FTC says COPPA does not require general-audience services to ask users' ages. That does not determine whether Trust is general-audience, mixed-audience, or child-directed; counsel must assess Trust's intended and likely audience, product, and marketing. Before expanding beyond the U.S., review each market's laws and Apple's regional age-assurance requirements, and confirm the selected App Store territories match that review. See the [FTC COPPA FAQ](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) and [Apple's age-assurance guidance](https://developer.apple.com/support/age-assurance/).

## Current implementation

- On iOS 26.2 and later, Trust checks Apple's `isEligibleForAgeFeatures` before requesting an age range. On iOS 26.4 and later, it reads `requiredRegulatoryFeatures` only after Apple reports eligibility. This ordering follows [Apple's current Declared Age Range guide](https://developer.apple.com/documentation/declaredagerange/requesting-people-share-their-age-range-with-your-app) and was corrected after the latest TestFlight startup feedback.
- When Apple indicates a required age flow, Trust requests Apple's shared age range and uses it on-device. A returned range below the lowest applicable gate blocks setup. A declined response stays distinct from a below-gate result; missing or overlapping bounds remain indeterminate and restricted. If Apple's required service cannot complete, Trust fails closed for that flow instead of silently falling back to a global birth-date check.
- iOS 26.4 and later uses Apple's per-person regulatory features for significant app changes. iOS 26.2–26.3 uses Apple's eligibility and shared range to decide whether parental approval is needed for a significant change. The app uses the verified StoreKit `originalAppVersion` to avoid asking new installs to acknowledge a change they already installed with.
- iOS 26.0–26.1 does not provide the regional eligibility signal used here. Trust does not infer a universal age rule from that gap. A previously established under-minimum block remains restricted and directs the person to Support.
- Trust does not store a date of birth, age range, or derived age band on the server. The range is used transiently on-device; it is not included in ordinary account or location requests.
- Before loading an authenticated account, the app links its signed StoreKit App Transaction to that Trust account. This lets the server enforce Apple's later consent-revocation notification. The transaction is not proof of age or initial parental consent. On revocation, the API blocks access while account deletion is retried durably; self-service deletion remains available.

## App Store age rating

On 30 September 2026, App Store Connect showed a calculated 4+ rating but had a manual 18+ override. The 18+ override was removed and the saved rating was verified after navigating away and returning: 4+ in 172 countries or regions, with Apple's regional equivalents, and a 4+ legacy rating for operating systems earlier than iOS 26. This follows the product direction against blanket age exclusion; it does not decide whether Trust is general-audience, mixed-audience, or child-directed, or settle COPPA duties. Counsel must still classify the audience and validate the intended territories. Apple's runtime age checks remain conditional on Apple's regional eligibility and regulatory signals.

## Launch gaps

- The current age flow does not provide a parent-managed child account or first-use parental-consent path. Do not market Trust as supporting child accounts until the audience classification and legal obligations are reviewed and any required flow is implemented.
- Apple age-range and parental-approval scenarios have not been proven on a signed physical device. The latest known feedback remains the build-35 report from iPhone 16 Pro/iOS 27.0: “We can't complete the required check.” Build 40 was uploaded on 2026-09-30 and appears as `Testing` in the `Trust Family Auto` internal group. Retry the required-check flow on that same iPhone using build 40. The avatar and age-gate UI tests use simulator fixtures and do not exercise Apple's live age service.
- The local six-test age-gate suite uses fixtures; it does not call Apple's live age service. See [release status](STATUS.md) and [App Store review readiness](../apps/trust-ios/AppStore/REVIEW-READINESS.md) for current build and CI evidence.

## References

- [Apple: request people to share their age range](https://developer.apple.com/documentation/declaredagerange/requesting-people-share-their-age-range-with-your-app)
- [Apple: age assurance frameworks Q&A](https://developer.apple.com/support/age-assurance)
- [Apple: implementing age assurance and permissions](https://developer.apple.com/documentation/declaredagerange/implementing-age-assurance-and-permissions)
- [FTC: COPPA frequently asked questions](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions)
