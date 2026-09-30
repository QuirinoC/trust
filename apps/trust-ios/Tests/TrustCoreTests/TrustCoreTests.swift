import Foundation
import TrustCore
import XCTest

final class AvatarArtworkPaletteTests: XCTestCase {
    func testPresetBackingUsesWarmLightAndMutedBlueGrayDarkColors() {
        XCTAssertEqual(AvatarArtworkPalette.backingHex(isDarkAppearance: false), 0xFCFAF2)
        XCTAssertEqual(AvatarArtworkPalette.backingHex(isDarkAppearance: true), 0x334055)
    }
}

final class TrustCircleRefreshBarrierTests: XCTestCase {
    func testReadStartedBeforeConfirmedMutationCannotCommitButLaterReadCan() {
        var barrier = TrustCircleRefreshBarrier()
        let beforeStop = barrier.capture()

        barrier.recordConfirmedMutation()
        XCTAssertFalse(barrier.permitsCommit(startedAt: beforeStop),
                       "A delayed pre-Stop circle response must not restore the prior sharing mode or member.")

        let afterStop = barrier.capture()
        XCTAssertTrue(barrier.permitsCommit(startedAt: afterStop),
                      "A fresh read started after the confirmed mutation may reconcile the circle.")
    }

    func testEachConfirmedMutationInvalidatesEveryOlderRead() {
        var barrier = TrustCircleRefreshBarrier()
        let beforeHomeUpdate = barrier.capture()
        barrier.recordConfirmedMutation()
        let beforeLocationUpdate = barrier.capture()
        barrier.recordConfirmedMutation()

        XCTAssertFalse(barrier.permitsCommit(startedAt: beforeHomeUpdate))
        XCTAssertFalse(barrier.permitsCommit(startedAt: beforeLocationUpdate))
        XCTAssertTrue(barrier.permitsCommit(startedAt: barrier.capture()))
    }
}

final class TrustShareMutationGateTests: XCTestCase {
    func testOnlyTheActiveConnectionBlocksNewEnableOrPauseIntents() {
        var gate = TrustShareMutationGate()
        let connection = UUID()
        let replacement = UUID()

        XCTAssertFalse(gate.blocksNonOffMutation(connectionID: connection))
        gate.begin(connectionID: connection)
        XCTAssertTrue(gate.blocksNonOffMutation(connectionID: connection))
        XCTAssertFalse(gate.blocksNonOffMutation(connectionID: replacement),
                       "A replacement relationship must not inherit a queued write from the old connection.")

        gate.finish(connectionID: connection)
        XCTAssertFalse(gate.blocksNonOffMutation(connectionID: connection))
    }

    func testStopAllKeepsConnectionBusyUntilEveryQueuedWriteFinishes() {
        var gate = TrustShareMutationGate()
        let connection = UUID()

        gate.begin(connectionID: connection)
        gate.begin(connectionID: connection)
        gate.finish(connectionID: connection)
        XCTAssertTrue(gate.blocksNonOffMutation(connectionID: connection))
        gate.finish(connectionID: connection)
        XCTAssertFalse(gate.blocksNonOffMutation(connectionID: connection))
    }
}

@MainActor
final class TrustShareMutationOrderingTests: XCTestCase {
    func testStopSubmittedAfterDelayedSealedMutationRunsLast() async {
        let queue = TrustAsyncSerialExecutor()
        var visibleMode = "off"
        let finished = expectation(description: "queued stop completes")

        queue.enqueue {
            try? await Task.sleep(nanoseconds: 40_000_000)
            visibleMode = "sealed"
        }
        queue.enqueue {
            visibleMode = "off"
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(visibleMode, "off")
    }
}

final class TrustAccountPrivacyHoldTests: XCTestCase {
    func testServerHoldResponseOnlyAppliesToMatchingAuthenticatedAccount() {
        XCTAssertTrue(TrustAccountPrivacyHoldState.isCurrentAccountHoldResponse(
            apiCode: "account_privacy_hold",
            requestToken: "active",
            activeToken: "active"))
        XCTAssertFalse(TrustAccountPrivacyHoldState.isCurrentAccountHoldResponse(
            apiCode: "account_privacy_hold",
            requestToken: "stale",
            activeToken: "active"))
        XCTAssertFalse(TrustAccountPrivacyHoldState.isCurrentAccountHoldResponse(
            apiCode: "some_other_error",
            requestToken: "active",
            activeToken: "active"))
    }

    func testOfflineSubmissionFailureKeepsLocalAccountRestrictedAndRetryable() {
        var state = TrustAccountPrivacyHoldState()
        let operation = TrustAccountOperation(token: "account-a", generation: 4)

        state.restrictLocally()
        XCTAssertTrue(state.isLocallyRestricted)
        state.beginSubmission(for: operation)
        XCTAssertTrue(state.failSubmission(operation: operation, currentToken: operation.token, generation: 4))

        XCTAssertTrue(state.isLocallyRestricted)
        XCTAssertEqual(state.submission, .retryRequired)
        XCTAssertFalse(state.acknowledge(operation: operation, currentToken: "account-b", generation: 5))
        XCTAssertEqual(state.submission, .retryRequired)
    }

    func testStaleAccountResponseCannotAcknowledgePrivacyHold() {
        var state = TrustAccountPrivacyHoldState()
        let previous = TrustAccountOperation(token: "previous-account", generation: 9)
        let current = TrustAccountOperation(token: "current-account", generation: 10)

        state.beginSubmission(for: previous)
        XCTAssertFalse(state.acknowledge(operation: previous, currentToken: current.token, generation: current.generation))
        XCTAssertTrue(state.isLocallyRestricted)
        XCTAssertEqual(state.submission, .submitting)
        XCTAssertTrue(state.acknowledge(operation: previous, currentToken: previous.token, generation: previous.generation))
        XCTAssertEqual(state.submission, .acknowledged)
    }
}

final class TrustCrossDeviceReadScopeTests: XCTestCase {
    func testRestoredSessionSubjectScopesTheCachedCircleToItsOwner() throws {
        let aliceID = UUID()
        let bobID = UUID()
        let claims = try JSONSerialization.data(withJSONObject: ["sub": aliceID.uuidString])
        let encodedClaims = claims.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(encodedClaims).signature"
        let circle = try JSONSerialization.data(withJSONObject: ["you": ["id": aliceID.uuidString], "members": []])

        XCTAssertEqual(TrustSessionIdentity.accountID(from: token), aliceID)
        XCTAssertTrue(TrustCircleCacheMutation.belongsToAccount(circle, accountID: aliceID))
        XCTAssertFalse(TrustCircleCacheMutation.belongsToAccount(circle, accountID: bobID))
        XCTAssertNil(TrustSessionIdentity.accountID(from: "not-a-jwt"))
    }

