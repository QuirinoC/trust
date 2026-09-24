import Foundation

/// Offline circle for DEBUG "See the app", App Store screenshots, and domain tests.
/// Mirrors the server rules the app relies on: join is Off both ways, Sealed needs a
/// confirmed Look and returns one snapshot, Available is viewed without a sheet and every
/// view is logged, Hidden presence never reaches the circle, Always / For a while are Plus.
/// The running app never uses this as its backend.
@MainActor
public final class DemoTrustService: ObservableObject {
    @Published public private(set) var you: Person
    @Published public private(set) var members: [Person] = []
    @Published public private(set) var lookLog: [LookEvent] = []
    /// Your open Look snapshot (one per subject, most recent wins).
    @Published public private(set) var snapshots: [UUID: LookSession] = [:]
    @Published public private(set) var lastReceipt: LookReceipt?
    @Published public private(set) var pendingInviteCode: String?
    @Published public private(set) var myPresence: HomePresenceKind = .home

    private var vaults: [UUID: EscrowVault] = [:]
    /// You → them.
    private var outbound: [UUID: PersonShareState] = [:]
    /// Them → you.
    private var inbound: [UUID: PersonShareState] = [:]
    private var presenceByPerson: [UUID: HomePresenceKind] = [:]
    private var placeLabels: [UUID: String] = [:]
    private var tickPhase: Double = 0
    private let clock: TrustClock

    public static let viewDedupeWindow: TimeInterval = 30 * 60

    public init(clock: TrustClock = SystemClock(), displayName: String = "Alex") {
        self.clock = clock
        you = Person(displayName: displayName)
    }

    // MARK: Snapshot

    public var coverage: CircleCoverage {
        let sponsor = you.hasPro ? you : nil
        return CircleCoverage(
            isCovered: sponsor != nil,
            sponsorName: sponsor?.displayName,
            actingIsSponsor: sponsor?.id == you.id
        )
    }

    public var circle: [TrustedPerson] {
        expireTimedShares()
        let now = clock.now()
        return members.map { person in
            let inboundPresentation = (inbound[person.id] ?? PersonShareState()).presentation(at: now)
            let available = inboundPresentation.isAvailable
            let presence = presenceByPerson[person.id] ?? .unknown
            let visiblePresence: HomePresenceSnapshot? = presence == .hidden
                ? nil
                : HomePresenceSnapshot(state: presence, changedAt: now.addingTimeInterval(-1800), placeLabel: placeLabels[person.id])
            return TrustedPerson(
                person: person,
                presence: PresenceSnapshot(lastActiveAt: now.addingTimeInterval(-600), batteryPercent: 70, isCharging: false),
                share: outbound[person.id] ?? PersonShareState(),
                inboundLive: available,
                livePoint: available ? vault(for: person.id).latest(now: now) : nil,
                outboundPresenceGranted: true,
                inboundPresenceGranted: true,
                homePresence: visiblePresence,
                promise: nil,
                inboundPresentation: inboundPresentation,
                locationHistory: inboundPresentation.acceptsLocation ? Self.visits(
                    place: placeLabels[person.id] ?? TrustCopy.location,
                    now: now,
                    origin: vault(for: person.id).latest(now: now)
                ) : []
            )
        }
    }

    public var visibleLookLog: [LookEvent] {
        let cutoff = clock.now().addingTimeInterval(-TimeInterval(coverage.lookLogRetentionDays * 86_400))
        return lookLog.filter { $0.at >= cutoff }.sorted { $0.at > $1.at }
    }

    public var retainedLookLogCount: Int { max(0, lookLog.count - visibleLookLog.count) }

    public var trustedCount: Int { members.count }

    public func makeCircleSnapshot() -> (
        you: Person,
        members: [TrustedPerson],
        coverage: CircleCoverage,
        invite: String?,
        log: [LookEvent],
        retained: Int,
        presence: HomePresenceKind
    ) {
        expireTimedShares()
        tickSimulator()
        return (you, circle, coverage, pendingInviteCode, visibleLookLog, retainedLookLogCount, myPresence)
    }

