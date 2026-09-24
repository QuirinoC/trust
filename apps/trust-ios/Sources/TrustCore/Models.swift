import Foundation

public protocol TrustClock: Sendable {
    func now() -> Date
}

public struct SystemClock: TrustClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct Person: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var displayName: String
    public var hasPro: Bool
    public var onboardingComplete: Bool
    public var phoneVerified: Bool
    public var handle: String?

    public var identity: String {
        if let handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return displayName
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        hasPro: Bool = false,
        onboardingComplete: Bool = true,
        phoneVerified: Bool = false,
        handle: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.hasPro = hasPro
        self.onboardingComplete = onboardingComplete
        self.phoneVerified = phoneVerified
        self.handle = handle
    }
}

public enum PairStatus: String, Codable, Sendable {
    case pending
    case active
    case revoked
}

public struct TrustPair: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var inviteCode: String
    public var status: PairStatus
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        inviteCode: String,
        status: PairStatus,
        createdAt: Date
    ) {
        self.id = id
        self.inviteCode = inviteCode
        self.status = status
        self.createdAt = createdAt
    }
}

/// Presence without coordinates. Home UI must never derive a map from this.
public struct PresenceSnapshot: Equatable, Codable, Sendable {
    public var lastActiveAt: Date
    public var batteryPercent: Int
    public var isCharging: Bool
    public var gotHomeAt: Date?
    public var checkedInAt: Date?

    public static let sealed = PresenceSnapshot(
        lastActiveAt: .distantPast,
        batteryPercent: 0,
        isCharging: false
    )

    public init(
        lastActiveAt: Date,
        batteryPercent: Int,
        isCharging: Bool,
        gotHomeAt: Date? = nil,
        checkedInAt: Date? = nil
    ) {
        self.lastActiveAt = lastActiveAt
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.gotHomeAt = gotHomeAt
        self.checkedInAt = checkedInAt
    }
}

/// Global, manual presence triad. `hidden` is deliberate — the circle sees no signal at all.
/// `unknown` is "no signal yet". Neither carries coordinates.
public enum HomePresenceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case unknown
    case home
    case away
    case hidden

    /// The three the user picks from on You. `unknown` is server-only.
    public static let triad: [HomePresenceKind] = [.home, .away, .hidden]

    public var label: String {
        switch self {
        case .home: return TrustCopy.presenceHome
        case .away: return TrustCopy.presenceAway
        case .hidden: return TrustCopy.presenceHidden
        case .unknown: return TrustCopy.presenceUnknown
        }
    }
}

public struct HomePresenceSnapshot: Equatable, Codable, Sendable {
    public var state: HomePresenceKind
    public var changedAt: Date
    public var placeLabel: String?

    public init(state: HomePresenceKind, changedAt: Date, placeLabel: String? = nil) {
        self.state = state
        self.changedAt = changedAt
        self.placeLabel = placeLabel
    }
}

public enum PromiseKind: String, Codable, Sendable, Equatable {
    case active
    case resolved
    case overdue
    case noSignal = "no_signal"
}

public struct PromiseSnapshot: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var subjectID: UUID
    public var trusteeID: UUID
    public var placeLabel: String
    public var deadlineAt: Date
    public var status: PromiseKind
    public var resolvedAt: Date?
    public var youAreSubject: Bool

    public init(
        id: UUID,
        subjectID: UUID,
        trusteeID: UUID,
        placeLabel: String,
        deadlineAt: Date,
        status: PromiseKind,
        resolvedAt: Date? = nil,
        youAreSubject: Bool
    ) {
        self.id = id
        self.subjectID = subjectID
        self.trusteeID = trusteeID
        self.placeLabel = placeLabel
        self.deadlineAt = deadlineAt
        self.status = status
        self.resolvedAt = resolvedAt
        self.youAreSubject = youAreSubject
    }
}

/// One stop on a person's location history. Newest first on the person screen.
public struct LocationVisit: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var at: Date
    public var point: LocationPoint?

    public init(id: UUID = UUID(), label: String, at: Date, point: LocationPoint? = nil) {
        self.id = id
        self.label = label
        self.at = at
        self.point = point
    }
}