    func testCircleCacheMutationPersistsConfirmedConsentAndRemovalForExactOwnerAndConnection() throws {
        let ownerID = UUID()
        let personID = UUID()
        let connectionID = UUID()
        let otherID = UUID()
        let payload: [String: Any] = [
            "you": ["id": ownerID.uuidString],
            "members": [
                [
                    "person": ["id": personID.uuidString],
                    "connectionId": connectionID.uuidString,
                    "share": ["resting": "always", "presentation": "always", "revision": 12]
                ],
                [
                    "person": ["id": otherID.uuidString],
                    "connectionId": UUID().uuidString,
                    "share": ["resting": "untilTheyLook", "presentation": "untilTheyLook", "revision": 4]
                ]
            ]
        ]
        let original = try JSONSerialization.data(withJSONObject: payload)

        let stoppedData = try XCTUnwrap(TrustCircleCacheMutation.updatingShare(
            in: original,
            accountID: ownerID,
            personID: personID,
            connectionID: connectionID,
            share: PersonShareState(resting: .off, revision: nil)
        ))
        let stopped = try XCTUnwrap(JSONSerialization.jsonObject(with: stoppedData) as? [String: Any])
        let stoppedMembers = try XCTUnwrap(stopped["members"] as? [[String: Any]])
        let stoppedShare = try XCTUnwrap(stoppedMembers[0]["share"] as? [String: Any])
        XCTAssertEqual(stoppedShare["resting"] as? String, "off")
        XCTAssertEqual(stoppedShare["presentation"] as? String, "off")
        XCTAssertTrue(stoppedShare["revision"] is NSNull)
        XCTAssertEqual(
            (stoppedMembers[1]["share"] as? [String: Any])?["resting"] as? String,
            "untilTheyLook",
            "A confirmed change for one connection must preserve other members."
        )

        let pauseUntil = Date(timeIntervalSince1970: 1_800_000_000)
        let pausedData = try XCTUnwrap(TrustCircleCacheMutation.updatingShare(
            in: original,
            accountID: ownerID,
            personID: personID,
            connectionID: connectionID,
            share: PersonShareState(resting: .paused, pauseUntil: pauseUntil, restoresTo: .always),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let paused = try XCTUnwrap(JSONSerialization.jsonObject(with: pausedData) as? [String: Any])
        let pausedMembers = try XCTUnwrap(paused["members"] as? [[String: Any]])
        let pausedShare = try XCTUnwrap(pausedMembers[0]["share"] as? [String: Any])
        XCTAssertEqual(pausedShare["resting"] as? String, "paused")
        XCTAssertEqual(pausedShare["presentation"] as? String, "paused")
        XCTAssertEqual(pausedShare["revertsTo"] as? String, "always")
        XCTAssertTrue(pausedShare["pauseUntil"] is String)

        XCTAssertNil(TrustCircleCacheMutation.updatingShare(
            in: original,
            accountID: UUID(),
            personID: personID,
            connectionID: connectionID,
            share: PersonShareState(resting: .off)
        ), "A stale cache from a different signed-in account cannot be mutated.")
        XCTAssertNil(TrustCircleCacheMutation.removing(
            from: original,
            accountID: ownerID,
            personID: personID,
            connectionID: UUID()
        ), "Removal must not delete a replacement relationship with a different connection ID.")

        let removedData = try XCTUnwrap(TrustCircleCacheMutation.removing(
            from: original,
            accountID: ownerID,
            personID: personID,
            connectionID: connectionID
        ))
        let removed = try XCTUnwrap(JSONSerialization.jsonObject(with: removedData) as? [String: Any])
        let remaining = try XCTUnwrap(removed["members"] as? [[String: Any]])
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual((remaining[0]["person"] as? [String: Any])?["id"] as? String, otherID.uuidString)
    }

    func testAcknowledgedRelationshipMutationsStayWithinTheOriginalConnection() {
        let personID = UUID()
        let connectionID = UUID()
        let replacementConnectionID = UUID()
        let original = TrustedPerson(
            person: Person(id: personID, displayName: "Alex"),
            connectionID: connectionID,
            presence: .sealed,
            share: PersonShareState(resting: .always, revision: 7),
            inboundLive: false
        )
        let stopped = PersonShareState(resting: .off, revision: nil)

        let updated = TrustConfirmedRelationshipMutation.applyingShare(
            stopped,
            personID: personID,
            connectionID: connectionID,
            to: [original]
        )
        XCTAssertEqual(updated?.first?.share, stopped)

        var replacement = original
        replacement.connectionID = replacementConnectionID
        XCTAssertNil(
            TrustConfirmedRelationshipMutation.applyingShare(
                stopped,
                personID: personID,
                connectionID: connectionID,
                to: [replacement]
            ),
            "An acknowledged write for an old relationship cannot rewrite a re-added connection."
        )
        XCTAssertNil(
            TrustConfirmedRelationshipMutation.removing(
                personID: personID,
                connectionID: connectionID,
                from: [replacement]
            ),
            "An acknowledged removal for an old relationship cannot remove a re-added connection."
        )
        XCTAssertEqual(
            TrustConfirmedRelationshipMutation.removing(
                personID: personID,
                connectionID: replacementConnectionID,
                from: [replacement]
            )?.count,
            0
        )
    }

    func testDelayedLookAndHistoryCannotCrossStopOrRemoveReadd() {
        let personID = UUID()
        let firstConnectionID = UUID()
        let original = TrustedPerson(
            person: Person(id: personID, displayName: "Alex"),
            connectionID: firstConnectionID,
            presence: .sealed,
            share: PersonShareState(),
            inboundLive: false,
            inboundPresentation: .untilTheyLook
        )
        let lookScope = TrustRelationshipScope(original)
        XCTAssertTrue(lookScope.permitsLookSnapshot(original))

        var pendingLook = TrustRequestValidity()
        let firstLookRequest = pendingLook.begin()
        XCTAssertTrue(pendingLook.accepts(firstLookRequest))

        var stopped = original
        stopped.inboundPresentation = .off
        XCTAssertFalse(lookScope.permitsLookSnapshot(stopped), "A delayed Look response must not restore a snapshot after Stop is observed.")
        pendingLook.invalidate()

        var resealed = original
        resealed.inboundPresentation = .untilTheyLook
        XCTAssertTrue(lookScope.permitsLookSnapshot(resealed), "The relationship itself remains the same after Stop and re-enable.")
        XCTAssertFalse(pendingLook.accepts(firstLookRequest), "Re-enabling Sealed cannot revive the request invalidated by observed Stop.")
        let freshLookRequest = pendingLook.begin()
        XCTAssertFalse(pendingLook.accepts(firstLookRequest))
        XCTAssertTrue(pendingLook.accepts(freshLookRequest))

        pendingLook.invalidate()
        let newerConfirmation = pendingLook.begin()
        XCTAssertFalse(pendingLook.accepts(firstLookRequest), "An obsolete response must not dismiss or complete a newer confirmation.")
        XCTAssertTrue(pendingLook.accepts(newerConfirmation))

        var reconnected = original
        reconnected.connectionID = UUID()
        XCTAssertFalse(lookScope.permitsLookSnapshot(reconnected), "Re-adding the same account creates a different consent relationship.")

        var always = original
        always.inboundPresentation = .always
        let historyScope = TrustRelationshipScope(always)
        XCTAssertTrue(historyScope.permitsHistory(always))
        XCTAssertFalse(historyScope.permitsHistory(stopped), "History must stop when the recipient observes Off.")

        var reconnectedAlways = always
        reconnectedAlways.connectionID = UUID()
        XCTAssertFalse(historyScope.permitsHistory(reconnectedAlways), "An old History response must not populate a replacement relationship, even when it is also Always.")
    }

    func testClearInvalidatesPendingHomeFixBeforeItCanBeQueued() {
        var state = TrustHomeFixRequestState()
        let pending = state.begin()
        XCTAssertTrue(state.accepts(pending))

        state.cancel()
        XCTAssertFalse(state.accepts(pending), "Clear Home must supersede an update still waiting for GPS.")

        let later = state.begin()
        XCTAssertFalse(state.accepts(pending), "A later Set must not make the stale callback valid again.")
        XCTAssertTrue(state.accepts(later))
    }
}

final class TrustPushDestinationTests: XCTestCase {
    func testLookAndHomeArrivalOpenRelevantScreens() {
        XCTAssertEqual(
            TrustPushDestination(userInfo: ["trust": ["kind": "look"]]),
            .activity
        )
        XCTAssertEqual(
            TrustPushDestination(userInfo: ["trust": ["kind": "home_arrival"]]),
            .people
        )
    }

    func testUnknownOrMalformedPushDoesNotNavigate() {
        XCTAssertNil(TrustPushDestination(userInfo: [:]))
        XCTAssertNil(TrustPushDestination(userInfo: ["trust": "look"]))
        XCTAssertNil(TrustPushDestination(userInfo: ["trust": ["kind": "unknown"]]))
    }
}

final class TrustAgePolicyTests: XCTestCase {
    func testAgeBandsMatchTexasCategoriesWithoutKeepingExactAge() {
        let thresholds = TrustAgePolicy.ageBandThresholds
        XCTAssertEqual(thresholds.minimum, 13)
        XCTAssertEqual(thresholds.olderTeen, 16)
        XCTAssertEqual(thresholds.adult, 18)

        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: nil, upperBound: 12), .under13)
        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: 13, upperBound: 15), .age13To15)
        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: 16, upperBound: 17), .age16To17)
        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: 18, upperBound: nil), .adult18Plus)
        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: 15, upperBound: 16), .indeterminate)
        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: nil, upperBound: 17), .under13)
        XCTAssertEqual(TrustAgePolicy.ageBand(lowerBound: 13, upperBound: nil), .indeterminate)
        XCTAssertEqual(
            TrustAgePolicy.ageBand(lowerBound: nil, upperBound: nil),
            .under13,
            "Apple defines a nil lower bound as below the lowest requested gate; declined sharing is a separate response."
        )
    }

    func testFirstUseBlocksOnlyAgeRangesProvenBelowMinimum() {
        XCTAssertEqual(
            TrustAgePolicy.initialUseDecision(lowerBound: nil, upperBound: 12),
            .accountCreationBlocked
        )
        XCTAssertEqual(
            TrustAgePolicy.initialUseDecision(lowerBound: nil, upperBound: 15),
            .accountCreationBlocked,
            "A nil lower bound means Apple placed the person below the lowest requested gate."
        )
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: nil, upperBound: 12), .accountCreationBlocked)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 12, upperBound: 15), .indeterminate)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 12, upperBound: nil), .indeterminate)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: nil, upperBound: nil), .accountCreationBlocked)
        XCTAssertEqual(
            TrustAgePolicy.initialUseDecision(lowerBound: 13, upperBound: 17),
            .continueSetup,
            "A confirmed lower bound at the minimum gate satisfies first-use eligibility even when the range spans age bands."
        )
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 13, upperBound: nil), .continueSetup)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 12, upperBound: 12), .accountCreationBlocked)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 12, upperBound: 13), .indeterminate)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 13, upperBound: 15), .continueSetup)
        XCTAssertEqual(TrustAgePolicy.initialUseDecision(lowerBound: 16, upperBound: 17), .continueSetup)
        XCTAssertEqual(
            TrustAgePolicy.initialUseDecision(lowerBound: 18, upperBound: nil),
            .continueSetup
        )
    }

    func testAgeRangeCorrectionRetryCannotBypassAppleEligibilitySignal() {
        XCTAssertEqual(
            TrustAgePolicy.ageRangeRequestDecision(
                ageRangeRequired: true, hasUnderMinimumBlock: false, retryRequested: false
            ),
            .request
        )
        XCTAssertEqual(
            TrustAgePolicy.ageRangeRequestDecision(
                ageRangeRequired: true, hasUnderMinimumBlock: true, retryRequested: false
            ),
            .remainBlocked,
            "A saved age block requires an explicit user retry before a new system prompt."
        )
        XCTAssertEqual(
            TrustAgePolicy.ageRangeRequestDecision(
                ageRangeRequired: true, hasUnderMinimumBlock: true, retryRequested: true
            ),
            .request
        )
        XCTAssertEqual(
            TrustAgePolicy.ageRangeRequestDecision(
                ageRangeRequired: false, hasUnderMinimumBlock: true, retryRequested: true
            ),
            .remainBlocked,
            "A correction retry cannot request an age signal when Apple says this region does not require one."
        )
        XCTAssertEqual(
            TrustAgePolicy.ageRangeRequestDecision(
                ageRangeRequired: false, hasUnderMinimumBlock: false, retryRequested: true
            ),
            .continueWithoutRequest
        )
    }

    func testOnlyExplicitRevocationRegistrationResponseMarksConsentWithdrawn() {
        XCTAssertTrue(TrustAgePolicy.isConsentRevocationResponse(apiCode: "consent_revoked"))
        XCTAssertFalse(TrustAgePolicy.isConsentRevocationResponse(apiCode: nil))
        XCTAssertFalse(TrustAgePolicy.isConsentRevocationResponse(apiCode: "server_unavailable"))
        XCTAssertFalse(TrustAgePolicy.isConsentRevocationResponse(apiCode: "storekit_unavailable"))
        XCTAssertTrue(TrustAgePolicy.isCurrentAccountConsentRevocation(
            apiCode: "consent_revoked", requestToken: "current", activeToken: "current"
        ))
        XCTAssertFalse(TrustAgePolicy.isCurrentAccountConsentRevocation(
            apiCode: "consent_revoked", requestToken: "previous", activeToken: "current"
        ), "A late response from a signed-out account must not clear the next account's session.")
        XCTAssertFalse(TrustAgePolicy.isCurrentAccountConsentRevocation(
            apiCode: "server_unavailable", requestToken: "current", activeToken: "current"
        ))
    }

    func testICloudAcknowledgementIsScopedToCurrentSignificantUpdateOnly() {
        XCTAssertTrue(TrustAgePolicy.isCurrentSignificantUpdateAcknowledged(storedUpdateID: "update-1", currentUpdateID: "update-1"))
        XCTAssertFalse(TrustAgePolicy.isCurrentSignificantUpdateAcknowledged(storedUpdateID: "update-1", currentUpdateID: "update-2"))
        XCTAssertFalse(TrustAgePolicy.isCurrentSignificantUpdateAcknowledged(storedUpdateID: nil, currentUpdateID: "update-1"))
    }

    func testSignificantUpdateVersionEligibilityDistinguishesNewInstallFromUpgrade() {
        let introducedInBuildNumber = TrustAgePolicy.significantUpdateIntroducedInBuildNumber

        XCTAssertFalse(TrustAgePolicy.significantUpdateApplies(
            originalAppBuildNumber: "33",
            introducedInBuildNumber: introducedInBuildNumber
        ), "An install at the build that introduced the change does not acknowledge it retroactively.")
        XCTAssertFalse(TrustAgePolicy.significantUpdateApplies(
            originalAppBuildNumber: "34",
            introducedInBuildNumber: introducedInBuildNumber
        ))
        XCTAssertTrue(TrustAgePolicy.significantUpdateApplies(
            originalAppBuildNumber: "32",
            introducedInBuildNumber: introducedInBuildNumber
        ), "An upgrade from an earlier original build still handles the significant change.")
        XCTAssertTrue(TrustAgePolicy.significantUpdateApplies(
            originalAppBuildNumber: nil,
            introducedInBuildNumber: introducedInBuildNumber
        ), "An unavailable or unverified transaction keeps the existing conservative behavior.")

        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 13,
                upperBound: 17,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: true,
                significantUpdateApplies: TrustAgePolicy.significantUpdateApplies(
                    originalAppBuildNumber: "33",
                    introducedInBuildNumber: introducedInBuildNumber
                )
            ),
            .none,
            "An update that predates the original install does not gate a current-version install."
        )
    }

    func testAgeUpdateApprovalCannotBeReusedForAStaleOrNewQuestion() {
        XCTAssertTrue(TrustAgePolicy.acceptsAgeUpdateResponse(responseQuestionID: "active-question", pendingQuestionID: "active-question"))
        XCTAssertFalse(TrustAgePolicy.acceptsAgeUpdateResponse(responseQuestionID: "old-question", pendingQuestionID: "new-question"))
        XCTAssertFalse(TrustAgePolicy.acceptsAgeUpdateResponse(responseQuestionID: "old-question", pendingQuestionID: nil))
    }

    func testBackgroundICloudAccountChangeConsumesOneForegroundRecheckAndKeepsAccessSuspended() {
        var state = TrustAgeAccessState()
        let originalEvaluation = state.beginEvaluation()
        XCTAssertTrue(state.completeEvaluation(originalEvaluation, permitted: true))
        XCTAssertTrue(state.isAllowed)

        let newAccountEvaluation = state.suspendForAppleAccountChange(isForeground: false)
        XCTAssertFalse(state.isAllowed, "A previously permitted Apple subject must lose access immediately on account change.")
        XCTAssertTrue(state.needsForegroundRecheck)
        XCTAssertFalse(state.completeEvaluation(originalEvaluation, permitted: true), "An in-flight result for the previous Apple account must be ignored.")
        XCTAssertTrue(state.consumeForegroundRecheck(), "Foreground must resume the pending check.")
        XCTAssertFalse(state.consumeForegroundRecheck(), "One account-change notification schedules only one foreground recheck.")
        XCTAssertTrue(state.isCurrentEvaluation(newAccountEvaluation))

        XCTAssertTrue(state.completeEvaluation(newAccountEvaluation, permitted: false))
        XCTAssertFalse(state.isAllowed, "Access stays suspended when the new Apple account does not satisfy the required flow.")
    }

    func testAccountHomeScopesAreDistinctWithoutProfileMutation() {
        let aliceHome = TrustHomeScope.key("placeId", accountID: "ALICE")
        let bobHome = TrustHomeScope.key("placeId", accountID: "bob")
        let signedOutHome = TrustHomeScope.key("placeId", accountID: nil)

        XCTAssertEqual(aliceHome, "trust.home.account.alice.placeId")
        XCTAssertNotEqual(aliceHome, bobHome)
        XCTAssertNotEqual(aliceHome, signedOutHome)
        XCTAssertNotEqual(bobHome, signedOutHome)
        XCTAssertTrue(TrustHomeScope.requiresSwitch(from: nil, to: "Alice"))
        XCTAssertFalse(TrustHomeScope.requiresSwitch(from: "ALICE", to: "alice"), "Repeated refreshes of the same account must not reset active Home monitoring.")
        XCTAssertTrue(TrustHomeScope.requiresSwitch(from: "alice", to: "bob"))
        XCTAssertFalse(TrustHomeScope.requiresSwitch(from: nil, to: nil))
    }

    func testStaleHomeOperationsCannotCommitAfterAccountSwitchOrSignOut() {
        let aliceOperation = TrustAccountOperation(token: "alice-token", generation: 4)

        XCTAssertTrue(aliceOperation.matches(token: "alice-token", generation: 4))
        XCTAssertFalse(aliceOperation.matches(token: "bob-token", generation: 5))
        XCTAssertFalse(aliceOperation.matches(token: nil, generation: 5))
        XCTAssertFalse(aliceOperation.matches(token: "alice-token", generation: 5))
    }

    @MainActor
    func testDelayedStoreKitRegistrationCannotUseTheNextAccountsBearerToken() async {
        let aliceOperation = TrustAccountOperation(token: "alice-token", generation: 8)
        var currentToken: String? = "alice-token"
        var currentGeneration: UInt64 = 8
        var dispatchedToken: String?

        XCTAssertEqual(aliceOperation.authorizationToken(currentToken: currentToken, generation: currentGeneration), "alice-token")
        let storeKitWait = Task { @MainActor in
            await Task.yield() // Models the suspension while AppTransaction.shared resolves.
            dispatchedToken = aliceOperation.authorizationToken(currentToken: currentToken, generation: currentGeneration)
        }
        currentToken = "bob-token"
        currentGeneration = 9
        await storeKitWait.value

        XCTAssertNil(dispatchedToken, "The stale A operation must stop before network dispatch, never substitute B's mutable token.")
        XCTAssertNotEqual(dispatchedToken, currentToken)
    }

    func testHistoryAndSharingResultsAreDiscardedAfterAccountSwitch() {
        let alice = TrustAccountOperation(token: "alice-token", generation: 12)
        XCTAssertTrue(alice.matches(token: "alice-token", generation: 12))

        XCTAssertFalse(alice.matches(token: "bob-token", generation: 13))
        XCTAssertNil(alice.authorizationToken(currentToken: "bob-token", generation: 13))
    }

    @MainActor
    func testDelayedAliceCircleResponseCannotReplaceBobsOfflineCache() async {
        let alice = TrustAccountOperation(token: "alice-token", generation: 20)
        let bob = TrustAccountOperation(token: "bob-token", generation: 21)
        var current = alice
        var cachedCircle = "bob-circle"

        let delayedResponse = Task { @MainActor in
            await Task.yield() // Models GET /circle returning after account restoration.
            return alice.commitIfCurrent(currentOperation: current) {
                cachedCircle = "alice-circle"
            }
        }
        current = bob
        let committed = await delayedResponse.value

        XCTAssertFalse(committed)
        XCTAssertEqual(cachedCircle, "bob-circle", "A stale Alice response cannot replace Bob's offline circle cache.")
        XCTAssertTrue(bob.commitIfCurrent(currentOperation: current) { cachedCircle = "bob-fresh-circle" })
        XCTAssertEqual(cachedCircle, "bob-fresh-circle")
    }

    @MainActor
    func testStopAllUsesTheAccountOperationCapturedAtInvocation() async {
        let alice = TrustAccountOperation(token: "alice-token", generation: 30)
        let bob = TrustAccountOperation(token: "bob-token", generation: 31)
        let current = CurrentAccountOperationBox(alice)
        var mutatedShareTokens: [String] = []

        let scheduledStopAll = Task { @MainActor in
            await Task.yield() // Models scheduling after the user taps Stop All.
            guard let token = alice.authorizationToken(
                currentToken: current.operation.token,
                generation: current.operation.generation
            ) else { return }
            mutatedShareTokens.append(token)
        }
        current.operation = bob
        await scheduledStopAll.value

        XCTAssertTrue(mutatedShareTokens.isEmpty, "Stop All from Alice must not apply to Bob after the Task is scheduled.")
    }

    @MainActor
    private final class CurrentAccountOperationBox {
        var operation: TrustAccountOperation

        init(_ operation: TrustAccountOperation) {
            self.operation = operation
        }
    }

    @MainActor
    func testDelayedHomeSetThenClearExecutesInUserIntentOrder() async throws {
        let queue = TrustAsyncSerialExecutor()
        var serverHome: String?
        var localHome: String?
        var setFinished = false

        queue.enqueue {
            try? await Task.sleep(nanoseconds: 80_000_000)
            serverHome = "home-place"
            localHome = "home-place"
            setFinished = true
        }
        queue.enqueue {
            XCTAssertTrue(setFinished, "Clear must wait for the delayed Set request and local commit.")
            serverHome = nil
            localHome = nil
        }

        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertNil(serverHome)
        XCTAssertNil(localHome, "A late Set completion must not restore Home after Clear succeeds.")
    }

    func testBirthDateEntryRequiresACompleteValidDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceNow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(monthText: "", dayText: "", yearText: ""),
            .incomplete
        )
        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(monthText: "2", dayText: "29", yearText: "2025"),
            .invalid
        )
        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(
                monthText: "9", dayText: "29", yearText: "2026", now: referenceNow, calendar: calendar),
            .invalid,
            "A birthday after the injected reference date must not pass the age check."
        )
    }

    func testBirthDateAgeBoundaryChangesOnThirteenthBirthday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27)))

        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(monthText: "9", dayText: "27", yearText: "2013", now: today, calendar: calendar),
            .eligible
        )
        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(monthText: "9", dayText: "28", yearText: "2013", now: today, calendar: calendar),
            .underMinimum
        )
        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(monthText: "2", dayText: "29", yearText: "2012", now: today, calendar: calendar),
            .eligible,
            "Leap-day birth dates remain valid."
        )
    }

    func testBirthDateInputUsesGregorianCalendarByDefault() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let today = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 9, day: 27)))

        XCTAssertEqual(
            TrustAgePolicy.birthDateEligibility(monthText: "9", dayText: "27", yearText: "2013", now: today),
            .eligible,
            "The MM/DD/YYYY fields represent Gregorian dates regardless of the device's preferred calendar."
        )
    }

    func testAppRatingObservationDetectsChangesWithoutInterpretingOpaqueCodes() {
        XCTAssertEqual(
            TrustAgePolicy.appRatingObservation(currentCode: nil, previousCode: nil),
            .unavailable
        )
        XCTAssertEqual(
            TrustAgePolicy.appRatingObservation(currentCode: 0, previousCode: nil),
            .unavailable,
            "StoreKit's development and TestFlight placeholder must not become a production baseline."
        )
        XCTAssertEqual(
            TrustAgePolicy.appRatingObservation(currentCode: 7, previousCode: nil),
            .firstObservation(code: 7)
        )
        XCTAssertEqual(
            TrustAgePolicy.appRatingObservation(currentCode: 7, previousCode: 7),
            .unchanged(code: 7)
        )
        XCTAssertEqual(
            TrustAgePolicy.appRatingObservation(currentCode: 8, previousCode: 7),
            .changed(previousCode: 7, currentCode: 8)
        )
        XCTAssertEqual(
            TrustAgePolicy.appRatingChangeUpdateID(previousCode: 7, currentCode: 8, occurrenceID: "first"),
            "2026-09-age-assurance-v1-app-rating-7-to-8-first"
        )
        let firstOccurrence = TrustAgePolicy.appRatingChangeUpdateID(
            previousCode: 7, currentCode: 8, occurrenceID: "first"
        )
        let laterOccurrence = TrustAgePolicy.appRatingChangeUpdateID(
            previousCode: 7, currentCode: 8, occurrenceID: "later"
        )
        XCTAssertNotEqual(firstOccurrence, laterOccurrence, "A repeated rating transition gets a fresh acknowledgement identity.")
        XCTAssertTrue(TrustAgePolicy.isAppRatingChangeUpdateID(
            firstOccurrence, previousCode: 7, currentCode: 8
        ), "The same pending transition can recover its ID after relaunch.")
        XCTAssertFalse(TrustAgePolicy.isAppRatingChangeUpdateID(
            firstOccurrence, previousCode: 8, currentCode: 7
        ))
        XCTAssertTrue(TrustAgePolicy.isAppRatingChangeUpdateID(firstOccurrence))
        XCTAssertEqual(
            TrustAgePolicy.acknowledgementIdentifiers(for: firstOccurrence),
            [firstOccurrence],
            "A rating-only approval must not mark an unmentioned release change as acknowledged."
        )
        XCTAssertEqual(
            TrustAgePolicy.acknowledgementIdentifiers(
                for: firstOccurrence,
                alsoAcknowledgingSignificantUpdate: true
            ),
            [firstOccurrence, "2026-09-age-assurance-v1"]
        )
        XCTAssertEqual(
            TrustAgePolicy.acknowledgementIdentifiers(for: "2026-09-age-assurance-v1"),
            ["2026-09-age-assurance-v1"]
        )
        XCTAssertEqual(
            TrustAgePolicy.acknowledgementIdentifiers(for: "old-policy-app-rating-7-to-8"),
            ["old-policy-app-rating-7-to-8"],
            "An old policy's rating acknowledgement must not authorize the current release."
        )
    }

    func testPendingRatingTransitionBlocksWhenStoreKitHasNoUsableRating() {
        XCTAssertTrue(TrustAgePolicy.shouldBlockForUnavailablePendingRating(
            hasPendingRatingTransition: true,
            acknowledgementComplete: false
        ), "A missing or placeholder rating must not clear an unresolved transition.")
        XCTAssertFalse(TrustAgePolicy.shouldBlockForUnavailablePendingRating(
            hasPendingRatingTransition: true,
            acknowledgementComplete: true
        ), "A completed acknowledgement can resolve the persisted pending transition.")
        XCTAssertFalse(TrustAgePolicy.shouldBlockForUnavailablePendingRating(
            hasPendingRatingTransition: false,
            acknowledgementComplete: false
        ))
    }

    func testRatingRequirementSurvivesDenialAndSessionResetUntilResolved() throws {
        let requirement = TrustAgePolicy.RatingTransitionRequirement(
            identifier: "2026-09-age-assurance-v1-app-rating-7-to-8-occurrence",
            previousCode: 7,
            targetCode: 8
        )
        // Permission questions and sessions may be cleared independently; the
        // durable marker round-trips by itself and still blocks on nil/0 ratings.
        let restored = try JSONDecoder().decode(
            TrustAgePolicy.RatingTransitionRequirement.self,
            from: JSONEncoder().encode(requirement)
        )
        XCTAssertEqual(restored, requirement)
        XCTAssertEqual(
            TrustAgePolicy.ratingRequirementDisposition(
                restored,
                observation: .unavailable,
                acknowledgementComplete: false
            ),
            .retain,
            "Denial or account/session cleanup must not erase an unresolved rating requirement."
        )
        XCTAssertEqual(
            TrustAgePolicy.ratingRequirementDisposition(
                restored,
                observation: .firstObservation(code: 8),
                acknowledgementComplete: false
            ),
            .restoreTransition(previousCode: 7, currentCode: 8),
            "The same current transition remains pending after relaunch without its old question."
        )
        XCTAssertEqual(
            TrustAgePolicy.ratingRequirementDisposition(
                restored,
                observation: .firstObservation(code: 7),
                acknowledgementComplete: false
            ),
            .clear,
            "A return to the known previous rating resolves the old transition."
        )
        XCTAssertEqual(
            TrustAgePolicy.ratingRequirementDisposition(
                restored,
                observation: .firstObservation(code: 9),
                acknowledgementComplete: false
            ),
            .supersedingTransition(previousCode: 7, currentCode: 9),
            "A different rating after losing the local baseline is still treated as a new transition."
        )
        XCTAssertEqual(
            TrustAgePolicy.ratingRequirementDisposition(
                restored,
                observation: .changed(previousCode: 7, currentCode: 9),
                acknowledgementComplete: false
            ),
            .clear,
            "A usable different transition supersedes the old marker."
        )
        XCTAssertEqual(
            TrustAgePolicy.ratingRequirementDisposition(
                restored,
                observation: .unavailable,
                acknowledgementComplete: true
            ),
            .approved(targetCode: 8)
        )
    }

    func testRatingPromptCoversReleaseOnlyWhenThatReleaseChangeIsStillPending() {
        XCTAssertTrue(TrustAgePolicy.significantUpdateAcknowledgementIsPending(
            applies: true,
            isRequired: true,
            isAcknowledged: false
        ))
        XCTAssertFalse(TrustAgePolicy.significantUpdateAcknowledgementIsPending(
            applies: true,
            isRequired: true,
            isAcknowledged: true
        ), "An acknowledged release must not be described or recorded again in a rating-only prompt.")
        XCTAssertFalse(TrustAgePolicy.significantUpdateAcknowledgementIsPending(
            applies: false,
            isRequired: true,
            isAcknowledged: false
        ), "A current-version install does not have an earlier release acknowledgement pending.")
        XCTAssertFalse(TrustAgePolicy.significantUpdateAcknowledgementIsPending(
            applies: true,
            isRequired: false,
            isAcknowledged: false
        ))
    }

    func testSupersededAgeEvaluationCannotRestoreAccessAfterAppleAccountChange() {
        var state = TrustAgeAccessState()
        let earlierEvaluation = state.beginEvaluation()
        XCTAssertTrue(state.completeEvaluation(earlierEvaluation, permitted: true))

        let currentEvaluation = state.suspendForAppleAccountChange(isForeground: true)
        XCTAssertFalse(state.completeEvaluation(earlierEvaluation, permitted: true))
        XCTAssertFalse(state.isAllowed)
        XCTAssertTrue(state.isCurrentEvaluation(currentEvaluation))
    }

    func testSignificantUpdateUsesAppleRegulatoryFlagsWhenAvailable() {
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: nil,
                upperBound: nil,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: true
            ),
            .parentApproval,
            "Apple's required parent-consent signal applies regardless of whether a range is returned."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: nil,
                upperBound: nil,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: true,
                parentConsentRequired: false
            ),
            .adultSystemAcknowledgement,
            "Apple's required adult-notification signal applies regardless of whether a range is returned."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 12,
                upperBound: 17,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: false
            ),
            .none,
            "The exact regulatory flags take precedence; an age-range request alone does not invent an under-13 account ban."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 13,
                upperBound: 17,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: false,
                appRatingChanged: true
            ),
            .parentApproval,
            "Apple's age-rating-change guidance requires a PermissionKit parent request for a known minor."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 18,
                upperBound: nil,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: false,
                appRatingChanged: true
            ),
            .none,
            "A known adult does not receive a parent-consent request for a rating change."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 13,
                upperBound: nil,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: false,
                appRatingChanged: true
            ),
            .unavailable,
            "A required age check with an ambiguous age range cannot silently accept a rating transition."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: false,
                lowerBound: nil,
                upperBound: nil,
                regulatorySignalsAvailable: true,
                adultNotificationRequired: false,
                parentConsentRequired: false,
                appRatingChanged: true
            ),
            .none,
            "A rating update alone does not trigger a global age prompt outside a regulated region."
        )
    }

    func testSignificantUpdateUsesEligibleSharedAgeRangeOnEarlierAppleSystems() {
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: nil,
                upperBound: 12,
                regulatorySignalsAvailable: false,
                adultNotificationRequired: false,
                parentConsentRequired: false,
                legacyEligibleMinor: true
            ),
            .parentApproval,
            "A shared under-18 range plus Apple's eligibility signal requires the parent flow on iOS 26.2–26.3."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 13,
                upperBound: 17,
                regulatorySignalsAvailable: false,
                adultNotificationRequired: false,
                parentConsentRequired: false,
                legacyEligibleMinor: true
            ),
            .parentApproval,
            "The Apple age range is only treated as a minor when Apple also says age features apply."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 18,
                upperBound: nil,
                regulatorySignalsAvailable: false,
                adultNotificationRequired: false,
                parentConsentRequired: false
            ),
            .none,
            "Adults do not receive an invented in-app acknowledgement on iOS 26.2–26.3."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: false,
                lowerBound: 13,
                upperBound: 17,
                regulatorySignalsAvailable: false,
                adultNotificationRequired: false,
                parentConsentRequired: false
            ),
            .none,
            "A voluntary age-range correction outside an eligible region does not create a parental-approval requirement."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: nil,
                upperBound: nil,
                regulatorySignalsAvailable: false,
                adultNotificationRequired: false,
                parentConsentRequired: false
            ),
            .unavailable,
            "When Apple says age features apply but no range is available, the required update cannot proceed."
        )
        XCTAssertEqual(
            TrustAgePolicy.significantUpdateAction(
                ageRangeRequired: true,
                lowerBound: 18,
                upperBound: nil,
                regulatorySignalsAvailable: false,
                adultNotificationRequired: false,
                parentConsentRequired: false
            ),
            .none
        )
    }
}