    // MARK: Fixtures

    /// Nine people. Inbound — Leo and Eli Always, Jules paused (restores to Sealed), Noah Off
    /// (chose off, not removed), everyone else Sealed. Inês, Eli, Noah Hidden. Outbound — Maya
    /// Sealed, Leo Always, Jules Sealed, the rest Off. You are on Free.
    public func startLeanDemo() {
        let now = clock.now()
        you = Person(displayName: "Alex Laurent", hasPro: false, onboardingComplete: true, handle: "alex")
        members = []
        vaults = [:]
        outbound = [:]
        inbound = [:]
        presenceByPerson = [:]
        placeLabels = [:]
        lookLog = []
        snapshots = [:]
        lastReceipt = nil
        pendingInviteCode = nil
        myPresence = .home

        let maya = add("Maya Chen", presence: .home, place: "Inner Sunset", origin: LocationTrail.DemoCity.missionSF.point(at: now), inbound: .untilTheyLook, outbound: .untilTheyLook, now: now)
        let leo = add("Leo Park", presence: .away, place: "Capitol Hill", origin: LocationTrail.DemoCity.capitolHillSeattle.point(at: now), inbound: .always, outbound: .always, now: now)
        add("Inês Costa", presence: .hidden, place: "Príncipe Real", origin: LocationPoint(timestamp: now, latitude: 38.7169, longitude: -9.1478), inbound: .untilTheyLook, outbound: .off, now: now)
        let jules = add("Jules Morgan", presence: .away, place: "Fort Greene", origin: LocationTrail.DemoCity.brooklyn.point(at: now), inbound: .untilTheyLook, outbound: .untilTheyLook, now: now)
        inbound[jules.id] = PersonShareState(
            resting: .paused,
            pauseUntil: now.addingTimeInterval(47 * 60),
            restoresTo: .untilTheyLook
        )
        add("Sam Rivera", presence: .home, place: "Hyde Park", origin: LocationTrail.DemoCity.austin.point(at: now), inbound: .untilTheyLook, outbound: .off, now: now)
        add("Eli Brooks", presence: .hidden, place: "Hackney", origin: LocationPoint(timestamp: now, latitude: 51.5450, longitude: -0.0553), inbound: .always, outbound: .off, now: now)
        add("Ren Tanaka", presence: .home, place: "Shimokitazawa", origin: LocationPoint(timestamp: now, latitude: 35.6613, longitude: 139.6681), inbound: .untilTheyLook, outbound: .off, now: now)
        add("Sofía López", presence: .away, place: "Condesa", origin: LocationPoint(timestamp: now, latitude: 19.4116, longitude: -99.1747), inbound: .untilTheyLook, outbound: .off, now: now)
        add("Noah Wilson", presence: .hidden, place: "Surry Hills", origin: LocationPoint(timestamp: now, latitude: -33.8845, longitude: 151.2110), inbound: .off, outbound: .off, now: now)

        // Prior activity so the view log is not blank: Leo looked at you yesterday; you viewed Leo.
        lookLog.append(LookEvent(
            viewerID: leo.id, viewerName: leo.displayName, subjectID: you.id, subjectName: you.displayName,
            at: now.addingTimeInterval(-26 * 3600), kind: .look
        ))
        lookLog.append(LookEvent(
            viewerID: you.id, viewerName: you.displayName, subjectID: maya.id, subjectName: maya.displayName,
            at: now.addingTimeInterval(-3 * 86_400), kind: .look
        ))
        seedYou(now: now)
    }

    /// Minimal two-person circle for tests: one member, Off both ways (join default).
    public func startPair(with name: String = "Jordan") {
        let now = clock.now()
        members = []
        vaults = [:]
        outbound = [:]
        inbound = [:]
        presenceByPerson = [:]
        placeLabels = [:]
        lookLog = []
        snapshots = [:]
        lastReceipt = nil
        pendingInviteCode = nil
        add(name, presence: .home, place: "Home", origin: LocationTrail.home, inbound: .off, outbound: .off, now: now)
        seedYou(now: now)
    }

