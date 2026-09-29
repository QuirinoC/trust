import Foundation

/// Age-related policy helpers. The 13-year threshold is used only for Apple's
/// requested regulatory age band and the debug-only legacy DOB fixture.
public enum TrustAgePolicy {
    public static let firstAgeBandThreshold = 13
    /// Texas' statutory categories are child (<13), younger teenager (13–15),
    /// older teenager (16–17), and adult (18+). Apple may return the
    /// jurisdiction's required bands regardless of these requested gates.
    public static let ageBandThresholds = (minimum: 13, olderTeen: 16, adult: 18)
    public static let policyVersion = "2026-09-v1"
    /// Bump this and update the copy whenever a release has a legally significant change.
    public static let significantUpdateID = "2026-09-age-assurance-v1"
    /// CFBundleVersion (CURRENT_PROJECT_VERSION) that introduced this update.
    /// Bump this alongside significantUpdateID for later significant changes.
    public static let significantUpdateIntroducedInBuildNumber = "33"

    /// Apple considers a change already handled for installs whose original
    /// StoreKit app version is at or beyond the version that introduced it.
    public static func significantUpdateApplies(originalAppBuildNumber: String?, introducedInBuildNumber: String) -> Bool {
        guard let originalAppBuildNumber else { return true }
        return originalAppBuildNumber.compare(introducedInBuildNumber, options: .numeric) == .orderedAscending
    }

    /// Distinguishes a permanent consent revocation from retryable registration failures.
    public static func isConsentRevocationResponse(apiCode: String?) -> Bool {
        apiCode == "consent_revoked"
    }

    public static func isCurrentAccountConsentRevocation(
        apiCode: String?,
        requestToken: String?,
        activeToken: String?
    ) -> Bool {
        isConsentRevocationResponse(apiCode: apiCode)
            && requestToken != nil
            && requestToken == activeToken
    }

    public static func isCurrentSignificantUpdateAcknowledged(storedUpdateID: String?, currentUpdateID: String) -> Bool {
        storedUpdateID == currentUpdateID
    }

    public static func acceptsAgeUpdateResponse(responseQuestionID: String, pendingQuestionID: String?) -> Bool {
        pendingQuestionID == responseQuestionID
    }

    public enum BirthDateEligibility: Equatable {
        case incomplete
        case invalid
        case underMinimum
        case eligible
    }

    public enum SignificantUpdateAction: Equatable {
        case none
        case adultSystemAcknowledgement
        case parentApproval
        case unavailable
    }

    /// StoreKit's age-rating value is opaque. Trust compares values only; it does
    /// not infer an age from the integer or send the value to the API.
    public enum AppRatingObservation: Equatable {
        case unavailable
        case firstObservation(code: Int)
        case unchanged(code: Int)
        case changed(previousCode: Int, currentCode: Int)
    }

    /// Durable marker for one observed rating transition. It intentionally has
    /// no dependency on the transient PermissionQuestion or signed-in session.
    public struct RatingTransitionRequirement: Codable, Equatable {
        public let identifier: String
        public let previousCode: Int
        public let targetCode: Int

        public init(identifier: String, previousCode: Int, targetCode: Int) {
            self.identifier = identifier
            self.previousCode = previousCode
            self.targetCode = targetCode
        }
    }

    public enum RatingRequirementDisposition: Equatable {
        case retain
        case restoreTransition(previousCode: Int, currentCode: Int)
        case supersedingTransition(previousCode: Int, currentCode: Int)
        case approved(targetCode: Int)
        case clear
    }