final class AvatarDescriptorTests: XCTestCase {
    func testNewAndLegacyPresetsRemainRecognized() {
        let pickerIDs = [
            "fox", "rabbit", "bear", "cat", "dog", "otter", "owl", "turtle", "siamese", "ragdoll", "british-shorthair"
        ]
        XCTAssertEqual(pickerIDs.count, 11)
        XCTAssertEqual(Set(pickerIDs).count, 11)

        for id in pickerIDs {
            XCTAssertEqual(AvatarDescriptor.preset(id).knownPresetID, id)
        }
        for id in ["ember", "sky", "ocean", "sunrise", "lavender", "raindrop", "rainbow", "river", "meadow", "bloom", "cherry", "lotus", "coral"] {
            XCTAssertEqual(AvatarDescriptor.preset(id).knownPresetID, id, "Legacy preset \(id) must remain displayable")
        }
    }
}

final class PersonLookupQueryTests: XCTestCase {
    func testHandleAndDomesticPhoneAreNormalized() {
        XCTAssertEqual(PersonLookupQuery.parse(" @Riley_7 "), .handle("riley_7"))
        XCTAssertEqual(PersonLookupQuery.parse("(415) 555-0198", region: "us"), .phone("4155550198", region: "US"))
    }

    func testInternationalPhoneDoesNotReceiveDomesticRegion() throws {
        XCTAssertEqual(PersonLookupQuery.parse("+44 20 7946 0958", region: "US"), .phone("+442079460958", region: nil))
        let encoded = try JSONEncoder().encode(PersonLookupQuery.phone("+442079460958", region: nil))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(body.count, 1)
        XCTAssertEqual(body["phone"] as? String, "+442079460958")
        XCTAssertNil(body["region"])
    }