    @discardableResult
    private func add(
        _ name: String,
        presence: HomePresenceKind,
        place: String,
        origin: LocationPoint,
        inbound inboundMode: ShareRestingMode,
        outbound outboundMode: ShareRestingMode,
        now: Date
    ) -> Person {
        let person = Person(displayName: name)
        members.append(person)
        presenceByPerson[person.id] = presence
        placeLabels[person.id] = place
        inbound[person.id] = PersonShareState(resting: inboundMode)
        outbound[person.id] = PersonShareState(resting: outboundMode)
        let vault = EscrowVault()
        for point in LocationTrail.seed(around: origin, now: now, hours: 3, intervalMinutes: 10, drift: 0.0004) {
            vault.ingest(point)
        }
        vaults[person.id] = vault
        return person
    }

    /// A few named stops while they are sharing. The last one sits outside the free
    /// window so Plus can keep a longer list; free still gets the recent places.
    private static func visits(place: String, now: Date, origin: LocationPoint?) -> [LocationVisit] {
        let names = extraPlaces(for: place)
        let stops: [(String, TimeInterval)] = [
            (names[0], 0),
            (names.count > 1 ? names[1] : place, -40 * 60),
            (names.count > 2 ? names[2] : place, -90 * 60),
            (place, -36 * 3600)
        ]
        return stops.map { name, offset in
            LocationVisit(label: name, at: now.addingTimeInterval(offset), point: origin)
        }
    }

    private static func extraPlaces(for place: String) -> [String] {
        switch place {
        case "Capitol Hill": return ["Capitol Hill", "Broadway", "Volunteer Park"]
        case "Inner Sunset": return ["Inner Sunset", "Irving", "Golden Gate Park"]
        case "Fort Greene": return ["Fort Greene", "Dekalb", "Brooklyn"]
        case "Hyde Park": return ["Hyde Park", "East Austin", "Downtown"]
        case "Príncipe Real": return ["Príncipe Real", "Bairro Alto", "Chiado"]
        case "Hackney": return ["Hackney", "London Fields", "Dalston"]
        case "Shimokitazawa": return ["Shimokitazawa", "Shibuya", "Yoyogi"]
        case "Condesa": return ["Condesa", "Roma Norte", "Juárez"]
        default: return [place, place, place]
        }
    }

    private func seedYou(now: Date) {
        let vault = EscrowVault()
        for point in LocationTrail.seed(around: LocationTrail.home, now: now, hours: 3, intervalMinutes: 10) {
            vault.ingest(point)
        }
        vaults[you.id] = vault
    }

    // MARK: Invite

    public func createInvite() {
        pendingInviteCode = Self.makeInviteCode()
    }

    /// Joining adds a fictional person, Off both ways. Invite ≠ permission.
    public func joinInvite(code: String, name: String = "Jordan") throws {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let pendingInviteCode, pendingInviteCode == normalized else { throw PairingError.invalidCode }
        guard members.count < coverage.trustedPeopleLimit else { throw CircleError.seatLimitReached }
        add(name, presence: .unknown, place: "Home", origin: LocationTrail.home, inbound: .off, outbound: .off, now: clock.now())
        self.pendingInviteCode = nil
    }

    public func setPro(enabled: Bool) {
        you.hasPro = enabled
    }

    public func setInboundForTesting(personID: UUID, _ state: PersonShareState) {
        inbound[personID] = state
    }

    public func setPresenceForTesting(personID: UUID, _ presence: HomePresenceKind) {
        presenceByPerson[personID] = presence
    }

    public func recordLookForTesting(_ event: LookEvent) {
        lookLog.append(event)
    }

    // MARK: Outbound

    public func shareState(for personID: UUID) -> PersonShareState {
        expireTimedShares()
        return outbound[personID] ?? PersonShareState()
    }

