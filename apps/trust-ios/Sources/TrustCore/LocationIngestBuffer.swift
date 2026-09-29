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

public struct LocationIngestBatch: Equatable, Sendable {
    public let queueIdentity: UUID
    public let points: [LocationPoint]

    public init(queueIdentity: UUID, points: [LocationPoint]) {
        self.queueIdentity = queueIdentity
        self.points = points
    }
}

/// Binds pending GPS points and in-flight acknowledgements to one account scope.
public struct AccountScopedLocationIngestBuffer: Equatable, Sendable {
    public private(set) var accountID: String?
    public private(set) var identity = UUID()
    public private(set) var buffer: LocationIngestBuffer

    public var points: [LocationPoint] { buffer.points }

    public init(accountID: String? = nil, points: [LocationPoint] = []) {
        self.accountID = accountID?.lowercased()
        self.buffer = LocationIngestBuffer(points: points)
    }

    public mutating func setAccountScope(_ accountID: String?, points: [LocationPoint] = []) {
        let next = accountID?.lowercased()
        guard next != self.accountID else { return }
        self.accountID = next
        buffer = LocationIngestBuffer(points: points)
        identity = UUID()
    }

    public mutating func append(_ points: [LocationPoint], now: Date = .now) {
        buffer.append(points, now: now)
    }

    public func nextBatch() -> LocationIngestBatch {
        LocationIngestBatch(queueIdentity: identity, points: buffer.nextBatch())
    }

    @discardableResult
    public mutating func acknowledge(_ batch: LocationIngestBatch) -> Bool {
        guard batch.queueIdentity == identity,
              !batch.points.isEmpty,
              Array(buffer.points.prefix(batch.points.count)) == batch.points else { return false }
        buffer.removePrefix(batch.points.count)
        return true
    }

    public mutating func clear() {
        buffer = LocationIngestBuffer()
        identity = UUID()
    }
}

/// Sends and acknowledges one API-sized prefix at a time. A failed/cancelled
/// send leaves that exact prefix (and all later points) queued for retry.
public enum LocationIngestBatchDrain {
    @MainActor
    public static func run(
        canContinue: () -> Bool,
        nextBatch: () -> LocationIngestBatch,
        send: (LocationIngestBatch) async throws -> Void,
        acknowledge: (LocationIngestBatch) -> Bool
    ) async throws {
        while canContinue() {
            let batch = nextBatch()
            guard !batch.points.isEmpty else { return }
            try await send(batch)
            try Task.checkCancellation()
            // Recheck sharing and account scope after the suspension. Never
            // acknowledge a batch after removal, sign-out, or queue retirement.
            guard canContinue() else { return }
            guard acknowledge(batch) else { return }
        }
    }
}
