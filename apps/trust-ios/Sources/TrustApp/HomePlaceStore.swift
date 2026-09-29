import CoreLocation
import Foundation
import TrustCore

/// Home coordinates stay on-device only (Keychain). Server gets place id + label.
struct HomePlaceStore {
    private let accountID: String?
    private static let legacyKeys = ["trust.home.latitude", "trust.home.longitude", "trust.home.placeId", "trust.home.label"]
    private static let migrationKey = "trust.home.account-scope-migrated"
    private static let radiusMeters: CLLocationDistance = 120

    init(accountID: String? = nil) {
        self.accountID = accountID
        if TrustKeychain.get(account: Self.migrationKey) == nil {
            // The previous device-global value has no safe account owner. Remove it
            // once instead of assigning one person's Home to whichever account signs in.
            Self.legacyKeys.forEach { TrustKeychain.delete(account: $0) }
            TrustKeychain.set("1", account: Self.migrationKey)
        }
    }

    private var latitudeKey: String { TrustHomeScope.key("latitude", accountID: accountID) }
    private var longitudeKey: String { TrustHomeScope.key("longitude", accountID: accountID) }
    private var placeIDKey: String { TrustHomeScope.key("placeId", accountID: accountID) }
    private var labelKey: String { TrustHomeScope.key("label", accountID: accountID) }

    var placeID: UUID? {
        guard let raw = TrustKeychain.get(account: placeIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    var label: String {
        TrustKeychain.get(account: labelKey) ?? "Home"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latRaw = TrustKeychain.get(account: latitudeKey),
              let lonRaw = TrustKeychain.get(account: longitudeKey),
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
        TrustKeychain.set(String(coordinate.latitude), account: latitudeKey)
        TrustKeychain.set(String(coordinate.longitude), account: longitudeKey)
        TrustKeychain.set(placeID.uuidString, account: placeIDKey)
        TrustKeychain.set(label, account: labelKey)
    }

    func clear() {
        TrustKeychain.delete(account: latitudeKey)
        TrustKeychain.delete(account: longitudeKey)
        TrustKeychain.delete(account: placeIDKey)
        TrustKeychain.delete(account: labelKey)
    }

    func contains(_ location: CLLocation) -> Bool {
        guard let coordinate else { return false }
        let home = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: home) <= Self.radiusMeters
    }
}