    public func setOff(personID: UUID) {
        outbound[personID] = PersonShareState(resting: .off)
    }

    public func setUntilTheyLook(personID: UUID) {
        outbound[personID] = PersonShareState(resting: .untilTheyLook)
    }

    public func setAlways(personID: UUID) throws {
        guard coverage.canShareAvailable else { throw CircleError.proRequired }
        outbound[personID] = PersonShareState(resting: .always)
    }

    /// Pause is free. It restores the previous Sealed or Always mode when the timer ends.
    public func pauseSharing(personID: UUID, duration: PauseDuration) throws {
        expireTimedShares()
        let current = outbound[personID] ?? PersonShareState()
        let restores: ShareRestingMode
        switch current.presentation(at: clock.now()) {
        case .always:
            restores = .always
        case .untilTheyLook:
            restores = .untilTheyLook
        case .paused(_, let reverts):
            restores = reverts
        case .off:
            throw LookError.shareOff
        }
        outbound[personID] = PersonShareState(
            resting: .paused,
            pauseUntil: duration.endDate(from: clock.now()),
            restoresTo: restores
        )
    }

    public func stopAll() {
        for id in outbound.keys {
            outbound[id] = PersonShareState(resting: .off)
        }
    }

    public var isSharingLocation: Bool {
        OutboundLocationSharing.isActive(shares: Array(outbound.values), at: clock.now())
    }

    public var locationTier: LocationSharingTier {
        OutboundLocationSharing.tier(shares: Array(outbound.values), at: clock.now())
    }

    public func expireTimedShares() {
        let now = clock.now()
        func restore(_ state: PersonShareState) -> PersonShareState? {
            guard state.resting == .paused, let until = state.pauseUntil, until <= now else { return nil }
            let mode: ShareRestingMode = state.restoresTo == .always ? .always : .untilTheyLook
            return PersonShareState(resting: mode)
        }
        for (id, state) in outbound {
            if let next = restore(state) { outbound[id] = next }
        }
        for (id, state) in inbound {
            if let next = restore(state) { inbound[id] = next }
        }
    }

    // MARK: Presence

    public func setMyPresence(_ presence: HomePresenceKind) {
        myPresence = presence
    }

    // MARK: Look (Sealed) & View (Available)

    /// Sealed only. Returns one snapshot — the latest point — and records a `look`.
    /// The subject's share stays sealed afterwards.
    public func look(confirmed: Bool, subjectID: UUID) throws -> LookSession {
        guard confirmed else { throw LookError.confirmationRequired }
        guard let subject = members.first(where: { $0.id == subjectID }) else { throw LookError.pairInactive }
        expireTimedShares()
        let now = clock.now()
        let presentation = (inbound[subject.id] ?? PersonShareState()).presentation(at: now)
        if presentation.isOff || presentation.isPaused { throw LookError.shareOff }
        if presentation.isAvailable { throw LookError.lookRequiresSealed }
        guard let live = vault(for: subject.id).latest(now: now) else { throw LookError.noPartner }
        let event = LookEvent(
            viewerID: you.id, viewerName: you.displayName,
            subjectID: subject.id, subjectName: subject.displayName,
            at: now, historyWindowHours: 0, includedLive: true, kind: .look
        )
        lookLog.append(event)
        let session = LookSession(id: event.id, event: event, live: live, trail: [live])
        snapshots[subject.id] = session
        lastReceipt = LookReceipt(
            title: TrustCopy.receiptTitle(viewer: you.displayName),
            body: TrustCopy.receiptBody,
            at: now
        )
        return session
    }