    func testLookupBodyEncodesExactlyOneHandleField() throws {
        let encoded = try JSONEncoder().encode(PersonLookupQuery.handle("riley"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(body.count, 1)
        XCTAssertEqual(body["handle"] as? String, "riley")
    }

    func testIncompleteOrMixedInputIsNotEligibleForLookup() {
        XCTAssertNil(PersonLookupQuery.parse("415-555"))
        XCTAssertNil(PersonLookupQuery.parse("415-555-0198x12"))
        XCTAssertNil(PersonLookupQuery.parse("+1+4155550198"))
        XCTAssertNil(PersonLookupQuery.parse("1234567890123456"))
    }
}

final class EscrowVaultTests: XCTestCase {
    func testPeekNeverReturnsCoordinates() {
        let vault = EscrowVault()
        vault.ingest(
            LocationPoint(timestamp: Date(), latitude: 37.75, longitude: -122.41)
        )
        XCTAssertTrue(vault.peekPlaintext().isEmpty)
        XCTAssertEqual(vault.sealedCount, 1)
    }

    func testUnlockKeepsThirtyDaysNotAShortWindow() {
        let vault = EscrowVault()
        let now = Date()
        vault.ingest(LocationPoint(timestamp: now.addingTimeInterval(-31 * 24 * 3600), latitude: 8, longitude: 8))
        vault.ingest(LocationPoint(timestamp: now.addingTimeInterval(-3 * 3600), latitude: 1, longitude: 1))
        vault.ingest(LocationPoint(timestamp: now.addingTimeInterval(-90 * 60), latitude: 2, longitude: 2))
        vault.ingest(LocationPoint(timestamp: now.addingTimeInterval(-20 * 60), latitude: 3, longitude: 3))
        vault.ingest(LocationPoint(timestamp: now.addingTimeInterval(-48 * 3600), latitude: 9, longitude: 9))

        let trail = vault.unlock(now: now)
        XCTAssertEqual(trail.map(\.latitude), [9, 1, 2, 3])
        XCTAssertEqual(EscrowVault.defaultHistoryWindow, 30 * 24 * 60 * 60)
    }

    func testDestroyGrantMakesHistoryUnavailable() {
        let vault = EscrowVault()
        let now = Date()
        vault.ingest(LocationPoint(timestamp: now, latitude: 10, longitude: 10))
        XCTAssertFalse(vault.unlock(now: now).isEmpty)
        vault.destroyGrant()
        XCTAssertTrue(vault.unlock(now: now).isEmpty)
        XCTAssertTrue(vault.peekPlaintext().isEmpty)
    }
}

final class LocationIngestBufferTests: XCTestCase {
    func testBufferKeepsTrailAndDropsOlderThanRetention() {
        var buffer = LocationIngestBuffer()
        let now = Date()
        buffer.append([
            LocationPoint(timestamp: now.addingTimeInterval(-31 * 24 * 3600), latitude: 1, longitude: 1),
            LocationPoint(timestamp: now.addingTimeInterval(-90 * 60), latitude: 2, longitude: 2),
            LocationPoint(timestamp: now.addingTimeInterval(-10 * 60), latitude: 3, longitude: 3)
        ], now: now)
        XCTAssertEqual(buffer.points.map(\.latitude), [2, 3])
        buffer.removePrefix(1)
        XCTAssertEqual(buffer.points.map(\.latitude), [3])
    }

    func testAccountSwitchInvalidatesDelayedBatchAndKeepsNewAccountPoint() {
        let oldPoint = LocationPoint(timestamp: Date(), latitude: 10, longitude: 20)
        let newPoint = LocationPoint(timestamp: Date().addingTimeInterval(1), latitude: 30, longitude: 40)
        var queue = AccountScopedLocationIngestBuffer(accountID: "alice", points: [oldPoint])
        let delayedAliceBatch = queue.nextBatch()

        queue.setAccountScope("bob")
        queue.append([newPoint])

        XCTAssertFalse(queue.acknowledge(delayedAliceBatch), "A delayed Alice response cannot acknowledge Bob's queue.")
        XCTAssertEqual(queue.points, [newPoint], "Bob's point remains queued after the old request completes.")
        XCTAssertEqual(queue.accountID, "bob")
    }

    func testAccountSwitchRetiresOldPointsInsteadOfReusingThem() {
        let alicePoint = LocationPoint(timestamp: Date(), latitude: 10, longitude: 20)
        var queue = AccountScopedLocationIngestBuffer(accountID: "alice", points: [alicePoint])

        queue.setAccountScope(nil)
        queue.setAccountScope("bob")

        XCTAssertEqual(queue.points, [], "Signed-out/account-switch scopes must not inherit prior GPS points.")
        XCTAssertEqual(queue.accountID, "bob")
    }

    func testNextBatchCapsAtAPIRequestLimitAndLeavesQueueUntouched() {
        let now = Date()
        var buffer = LocationIngestBuffer()
        let points = (0...100).map {
            LocationPoint(timestamp: now.addingTimeInterval(Double($0)), latitude: Double($0), longitude: 0)
        }
        buffer.append(points, now: now)

        let firstBatch = buffer.nextBatch()
        XCTAssertEqual(firstBatch.count, 100)
        XCTAssertEqual(firstBatch.first?.latitude, 0)
        XCTAssertEqual(firstBatch.last?.latitude, 99)
        XCTAssertEqual(buffer.points.count, 101, "Selecting a batch must not dequeue unconfirmed points")

        buffer.removePrefix(firstBatch.count)
        XCTAssertEqual(buffer.nextBatch().map(\.latitude), [100])
        XCTAssertEqual(buffer.points.count, 1)
    }

    func testUnconfirmedBatchRemainsQueued() {
        let now = Date()
        var buffer = LocationIngestBuffer()
        let points = (0..<101).map {
            LocationPoint(timestamp: now.addingTimeInterval(Double($0)), latitude: Double($0), longitude: 0)
        }
        buffer.append(points, now: now)

        let attemptedBatch = buffer.nextBatch()
        // A failed or cancelled request performs no removePrefix call.
        XCTAssertEqual(attemptedBatch.count, 100)
        XCTAssertEqual(buffer.points, points)
    }

    @MainActor
    func testDrainOverOneHundredPointsAndRetryFailedSecondBatchInOrder() async throws {
        let now = Date()
        let points = (0..<250).map {
            LocationPoint(timestamp: now.addingTimeInterval(Double($0)), latitude: Double($0), longitude: 0)
        }
        var queue = AccountScopedLocationIngestBuffer(accountID: "alice", points: points)
        var attempts: [[LocationPoint]] = []
        var acknowledged: [[LocationPoint]] = []
        var shouldFailSecondBatch = true

        do {
            try await LocationIngestBatchDrain.run(
                canContinue: { true },
                nextBatch: { queue.nextBatch() },
                send: { batch in
                    attempts.append(batch.points)
                    if shouldFailSecondBatch && attempts.count == 2 {
                        shouldFailSecondBatch = false
                        throw URLError(.networkConnectionLost)
                    }
                    acknowledged.append(batch.points)
                },
                acknowledge: { queue.acknowledge($0) }
            )
            XCTFail("The injected second-batch error should bubble up")
        } catch is URLError {
            // The first request is committed locally; the failed second request is not.
        }

        XCTAssertEqual(attempts.map { $0.first?.latitude }, [0, 100])
        XCTAssertEqual(acknowledged.map { $0.first?.latitude }, [0])
        XCTAssertEqual(queue.points.count, 150)
        XCTAssertEqual(queue.points.first?.latitude, 100)

        let retryStart = attempts.count
        try await LocationIngestBatchDrain.run(
            canContinue: { true },
            nextBatch: { queue.nextBatch() },
            send: { batch in
                attempts.append(batch.points)
                acknowledged.append(batch.points)
            },
            acknowledge: { queue.acknowledge($0) }
        )

        let retriedBatches = Array(attempts.dropFirst(retryStart))
        XCTAssertEqual(retriedBatches.map { $0.count }, [100, 50])
        XCTAssertEqual(retriedBatches.flatMap { $0 }.map(\.latitude), (100..<250).map(Double.init))
        XCTAssertEqual(acknowledged.flatMap { $0 }.map(\.latitude), (0..<250).map(Double.init))
        XCTAssertTrue(queue.points.isEmpty)
    }

    @MainActor
    func testDrainStopsAndDoesNotAcknowledgeWhenSharingIsRevokedDuringRequest() async throws {
        let now = Date()
        let points = (0..<120).map {
            LocationPoint(timestamp: now.addingTimeInterval(Double($0)), latitude: Double($0), longitude: 0)
        }
        var queue = AccountScopedLocationIngestBuffer(accountID: "alice", points: points)
        var canUpload = true
        var sent: [LocationIngestBatch] = []

        try await LocationIngestBatchDrain.run(
            canContinue: { canUpload },
            nextBatch: { queue.nextBatch() },
            send: { batch in
                sent.append(batch)
                canUpload = false
            },
            acknowledge: { queue.acknowledge($0) }
        )

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].points.count, 100)
        XCTAssertEqual(queue.points.count, 120, "A response completing after sharing stops cannot dequeue queued fixes")
        queue.clear()
        XCTAssertFalse(queue.acknowledge(sent[0]), "Clearing on Off invalidates an in-flight acknowledgement")
        XCTAssertTrue(queue.points.isEmpty)
    }
}

