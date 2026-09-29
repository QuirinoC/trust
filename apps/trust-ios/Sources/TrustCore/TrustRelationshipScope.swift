import Foundation

/// Prevents a circle response that started before a confirmed write from being
/// published over that newer state. Capture before a read and check immediately
/// before the model and disk cache are committed.
public struct TrustCircleRefreshBarrier: Sendable {
    private var generation: UInt64 = 0

    public init() {}

    public func capture() -> UInt64 { generation }

    public mutating func recordConfirmedMutation() {
        generation &+= 1
    }

    public func permitsCommit(startedAt readGeneration: UInt64) -> Bool {
        generation == readGeneration
    }
}

/// Tracks this device's unresolved share writes by connection incarnation.
/// Callers may keep Off available as an emergency reduction while blocking a
/// second enable/Pause intent until the prior write has an authoritative result.
public struct TrustShareMutationGate: Sendable {
    private var pendingCounts: [UUID: Int] = [:]

    public init() {}

    public var updatingConnectionIDs: Set<UUID> { Set(pendingCounts.keys) }

    public func blocksNonOffMutation(connectionID: UUID) -> Bool {
        pendingCounts[connectionID, default: 0] > 0
    }

    public mutating func begin(connectionID: UUID) {
        pendingCounts[connectionID, default: 0] += 1
    }

    public mutating func finish(connectionID: UUID) {
        let remaining = max(0, pendingCounts[connectionID, default: 0] - 1)
        if remaining == 0 {
            pendingCounts.removeValue(forKey: connectionID)
        } else {
            pendingCounts[connectionID] = remaining
        }
    }
}

/// Pins an asynchronous read to the membership incarnation it started under.
/// A person can be removed and later re-added with the same account ID, so person ID
/// alone is not enough to authorize a delayed Look or History response.
public struct TrustRelationshipScope: Equatable, Sendable {
    public let personID: UUID
    public let connectionID: UUID?

    public init(_ person: TrustedPerson) {
        personID = person.id
        connectionID = person.connectionID
    }

    public func matches(_ current: TrustedPerson?) -> Bool {
        current?.id == personID && current?.connectionID == connectionID
    }

    /// A previously requested Look may finish only while the same relationship
    /// remains and the other person has not explicitly turned sharing Off.
    public func permitsLookSnapshot(_ current: TrustedPerson?) -> Bool {
        guard matches(current), let current else { return false }
        return current.inboundPresentation?.isOff != true
    }

    /// Location history is readable only for the same relationship while Always
    /// sharing is still active.
    public func permitsHistory(_ current: TrustedPerson?) -> Bool {
        matches(current) && current?.isAvailable == true
    }
}

/// Invalidates an in-flight read after the app observes consent revoked. A later
/// re-enable must not make an older response valid again; the user must start a
/// fresh read under the new consent state.
public struct TrustRequestValidity: Sendable {
    private var activeID: UUID?

    public init() {}

    @discardableResult
    public mutating func begin() -> UUID {
        let id = UUID()
        activeID = id
        return id
    }

    public mutating func invalidate() {
        activeID = nil
    }

    public func accepts(_ id: UUID) -> Bool {
        activeID == id
    }
}

/// Applies a server-acknowledged relationship mutation to the cached circle without
/// ever crossing into a later remove/re-add incarnation of the same account pair.
public enum TrustConfirmedRelationshipMutation {
    public static func applyingShare(
        _ share: PersonShareState,
        personID: UUID,
        connectionID: UUID,
        to members: [TrustedPerson]
    ) -> [TrustedPerson]? {
        guard let index = members.firstIndex(where: { $0.id == personID && $0.connectionID == connectionID }) else {
            return nil
        }
        var updated = members
        updated[index].share = share
        return updated
    }

    public static func removing(
        personID: UUID,
        connectionID: UUID,
        from members: [TrustedPerson]
    ) -> [TrustedPerson]? {
        guard members.contains(where: { $0.id == personID && $0.connectionID == connectionID }) else {
            return nil
        }
        return members.filter { !($0.id == personID && $0.connectionID == connectionID) }
    }
}

/// Identifies one GPS request used to set or update Home. Clear Home can invalidate
/// the token before a delayed Core Location callback queues a stale Set operation.
public struct TrustHomeFixRequestState: Sendable {
    private var activeID: UUID?

    public init() {}

    @discardableResult
    public mutating func begin() -> UUID {
        let id = UUID()
        activeID = id
        return id
    }

    public mutating func cancel() {
        activeID = nil
    }

    public func accepts(_ id: UUID) -> Bool {
        activeID == id
    }
}
