@preconcurrency import DeclaredAgeRange
import Foundation
import PermissionKit
import StoreKit
import TrustCore
import UIKit

@MainActor
final class AgeAssuranceCoordinator {
    enum UnderMinimumAgeSource: String {
        case localBirthDate
        case appleAgeRange
    }

    enum Decision {
        case permitted
        case selfAttestationRequired
        case underMinimumAge
        case ageRangeBelowMinimum
        case parentApprovalRequired
        case parentApprovalDenied
        case unavailable
    }

    enum UpdateResponseResult {
        case approved
        case denied
        case persistenceUnavailable
    }

    private let defaults = UserDefaults.standard
    private let updateStore = NSUbiquitousKeyValueStore.default
    private let selfAttestationKey = "trust.age.self-attestation.\(TrustAgePolicy.policyVersion)"
    private let underMinimumAgeKey = "trust.age.under-minimum"
    private let underMinimumAgeSourceKey = "trust.age.under-minimum-source"
    private let legacyAcknowledgedUpdateKey = "trust.age.significant-update.acknowledged"
    private let acknowledgedUpdateKeyPrefix = "trust.age.significant-update.acknowledged."
    private let pendingUpdateQuestionKey = "trust.age.significant-update.pending-question"
    private let pendingUpdateQuestionIDKey = "trust.age.significant-update.pending-question-id"
    private let pendingUpdateIdentifierKey = "trust.age.significant-update.pending-identifier"
    private let pendingAppRatingCodeKey = "trust.age.significant-update.pending-rating-code"
    private let pendingUpdateCoversReleaseKey = "trust.age.significant-update.pending-covers-release"
    private let ratingRequirementIdentifierKey = "trust.age.rating-transition.requirement-identifier"
    private let ratingRequirementPreviousCodeKey = "trust.age.rating-transition.requirement-previous-code"
    private let ratingRequirementTargetCodeKey = "trust.age.rating-transition.requirement-target-code"
    private let appRatingCodeKey = "trust.age.app-rating-code"
    private let appRatingCodeKeychainAccount = "trust.age.app-rating-code"
    private var pendingUpdateQuestion: Any?
    private var pendingUpdateIdentifier: String?
    private var pendingAppRatingCode: Int?
    private var pendingUpdateCoversRelease = false
    private var ratingRequirementIdentifier: String?
    private var ratingRequirementPreviousCode: Int?
    private var ratingRequirementTargetCode: Int?
    private var ageRangeRequiredForCurrentPerson = false
    private var evaluationGeneration: UInt64 = 0
    var onAppleAccountChanged: (() -> Void)?
    private var appleAccountChangeObserver: NSObjectProtocol?

