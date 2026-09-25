import Foundation
import TrustCore
import XCTest

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
