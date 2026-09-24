import Foundation

/// Location points stay sealed until a look releases the vault key.
/// The store never exposes plaintext coordinates except through `unlock`.
public final class EscrowVault: @unchecked Sendable {
    /// Demo store cap. Matches the server's 30-day retention, not a 2-hour peek.
    public static let defaultHistoryWindow: TimeInterval = 30 * 24 * 60 * 60

    private var key: [UInt8]
    private var records: [SealedRecord] = []
    private var grantAlive = true
    private let lock = NSLock()

    public init(key: [UInt8]? = nil) {
        if let key, !key.isEmpty {
            self.key = key
        } else {
            self.key = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
    }

    public var sealedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }

    /// Partner, company, and UI cannot read coordinates from escrow without a look.
    public func peekPlaintext() -> [LocationPoint] {
        []
    }

    public func ingest(_ point: LocationPoint) {
        lock.lock()
        defer { lock.unlock() }
        records.append(seal(point))
    }

    public func unlock(now: Date, window: TimeInterval = EscrowVault.defaultHistoryWindow) -> [LocationPoint] {
        lock.lock()
        defer { lock.unlock() }
        guard grantAlive else { return [] }
        return records.compactMap { decrypt($0) }
            .filter { now.timeIntervalSince($0.timestamp) <= window && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func latest(now: Date, window: TimeInterval = EscrowVault.defaultHistoryWindow) -> LocationPoint? {
        unlock(now: now, window: window).last
    }

    /// Revoke destroys the grant. History is no longer available to a viewer.
    public func destroyGrant() {
        lock.lock()
        defer { lock.unlock() }
        grantAlive = false
        key = (0..<32).map { _ in UInt8.random(in: 0...255) }
        records.removeAll()
    }

    public func replaceGrant() {
        lock.lock()
        defer { lock.unlock() }
        grantAlive = true
        key = (0..<32).map { _ in UInt8.random(in: 0...255) }
        records.removeAll()
    }

    private struct SealedRecord {
        var timestamp: Date
        var nonce: [UInt8]
        var ciphertext: [UInt8]
    }

    private struct WirePoint: Codable {
        var timestamp: Date
        var latitude: Double
        var longitude: Double
    }

    private func seal(_ point: LocationPoint) -> SealedRecord {
        let wire = WirePoint(
            timestamp: point.timestamp,
            latitude: point.latitude,
            longitude: point.longitude
        )
        let json = (try? JSONEncoder().encode(wire)) ?? Data()
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
        var cipher = [UInt8](json)
        for index in cipher.indices {
            cipher[index] ^= key[index % key.count] ^ nonce[index % nonce.count]
        }
        return SealedRecord(timestamp: point.timestamp, nonce: nonce, ciphertext: cipher)
    }

    private func decrypt(_ record: SealedRecord) -> LocationPoint? {
        var plain = record.ciphertext
        for index in plain.indices {
            plain[index] ^= key[index % key.count] ^ record.nonce[index % record.nonce.count]
        }
        guard let wire = try? JSONDecoder().decode(WirePoint.self, from: Data(plain)) else {
            return nil
        }
        return LocationPoint(
            timestamp: wire.timestamp,
            latitude: wire.latitude,
            longitude: wire.longitude
        )
    }
}