public struct LocationPoint: Equatable, Codable, Sendable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double

    public init(timestamp: Date, latitude: Double, longitude: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// `look` — Sealed: notify-first confirm, one snapshot, receipt push.
/// `view` — Available: no sheet, logged, no push.
public enum LookKind: String, Codable, Sendable, Equatable {
    case look
    case view
    case removed
}

public struct LookEvent: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var viewerID: UUID
    public var viewerName: String
    public var subjectID: UUID
    public var subjectName: String
    public var at: Date
    public var historyWindowHours: Int
    public var includedLive: Bool
    public var kind: LookKind

    public init(
        id: UUID = UUID(),
        viewerID: UUID,
        viewerName: String,
        subjectID: UUID,
        subjectName: String,
        at: Date,
        historyWindowHours: Int = 0,
        includedLive: Bool = true,
        kind: LookKind = .look
    ) {
        self.id = id
        self.viewerID = viewerID
        self.viewerName = viewerName
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.at = at
        self.historyWindowHours = historyWindowHours
        self.includedLive = includedLive
        self.kind = kind
    }

    /// View log is bidirectional; this is the row copy from `you`'s point of view.
    public func logLine(youID: UUID) -> String {
        let youViewed = viewerID == youID
        switch (kind, youViewed) {
        case (.look, true): return TrustCopy.logYouLooked(name: subjectName)
        case (.look, false): return TrustCopy.logTheyLooked(name: viewerName)
        case (.view, true): return TrustCopy.logYouViewed(name: subjectName)
        case (.view, false): return TrustCopy.logTheyViewed(name: viewerName)
        case (.removed, true): return TrustCopy.logYouRemoved(name: subjectName)
        case (.removed, false): return TrustCopy.logTheyRemoved(name: viewerName)
        }
    }

    /// Log subtitle. Removed is not a Look and not a View.
    public var logKindLabel: String {
        switch kind {
        case .look: return TrustCopy.kindLook
        case .view: return TrustCopy.kindView
        case .removed: return TrustCopy.kindRemoved
        }
    }
}

public struct LookSession: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var event: LookEvent
    public var live: LocationPoint
    public var trail: [LocationPoint]

    public init(id: UUID = UUID(), event: LookEvent, live: LocationPoint, trail: [LocationPoint]) {
        self.id = id
        self.event = event
        self.live = live
        self.trail = trail
    }
}

public struct LookReceipt: Equatable, Sendable {
    public var title: String
    public var body: String
    public var at: Date

    public init(title: String, body: String, at: Date) {
        self.title = title
        self.body = body
        self.at = at
    }
}

/// Resting outbound mode toward one person. Join default is `off` both ways —
/// an invite is not a permission.
public enum ShareRestingMode: String, Codable, Sendable, Equatable {
    case off
    case untilTheyLook
    case always
    case paused

    /// Wire value for `PATCH /people/{id}/share`.
    public var apiValue: String { rawValue }
}

public enum SharePresentation: Equatable, Sendable {
    case off
    case untilTheyLook
    case always
    case paused(ends: Date, revertsTo: ShareRestingMode)

    /// Always is the only live share. Pause is not visible.
    public var isAvailable: Bool {
        if case .always = self { return true }
        return false
    }

    public var isSealed: Bool {
        if case .untilTheyLook = self { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    public var isOff: Bool {
        if case .off = self { return true }
        return false
    }

    /// Sealed and Always upload. Pause and Off do not.
    public var acceptsLocation: Bool {
        switch self {
        case .always, .untilTheyLook: return true
        case .off, .paused: return false
        }
    }
}

public struct PersonShareState: Equatable, Codable, Sendable {
    public var resting: ShareRestingMode
    public var pauseUntil: Date?
    public var restoresTo: ShareRestingMode?

    public init(
        resting: ShareRestingMode = .off,
        pauseUntil: Date? = nil,
        restoresTo: ShareRestingMode? = nil
    ) {
        self.resting = resting
        self.pauseUntil = pauseUntil
        self.restoresTo = restoresTo
    }

    public func presentation(at now: Date) -> SharePresentation {
        if resting == .paused {
            if let pauseUntil, pauseUntil > now {
                let restores = restoresTo == .always ? ShareRestingMode.always : .untilTheyLook
                return .paused(ends: pauseUntil, revertsTo: restores)
            }
            return restoresTo == .always ? .always : .untilTheyLook
        }
        switch resting {
        case .always: return .always
        case .untilTheyLook: return .untilTheyLook
        case .off: return .off
        case .paused: return .off
        }
    }

    public func chipLabel(at now: Date) -> String {
        switch presentation(at: now) {
        case .off:
            return TrustCopy.notSharing
        case .untilTheyLook:
            return TrustCopy.untilTheyLook
        case .always:
            return TrustCopy.always
        case .paused:
            return TrustCopy.pause
        }
    }
}

/// How hard the device works. Off and Pause do not upload. Sealed is coarse.
/// Always uses the finer tier. A Look does not.
public enum LocationSharingTier: Equatable, Sendable {
    case off
    case sealed
    case available
}

/// Upload while any outbound share is Sealed or Always. Pause does not upload.
public enum OutboundLocationSharing: Sendable {
    public static func isActive(shares: [PersonShareState], at now: Date = Date()) -> Bool {
        shares.contains { $0.presentation(at: now).acceptsLocation }
    }

    public static func tier(shares: [PersonShareState], at now: Date = Date()) -> LocationSharingTier {
        let presentations = shares.map { $0.presentation(at: now) }
        guard presentations.contains(where: \.acceptsLocation) else { return .off }
        if presentations.contains(where: \.isAvailable) { return .available }
        return .sealed
    }
}

/// Server pause durations. The phone does not keep the timer.
public enum PauseDuration: String, CaseIterable, Sendable, Equatable {
    case oneHour = "1h"
    case eightHours = "8h"
    case oneDay = "1d"
    case twoDays = "2d"
    case threeDays = "3d"

    public var seconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .eightHours: return 8 * 3600
        case .oneDay: return 24 * 3600
        case .twoDays: return 2 * 24 * 3600
        case .threeDays: return 3 * 24 * 3600
        }
    }