    /// Available only. No sheet, no push; logged unless the same person was viewed within the
    /// dedupe window. Returns the new event, or nil when deduped.
    public func view(subjectID: UUID) throws -> LookEvent? {
        guard let subject = members.first(where: { $0.id == subjectID }) else { throw LookError.pairInactive }
        expireTimedShares()
        let now = clock.now()
        guard (inbound[subject.id] ?? PersonShareState()).presentation(at: now).isAvailable else {
            throw LookError.viewRequiresAvailable
        }
        let recent = lookLog.contains {
            $0.kind == .view && $0.viewerID == you.id && $0.subjectID == subject.id
                && now.timeIntervalSince($0.at) < Self.viewDedupeWindow
        }
        if recent { return nil }
        let event = LookEvent(
            viewerID: you.id, viewerName: you.displayName,
            subjectID: subject.id, subjectName: subject.displayName,
            at: now, historyWindowHours: 0, includedLive: true, kind: .view
        )
        lookLog.append(event)
        return event
    }

    public func closeLook(subjectID: UUID? = nil) {
        if let subjectID {
            snapshots[subjectID] = nil
        } else {
            snapshots = [:]
        }
    }

    public func snapshot(for personID: UUID) -> LookSession? { snapshots[personID] }

    public func isLocationVisible(_ personID: UUID) -> Bool {
        (inbound[personID]?.presentation(at: clock.now()).isAvailable ?? false) || snapshots[personID] != nil
    }

    /// Live point for someone Available, or their opened snapshot. Never a sealed peek.
    public func visiblePoint(for personID: UUID) -> LocationPoint? {
        let now = clock.now()
        if inbound[personID]?.presentation(at: now).isAvailable == true {
            return vault(for: personID).latest(now: now)
        }
        return snapshots[personID]?.live
    }

    public func visibleMapPins() -> [(id: UUID, name: String, point: LocationPoint, live: Bool)] {
        guard coverage.isCovered else { return [] }
        return circle.compactMap { member in
            guard member.isAvailable, let point = member.livePoint else { return nil }
            return (member.id, member.person.displayName, point, true)
        }
    }

    public func revoke(personID: UUID) {
        let name = members.first { $0.id == personID }?.displayName ?? "Someone"
        lookLog.append(LookEvent(
            viewerID: you.id,
            viewerName: you.displayName,
            subjectID: personID,
            subjectName: name,
            at: clock.now(),
            historyWindowHours: 0,
            includedLive: false,
            kind: .removed
        ))
        members.removeAll { $0.id == personID }
        vaults[personID] = nil
        outbound[personID] = nil
        inbound[personID] = nil
        presenceByPerson[personID] = nil
        placeLabels[personID] = nil
        snapshots[personID] = nil
    }


    /// Free: 24h trail. Plus: 30 days. Requires an open Look session.
    public func extendLook(subjectID: UUID) throws -> LookSession {
        guard let open = snapshots[subjectID] else { throw LookError.pairInactive }
        let now = clock.now()
        let hours = coverage.historyHours
        let trail = vault(for: subjectID).unlock(now: now, window: TimeInterval(hours * 3600))
        guard let live = trail.last ?? vault(for: subjectID).latest(now: now, window: 3 * 3600) else {
            throw LookError.noPartner
        }
        var event = open.event
        event.historyWindowHours = hours
        let session = LookSession(id: open.id, event: event, live: live, trail: trail.isEmpty ? [live] : trail)
        snapshots[subjectID] = session
        if let index = lookLog.firstIndex(where: { $0.id == event.id }) {
            lookLog[index] = event
        }
        return session
    }

    public func peekEscrow(for personID: UUID) -> [LocationPoint] {
        vault(for: personID).peekPlaintext()
    }

    // MARK: Simulator feed

    public func tickSimulator() {
        let now = clock.now()
        tickPhase += 0.35
        var phase = tickPhase
        for id in [you.id] + members.map(\.id) {
            let vault = vault(for: id)
            let last = vault.latest(now: now) ?? LocationTrail.home
            vault.ingest(LocationTrail.step(last, at: now, phase: phase))
            phase += 0.8
        }
        expireTimedShares()
    }

    private func vault(for personID: UUID) -> EscrowVault {
        if let existing = vaults[personID] { return existing }
        let created = EscrowVault()
        vaults[personID] = created
        return created
    }

    private static func makeInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