final class LookServiceTests: XCTestCase {
    @MainActor
    private func sealedPair() -> (DemoTrustService, UUID) {
        let service = DemoTrustService(displayName: "Sam")
        service.startPair(with: "Jordan")
        let jordan = service.members.first!.id
        service.setInboundForTesting(personID: jordan, PersonShareState(resting: .untilTheyLook))
        return (service, jordan)
    }

    @MainActor
    func testJoinIsOffBothWaysAndLookIsRefused() {
        let service = DemoTrustService(displayName: "Sam")
        service.startPair(with: "Jordan")
        let jordan = service.members.first!.id
        XCTAssertEqual(service.shareState(for: jordan).presentation(at: Date()), .off)
        XCTAssertFalse(service.isSharingLocation)
        XCTAssertThrowsError(try service.look(confirmed: true, subjectID: jordan)) { error in
            XCTAssertEqual(error as? LookError, .shareOff)
        }
        XCTAssertTrue(service.lookLog.isEmpty)
    }

    @MainActor
    func testLookRequiresConfirmReturnsOneSnapshotAndAppendsLog() throws {
        let (service, jordan) = sealedPair()

        XCTAssertThrowsError(try service.look(confirmed: false, subjectID: jordan)) { error in
            XCTAssertEqual(error as? LookError, .confirmationRequired)
        }
        XCTAssertTrue(service.lookLog.isEmpty)
        XCTAssertTrue(service.peekEscrow(for: jordan).isEmpty)

        let session = try service.look(confirmed: true, subjectID: jordan)
        XCTAssertEqual(session.event.viewerName, "Sam")
        XCTAssertEqual(session.event.subjectName, "Jordan")
        XCTAssertEqual(session.event.kind, .look)
        XCTAssertEqual(session.event.historyWindowHours, 0, "Sealed Look is one snapshot, not a trail")
        XCTAssertEqual(session.trail.count, 1)
        XCTAssertEqual(session.trail.first, session.live)
        XCTAssertEqual(service.lookLog.count, 1)

        // The subject's share stays sealed — an opened snapshot never flips them Available.
        XCTAssertTrue(service.circle.first { $0.id == jordan }!.isSealed)
        XCTAssertTrue(service.isLocationVisible(jordan))
    }

