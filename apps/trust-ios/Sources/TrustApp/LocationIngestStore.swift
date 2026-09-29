import Foundation
import TrustCore

@MainActor
final class LocationIngestStore {
    private static let legacyKey = "trust.location.pendingIngest"
    private static let migrationKey = "trust.location.pendingIngest.account-scope-migrated"
    private var buffer = AccountScopedLocationIngestBuffer()

    var points: [LocationPoint] { buffer.points }
    var queueIdentity: UUID { buffer.identity }

    func nextBatch() -> LocationIngestBatch {
        buffer.nextBatch()
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.migrationKey) == nil {
            // The old device-global queue has no safe account owner. Discard it once.
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
        }
    }

    func setAccountScope(_ accountID: String?) {
        let normalized = accountID?.lowercased()
        guard normalized != buffer.accountID else { return }

        // Retire queued coordinates when leaving an account. A delayed old request
        // cannot acknowledge or upload a later account's queue.
        if let current = buffer.accountID {
            UserDefaults.standard.removeObject(forKey: Self.key(accountID: current))
        }
        buffer.clear()
        let points = normalized.flatMap { id -> [LocationPoint]? in
            guard let data = UserDefaults.standard.data(forKey: Self.key(accountID: id)),
                  let stored = try? JSONDecoder().decode(LocationIngestBuffer.self, from: data) else { return nil }
            var retained = stored
            retained.prune(now: Date())
            return retained.points
        } ?? []
        buffer.setAccountScope(normalized, points: points)
        persist()
    }

    func append(_ points: [LocationPoint]) {
        buffer.append(points, now: Date())
        persist()
    }

    @discardableResult
    func acknowledge(_ batch: LocationIngestBatch) -> Bool {
        guard buffer.acknowledge(batch) else { return false }
        persist()
        return true
    }

    func clear() {
        buffer.clear()
        persist()
    }

    private func persist() {
        guard let accountID = buffer.accountID else { return }
        guard let data = try? JSONEncoder().encode(buffer.buffer) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(accountID: accountID))
    }

    private static func key(accountID: String) -> String {
        "trust.location.pendingIngest.account.\(accountID)"
    }
}
