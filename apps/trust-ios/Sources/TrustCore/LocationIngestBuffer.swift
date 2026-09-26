import Foundation

/// Client-side buffer of GPS points waiting to reach the API.
/// Matches the server's 30-day retention so a failed upload can still fill a Plus trail.
public struct LocationIngestBuffer: Equatable, Codable, Sendable {
    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    /// The API accepts at most 100 points in one location-ingest request.
    public static let maximumBatchSize = 100

    public var points: [LocationPoint]

    public init(points: [LocationPoint] = []) {
        self.points = points
    }

    public mutating func append(_ incoming: [LocationPoint], now: Date) {
        for point in incoming.sorted(by: { $0.timestamp < $1.timestamp }) {
            if points.last == point { continue }
            points.append(point)
        }
        prune(now: now)
    }

    public mutating func prune(now: Date) {
        let oldest = now.addingTimeInterval(-Self.retention)
        let newest = now.addingTimeInterval(120)
        points.removeAll { $0.timestamp < oldest || $0.timestamp > newest }
        points.sort { $0.timestamp < $1.timestamp }
    }

    public mutating func removePrefix(_ count: Int) {
        guard count > 0, !points.isEmpty else { return }
        points.removeFirst(min(count, points.count))
    }

    /// Returns the next request-sized batch without changing the pending queue.
    /// Call `removePrefix(batch.count)` only after the server confirms ingestion.
    public func nextBatch() -> [LocationPoint] {
        Array(points.prefix(Self.maximumBatchSize))
    }
}
