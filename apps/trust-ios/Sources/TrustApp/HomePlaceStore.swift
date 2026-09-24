import CoreLocation
import Foundation

/// Home coordinates stay on-device only (Keychain). Server gets place id + label.
struct HomePlaceStore {
    private static let latitudeKey = "trust.home.latitude"
    private static let longitudeKey = "trust.home.longitude"
    private static let placeIDKey = "trust.home.placeId"
    private static let labelKey = "trust.home.label"
    private static let radiusMeters: CLLocationDistance = 120

    var placeID: UUID? {
        guard let raw = TrustKeychain.get(account: Self.placeIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    var label: String {
        TrustKeychain.get(account: Self.labelKey) ?? "Home"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latRaw = TrustKeychain.get(account: Self.latitudeKey),
              let lonRaw = TrustKeychain.get(account: Self.longitudeKey),
              let lat = Double(latRaw),
              let lon = Double(lonRaw) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var region: CLCircularRegion? {
        guard let coordinate, let placeID else { return nil }
        let region = CLCircularRegion(
            center: coordinate,
            radius: Self.radiusMeters,
            identifier: "trust.home.\(placeID.uuidString)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    var isSet: Bool { coordinate != nil && placeID != nil }

    func save(coordinate: CLLocationCoordinate2D, label: String = "Home", placeID: UUID = UUID()) {
        TrustKeychain.set(String(coordinate.latitude), account: Self.latitudeKey)
        TrustKeychain.set(String(coordinate.longitude), account: Self.longitudeKey)
        TrustKeychain.set(placeID.uuidString, account: Self.placeIDKey)
        TrustKeychain.set(label, account: Self.labelKey)
    }

    func clear() {
        TrustKeychain.delete(account: Self.latitudeKey)
        TrustKeychain.delete(account: Self.longitudeKey)
        TrustKeychain.delete(account: Self.placeIDKey)
        TrustKeychain.delete(account: Self.labelKey)
    }

    func contains(_ location: CLLocation) -> Bool {
        guard let coordinate else { return false }
        let home = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: home) <= Self.radiusMeters
    }
}
