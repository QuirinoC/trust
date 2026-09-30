import Foundation

/// Presentation-only age of a location point. It never changes sharing permission or data access.
public enum LocationFreshness: Equatable, Sendable {
    case unavailable
    case recent
    case stale

    public static let staleAfter: TimeInterval = 5 * 60

    public static func status(timestamp: Date?, now: Date) -> Self {
        guard let timestamp else { return .unavailable }
        return now.timeIntervalSince(timestamp) > staleAfter ? .stale : .recent
    }
}