    @MainActor
    func testReceiptCopyIsPlain() throws {
        let (service, jordan) = sealedPair()
        _ = try service.look(confirmed: true, subjectID: jordan)
        XCTAssertEqual(service.lastReceipt?.title, "Sam looked at your location.")
        XCTAssertEqual(service.lastReceipt?.body, "One snapshot of your current place.")
    }

    @MainActor
    func testClosingASnapshotRequiresANewConfirmAndRevokeKeepsTheLog() throws {
        let (service, jordan) = sealedPair()
        _ = try service.look(confirmed: true, subjectID: jordan)
        service.closeLook(subjectID: jordan)
        XCTAssertNil(service.snapshot(for: jordan))

        _ = try service.look(confirmed: true, subjectID: jordan)
        XCTAssertEqual(service.lookLog.count, 2)

        service.revoke(personID: jordan)
        XCTAssertTrue(service.members.isEmpty)
        XCTAssertEqual(service.lookLog.filter { $0.kind == .look }.count, 2, "revoke keeps the looks")
        let removed = try XCTUnwrap(service.lookLog.last { $0.kind == .removed })
        XCTAssertEqual(removed.logLine(youID: service.you.id), "You removed Jordan.")
        XCTAssertEqual(removed.logKindLabel, TrustCopy.kindRemoved)
        XCTAssertThrowsError(try service.look(confirmed: true, subjectID: jordan)) { error in
            XCTAssertEqual(error as? LookError, .pairInactive)
        }
    }

    @MainActor
    func testViewNeedsAvailableLogsOnceAndLookIsRefused() throws {
        let (service, jordan) = sealedPair()
        XCTAssertThrowsError(try service.view(subjectID: jordan)) { error in
            XCTAssertEqual(error as? LookError, .viewRequiresAvailable)
        }

        service.setInboundForTesting(personID: jordan, PersonShareState(resting: .always))
        XCTAssertTrue(service.circle.first { $0.id == jordan }!.isAvailable)
        XCTAssertThrowsError(try service.look(confirmed: true, subjectID: jordan)) { error in
            XCTAssertEqual(error as? LookError, .lookRequiresSealed)
        }

        let first = try service.view(subjectID: jordan)
        XCTAssertEqual(first?.kind, .view)
        XCTAssertNil(try service.view(subjectID: jordan), "repeat views dedupe within the window")
        XCTAssertEqual(service.lookLog.filter { $0.kind == .view }.count, 1)
        XCTAssertNil(service.lastReceipt, "View never notifies")
    }

    @MainActor
    func testViewLogLinesReadBothDirections() {
        let you = UUID()
        let leo = UUID()
        let theyLooked = LookEvent(viewerID: leo, viewerName: "Leo", subjectID: you, subjectName: "Alex", at: Date(), kind: .look)
        let youViewed = LookEvent(viewerID: you, viewerName: "Alex", subjectID: leo, subjectName: "Leo", at: Date(), kind: .view)
        let youRemoved = LookEvent(viewerID: you, viewerName: "Alex", subjectID: leo, subjectName: "Leo", at: Date(), kind: .removed)
        let theyRemoved = LookEvent(viewerID: leo, viewerName: "Leo", subjectID: you, subjectName: "Alex", at: Date(), kind: .removed)
        XCTAssertEqual(theyLooked.logLine(youID: you), "Leo looked at you.")
        XCTAssertEqual(youViewed.logLine(youID: you), "You viewed Leo.")
        XCTAssertEqual(youRemoved.logLine(youID: you), "You removed Leo.")
        XCTAssertEqual(theyRemoved.logLine(youID: you), "Leo removed you.")
        XCTAssertEqual(theyRemoved.logKindLabel, "removed")
        XCTAssertNotEqual(theyRemoved.logKindLabel, TrustCopy.kindLook)
    }

