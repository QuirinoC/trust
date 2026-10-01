import CoreLocation
import Foundation
import TrustCore

final class LocationCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let precisePurposeKey = "PreciseEscrow"

    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published var lastFix: LocationPoint?
    private var homeAccountID: String?
    @Published var isUsingSimulatorFeed = true
    @Published var isSharing = false
    @Published private(set) var sharingTier: LocationSharingTier = .off
    @Published private(set) var homeIsSet = false
    @Published private(set) var homeIsOwnedByAnotherDevice = false

    var onLocations: (([LocationPoint]) -> Void)?
    var onHomePresence: ((HomePresenceKind, Date, UUID) -> Void)?

    private let manager = CLLocationManager()
    private let alwaysAskedKey = "trust.location.didRequestAlways"
    private var homeStore = HomePlaceStore()
    private var isMapActive = false
    private var isAppActive = true
    private var isAgeAccessAllowed = false
    private var pendingAlwaysAfterWhenInUse = false
    private var awaitingAlwaysAnswer = false
    private var didRequestPreciseThisSession = false
    private var monitoringHome = false
    private var hasReconciledServerHome = false
    private var serverHomePlaceID: UUID?
    private var lastPostedHomeState: HomePresenceKind?
    private var pendingOneShotLocationCompletion: ((LocationPoint?) -> Void)?
    private var pendingOneShotLocationRequestID: UUID?

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

    func setHomeAccountScope(_ accountID: String?) {
        guard TrustHomeScope.requiresSwitch(from: homeAccountID, to: accountID) else { return }
        finishOneShotLocationRequest(nil)
        setHomeMonitoring(false)
        homeAccountID = TrustHomeScope.normalizedAccountID(accountID)
        homeStore = HomePlaceStore(accountID: homeAccountID)
        homeIsSet = homeStore.isSet
        homeIsOwnedByAnotherDevice = false
        hasReconciledServerHome = false
        serverHomePlaceID = nil
        lastPostedHomeState = nil
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

    func setAgeAccessAllowed(_ allowed: Bool) {
        isAgeAccessAllowed = allowed
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
        homeIsOwnedByAnotherDevice = false
        hasReconciledServerHome = true
        serverHomePlaceID = nil
        monitoringHome = false
        lastPostedHomeState = nil
        applyHomeMonitoring()
    }

    /// Reconcile local monitoring with the canonical Home marker from a successful
    /// authenticated circle response. Coordinates remain in this device's Keychain.
    func reconcileHomePlace(serverPlaceID: UUID?) {
        hasReconciledServerHome = true
        serverHomePlaceID = serverPlaceID
        switch TrustHomeReconciliation.outcome(
            localPlaceID: homeStore.placeID,
            serverPlaceID: serverPlaceID,
            hasSuccessfulSnapshot: true
        ) {
        case .awaitingServer:
            break
        case .noLocalHome:
            homeIsOwnedByAnotherDevice = false
        case .activeHere:
            homeIsOwnedByAnotherDevice = false
        case .activeElsewhere:
            homeIsOwnedByAnotherDevice = true
            monitoringHome = false
        case .serverClearedLocalHome:
            homeIsOwnedByAnotherDevice = false
            clearHome()
        }
        applyHomeMonitoring()
    }

    func setHomeMonitoring(_ enabled: Bool) {
        let reconciliation = TrustHomeReconciliation.outcome(
            localPlaceID: homeStore.placeID,
            serverPlaceID: serverHomePlaceID,
            hasSuccessfulSnapshot: hasReconciledServerHome
        )
        monitoringHome = enabled && homeStore.isSet && reconciliation.allowsMonitoring
        applyHomeMonitoring()
    }

    func homeCandidateFromCurrentFix(label: String = "Home") -> (placeID: UUID, label: String, coordinate: CLLocationCoordinate2D)? {
        guard let fix = currentUsableLocationFix() else { return nil }
        return homeCandidate(from: fix, label: label)
    }

    private func currentUsableLocationFix() -> LocationPoint? {
        let fixes = [lastFix, manager.location.map {
            LocationPoint(timestamp: $0.timestamp, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }].compactMap { $0 }
        return fixes.first { abs($0.timestamp.timeIntervalSinceNow) <= 300 }
    }

    func homeCandidate(from fix: LocationPoint, label: String = "Home") -> (placeID: UUID, label: String, coordinate: CLLocationCoordinate2D)? {
        guard
              abs(fix.timestamp.timeIntervalSinceNow) <= 300,
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)) else {
            return nil
        }
        return (homeStore.placeID ?? UUID(), label, CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude))
    }

    /// Requests a fresh one-shot fix for user actions such as choosing Home.
    /// If permission is new, the request resumes after the authorization prompt.
    func requestCurrentFix(completion: @escaping (LocationPoint?) -> Void) {
        guard !isDenied else {
            completion(nil)
            return
        }
        finishOneShotLocationRequest(nil)
        let requestID = UUID()
        pendingOneShotLocationRequestID = requestID
        pendingOneShotLocationCompletion = completion
        if hasAccess {
            beginOneShotLocationRequest()
        } else {
            manager.requestWhenInUseAuthorization()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard self?.pendingOneShotLocationRequestID == requestID else { return }
            self?.finishOneShotLocationRequest(self?.currentUsableLocationFix())
        }
    }

    private func finishOneShotLocationRequest(_ fix: LocationPoint?) {
        let completion = pendingOneShotLocationCompletion
        pendingOneShotLocationCompletion = nil
        pendingOneShotLocationRequestID = nil
        applyTracking()
        completion?(fix)
    }

    private func beginOneShotLocationRequest() {
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func commitHome(_ candidate: (placeID: UUID, label: String, coordinate: CLLocationCoordinate2D)) {
        homeStore.save(coordinate: candidate.coordinate, label: candidate.label, placeID: candidate.placeID)
        homeIsSet = true
        homeIsOwnedByAnotherDevice = false
        hasReconciledServerHome = true
        serverHomePlaceID = candidate.placeID
        lastPostedHomeState = nil
        applyHomeMonitoring()
        evaluateHomePresence(at: CLLocation(latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude))
    }

    @discardableResult
    func setHomeFromCurrentFix(label: String = "Home") -> (placeID: UUID, label: String)? {
        guard let candidate = homeCandidateFromCurrentFix(label: label) else { return nil }
        commitHome(candidate)
        return (candidate.placeID, candidate.label)
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
            if self.pendingOneShotLocationCompletion != nil {
                if self.hasAccess {
                    self.beginOneShotLocationRequest()
                } else if self.isDenied {
                    self.finishOneShotLocationRequest(nil)
                }
            }
            // Do not infer permission to monitor from a saved Home place or the
            // system authorization callback. AppModel enables monitoring only
            // after age access and an authenticated account have been restored.
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
            if let last = points.last, self.pendingOneShotLocationCompletion != nil {
                self.finishOneShotLocationRequest(last)
            }
            if let latest = locations.last {
                self.evaluateHomePresence(at: latest)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("trust.home.") else { return }
        DispatchQueue.main.async {
            guard self.monitoringHome,
                  let currentRegion = self.homeStore.region,
                  currentRegion.identifier == region.identifier,
                  let placeID = self.homeStore.placeID else { return }
            self.postHomeState(.home, signaledAt: Date(), placeID: placeID)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("trust.home.") else { return }
        DispatchQueue.main.async {
            guard self.monitoringHome,
                  let currentRegion = self.homeStore.region,
                  currentRegion.identifier == region.identifier,
                  let placeID = self.homeStore.placeID else { return }
            self.postHomeState(.away, signaledAt: Date(), placeID: placeID)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isUsingSimulatorFeed = true
            if let coreLocationError = error as? CLError, coreLocationError.code == .locationUnknown {
                return
            }
            if self.pendingOneShotLocationCompletion != nil {
                self.finishOneShotLocationRequest(self.currentUsableLocationFix())
            }
        }
    }

    private var wantsBackground: Bool {
        isAgeAccessAllowed && (isSharing || monitoringHome) && authorization == .authorizedAlways
    }

    private var wantsForegroundUpdates: Bool {
        isAgeAccessAllowed && hasAccess && isAppActive && (isMapActive || isSharing || monitoringHome)
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
        // Remove stale regions even while the user is signed out or age-blocked.
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
        guard let placeID = homeStore.placeID else { return }
        postHomeState(homeStore.contains(location) ? .home : .away, signaledAt: location.timestamp, placeID: placeID)
    }

    private func postHomeState(_ state: HomePresenceKind, signaledAt: Date, placeID: UUID) {
        guard lastPostedHomeState != state else { return }
        lastPostedHomeState = state
        onHomePresence?(state, signaledAt, placeID)
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