    /// Resolve the durable marker independently from any pending question. A
    /// missing/placeholder rating keeps an unapproved transition blocked.
    public static func ratingRequirementDisposition(
        _ requirement: RatingTransitionRequirement,
        observation: AppRatingObservation,
        acknowledgementComplete: Bool
    ) -> RatingRequirementDisposition {
        switch observation {
        case .unavailable:
            return acknowledgementComplete ? .approved(targetCode: requirement.targetCode) : .retain
        case .firstObservation(let currentCode):
            if currentCode == requirement.targetCode {
                return .restoreTransition(previousCode: requirement.previousCode, currentCode: currentCode)
            }
            if currentCode == requirement.previousCode { return .clear }
            // The baseline may have been lost across reinstall or an iCloud
            // read failure. Preserve the known prior code so a different
            // positive current code becomes a fresh transition, not a first use.
            return .supersedingTransition(previousCode: requirement.previousCode, currentCode: currentCode)
        case .unchanged:
            return .clear
        case .changed(let previousCode, let currentCode):
            return previousCode == requirement.previousCode && currentCode == requirement.targetCode
                ? .restoreTransition(previousCode: previousCode, currentCode: currentCode)
                : .clear
        }
    }

    public static func appRatingObservation(currentCode: Int?, previousCode: Int?) -> AppRatingObservation {
        // StoreKit returns 0 in Xcode and Sandbox builds, including TestFlight.
        // Do not persist that placeholder as the App Store's production rating.
        guard let currentCode, currentCode > 0 else { return .unavailable }
        guard let previousCode else { return .firstObservation(code: currentCode) }
        guard currentCode != previousCode else { return .unchanged(code: currentCode) }
        return .changed(previousCode: previousCode, currentCode: currentCode)
    }

    public static func appRatingChangeUpdateID(
        previousCode: Int,
        currentCode: Int,
        occurrenceID: String
    ) -> String {
        "\(appRatingChangeUpdatePrefix(previousCode: previousCode, currentCode: currentCode))\(occurrenceID)"
    }

    public static func isAppRatingChangeUpdateID(
        _ updateIdentifier: String,
        previousCode: Int,
        currentCode: Int
    ) -> Bool {
        let prefix = appRatingChangeUpdatePrefix(previousCode: previousCode, currentCode: currentCode)
        return updateIdentifier.hasPrefix(prefix) && updateIdentifier.count > prefix.count
    }

    public static func isAppRatingChangeUpdateID(_ updateIdentifier: String) -> Bool {
        updateIdentifier.hasPrefix("\(significantUpdateID)-app-rating-")
    }

    public static func appRatingTransitionCodes(from updateIdentifier: String) -> (previousCode: Int, currentCode: Int)? {
        guard isAppRatingChangeUpdateID(updateIdentifier) else { return nil }
        let prefix = "\(significantUpdateID)-app-rating-"
        let parts = updateIdentifier.dropFirst(prefix.count).split(separator: "-")
        guard parts.count >= 3, parts[1] == "to",
              let previousCode = Int(parts[0]),
              let currentCode = Int(parts[2]) else { return nil }
        return (previousCode, currentCode)
    }

    private static func appRatingChangeUpdatePrefix(previousCode: Int, currentCode: Int) -> String {
        "\(significantUpdateID)-app-rating-\(previousCode)-to-\(currentCode)-"
    }

    /// Persist the transition identity and include the release identity only when
    /// the prompt actually covers that still-pending significant update.
    public static func acknowledgementIdentifiers(
        for updateIdentifier: String,
        alsoAcknowledgingSignificantUpdate: Bool = false
    ) -> [String] {
        let ratingTransitionPrefix = "\(significantUpdateID)-app-rating-"
        guard alsoAcknowledgingSignificantUpdate,
              updateIdentifier.hasPrefix(ratingTransitionPrefix) else { return [updateIdentifier] }
        return [updateIdentifier, significantUpdateID]
    }

    public static func significantUpdateAcknowledgementIsPending(
        applies: Bool,
        isRequired: Bool,
        isAcknowledged: Bool?
    ) -> Bool {
        applies && isRequired && isAcknowledged != true
    }

    public static func shouldBlockForUnavailablePendingRating(
        hasPendingRatingTransition: Bool,
        acknowledgementComplete: Bool
    ) -> Bool {
        hasPendingRatingTransition && !acknowledgementComplete
    }

