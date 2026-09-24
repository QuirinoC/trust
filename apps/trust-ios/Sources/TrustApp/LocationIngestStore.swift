import Foundation
import TrustCore

@MainActor
final class LocationIngestStore {
    private static let key = "trust.location.pendingIngest"
    private var buffer: LocationIngestBuffer

    var points: [LocationPoint] { buffer.points }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LocationIngestBuffer.self, from: data) {
            buffer = decoded
            buffer.prune(now: Date())
        } else {
            buffer = LocationIngestBuffer()
        }
    }

    func append(_ points: [LocationPoint]) {
        buffer.append(points, now: Date())
        persist()
    }

    func removePrefix(_ count: Int) {
        buffer.removePrefix(count)
        persist()
    }

    func clear() {
        buffer = LocationIngestBuffer()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(buffer) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
