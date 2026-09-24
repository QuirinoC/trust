import CoreLocation
import Foundation
import TrustCore

final class LocationCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let precisePurposeKey = "PreciseEscrow"

    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published var lastFix: LocationPoint?
    @Published var isUsingSimulatorFeed = true
    @Published var isSharing = false
    @Published private(set) var sharingTier: LocationSharingTier = .off
    @Published private(set) var homeIsSet = false

    var onLocations: (([LocationPoint]) -> Void)?
    var onHomePresence: ((HomePresenceKind) -> Void)?

    private let manager = CLLocationManager()
    private let alwaysAskedKey = "trust.location.didRequestAlways"
    private let homeStore = HomePlaceStore()
    private var isMapActive = false
    private var isAppActive = true
    private var pendingAlwaysAfterWhenInUse = false
    private var awaitingAlwaysAnswer = false
    private var didRequestPreciseThisSession = false
    private var monitoringHome = false
    private var lastPostedHomeState: HomePresenceKind?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
        // Never the blue navigation pill. That indicator is for turn-by-turn, and Trust is not navigating.
        manager.showsBackgroundLocationIndicator = false
        manager.allowsBackgroundLocationUpdates = false
        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        homeIsSet = homeStore.isSet
    }

    var homePlaceID: UUID? { homeStore.placeID }
    var homeLabel: String { homeStore.label }

    var hasAccess: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    var hasAlways: Bool {
        authorization == .authorizedAlways
    }

    var isPrecise: Bool {
        accuracyAuthorization == .fullAccuracy
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    var needsAlwaysForSharing: Bool {
        isSharing && authorization == .authorizedWhenInUse
    }

    var needsSystemSettings: Bool {
        if isDenied { return true }
        return isSharing && authorization == .authorizedWhenInUse && didRequestAlwaysUpgrade
    }

    var statusLabel: String {
        switch authorization {
        case .authorizedAlways: return TrustCopy.always
        case .authorizedWhenInUse: return TrustCopy.whileUsing
        case .denied, .restricted: return TrustCopy.denied
        case .notDetermined: return TrustCopy.notAsked
        @unknown default: return TrustCopy.unknown
        }
    }

    var accuracyLabel: String {
        isPrecise ? TrustCopy.precise : TrustCopy.approximate
    }

    func setMapActive(_ active: Bool) {
        isMapActive = active
        applyTracking()
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
        applyTracking()
    }

    func setSharing(_ sharing: Bool) {
        setSharingTier(sharing ? (sharingTier == .off ? .available : sharingTier) : .off)
    }

    /// Off stops the stack. Sealed stays coarse (significant-change). Always is finer.
    /// A Look does not raise accuracy.
    func setSharingTier(_ tier: LocationSharingTier) {
        sharingTier = tier
        isSharing = tier != .off
        if tier == .available {
            requestPreciseIfNeeded()
        } else {
            didRequestPreciseThisSession = false
        }
        applyTracking()
    }

    func clearHome() {
        homeStore.clear()
        homeIsSet = false
        lastPostedHomeState = nil
        applyHomeMonitoring()
    }

    func setHomeMonitoring(_ enabled: Bool) {
        monitoringHome = enabled && homeStore.isSet
        applyHomeMonitoring()
    }

    @discardableResult
    func setHomeFromCurrentFix(label: String = "Home") -> (placeID: UUID, label: String)? {
        guard let fix = lastFix ?? manager.location.map({
            LocationPoint(timestamp: $0.timestamp, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }) else {
            return nil
        }
        let placeID = homeStore.placeID ?? UUID()
        homeStore.save(
            coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
            label: label,
            placeID: placeID
        )
        homeIsSet = true
        applyHomeMonitoring()
        evaluateHomePresence(at: CLLocation(latitude: fix.latitude, longitude: fix.longitude))
        return (placeID, label)
    }

    func requestWhenInUse() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        switch authorization {
        case .notDetermined:
            pendingAlwaysAfterWhenInUse = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            awaitingAlwaysAnswer = true
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            applyTracking()
        default:
            break
        }
    }

    func requestPrecise() {
        guard hasAccess, !isPrecise else { return }
        didRequestPreciseThisSession = true
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.precisePurposeKey) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.accuracyAuthorization = self.manager.accuracyAuthorization
                self.applyTracking()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorization = manager.authorizationStatus
            self.accuracyAuthorization = manager.accuracyAuthorization
            if self.awaitingAlwaysAnswer {
                self.awaitingAlwaysAnswer = false
                if self.authorization == .authorizedWhenInUse || self.isDenied {
                    self.didRequestAlwaysUpgrade = true
                }
            }
            if self.pendingAlwaysAfterWhenInUse, self.authorization == .authorizedWhenInUse {
                self.pendingAlwaysAfterWhenInUse = false
                self.requestAlways()
            } else if self.pendingAlwaysAfterWhenInUse, self.isDenied {
                self.pendingAlwaysAfterWhenInUse = false
            }
            self.requestPreciseIfNeeded()
            // Home set earlier without Always: start the region once Always lands.
            if self.homeStore.isSet && self.hasAlways {
                self.monitoringHome = true
                self.applyHomeMonitoring()
            }
            self.applyTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.map {
            LocationPoint(
                timestamp: $0.timestamp,
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }
        DispatchQueue.main.async {
            if let last = points.last {
                self.lastFix = last
                self.isUsingSimulatorFeed = false
            }
            if !points.isEmpty {
                self.onLocations?(points)
            }
            if let latest = locations.last {
                self.evaluateHomePresence(at: latest)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("trust.home.") else { return }
        DispatchQueue.main.async {
            self.postHomeState(.home)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("trust.home.") else { return }
        DispatchQueue.main.async {
            self.postHomeState(.away)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isUsingSimulatorFeed = true
        }
    }

    private var wantsBackground: Bool {
        (isSharing || monitoringHome) && authorization == .authorizedAlways
    }

    private var wantsForegroundUpdates: Bool {
        hasAccess && isAppActive && (isMapActive || isSharing || monitoringHome)
    }

    private func applyTracking() {
        let background = wantsBackground
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = false
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = sharingTier != .available

        switch sharingTier {
        case .off:
            if wantsForegroundUpdates && isMapActive {
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.distanceFilter = 50
                manager.startUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
            } else {
                manager.stopUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
                if !hasAccess {
                    isUsingSimulatorFeed = true
                }
            }
        case .sealed:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 200
            if background || wantsForegroundUpdates {
                manager.startMonitoringSignificantLocationChanges()
                if isAppActive || isMapActive {
                    manager.startUpdatingLocation()
                } else {
                    manager.stopUpdatingLocation()
                }
            } else {
                manager.stopUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
            }
        case .available:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 25
            if background || wantsForegroundUpdates {
                manager.startUpdatingLocation()
                manager.startMonitoringSignificantLocationChanges()
            } else {
                manager.stopUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
            }
        }
        applyHomeMonitoring()
    }

    private func applyHomeMonitoring() {
        // Region monitoring needs authorization; nothing to reconcile before the user has answered.
        guard hasAccess else { return }
        let existing = manager.monitoredRegions.filter { $0.identifier.hasPrefix("trust.home.") }
        for region in existing {
            manager.stopMonitoring(for: region)
        }
        guard monitoringHome, hasAlways, let region = homeStore.region else { return }
        manager.startMonitoring(for: region)
        if let location = manager.location {
            evaluateHomePresence(at: location)
        }
    }

    private func evaluateHomePresence(at location: CLLocation) {
        guard monitoringHome, homeStore.isSet else { return }
        postHomeState(homeStore.contains(location) ? .home : .away)
    }

    private func postHomeState(_ state: HomePresenceKind) {
        guard lastPostedHomeState != state else { return }
        lastPostedHomeState = state
        onHomePresence?(state)
    }

    private func requestPreciseIfNeeded() {
        guard sharingTier == .available, hasAccess, !isPrecise, !didRequestPreciseThisSession else { return }
        requestPrecise()
    }

    private var didRequestAlwaysUpgrade: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysAskedKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysAskedKey) }
    }
}