    @MainActor
    func testOffStaysInTheListAndRevokeDropsThePair() {
        let service = DemoTrustService(displayName: "Sam")
        service.startPair(with: "Noah")
        let noah = service.members.first!.id
        service.setInboundForTesting(personID: noah, PersonShareState(resting: .off))
        XCTAssertEqual(service.circle.count, 1)
        XCTAssertTrue(service.circle[0].isNotSharingWithYou)
        XCTAssertFalse(service.lookLog.contains { $0.kind == .removed })

        service.revoke(personID: noah)
        XCTAssertTrue(service.circle.isEmpty)
        XCTAssertEqual(service.lookLog.filter { $0.kind == .removed }.count, 1)
        XCTAssertEqual(service.lookLog.last?.logLine(youID: service.you.id), "You removed Noah.")
    }

    @MainActor
    func testPresenceHasNoCoordinates() {
        let presence = PresenceSnapshot(lastActiveAt: Date(), batteryPercent: 64, isCharging: false, gotHomeAt: Date())
        let keys = Mirror(reflecting: presence).children.compactMap(\.label)
        XCTAssertFalse(keys.contains { $0.lowercased().contains("lat") })
        XCTAssertFalse(keys.contains { $0.lowercased().contains("lon") })
        XCTAssertFalse(keys.contains { $0.lowercased().contains("coord") })
        let home = HomePresenceSnapshot(state: .home, changedAt: Date())
        let homeKeys = Mirror(reflecting: home).children.compactMap(\.label)
        XCTAssertFalse(homeKeys.contains { $0.lowercased().contains("lat") })
    }

    @MainActor
    func testHiddenPresenceNeverReachesTheCircle() {
        let (service, jordan) = sealedPair()
        service.setPresenceForTesting(personID: jordan, .hidden)
        let row = service.circle.first { $0.id == jordan }!
        XCTAssertNil(row.homePresence)
        XCTAssertNil(row.visiblePresence)

        service.setPresenceForTesting(personID: jordan, .away)
        XCTAssertEqual(service.circle.first { $0.id == jordan }!.visiblePresence, .away)
        XCTAssertEqual(HomePresenceKind.triad, [.home, .away, .hidden])
    }

    @MainActor
    func testJoinInviteRequiresMatchingCodeAndStaysOff() {
        let service = DemoTrustService(displayName: "Sam")
        service.createInvite()
        XCTAssertThrowsError(try service.joinInvite(code: "NOPE")) { error in
            XCTAssertEqual(error as? PairingError, .invalidCode)
        }
        try? service.joinInvite(code: service.pendingInviteCode!)
        XCTAssertEqual(service.members.first?.displayName, "Jordan")
        XCTAssertNil(service.pendingInviteCode)
        XCTAssertEqual(service.shareState(for: service.members.first!.id).presentation(at: Date()), .off)
    }

    @MainActor
    func testFreeSeatsAreFiveAndAvailableModesArePlus() throws {
        let (service, jordan) = sealedPair()
        XCTAssertFalse(service.coverage.isCovered)
        XCTAssertEqual(service.coverage.trustedPeopleLimit, 5)
        XCTAssertEqual(service.coverage.lookLogRetentionDays, 30)
        XCTAssertFalse(service.coverage.canShareAvailable)

        // Look is never paywalled.
        _ = try service.look(confirmed: true, subjectID: jordan)

        XCTAssertThrowsError(try service.setAlways(personID: jordan)) { error in
            XCTAssertEqual(error as? CircleError, .proRequired)
        }
        XCTAssertThrowsError(try service.pauseSharing(personID: jordan, duration: .oneHour)) { error in
            XCTAssertEqual(error as? LookError, .shareOff)
        }
        service.setUntilTheyLook(personID: jordan)
        try service.pauseSharing(personID: jordan, duration: .oneHour)
        if case .paused(_, let revert) = service.shareState(for: jordan).presentation(at: Date()) {
            XCTAssertEqual(revert, .untilTheyLook)
        } else {
            XCTFail("pause is free and restores Sealed")
        }
        service.setUntilTheyLook(personID: jordan)
        XCTAssertEqual(service.shareState(for: jordan).presentation(at: Date()), .untilTheyLook)

        for index in 0..<4 {
            service.createInvite()
            try service.joinInvite(code: service.pendingInviteCode!, name: "Person \(index)")
        }
        service.createInvite()
        XCTAssertThrowsError(try service.joinInvite(code: service.pendingInviteCode!, name: "Sixth")) { error in
            XCTAssertEqual(error as? CircleError, .seatLimitReached)
        }

        service.setPro(enabled: true)
        XCTAssertTrue(service.coverage.isCovered)
        XCTAssertTrue(service.coverage.actingIsSponsor)
        XCTAssertEqual(service.coverage.trustedPeopleLimit, 20)
        XCTAssertEqual(service.coverage.banner, "Plus is on this account")
        try service.setAlways(personID: jordan)
        XCTAssertEqual(service.shareState(for: jordan).presentation(at: Date()), .always)
    }

    @MainActor
    func testServerCoverageValuesWin() {
        let coverage = CircleCoverage(isCovered: false, sponsorName: nil, actingIsSponsor: false, serverSeatLimit: 7, serverLookLogDays: 14)
        XCTAssertEqual(coverage.trustedPeopleLimit, 7)
        XCTAssertEqual(coverage.lookLogRetentionDays, 14)
        XCTAssertEqual(TrustCopy.plusOnThisAccount, "Plus is on this account")
        XCTAssertNil(CircleCoverage(isCovered: true, sponsorName: "Sam", actingIsSponsor: false).banner)
    }

    @MainActor
    func testViewLogRetention() throws {
        let (service, jordan) = sealedPair()
        XCTAssertEqual(CircleCoverage.freeLookLogDays, 30)
        XCTAssertFalse(service.coverage.canExportLookLog)

        let recent = LookEvent(viewerID: service.you.id, viewerName: "Sam", subjectID: jordan, subjectName: "Jordan", at: Date().addingTimeInterval(-10 * 86_400))
        let old = LookEvent(viewerID: service.you.id, viewerName: "Sam", subjectID: jordan, subjectName: "Jordan", at: Date().addingTimeInterval(-40 * 86_400))
        service.recordLookForTesting(recent)
        service.recordLookForTesting(old)
        XCTAssertEqual(service.visibleLookLog.map(\.id), [recent.id])
        XCTAssertEqual(service.retainedLookLogCount, 1)

        service.setPro(enabled: true)
        XCTAssertTrue(service.coverage.canExportLookLog)
        XCTAssertEqual(service.visibleLookLog.count, 2)
    }

    @MainActor
    func testPauseRestoresPreviousModeAndEncodesDurations() throws {
        let (service, alex) = sealedPair()
        service.setUntilTheyLook(personID: alex)
        try service.pauseSharing(personID: alex, duration: .oneHour)
        if case .paused(_, let revert) = service.shareState(for: alex).presentation(at: Date()) {
            XCTAssertEqual(revert, .untilTheyLook)
        } else {
            XCTFail("expected pause on Sealed")
        }
        XCTAssertFalse(service.isSharingLocation)

        service.setPro(enabled: true)
        try service.setAlways(personID: alex)
        try service.pauseSharing(personID: alex, duration: .eightHours)
        if case .paused(_, let revert) = service.shareState(for: alex).presentation(at: Date()) {
            XCTAssertEqual(revert, .always)
        } else {
            XCTFail("expected pause on Always")
        }

        XCTAssertEqual(PauseDuration.allCases.map(\.rawValue), ["1h", "8h", "1d", "2d", "3d"])
        XCTAssertEqual(TrustProductRules.pauseWireValue(.oneDay), "1d")
        XCTAssertEqual(TrustProductRules.pauseWireValue(.threeDays), "3d")
        XCTAssertEqual(TrustProductRules.historyWindowHours(viewerHasPlus: false), 24)
        XCTAssertEqual(TrustProductRules.historyWindowHours(viewerHasPlus: true), 30 * 24)
        XCTAssertEqual(TrustProductRules.peek(inbound: .untilTheyLook), .look)
        XCTAssertEqual(TrustProductRules.peek(inbound: .always), .view)
        XCTAssertEqual(TrustProductRules.peek(inbound: .off), .none)
        XCTAssertEqual(TrustProductRules.peek(inbound: .paused(ends: Date().addingTimeInterval(60), revertsTo: .always)), .none)
        XCTAssertTrue(TrustProductRules.rowOpensPerson())
        XCTAssertFalse(TrustProductRules.showsLivePin(viewerHasPlus: false, inbound: .always))
        XCTAssertTrue(TrustProductRules.showsLivePin(viewerHasPlus: true, inbound: .always))
        XCTAssertFalse(TrustProductRules.showsLivePin(viewerHasPlus: true, inbound: .untilTheyLook))
    }