    public var label: String {
        switch self {
        case .oneHour: return "1 hour"
        case .eightHours: return "8 hours"
        case .oneDay: return "1 day"
        case .twoDays: return "2 days"
        case .threeDays: return "3 days"
        }
    }

    public func endDate(from now: Date) -> Date {
        now.addingTimeInterval(seconds)
    }

    public static func matching(seconds: TimeInterval) -> PauseDuration {
        allCases.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) } ?? .oneHour
    }
}

/// Rules the person row, map, and history window share. Tested without a device.
public enum TrustProductRules {
    public static let freeHistoryHours = 24
    public static let plusHistoryDays = 30

    public static func historyWindowHours(viewerHasPlus: Bool) -> Int {
        viewerHasPlus ? plusHistoryDays * 24 : freeHistoryHours
    }

    public enum Peek: Equatable {
        case look
        case view
        case none
    }

    /// Row tap opens the person. It is not a Look.
    public static func rowOpensPerson() -> Bool { true }

    public static func peek(inbound: SharePresentation) -> Peek {
        switch inbound {
        case .untilTheyLook: return .look
        case .always: return .view
        case .off, .paused: return .none
        }
    }

    /// Live pin only when they are Always and you have Plus.
    public static func showsLivePin(viewerHasPlus: Bool, inbound: SharePresentation) -> Bool {
        viewerHasPlus && inbound.isAvailable
    }

    public static func pauseWireValue(_ duration: PauseDuration) -> String {
        duration.rawValue
    }
}

public struct TrustedPerson: Identifiable, Equatable, Sendable {
    public var person: Person
    public var presence: PresenceSnapshot
    /// Your outbound share toward this person.
    public var share: PersonShareState
    /// Their share toward you reveals live (Always / For a while) — "Available".
    public var inboundLive: Bool
    /// Coordinates only when this person is visible to you. Always nil when sealed.
    public var livePoint: LocationPoint?
    public var outboundPresenceGranted: Bool
    public var inboundPresenceGranted: Bool
    /// Nil when they are Hidden, have no signal yet, or have not granted presence.
    public var homePresence: HomePresenceSnapshot?
    public var promise: PromiseSnapshot?
    /// Their share toward you, when the server says. Nil = not in the payload (pre-`inboundShare`
    /// servers), so the client only learns "Off" from a `share_off` Look answer.
    public var inboundPresentation: SharePresentation?
    /// Points collected while they are sharing. Empty when the payload has none.
    /// Newest is not assumed to be the only point.
    public var locationHistory: [LocationVisit]

    public var id: UUID { person.id }
    public var displayName: String { person.identity }
    /// First name for sheets and toasts ("Look at Maya?").
    public var firstName: String { person.displayName.trustFirstName }

    /// Their share toward you is Always. Sealed, Paused, and Off are not live pins.
    public var isAvailable: Bool { inboundPresentation?.isAvailable == true }
    public var isSealed: Bool { inboundPresentation?.isSealed == true }
    public var isPaused: Bool { inboundPresentation?.isPaused == true }
    /// True only when the server said their share toward you is Off.
    public var isNotSharingWithYou: Bool { inboundPresentation?.isOff == true }

    /// Home / Away when visible; nil means the row reads "presence hidden".
    public var visiblePresence: HomePresenceKind? {
        guard let state = homePresence?.state, state == .home || state == .away else { return nil }
        return state
    }

    public init(
        person: Person,
        presence: PresenceSnapshot,
        share: PersonShareState,
        inboundLive: Bool,
        livePoint: LocationPoint? = nil,
        outboundPresenceGranted: Bool = false,
        inboundPresenceGranted: Bool = false,
        homePresence: HomePresenceSnapshot? = nil,
        promise: PromiseSnapshot? = nil,
        inboundPresentation: SharePresentation? = nil,
        locationHistory: [LocationVisit] = []
    ) {
        self.person = person
        self.presence = presence
        self.share = share
        self.inboundLive = inboundLive
        self.livePoint = inboundLive ? livePoint : nil
        self.outboundPresenceGranted = outboundPresenceGranted
        self.inboundPresenceGranted = inboundPresenceGranted
        self.homePresence = homePresence
        self.promise = promise
        self.inboundPresentation = inboundPresentation
        self.locationHistory = locationHistory
    }
}

public enum LookError: Error, Equatable {
    case confirmationRequired
    case pairInactive
    case noPartner
    /// Their share toward you is Off — nothing to Look at.
    case shareOff
    /// Their share toward you is already Available — use View, not Look.
    case lookRequiresSealed
    /// View only works while their share toward you is Available.
    case viewRequiresAvailable
}

public extension String {
    /// "Maya Chen" → "Maya"; "@maya" → "maya".
    var trustFirstName: String {
        var trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { trimmed = String(trimmed.dropFirst()) }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }
}

public enum PairingError: Error, Equatable {
    case invalidCode
    case alreadyPaired
}