    /// First-use eligibility is independent of whether a significant update needs
    /// Apple's adult acknowledgement or parent approval. Apple may replace the
    /// app-requested gates with region-specific regulatory gates. Only an upper
    /// bound below Trust's configured threshold proves the whole shared range is
    /// below that threshold; overlapping or missing bounds are indeterminate.
    public enum InitialUseDecision: Equatable {
        case continueSetup
        case accountCreationBlocked
        case indeterminate
    }

    /// A coarse, transient classification from Apple's shared age range. Trust
    /// must not store or transmit the underlying range as part of this decision.
    public enum AgeBand: Equatable {
        case under13
        case age13To15
        case age16To17
        case adult18Plus
        case indeterminate
    }

    public enum AgeRangeRequestDecision: Equatable {
        case request
        case remainBlocked
        case continueWithoutRequest
    }

    /// A correction retry may re-request Apple's age range only while Apple says the
    /// current user needs age assurance. A saved under-minimum result stays blocked
    /// outside that signal without collecting an unnecessary age signal.
    public static func ageRangeRequestDecision(
        ageRangeRequired: Bool,
        hasUnderMinimumBlock: Bool,
        retryRequested: Bool
    ) -> AgeRangeRequestDecision {
        if ageRangeRequired && (!hasUnderMinimumBlock || retryRequested) { return .request }
        if hasUnderMinimumBlock { return .remainBlocked }
        return .continueWithoutRequest
    }

    public static func ageBand(lowerBound: Int?, upperBound: Int?) -> AgeBand {
        let thresholds = ageBandThresholds
        // Apple's Declared Age Range API defines a nil lower bound as below the
        // lowest requested gate. With the first gate set to 13, that is the
        // under-13 band; a declined request is represented separately.
        if lowerBound == nil { return .under13 }
        if let upperBound, upperBound < thresholds.minimum { return .under13 }
        if let lowerBound, lowerBound >= thresholds.adult { return .adult18Plus }
        if let lowerBound, let upperBound,
           lowerBound >= thresholds.olderTeen, upperBound < thresholds.adult {
            return .age16To17
        }
        if let lowerBound, let upperBound,
           lowerBound >= thresholds.minimum, upperBound < thresholds.olderTeen {
            return .age13To15
        }
        return .indeterminate
    }

    public static func initialUseDecision(lowerBound: Int?, upperBound: Int?) -> InitialUseDecision {
        // Apple's lower bound is the signal to compare with the requested
        // minimum gate. Upper bounds may span multiple age bands and do not
        // make a confirmed lower bound of 13 or older ambiguous for this check.
        if lowerBound == nil {
            return .accountCreationBlocked
        }
        if let lowerBound, lowerBound >= ageBandThresholds.minimum {
            return .continueSetup
        }
        if let upperBound, upperBound < ageBandThresholds.minimum {
            return .accountCreationBlocked
        }
        // A range that overlaps Trust's minimum gate remains unresolved.
        // The caller keeps access restricted while asking Apple again.
        return .indeterminate
    }

    /// Evaluates a neutral month/day/year entry without retaining the date.
    /// Uses the device's calendar and current local date for the age boundary.
    public static func birthDateEligibility(
        monthText: String,
        dayText: String,
        yearText: String,
        now: Date = .now,
        calendar: Calendar? = nil
    ) -> BirthDateEligibility {
        guard !monthText.isEmpty, !dayText.isEmpty, !yearText.isEmpty else { return .incomplete }
        guard monthText.allSatisfy(\.isNumber), dayText.allSatisfy(\.isNumber), yearText.allSatisfy(\.isNumber),
              let month = Int(monthText), let day = Int(dayText), let year = Int(yearText) else { return .invalid }
        guard (1...12).contains(month), (1...31).contains(day), yearText.count == 4 else { return .invalid }

        var ageCalendar = calendar ?? Calendar(identifier: .gregorian)
        if calendar == nil {
            ageCalendar.timeZone = .current
        }

        var birthComponents = DateComponents()
        birthComponents.year = year
        birthComponents.month = month
        birthComponents.day = 1
        guard let firstOfMonth = ageCalendar.date(from: birthComponents),
              let days = ageCalendar.range(of: .day, in: .month, for: firstOfMonth),
              days.contains(day) else { return .invalid }

        let today = ageCalendar.dateComponents([.year, .month, .day], from: now)
        guard let currentYear = today.year, let currentMonth = today.month, let currentDay = today.day else {
            return .invalid
        }
        guard (year, month, day) <= (currentYear, currentMonth, currentDay) else { return .invalid }

        var age = currentYear - year
        if (month, day) > (currentMonth, currentDay) {
            age -= 1
        }
        return age >= firstAgeBandThreshold ? .eligible : .underMinimum
    }