    @MainActor
    func testLeanDemoMatchesDesignFixture() throws {
        let service = DemoTrustService()
        service.startLeanDemo()
        XCTAssertEqual(service.circle.count, 5, "the Free demo fills, but does not exceed, its five-person circle")
        XCTAssertFalse(service.coverage.isCovered, "the fixture account is on Free")

        func row(_ name: String) -> TrustedPerson {
            service.circle.first { $0.person.displayName == name }!
        }
        XCTAssertTrue(row("Maya Chen").isSealed)
        XCTAssertEqual(row("Maya Chen").visiblePresence, .home)
        XCTAssertTrue(row("Leo Park").isAvailable)
        XCTAssertNotNil(row("Leo Park").livePoint)
        XCTAssertEqual(row("Leo Park").visiblePresence, .away)
        XCTAssertTrue(row("Jules Morgan").isPaused, "Pause is not a live share")
        XCTAssertFalse(row("Jules Morgan").isAvailable)
        XCTAssertTrue(row("Eli Brooks").isAvailable)
        XCTAssertNil(row("Eli Brooks").visiblePresence, "Hidden presence, location Available")
        XCTAssertEqual(row("Noah Wilson").inboundPresentation, .off)
        XCTAssertEqual(row("Noah Wilson").visiblePresence, .home, "Off does not remove someone or hide their presence")
        XCTAssertNil(row("Maya Chen").livePoint, "sealed rows never carry coordinates")

        XCTAssertEqual(service.shareState(for: row("Maya Chen").id).presentation(at: Date()), .untilTheyLook)
        XCTAssertEqual(service.shareState(for: row("Leo Park").id).presentation(at: Date()), .untilTheyLook,
                       "Alex can share Sealed on Free while Leo's inbound Always share remains independent")
        XCTAssertEqual(service.shareState(for: row("Noah Wilson").id).presentation(at: Date()), .off)

        XCTAssertEqual(service.visibleMapPins().count, 0, "Free does not get live pins")
        service.setPro(enabled: true)
        XCTAssertEqual(service.visibleMapPins().count, 2, "Only Always people, and only with Plus")
        _ = try service.look(confirmed: true, subjectID: row("Maya Chen").id)
        XCTAssertEqual(service.visibleMapPins().count, 2, "A Look snapshot is not a live pin")
        XCTAssertEqual(service.visibleLookLog.count, 3)
        XCTAssertEqual(service.visibleLookLog.first?.logLine(youID: service.you.id), "You looked at Maya Chen.")
    }
}

final class LocationSharingTests: XCTestCase {
    func testOnlyNonOffOutboundSharesTrack() {
        XCTAssertFalse(OutboundLocationSharing.isActive(shares: []))
        XCTAssertFalse(OutboundLocationSharing.isActive(shares: [PersonShareState(resting: .off)]))
        XCTAssertTrue(OutboundLocationSharing.isActive(shares: [PersonShareState(resting: .off), PersonShareState(resting: .untilTheyLook)]))
        let paused = PersonShareState(resting: .paused, pauseUntil: Date().addingTimeInterval(600), restoresTo: .untilTheyLook)
        XCTAssertFalse(OutboundLocationSharing.isActive(shares: [paused]))
        let expiredPause = PersonShareState(resting: .paused, pauseUntil: Date().addingTimeInterval(-60), restoresTo: .untilTheyLook)
        XCTAssertTrue(OutboundLocationSharing.isActive(shares: [expiredPause]))
    }

    func testTierIsOffThenSealedThenAvailable() {
        let now = Date()
        XCTAssertEqual(OutboundLocationSharing.tier(shares: [], at: now), .off)
        XCTAssertEqual(OutboundLocationSharing.tier(shares: [PersonShareState(resting: .off)], at: now), .off)
        XCTAssertEqual(OutboundLocationSharing.tier(shares: [PersonShareState(resting: .untilTheyLook)], at: now), .sealed)
        XCTAssertEqual(
            OutboundLocationSharing.tier(shares: [PersonShareState(resting: .untilTheyLook), PersonShareState(resting: .off)], at: now),
            .sealed
        )
        XCTAssertEqual(OutboundLocationSharing.tier(shares: [PersonShareState(resting: .always)], at: now), .available)
        let paused = PersonShareState(resting: .paused, pauseUntil: now.addingTimeInterval(600), restoresTo: .untilTheyLook)
        XCTAssertEqual(OutboundLocationSharing.tier(shares: [paused], at: now), .off)
        let expiredPause = PersonShareState(resting: .paused, pauseUntil: now.addingTimeInterval(-60), restoresTo: .always)
        XCTAssertEqual(OutboundLocationSharing.tier(shares: [expiredPause], at: now), .available)
    }

    @MainActor
    func testInboundPresentationIsExposedOnTheRow() {
        let service = DemoTrustService(displayName: "Sam")
        service.startPair(with: "Jordan")
        let jordan = service.members.first!.id
        XCTAssertEqual(service.circle.first?.inboundPresentation, .off, "join is Off both ways")
        XCTAssertTrue(service.circle.first!.isNotSharingWithYou)
        XCTAssertEqual(service.locationTier, .off)

        service.setInboundForTesting(personID: jordan, PersonShareState(resting: .untilTheyLook))
        XCTAssertEqual(service.circle.first?.inboundPresentation, .untilTheyLook)
        XCTAssertFalse(service.circle.first!.isNotSharingWithYou)

        // Unknown (pre-`inboundShare` server) never reads as "not sharing".
        let unknown = TrustedPerson(person: Person(displayName: "Old"), presence: .sealed, share: PersonShareState(), inboundLive: false)
        XCTAssertNil(unknown.inboundPresentation)
        XCTAssertFalse(unknown.isNotSharingWithYou)

        service.setUntilTheyLook(personID: jordan)
        XCTAssertEqual(service.locationTier, .sealed)
        service.setPro(enabled: true)
        try? service.setAlways(personID: jordan)
        XCTAssertEqual(service.locationTier, .available)
    }

    func testLocationPurposeStringsAreEscrowVoice() {
        XCTAssertTrue(TrustCopy.locationWhenInUsePurpose.contains("while the app is open"))
        XCTAssertTrue(TrustCopy.locationWhenInUsePurpose.contains("does not sell"))
        XCTAssertFalse(TrustCopy.locationWhenInUsePurpose.lowercased().contains("emergency"))
        XCTAssertFalse(TrustCopy.locationWhenInUsePurpose.lowercased().contains("adult"))
        XCTAssertTrue(TrustCopy.locationAlwaysPurpose.contains("Look"))
        XCTAssertFalse(TrustCopy.locationAlwaysPurpose.lowercased().contains("escrow"))
        XCTAssertTrue(TrustCopy.locationAlwaysPurpose.contains("background"))
        XCTAssertTrue(TrustCopy.locationAlwaysPurpose.contains("does not sell"))
        XCTAssertFalse(TrustCopy.locationAlwaysPurpose.lowercased().contains("emergency"))
        XCTAssertFalse(TrustCopy.locationAlwaysPurpose.lowercased().contains("adult"))
        XCTAssertFalse(TrustCopy.locationPrecisePurpose.lowercased().contains("adult"))
        XCTAssertTrue(TrustCopy.locationPrecisePurpose.contains("precise"))
    }
}

final class TrustHandleTests: XCTestCase {
    func testNormalizesAtPrefixAndCase() {
        if case .valid(let handle) = TrustHandle.status(of: "@Jordan") {
            XCTAssertEqual(handle, "jordan")
        } else {
            XCTFail("jordan should be valid")
        }
        XCTAssertEqual(TrustHandle.normalize("@Jordan"), "jordan")
        XCTAssertEqual(TrustHandle.sanitizeDraft("Jo-rdan!"), "jordan")
    }

    func testRejectsShortReservedAndLeadingDigit() {
        XCTAssertEqual(TrustHandle.status(of: "ab"), .invalid)
        XCTAssertEqual(TrustHandle.status(of: "1jordan"), .invalid)
        XCTAssertEqual(TrustHandle.status(of: "admin"), .reserved)
        XCTAssertEqual(TrustHandle.status(of: "you"), .reserved)
        XCTAssertEqual(TrustHandle.status(of: "trust"), .reserved)
    }

    func testSuggestsFromDisplayName() {
        XCTAssertEqual(TrustHandle.suggest(from: "Juan Quirino"), "juanquirino")
        XCTAssertEqual(TrustHandle.suggest(from: "You"), nil)
        XCTAssertEqual(TrustHandle.suggest(from: "Jordan"), "jordan")
    }
}

final class LocationFreshnessTests: XCTestCase {
    func testRecentYesterdayMissingAndTimeProgression() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(LocationFreshness.status(timestamp: now.addingTimeInterval(-60), now: now), .recent)
        XCTAssertEqual(LocationFreshness.status(timestamp: now.addingTimeInterval(-86_400), now: now), .stale)
        XCTAssertEqual(LocationFreshness.status(timestamp: nil, now: now), .unavailable)

        let pointTime = now.addingTimeInterval(-240)
        XCTAssertEqual(LocationFreshness.status(timestamp: pointTime, now: now), .recent)
        XCTAssertEqual(LocationFreshness.status(timestamp: pointTime, now: now.addingTimeInterval(61)), .stale)
    }

    func testStaleCueBeginsAfterFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(LocationFreshness.status(timestamp: now.addingTimeInterval(-300), now: now), .recent)
        XCTAssertEqual(LocationFreshness.status(timestamp: now.addingTimeInterval(-301), now: now), .stale)
    }

    func testMissingAlwaysPointDistinguishesUnavailableFromPlusAccessAndKeepsPresence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(
            TrustCopy.availableLocationStatus(timestamp: nil, now: now, viewerHasPlus: true),
            TrustCopy.locationUnavailable
        )
        let freeViewer = TrustCopy.availableLocationStatus(timestamp: nil, now: now, viewerHasPlus: false, presence: "Home")
        XCTAssertTrue(freeViewer.contains("Home"))
        XCTAssertTrue(freeViewer.contains(TrustCopy.plusLockHint))
        XCTAssertFalse(freeViewer.contains(TrustCopy.locationUnavailable))
    }
}

final class TrustAccountOperationTests: XCTestCase {
    func testAgeGateStopCompletionIsDiscardedAfterAccountSwitch() {
        let pending = TrustAccountOperation(token: "account-a", generation: 10)
        XCTAssertTrue(pending.matches(token: "account-a", generation: 10))
        XCTAssertFalse(pending.matches(token: "account-b", generation: 11))
        XCTAssertFalse(pending.matches(token: "account-a", generation: 11))
    }
}
