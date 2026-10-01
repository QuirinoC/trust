import Foundation

/// Compares this device's private Home region with the account's server marker.
/// The server marker contains no coordinates; it identifies which device last
/// claimed Home monitoring for the account.
public enum TrustHomeReconciliation {
    public enum Outcome: Equatable {
        case awaitingServer
        case noLocalHome
        case activeHere
        case activeElsewhere
        case serverClearedLocalHome

        public var allowsMonitoring: Bool {
            self == .awaitingServer || self == .activeHere
        }
    }

    /// Before the first successful snapshot, keep local state intact and allow the
    /// existing region to run. A nil server ID is authoritative only after a read.
    public static func outcome(
        localPlaceID: UUID?,
        serverPlaceID: UUID?,
        hasSuccessfulSnapshot: Bool
    ) -> Outcome {
        guard hasSuccessfulSnapshot else { return .awaitingServer }
        guard let localPlaceID else {
            return serverPlaceID == nil ? .noLocalHome : .activeElsewhere
        }
        guard let serverPlaceID else { return .serverClearedLocalHome }
        return localPlaceID == serverPlaceID ? .activeHere : .activeElsewhere
    }
}