    init() {
        pendingUpdateIdentifier = defaults.string(forKey: pendingUpdateIdentifierKey)
        pendingAppRatingCode = defaults.object(forKey: pendingAppRatingCodeKey) as? Int
        let savedReleaseCoverage = defaults.object(forKey: pendingUpdateCoversReleaseKey) as? Bool
        pendingUpdateCoversRelease = savedReleaseCoverage ?? false
        if savedReleaseCoverage == nil, pendingAppRatingCode != nil {
            // Older rating questions did not record whether the release change
            // was pending. Rebuild the question after reevaluating current signals.
            defaults.removeObject(forKey: pendingUpdateQuestionKey)
            defaults.removeObject(forKey: pendingUpdateQuestionIDKey)
        }
        ratingRequirementIdentifier = defaults.string(forKey: ratingRequirementIdentifierKey)
        ratingRequirementPreviousCode = defaults.object(forKey: ratingRequirementPreviousCodeKey) as? Int
        ratingRequirementTargetCode = defaults.object(forKey: ratingRequirementTargetCodeKey) as? Int
        if ratingRequirementIdentifier == nil,
           let pendingUpdateIdentifier,
           let transition = TrustAgePolicy.appRatingTransitionCodes(from: pendingUpdateIdentifier),
           let pendingAppRatingCode {
            // Migrate an older pending rating question into its independent marker.
            persistRatingRequirement(
                identifier: pendingUpdateIdentifier,
                previousCode: transition.previousCode,
                targetCode: pendingAppRatingCode
            )
        }
        appleAccountChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
                  reason == NSUbiquitousKeyValueStoreAccountChange else { return }
            Task { @MainActor [weak self] in
                self?.onAppleAccountChanged?()
            }
        }
    }

    var canTryAppleAgeRangeAfterUnderage: Bool {
        hasUnderMinimumAgeBlock && ageRangeRequiredForCurrentPerson
    }

    func evaluate(
        forceAppleAgeRange: Bool = false,
        isCurrent: () -> Bool = { true }
    ) async -> Decision {
        evaluationGeneration &+= 1
        let currentEvaluation = evaluationGeneration
        ageRangeRequiredForCurrentPerson = false
        func evaluationIsCurrent() -> Bool {
            currentEvaluation == evaluationGeneration && isCurrent()
        }

        var appRatingObservation = await observeAppRating()
        guard evaluationIsCurrent() else { return .unavailable }
        if let requirementIdentifier = ratingRequirementIdentifier {
            let requirement = TrustAgePolicy.RatingTransitionRequirement(
                identifier: requirementIdentifier,
                previousCode: ratingRequirementPreviousCode ?? 0,
                targetCode: ratingRequirementTargetCode ?? 0
            )
            guard requirement.previousCode > 0, requirement.targetCode > 0 else { return .unavailable }
            let acknowledgementComplete = isAcknowledged(updateIdentifier: requirementIdentifier) == true
            switch TrustAgePolicy.ratingRequirementDisposition(
                requirement,
                observation: appRatingObservation,
                acknowledgementComplete: acknowledgementComplete
            ) {
            case .retain:
                    return .unavailable
            case .approved(let targetCode):
                // An acknowledgement may have persisted just before interruption.
                // Commit its target so StoreKit recovery won't create a new occurrence.
                storeAppRatingCode(targetCode)
                clearRatingRequirement()
            case .restoreTransition(let previousCode, let currentCode):
                    // The local rating baseline may be unavailable after reinstall;
                    // the independent marker still identifies the unresolved change.
                    appRatingObservation = .changed(previousCode: previousCode, currentCode: currentCode)
            case .supersedingTransition(let previousCode, let currentCode):
                clearRatingRequirement()
                appRatingObservation = .changed(previousCode: previousCode, currentCode: currentCode)
            case .clear:
                clearRatingRequirement()
            }
        }
        let originalAppBuildNumber = await verifiedOriginalAppVersion()
        guard evaluationIsCurrent() else { return .unavailable }
        let significantUpdateApplies = TrustAgePolicy.significantUpdateApplies(
            originalAppBuildNumber: originalAppBuildNumber,
            introducedInBuildNumber: TrustAgePolicy.significantUpdateIntroducedInBuildNumber
        )
        if case .firstObservation = appRatingObservation {
            persistObservedAppRating(appRatingObservation)
        }

        let appRatingChange: (previousCode: Int, currentCode: Int)? = {
            guard case let .changed(previousCode, currentCode) = appRatingObservation else { return nil }
            return (previousCode, currentCode)
        }()

        if #available(iOS 26, *) {
            let service = AgeRangeService.shared
            do {
                var regulatorySignalsAvailable = false
                var requiresAdultAcknowledgement = false
                var requiresParentApproval = false
                var legacyEligibleMinor = false
                let ageRangeRequired: Bool
                let shouldRequestAgeRange: Bool
                var acceptedAppleAgeRange = false
                var lowerBound: Int?
                var upperBound: Int?
                if #available(iOS 26.4, *) {
                    regulatorySignalsAvailable = true
                    let eligible = try await service.isEligibleForAgeFeatures
                    guard evaluationIsCurrent() else { return .unavailable }
                    let regulatoryFeatures: Set<AgeRangeService.RegulatoryFeature>
                    if eligible {
                        regulatoryFeatures = try await service.requiredRegulatoryFeatures
                        guard evaluationIsCurrent() else { return .unavailable }
                    } else {
                        regulatoryFeatures = []
                    }
                    ageRangeRequired = eligible || regulatoryFeatures.contains(.declaredAgeRangeRequired)
                    ageRangeRequiredForCurrentPerson = ageRangeRequired
                    requiresAdultAcknowledgement = regulatoryFeatures.contains(.significantAppChangeRequiresAdultNotification)
                    requiresParentApproval = regulatoryFeatures.contains(.significantAppChangeRequiresParentalConsent)
                } else if #available(iOS 26.2, *) {
                    ageRangeRequired = try await service.isEligibleForAgeFeatures
                    guard evaluationIsCurrent() else { return .unavailable }
                    ageRangeRequiredForCurrentPerson = ageRangeRequired
                } else {
                    // iOS 26.0–26.1 cannot tell whether this person is in a region that
                    // requires age assurance. Do not request an age signal without that
                    // determination; preserve any prior block and direct them to Support.
                    ageRangeRequired = false
                    ageRangeRequiredForCurrentPerson = false
                }

                let requestDecision = TrustAgePolicy.ageRangeRequestDecision(
                    ageRangeRequired: ageRangeRequired,
                    hasUnderMinimumBlock: hasUnderMinimumAgeBlock,
                    retryRequested: forceAppleAgeRange
                )
                shouldRequestAgeRange = requestDecision == .request
                if requestDecision == .remainBlocked { return .ageRangeBelowMinimum }

                if shouldRequestAgeRange {
                    guard let viewController = foregroundViewController() else { return .unavailable }
                    let thresholds = TrustAgePolicy.ageBandThresholds
                    let response = try await service.requestAgeRange(
                        ageGates: thresholds.minimum,
                        thresholds.olderTeen,
                        thresholds.adult,
                        in: viewController
                    )
                    guard evaluationIsCurrent() else { return .unavailable }
                    let range: AgeRangeService.AgeRange
                    switch response {
                    case .declinedSharing:
                        if hasAppleUnderMinimumAgeBlock { return .ageRangeBelowMinimum }
                        return hasUnderMinimumAgeBlock ? .underMinimumAge : .unavailable
                    case .sharing(let sharedRange):
                        range = sharedRange
                    @unknown default:
                        return .unavailable
                    }

                    switch TrustAgePolicy.initialUseDecision(
                        lowerBound: range.lowerBound,
                        upperBound: range.upperBound
                    ) {
                    case .accountCreationBlocked:
                        recordUnderMinimumAge(source: .appleAgeRange)
                        return .ageRangeBelowMinimum
                    case .continueSetup:
                        clearUnderMinimumAge()
                    case .indeterminate:
                        return .unavailable
                    }

                    lowerBound = range.lowerBound
                    upperBound = range.upperBound
                    if #available(iOS 26.2, *), !regulatorySignalsAvailable {
                        // Apple deprecated significantAppChangeApprovalRequired.
                        // On iOS 26.2–26.3, its current guidance is to combine the
                        // regional eligibility signal with the shared age range.
                        legacyEligibleMinor = ageRangeRequired
                            && range.upperBound.map { $0 < 18 } == true
                    }
                    acceptedAppleAgeRange = true
                }

                let ratingTransitionIdentifier: String?
                if let appRatingChange {
                    if let ratingRequirementIdentifier,
                       ratingRequirementPreviousCode == appRatingChange.previousCode,
                       ratingRequirementTargetCode == appRatingChange.currentCode {
                        ratingTransitionIdentifier = ratingRequirementIdentifier
                    } else if let pendingUpdateIdentifier,
                              TrustAgePolicy.isAppRatingChangeUpdateID(
                                pendingUpdateIdentifier,
                                previousCode: appRatingChange.previousCode,
                                currentCode: appRatingChange.currentCode
                              ) {
                        ratingTransitionIdentifier = pendingUpdateIdentifier
                        persistRatingRequirement(
                            identifier: pendingUpdateIdentifier,
                            previousCode: appRatingChange.previousCode,
                            targetCode: appRatingChange.currentCode
                        )
                    } else {
                        let identifier = TrustAgePolicy.appRatingChangeUpdateID(
                            previousCode: appRatingChange.previousCode,
                            currentCode: appRatingChange.currentCode,
                            occurrenceID: UUID().uuidString.lowercased()
                        )
                        ratingTransitionIdentifier = identifier
                        persistRatingRequirement(
                            identifier: identifier,
                            previousCode: appRatingChange.previousCode,
                            targetCode: appRatingChange.currentCode
                        )
                    }
                } else {
                    ratingTransitionIdentifier = nil
                }
                let ratingAcknowledged: Bool?
                if let ratingTransitionIdentifier {
                    ratingAcknowledged = isAcknowledged(updateIdentifier: ratingTransitionIdentifier)
                    if ratingAcknowledged == nil {
                        if pendingUpdateIdentifier != ratingTransitionIdentifier, let appRatingChange {
                            setPendingUpdate(
                                identifier: ratingTransitionIdentifier,
                                appRatingCode: appRatingChange.currentCode,
                                coversRelease: false
                            )
                        }
                        return .unavailable
                    }
                } else {
                    ratingAcknowledged = nil
                }
                let ratingNeedsAcknowledgement = appRatingChange != nil && ratingAcknowledged != true
                if appRatingChange != nil, !ratingNeedsAcknowledgement {
                    // The rating change was already approved. Its baseline can
                    // advance independently of any still-pending release update.
                    persistObservedAppRating(appRatingObservation)
                    clearRatingRequirement()
                }
                let updateAction = TrustAgePolicy.significantUpdateAction(
                    ageRangeRequired: ageRangeRequired,
                    lowerBound: lowerBound,
                    upperBound: upperBound,
                    regulatorySignalsAvailable: regulatorySignalsAvailable,
                    adultNotificationRequired: requiresAdultAcknowledgement,
                    parentConsentRequired: requiresParentApproval,
                    legacyEligibleMinor: legacyEligibleMinor,
                    appRatingChanged: ratingNeedsAcknowledgement,
                    significantUpdateApplies: significantUpdateApplies
                )
                let releaseChangeRequired = requiresAdultAcknowledgement
                    || requiresParentApproval
                    || legacyEligibleMinor
                let releaseAlreadyAcknowledged: Bool? = ratingNeedsAcknowledgement && releaseChangeRequired
                    ? isAcknowledged(updateIdentifier: TrustAgePolicy.significantUpdateID)
                    : nil
                if ratingNeedsAcknowledgement,
                   significantUpdateApplies,
                   releaseChangeRequired,
                   releaseAlreadyAcknowledged == nil {
                    if pendingUpdateIdentifier != ratingTransitionIdentifier, let appRatingChange,
                       let ratingTransitionIdentifier {
                        setPendingUpdate(
                            identifier: ratingTransitionIdentifier,
                            appRatingCode: appRatingChange.currentCode,
                            coversRelease: false
                        )
                    }
                    return .unavailable
                }
                let ratingPromptCoversRelease = TrustAgePolicy.significantUpdateAcknowledgementIsPending(
                    applies: significantUpdateApplies,
                    isRequired: ratingNeedsAcknowledgement && releaseChangeRequired,
                    isAcknowledged: releaseAlreadyAcknowledged
                )
                let updateIdentifier = ratingNeedsAcknowledgement
                    ? (ratingTransitionIdentifier ?? TrustAgePolicy.significantUpdateID)
                    : TrustAgePolicy.significantUpdateID
                if pendingUpdateIdentifier != nil, pendingUpdateIdentifier != updateIdentifier {
                    // Never carry a parent's pending response across a material
                    // update or a distinct StoreKit rating transition.
                    clearPendingQuestionState()
                }
                switch updateAction {
                case .none:
                    guard evaluationIsCurrent() else { return .unavailable }
                    clearPendingQuestionState()
                    clearRatingRequirement()
                    persistObservedAppRating(appRatingObservation)
                case .adultSystemAcknowledgement:
                    guard let acknowledged = isAcknowledged(updateIdentifier: updateIdentifier) else {
                        return .unavailable
                    }
                    if acknowledged {
                        clearPendingQuestionState()
                        persistObservedAppRating(appRatingObservation)
                        clearRatingRequirement()
                        break
                    }
                    if ratingNeedsAcknowledgement, let appRatingChange {
                        // Keep the unique occurrence ID if the system sheet is
                        // dismissed or the app relaunches before acknowledgement.
                        setPendingUpdate(
                            identifier: updateIdentifier,
                            appRatingCode: appRatingChange.currentCode,
                            coversRelease: ratingPromptCoversRelease
                        )
                    }
                    if #available(iOS 26.4, *) {
                        guard let scene = foregroundWindowScene() else { return .unavailable }
                        try await service.showSignificantUpdateAcknowledgment(
                            in: scene,
                            updateDescription: !ratingNeedsAcknowledgement
                                ? TrustCopy.ageUpdateDescription
                                : (ratingPromptCoversRelease
                                    ? TrustCopy.ageRatingAndUpdateDescription
                                    : TrustCopy.ageRatingChangeDescription)
                        )
                        guard evaluationIsCurrent() else { return .unavailable }
                        guard persistAcknowledgement(
                            updateIdentifier: updateIdentifier,
                            alsoAcknowledgingSignificantUpdate: ratingPromptCoversRelease
                        ) else {
                            return .unavailable
                        }
                        clearPendingQuestionState()
                        persistObservedAppRating(appRatingObservation)
                        clearRatingRequirement()
                    } else {
                        return .unavailable
                    }
                case .parentApproval:
                    guard evaluationIsCurrent() else { return .unavailable }
                    guard let acknowledged = isAcknowledged(updateIdentifier: updateIdentifier) else {
                        return .unavailable
                    }
                    if acknowledged {
                        guard evaluationIsCurrent() else { return .unavailable }
                        clearPendingQuestionState()
                        persistObservedAppRating(appRatingObservation)
                        clearRatingRequirement()
                        break
                    }
                    guard evaluationIsCurrent() else { return .unavailable }
                    setPendingUpdate(
                        identifier: updateIdentifier,
                        appRatingCode: ratingNeedsAcknowledgement ? appRatingChange?.currentCode : nil,
                        coversRelease: ratingPromptCoversRelease
                    )
                    return .parentApprovalRequired
                case .unavailable:
                    // In a regulated region, a rating transition cannot be accepted
                    // until Apple's shared range determines whether parent approval applies.
                    if ratingNeedsAcknowledgement, let appRatingChange {
                        setPendingUpdate(
                            identifier: updateIdentifier,
                            appRatingCode: appRatingChange.currentCode,
                            coversRelease: ratingPromptCoversRelease
                        )
                    }
                    return .unavailable
                }

                // Apple age assurance is required only when its regulatory signals say so.
                // Outside those signals, Trust does not impose a universal DOB gate.
                if acceptedAppleAgeRange || !ageRangeRequired { return .permitted }
        } catch {
            guard evaluationIsCurrent() else { return .unavailable }
            // In a region requiring age assurance, failure to obtain Apple's result
            // must not silently fall back to a weaker self-attestation.
            return .unavailable
            }
        }

        // Before iOS 26.2, Apple exposes no regional eligibility signal. Do not infer
        // a global age requirement from that absence; continue and document the gap.
        return .permitted
    }

    func recordSelfAttestation() {
        defaults.set(true, forKey: selfAttestationKey)
    }

    func recordUnderMinimumAge(source: UnderMinimumAgeSource) {
        defaults.set(true, forKey: underMinimumAgeKey)
        defaults.set(source.rawValue, forKey: underMinimumAgeSourceKey)
        // Keep the block device-only and outside app preferences so reinstalling
        // the app does not clear a failed age screen. We never store the birth date.
        TrustKeychain.set(source.rawValue, account: underMinimumAgeKey)
        defaults.removeObject(forKey: selfAttestationKey)
    }

    private var hasUnderMinimumAgeBlock: Bool {
        if let value = TrustKeychain.get(account: underMinimumAgeKey),
           value == "1" || UnderMinimumAgeSource(rawValue: value) != nil {
            return true
        }
        guard defaults.bool(forKey: underMinimumAgeKey) else { return false }
        // Migrate blocks written by builds that stored only in UserDefaults.
        TrustKeychain.set(
            defaults.string(forKey: underMinimumAgeSourceKey) ?? "1",
            account: underMinimumAgeKey
        )
        return true
    }

    private var hasAppleUnderMinimumAgeBlock: Bool {
        guard hasUnderMinimumAgeBlock else { return false }
        if TrustKeychain.get(account: underMinimumAgeKey)
            == UnderMinimumAgeSource.appleAgeRange.rawValue {
            return true
        }
        guard defaults.string(forKey: underMinimumAgeSourceKey)
            == UnderMinimumAgeSource.appleAgeRange.rawValue else { return false }
        // Migrate Apple age-range blocks recorded before source provenance was stored
        // outside app preferences. Clearing UserDefaults must not change the result.
        TrustKeychain.set(UnderMinimumAgeSource.appleAgeRange.rawValue, account: underMinimumAgeKey)
        return true
    }

    private func clearUnderMinimumAge() {
        defaults.removeObject(forKey: underMinimumAgeKey)
        defaults.removeObject(forKey: underMinimumAgeSourceKey)
        TrustKeychain.delete(account: underMinimumAgeKey)
    }

    func resetAccountAttestations() {
        defaults.removeObject(forKey: selfAttestationKey)
        invalidatePendingUpdate()
    }

    /// Age decisions recorded before Trust authentication belong to the person who
    /// used the current Apple Account. A shared device can later be used by someone
    /// else, so do not let a device-wide Keychain result carry into that person's
    /// Apple age-range evaluation. In regulated regions Apple supplies the new
    /// account's range before Trust opens account features.
    func resetPersonScopedStateForAppleAccountChange() {
        clearUnderMinimumAge()
        defaults.removeObject(forKey: selfAttestationKey)
        defaults.removeObject(forKey: legacyAcknowledgedUpdateKey)
        invalidatePendingUpdate()
    }

    #if DEBUG
    /// Retained only for explicit local UI-test fixture launches. Normal app startup
    /// never invokes this DOB/self-attestation flow.
    func evaluateLocalAttestationForDebugTest() -> Decision {
        if ProcessInfo.processInfo.environment["TRUST_AGE_TEST_APPLE_ACCOUNT_CHANGED"] == "1" {
            resetPersonScopedStateForAppleAccountChange()
        }
        ageRangeRequiredForCurrentPerson = ProcessInfo.processInfo.environment["TRUST_AGE_TEST_AGE_RANGE_REQUIRED"] == "1"
        if ProcessInfo.processInfo.environment["TRUST_AGE_TEST_AGE_RANGE_BLOCKED"] == "1" {
            recordUnderMinimumAge(source: .appleAgeRange)
            return .ageRangeBelowMinimum
        }
        if hasAppleUnderMinimumAgeBlock { return .ageRangeBelowMinimum }
        if hasUnderMinimumAgeBlock { return .underMinimumAge }
        return defaults.bool(forKey: selfAttestationKey) ? .permitted : .selfAttestationRequired
    }

    func resetAgeGateForDebugTest() {
        resetAgeGatePreferencesForDebugTest()
        TrustKeychain.delete(account: underMinimumAgeKey)
    }

    func resetAgeGatePreferencesForDebugTest() {
        defaults.removeObject(forKey: selfAttestationKey)
        defaults.removeObject(forKey: underMinimumAgeKey)
        defaults.removeObject(forKey: underMinimumAgeSourceKey)
        invalidatePendingUpdate()
    }

    #endif

    @available(iOS 26.2, *)
    func updateQuestion() -> PermissionQuestion<SignificantAppUpdateTopic> {
        let updateIdentifier = pendingUpdateIdentifier ?? TrustAgePolicy.significantUpdateID
        if let pending = pendingUpdateQuestion as? PermissionQuestion<SignificantAppUpdateTopic>,
           pendingUpdateIdentifier == updateIdentifier {
            return pending
        }
        if let restored = restoredPendingUpdateQuestion(),
           pendingUpdateIdentifier == updateIdentifier {
            pendingUpdateQuestion = restored
            return restored
        }
        let description: String
        if pendingAppRatingCode == nil {
            description = TrustCopy.ageUpdateDescription
        } else if pendingUpdateCoversRelease {
            description = TrustCopy.ageRatingAndUpdateDescription
        } else {
            description = TrustCopy.ageRatingChangeDescription
        }
        let topic = SignificantAppUpdateTopic(description: description)
        let question = PermissionQuestion(significantAppUpdateTopic: topic)
        pendingUpdateQuestion = question
        pendingUpdateIdentifier = updateIdentifier
        defaults.set(updateIdentifier, forKey: pendingUpdateIdentifierKey)
        defaults.set(pendingUpdateCoversRelease, forKey: pendingUpdateCoversReleaseKey)
        defaults.set(String(describing: question.id), forKey: pendingUpdateQuestionIDKey)
        if let data = try? JSONEncoder().encode(question) {
            defaults.set(data, forKey: pendingUpdateQuestionKey)
        }
        return question
    }

    @available(iOS 26.2, *)
    private func restoredPendingUpdateQuestion() -> PermissionQuestion<SignificantAppUpdateTopic>? {
        guard let data = defaults.data(forKey: pendingUpdateQuestionKey) else { return nil }
        return try? JSONDecoder().decode(PermissionQuestion<SignificantAppUpdateTopic>.self, from: data)
    }

    @available(iOS 26.2, *)
    func handle(_ response: PermissionResponse<SignificantAppUpdateTopic>) -> UpdateResponseResult? {
        guard pendingUpdateIdentifier != nil else { return nil }
        let pendingQuestionID: String
        if let pending = pendingUpdateQuestion as? PermissionQuestion<SignificantAppUpdateTopic> {
            pendingQuestionID = String(describing: pending.id)
        } else if let storedID = defaults.string(forKey: pendingUpdateQuestionIDKey) {
            // AskCenter may deliver a persisted response before the UI has rebuilt
            // the Codable question after process relaunch. The stable ID is sufficient
            // to match that response without requiring a live view.
            pendingQuestionID = storedID
            pendingUpdateQuestion = restoredPendingUpdateQuestion()
        } else if let restored = restoredPendingUpdateQuestion() {
            pendingQuestionID = String(describing: restored.id)
            pendingUpdateQuestion = restored
        } else {
            return nil
        }
        guard TrustAgePolicy.acceptsAgeUpdateResponse(
            responseQuestionID: String(describing: response.question.id),
            pendingQuestionID: pendingQuestionID) else { return nil }

        pendingUpdateQuestion = nil
        let updateIdentifier = pendingUpdateIdentifier ?? TrustAgePolicy.significantUpdateID
        guard response.choice.answer == .approval else {
            clearPendingQuestionState()
            return .denied
        }

        let acknowledgementKey = acknowledgedUpdateKeyPrefix + updateIdentifier
        guard persistAcknowledgement(
            updateIdentifier: updateIdentifier,
            alsoAcknowledgingSignificantUpdate: pendingUpdateCoversRelease
        ),
              updateStore.string(forKey: acknowledgementKey) == updateIdentifier else {
            return .persistenceUnavailable
        }
        return .approved
    }

    func invalidatePendingUpdate() {
        evaluationGeneration &+= 1
        clearPendingQuestionState()
    }

    private func clearPendingQuestionState() {
        pendingUpdateQuestion = nil
        pendingUpdateIdentifier = nil
        pendingAppRatingCode = nil
        pendingUpdateCoversRelease = false
        defaults.removeObject(forKey: pendingUpdateQuestionKey)
        defaults.removeObject(forKey: pendingUpdateQuestionIDKey)
        defaults.removeObject(forKey: pendingUpdateIdentifierKey)
        defaults.removeObject(forKey: pendingAppRatingCodeKey)
        defaults.removeObject(forKey: pendingUpdateCoversReleaseKey)
    }

    private func persistRatingRequirement(identifier: String, previousCode: Int, targetCode: Int) {
        ratingRequirementIdentifier = identifier
        ratingRequirementPreviousCode = previousCode
        ratingRequirementTargetCode = targetCode
        defaults.set(identifier, forKey: ratingRequirementIdentifierKey)
        defaults.set(previousCode, forKey: ratingRequirementPreviousCodeKey)
        defaults.set(targetCode, forKey: ratingRequirementTargetCodeKey)
    }

    private func clearRatingRequirement() {
        if ratingRequirementIdentifier != nil, pendingUpdateIdentifier == ratingRequirementIdentifier {
            clearPendingQuestionState()
        }
        ratingRequirementIdentifier = nil
        ratingRequirementPreviousCode = nil
        ratingRequirementTargetCode = nil
        defaults.removeObject(forKey: ratingRequirementIdentifierKey)
        defaults.removeObject(forKey: ratingRequirementPreviousCodeKey)
        defaults.removeObject(forKey: ratingRequirementTargetCodeKey)
    }

    private func persistAcknowledgement(
        updateIdentifier: String,
        alsoAcknowledgingSignificantUpdate: Bool = false
    ) -> Bool {
        let identifiers = TrustAgePolicy.acknowledgementIdentifiers(
            for: updateIdentifier,
            alsoAcknowledgingSignificantUpdate: alsoAcknowledgingSignificantUpdate
        )
        for identifier in identifiers {
            updateStore.set(identifier, forKey: acknowledgedUpdateKeyPrefix + identifier)
        }
        guard updateStore.synchronize() else { return false }
        return identifiers.allSatisfy {
            updateStore.string(forKey: acknowledgedUpdateKeyPrefix + $0) == $0
        }
    }

    private func setPendingUpdate(identifier: String, appRatingCode: Int?, coversRelease: Bool = false) {
        if pendingUpdateIdentifier != identifier || pendingUpdateCoversRelease != coversRelease {
            pendingUpdateQuestion = nil
            defaults.removeObject(forKey: pendingUpdateQuestionKey)
            defaults.removeObject(forKey: pendingUpdateQuestionIDKey)
        }
        pendingUpdateIdentifier = identifier
        pendingAppRatingCode = appRatingCode
        pendingUpdateCoversRelease = coversRelease
        defaults.set(identifier, forKey: pendingUpdateIdentifierKey)
        defaults.set(coversRelease, forKey: pendingUpdateCoversReleaseKey)
        if let appRatingCode {
            defaults.set(appRatingCode, forKey: pendingAppRatingCodeKey)
        } else {
            defaults.removeObject(forKey: pendingAppRatingCodeKey)
        }
    }

    private func isAcknowledged(updateIdentifier: String) -> Bool? {
        guard updateStore.synchronize() else { return nil }
        let key = acknowledgedUpdateKeyPrefix + updateIdentifier
        if updateStore.string(forKey: key) == updateIdentifier { return true }
        // Preserve acknowledgements written by earlier builds for the stable
        // significant-update ID. Rating changes use their own unique IDs.
        return updateIdentifier == TrustAgePolicy.significantUpdateID
            && updateStore.string(forKey: legacyAcknowledgedUpdateKey) == updateIdentifier
    }

    private func observeAppRating() async -> TrustAgePolicy.AppRatingObservation {
        guard #available(iOS 26.2, *) else { return .unavailable }
        let currentCode = await AppStore.ageRatingCode
        return TrustAgePolicy.appRatingObservation(
            currentCode: currentCode,
            previousCode: storedAppRatingCode()
        )
    }

    private func verifiedOriginalAppVersion() async -> String? {
        do {
            let result = try await AppTransaction.shared
            guard case let .verified(transaction) = result else { return nil }
            return transaction.originalAppVersion
        } catch {
            // An unavailable transaction must not exempt this install from the
            // existing significant-update acknowledgement flow.
            return nil
        }
    }

    private func persistObservedAppRating(_ observation: TrustAgePolicy.AppRatingObservation) {
        switch observation {
        case let .firstObservation(code), let .unchanged(code):
            storeAppRatingCode(code)
        case let .changed(_, currentCode):
            storeAppRatingCode(currentCode)
        case .unavailable:
            break
        }
    }

    private func storedAppRatingCode() -> Int? {
        if let code = Int(updateStore.string(forKey: appRatingCodeKey) ?? ""), code > 0 {
            return code
        }
        if let code = TrustKeychain.get(account: appRatingCodeKeychainAccount).flatMap(Int.init), code > 0 {
            return code
        }
        // Migrate the preference value written by earlier builds into durable stores so
        // reinstalling the app cannot erase the age-rating transition baseline.
        guard let legacy = defaults.object(forKey: appRatingCodeKey) as? Int, legacy > 0 else { return nil }
        storeAppRatingCode(legacy)
        return legacy
    }

    private func storeAppRatingCode(_ code: Int) {
        guard code > 0 else { return }
        updateStore.set(String(code), forKey: appRatingCodeKey)
        _ = updateStore.synchronize()
        TrustKeychain.set(String(code), account: appRatingCodeKeychainAccount)
        defaults.removeObject(forKey: appRatingCodeKey)
    }

    private func foregroundWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func foregroundViewController() -> UIViewController? {
        guard let scene = foregroundWindowScene(),
              let window = scene.windows.first(where: \.isKeyWindow) else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