    /// Chooses the legally signaled significant-update flow without persisting or
    /// transmitting an age range. iOS 26.4+ exposes exact per-person regulatory flags;
    /// iOS 26.2–26.3 combines Apple's eligibility signal with the shared age range.
    public static func significantUpdateAction(
        ageRangeRequired: Bool,
        lowerBound: Int?,
        upperBound: Int?,
        regulatorySignalsAvailable: Bool,
        adultNotificationRequired: Bool,
        parentConsentRequired: Bool,
        legacyEligibleMinor: Bool = false,
        appRatingChanged: Bool = false,
        significantUpdateApplies: Bool = true
    ) -> SignificantUpdateAction {
        let ratingChangeRequiresParent = appRatingChanged
            && ageRangeRequired
            && upperBound.map { $0 < 18 } == true
        let ratingChangeAgeIsIndeterminate = appRatingChanged
            && ageRangeRequired
            && upperBound.map { $0 < 18 } != true
            && lowerBound.map { $0 >= 18 } != true

        if regulatorySignalsAvailable {
            // Apple's per-person requirements are authoritative. Apple also directs apps
            // to request parent consent after an age-rating change for a known minor.
            if (significantUpdateApplies && parentConsentRequired) || ratingChangeRequiresParent {
                return .parentApproval
            }
            if significantUpdateApplies && adultNotificationRequired {
                return .adultSystemAcknowledgement
            }
            if ratingChangeAgeIsIndeterminate { return .unavailable }
            return .none
        }

        // Before iOS 26.4, Apple directs apps to check regional eligibility and
        // request the age range. A known minor in an eligible region needs the
        // PermissionKit decision for this significant update. The deprecated
        // activeParentalControls flag is not a regulatory signal and must not be used.
        if (significantUpdateApplies && legacyEligibleMinor) || ratingChangeRequiresParent {
            return .parentApproval
        }
        if ratingChangeAgeIsIndeterminate { return .unavailable }
        if ageRangeRequired, lowerBound == nil, upperBound == nil { return .unavailable }
        return .none
    }
}

/// Prevents a result obtained for an earlier Apple account from reauthorizing this session.
public struct TrustAgeAccessState: Equatable {
    public private(set) var isAllowed = false
    public private(set) var generation: UInt64 = 0
    public private(set) var needsForegroundRecheck = false

    public init() {}

    @discardableResult
    public mutating func beginEvaluation() -> UInt64 {
        generation &+= 1
        isAllowed = false
        return generation
    }

    @discardableResult
    public mutating func suspendForAppleAccountChange(isForeground: Bool) -> UInt64 {
        let nextGeneration = beginEvaluation()
        needsForegroundRecheck = !isForeground
        return nextGeneration
    }

    public mutating func consumeForegroundRecheck() -> Bool {
        guard needsForegroundRecheck else { return false }
        needsForegroundRecheck = false
        return true
    }

    public func isCurrentEvaluation(_ generation: UInt64) -> Bool {
        self.generation == generation
    }

    @discardableResult
    public mutating func completeEvaluation(_ generation: UInt64, permitted: Bool) -> Bool {
        guard isCurrentEvaluation(generation) else { return false }
        isAllowed = permitted
        if permitted { needsForegroundRecheck = false }
        return true
    }

    public mutating func setAllowedOutsideEvaluation(_ allowed: Bool) {
        generation &+= 1
        isAllowed = allowed
        needsForegroundRecheck = false
    }
}
