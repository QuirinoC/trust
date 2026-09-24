import Combine
import Foundation
import StoreKit
import SwiftUI
import TrustCore
import UIKit

enum AppPhase: Equatable {
    case login
    /// A2 — pick `@handle` once after the first Sign in with Apple.
    case handle
    /// A verification text is required before Home.
    case phone
    case home
}

enum MainTab: String, CaseIterable, Identifiable {
    case circle
    case sharing
    case log
    case you

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return TrustCopy.circle
        case .sharing: return TrustCopy.sharing
        case .log: return TrustCopy.log
        case .you: return TrustCopy.you
        }
    }

    /// Filled SF Symbols — HIG prefers familiar, scalable tab icons.
    var systemImage: String {
        switch self {
        case .circle: return "person.2.fill"
        case .sharing: return "location.fill"
        case .log: return "list.bullet"
        case .you: return "person.crop.circle.fill"
        }
    }
}

/// Destinations pushed over the People tab: person (presence only), Look/View location, map.
enum CircleRoute: Hashable {
    case person(UUID)
    case view(UUID)
    case map
}

/// One-line status the shell shows for ~4 s. Replaces alerts for non-blocking outcomes.
struct TrustToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let at = Date()
}

@MainActor
final class AppModel: ObservableObject {
    let client = TrustClient()
    let store: StoreManager
    let location: LocationCoordinator
    let receipts: LookReceiptNotifier
    let auth: AuthSession
    private let ingestStore: LocationIngestStore
    private var isFlushingIngest = false
    private var ingestFlushTask: Task<Void, Never>?

    @Published var phase: AppPhase
    @Published var selectedTab: MainTab = .circle
    @Published var circlePath: [CircleRoute] = []
    @Published var snapshot: CircleSnapshot?
    @Published private(set) var isOffline = false
    @Published private(set) var isRefreshing = false
    @Published var toast: TrustToast?

    /// Look confirm sheet subject (Sealed rows only).
    @Published var lookSubject: TrustedPerson?
    @Published private(set) var isLooking = false
    /// Snapshots opened this session, by subject. A Look never flips a Sealed row Available.
    @Published private(set) var openedSnapshots: [UUID: LookSession] = [:]
    /// Location history is only fetched for Always shares.
    @Published private(set) var historyByPerson: [UUID: [LocationVisit]] = [:]
    @Published private(set) var historyLoadingIDs: Set<UUID> = []
    @Published private(set) var historyLoadedIDs: Set<UUID> = []
    @Published private(set) var historyErrors: Set<UUID> = []
    private var historyFetchedAt: [UUID: Date] = [:]

    @Published var showingViewLog = false
    @Published var showingPaywall = false
    @Published var showingAlwaysExplainer = false
    /// Pause sheet. Set from Sharing, or from a screenshot launch.
    @Published var pauseSheetPersonID: UUID?
    @Published var stopAllRequested = false

    @Published var inviteCodeDraft = ""
    @Published var inviteNotice: String?
    @Published var phoneInviteCode: String?
    @Published private(set) var isJoining = false

    @Published var isSigningIn = false
    @Published var isDemoMode = false

    /// Optimistic presence while the POST is in flight; falls back to the snapshot.
    @Published private var presenceOverride: HomePresenceKind?

    @Published var phoneDraft = ""
    @Published var phoneConsentChecked = false
    @Published var phoneCodeDraft = ""
    @Published var phoneNotice: String?
    @Published var phoneCodeSent = false
    @Published var isSendingPhone = false

    @Published var addPhoneDraft = ""
    @Published private(set) var isAddingByPhone = false

    @Published var onboardingHandle = ""
    @Published var onboardingNotice: String?
    @Published var handleAvailability: Bool?
    @Published var isOnboardingBusy = false
    private var handleCheckTask: Task<Void, Never>?
    private var demo: DemoTrustService?
    private var demoTickTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var lastRefreshAttemptAt: Date?
    private var refreshQueued = false
    private var queuedRefreshEntersHome = false
    private var queuedRefreshFallback: Bool?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    private var cancellables: Set<AnyCancellable> = []

    var authNotice: String? { auth.notice }

    var you: Person {
        snapshot?.you ?? Person(displayName: auth.account?.displayName ?? TrustCopy.you)
    }

    var circle: [TrustedPerson] { snapshot?.members ?? [] }

    var coverage: CircleCoverage {
        snapshot?.coverage ?? CircleCoverage(isCovered: false, sponsorName: nil, actingIsSponsor: false)
    }

    var lookLog: [LookEvent] { snapshot?.lookLog ?? [] }
    var pendingInviteCode: String? { snapshot?.pendingInviteCode }

    /// Upload while Sealed or Always. Pause and Off do not.
    var isSharingLocation: Bool {
        locationSharingTier != .off
    }

    /// Sealed stays coarse. Always is finer. A Look does not raise the tier.
    var locationSharingTier: LocationSharingTier {
        OutboundLocationSharing.tier(shares: circle.map(\.share))
    }

    var outboundActiveCount: Int {
        let now = Date()
        return circle.filter { !$0.share.presentation(at: now).isOff }.count
    }

    var myPresence: HomePresenceKind {
        presenceOverride ?? snapshot?.yourHomeState ?? .unknown
    }

    func member(_ id: UUID) -> TrustedPerson? {
        circle.first { $0.id == id }
    }

    func openedSnapshot(for id: UUID) -> LookSession? {
        openedSnapshots[id]
    }

    /// Row state for Circle (design SoT Round 7).
    func isOpened(_ member: TrustedPerson) -> Bool {
        openedSnapshot(for: member.id) != nil
    }

    /// Confirmed Looks are visible as single pins for everyone. Live pins require Plus.
    var homeMapPins: [MapPin] {
        var pins: [MapPin] = []
        for member in circle {
            if coverage.isCovered,
               TrustProductRules.showsLivePin(viewerHasPlus: true, inbound: member.inboundPresentation ?? .off),
               let live = member.livePoint {
                pins.append(MapPin(id: member.id, name: member.person.displayName, point: live, live: true))
            } else if let snapshot = openedSnapshot(for: member.id) {
                pins.append(MapPin(id: member.id, name: member.person.displayName, point: snapshot.live, live: false))
            }
        }
        return pins
    }

    struct MapPin: Identifiable, Equatable {
        let id: UUID
        let name: String
        let point: LocationPoint
        let live: Bool
    }

    init() {
        let auth = AuthSession()
        self.auth = auth
        store = StoreManager()
        location = LocationCoordinator()
        receipts = LookReceiptNotifier()
        LookReceiptNotifier.shared = receipts
        ingestStore = LocationIngestStore()
        client.token = auth.sessionToken
        #if DEBUG
        // Demo is opt-in only. When requested, hold on Login until start() seeds the
        // fixture so Circle never paints empty; otherwise Debug behaves exactly like Release.
        phase = Self.debugDemoRequested(sessionToken: auth.sessionToken)
            ? .login
            : (auth.isAuthenticated ? .home : .login)
        #else
        phase = auth.isAuthenticated ? .home : .login
        #endif
        if auth.isAuthenticated, !isDemoMode, let cached = client.cachedCircle() {
            // Paint the last good circle immediately; refresh() decides whether it is stale.
            snapshot = cached
            if !Self.debugDemoRequested(sessionToken: auth.sessionToken) {
                phase = Self.phase(for: cached.you)
            }
        }
        bind()
    }

    /// The offline demo runs only when explicitly asked for: the persisted “See the app”
    /// session token, or `TRUST_DEMO=1` in the scheme / `SIMCTL_CHILD_TRUST_DEMO=1` via simctl.
    private static func debugDemoRequested(sessionToken: String?) -> Bool {
        sessionToken == "demo" || ProcessInfo.processInfo.environment["TRUST_DEMO"] == "1"
    }

    /// App Store shot launch (`SIMCTL_CHILD_TRUST_SCREENSHOT=…`). Hides demo chrome and
    /// skips permission prompts so captures are listing-safe.
    var isScreenshotLaunch: Bool {
        !(ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] ?? "").isEmpty
    }

    /// XCUITest sets this so the demo walk is not blocked by system permission sheets.
    /// Debug only. Release ignores the variable.
    var isUITestLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TRUST_UI_TEST"] == "1"
        #else
        false
        #endif
    }

    // MARK: Lifecycle

    func start() async {
        await client.prepare()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TRUST_DEV_SESSION"] == "1" {
            await signInWithLocalAPI()
            await store.loadProducts()
            applyScreenshotLaunch()
            return
        }
        if Self.debugDemoRequested(sessionToken: auth.sessionToken) {
            enterDemo()
            await store.loadProducts()
            applyScreenshotLaunch()
            return
        }
        #endif
        await auth.validateRestoredAppleCredential()
        if auth.isAuthenticated {
            await refresh(enterHome: true)
        } else {
            phase = .login
            if let warning = client.reachabilityNotice {
                auth.notice = warning
            }
        }
        await store.loadProducts()
        receipts.prepare(client: client)
        _ = await store.refreshEntitlement()
        if auth.isAuthenticated {
            await refreshStoreKitToken()
            await syncCircleEntitlement()
        }
        receipts.refreshStatus()
        UIDevice.current.isBatteryMonitoringEnabled = true
        if phase == .home, !circle.isEmpty, !isUITestLaunch, ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] == nil {
            await receipts.requestPermission()
        }
        applyScreenshotLaunch()
    }

    /// DEBUG screenshot launch routes. Pair with `TRUST_DEMO=1` for fixture-backed screens.
    private func applyScreenshotLaunch() {
        #if DEBUG
        let shot = ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] ?? ""
        guard !shot.isEmpty else { return }
        switch shot {
        case "login":
            phase = .login
        case "handle":
            phase = .handle
        case "phone":
            phase = .phone
        case "paywall":
            selectedTab = .you
            showingPaywall = true
        case "circle":
            guard auth.isAuthenticated else { return }
            selectedTab = .circle
        case "person":
            guard auth.isAuthenticated else { return }
            selectedTab = .circle
            if let member = circle.first(where: { $0.isAvailable }) ?? circle.first {
                openPerson(member)
            }
        case "empty":
            guard auth.isAuthenticated else { return }
            selectedTab = .circle
            if let member = circle.first(where: { $0.person.displayName == "Maya Chen" }) ?? circle.first {
                openPerson(member)
            }
        case "pause":
            guard auth.isAuthenticated else { return }
            selectedTab = .sharing
            pauseSheetPersonID = circle.first(where: { $0.person.displayName == "Maya Chen" })?.id ?? circle.first?.id
        case "look":
            guard auth.isAuthenticated else { return }
            if let sealed = circle.first(where: \.isSealed) { openLook(sealed) }
        case "view":
            guard auth.isAuthenticated else { return }
            if let available = circle.first(where: \.isAvailable) { openView(available) }
        case "log":
            guard auth.isAuthenticated else { return }
            selectedTab = .log
        case "share":
            guard auth.isAuthenticated else { return }
            selectedTab = .sharing
        case "you", "settings":
            guard auth.isAuthenticated else { return }
            selectedTab = .you
        case "map":
            guard auth.isAuthenticated else { return }
            openMap()
        case "invite":
            guard auth.isAuthenticated else { return }
            selectedTab = .sharing
        default:
            break
        }
        #endif
    }

    func prepareLogin() async {
        await client.prepare()
        if let warning = client.reachabilityNotice {
            auth.notice = warning
        }
    }

    // MARK: Demo (DEBUG)

    /// Offline fixture from the design SoT. DEBUG only; entered from “See the app” or `TRUST_DEMO=1`.
    func enterDemo() {
        #if DEBUG
        let service = DemoTrustService()
        service.startLeanDemo()
        demo = service
        isDemoMode = true
        auth.persist(
            account: AuthAccount(provider: .apple, displayName: service.you.displayName, appleUserID: "demo.alex"),
            token: "demo"
        )
        client.token = "demo"
        publishDemoSnapshot()
        selectedTab = .circle
        phase = .home
        if !isScreenshotLaunch {
            showToast(TrustCopy.demoBannerBody)
        }
        startDemoTicks()
        #endif
    }

    private func publishDemoSnapshot() {
        guard let demo else { return }
        let pack = demo.makeCircleSnapshot()
        snapshot = CircleSnapshot(
            you: pack.you,
            members: pack.members,
            coverage: pack.coverage,
            pendingInviteCode: pack.invite,
            lookLog: pack.log,
            retainedLookLogCount: pack.retained,
            allowsDevelopmentSignIn: true,
            allowsReviewUnlock: false,
            yourHomePlaceID: nil,
            yourHomeLabel: nil,
            yourHomeState: pack.presence
        )
        openedSnapshots = demo.snapshots
        isOffline = false
        if !isScreenshotLaunch {
            syncLocationSharing()
        }
    }

    private func startDemoTicks() {
        demoTickTask?.cancel()
        demoTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.isDemoMode else { return }
                self.publishDemoSnapshot()
            }
        }
    }

    private func stopDemo() {
        demoTickTask?.cancel()
        demoTickTask = nil
        demo = nil
        isDemoMode = false
    }

    // MARK: Auth

    #if DEBUG
    /// Signs in against the configured API with `POST /api/v1/session/development`.
    /// Not compiled into Release. Does not touch Sign in with Apple.
    func signInWithLocalAPI() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        stopDemo()
        do {
            await client.prepare()
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "trust-debug-simulator"
            let session = try await client.developmentSession(displayName: "Dev", deviceId: deviceId)
            auth.persist(
                account: AuthAccount(
                    provider: .apple,
                    displayName: session.you.displayName,
                    appleUserID: nil
                ),
                token: client.token ?? ""
            )
            if session.you.onboardingComplete != true, session.you.handle == nil {
                try await claimDebugHandle(deviceId: deviceId)
            }
            await refresh(enterHome: true, fallbackOnboardingComplete: true)
            receipts.prepare(client: client)
        } catch is CancellationError {
            return
        } catch {
            auth.notice = plainMessage(for: error)
        }
    }

    /// A real `PUT /me/handle` so the first local session can leave onboarding. Same account
    /// keeps the handle it already owns.
    private func claimDebugHandle(deviceId: String) async throws {
        let compact = deviceId.replacingOccurrences(of: "-", with: "").lowercased()
        let suffix = String(compact.prefix(8))
        var last: Error?
        for handle in ["devsim", "dev\(suffix)"] {
            do {
                try await client.setHandle(handle)
                return
            } catch {
                last = error
            }
        }
        if let last { throw last }
    }
    #endif

    func signIn(with provider: AuthenticationProvider) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            switch provider {
            case .apple:
                let apple = try await auth.signInWithApple()
                await client.prepare()
                let session = try await client.appleSession(
                    identityToken: apple.identityToken,
                    displayName: apple.displayName,
                    nonce: apple.nonce
                )
                auth.persist(
                    account: AuthAccount(
                        provider: .apple,
                        displayName: apple.displayName ?? session.you.displayName,
                        appleUserID: apple.userID
                    ),
                    token: client.token ?? ""
                )
                await refresh(enterHome: true, fallbackOnboardingComplete: session.you.model.onboardingComplete)
            case .google:
                auth.notice = TrustCopy.trustUsesSignInWithApple
                return
            }
            receipts.prepare(client: client)
            await refreshStoreKitToken()
        } catch is CancellationError {
            return
        } catch {
            auth.notice = plainMessage(for: error)
        }
    }

    func signOut() {
        Task { await receipts.unregister() }
        store.clearAfterSignOut()
        auth.signOut()
        client.token = nil
        client.clearCache()
        stopDemo()
        snapshot = nil
        openedSnapshots = [:]
        historyByPerson = [:]
        historyLoadingIDs = []
        historyLoadedIDs = []
        historyErrors = []
        historyFetchedAt = [:]
        presenceOverride = nil
        isOffline = false
        phase = .login
        selectedTab = .circle
        circlePath = []
        showingViewLog = false
        showingPaywall = false
        showingAlwaysExplainer = false
        lookSubject = nil
        inviteNotice = nil
        toast = nil
        resetPhoneDraft()
        addPhoneDraft = ""
        resetOnboardingDraft()
        ingestStore.clear()
        location.setSharing(false)
        location.setHomeMonitoring(false)
        location.setMapActive(false)
    }

    func deleteAccount() async {
        if isDemoMode {
            signOut()
            return
        }
        do {
            try await client.deleteAccount()
            await receipts.unregister()
            store.clearAfterSignOut()
            signOut()
        } catch {
            showToast(plainMessage(for: error))
        }
    }

    // MARK: Refresh / offline

    /// Refresh circle data when returning to a tab or foregrounding, but avoid a request
    /// for every quick tab switch. The interval is based on attempts so an offline device
    /// does not hammer the API while the user moves around the app.
    func refreshIfStale(minimumInterval: TimeInterval = 45) async {
        guard phase == .home, auth.isAuthenticated else { return }
        guard !isDemoMode else { return }
        guard !isRefreshing else { return }
        let lastAttempt = lastRefreshAttemptAt ?? snapshot?.fetchedAt
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < minimumInterval { return }
        await refresh()
    }

    func refresh(enterHome: Bool = false, fallbackOnboardingComplete: Bool? = nil) async {
        if isDemoMode {
            publishDemoSnapshot()
            if enterHome { phase = .home }
            return
        }
        if isRefreshing {
            refreshQueued = true
            queuedRefreshEntersHome = queuedRefreshEntersHome || enterHome
            if fallbackOnboardingComplete != nil {
                queuedRefreshFallback = fallbackOnboardingComplete
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                refreshWaiters.append(continuation)
            }
            return
        }

        isRefreshing = true
        var nextEntersHome = enterHome
        var nextFallback = fallbackOnboardingComplete
        repeat {
            refreshQueued = false
            queuedRefreshEntersHome = false
            queuedRefreshFallback = nil
            await performRefresh(enterHome: nextEntersHome, fallbackOnboardingComplete: nextFallback)
            nextEntersHome = queuedRefreshEntersHome
            nextFallback = queuedRefreshFallback
        } while refreshQueued

        isRefreshing = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func performRefresh(enterHome: Bool, fallbackOnboardingComplete: Bool?) async {
        client.token = auth.sessionToken
        lastRefreshAttemptAt = Date()
        do {
            let fresh = try await client.refreshCircle()
            snapshot = fresh
            reconcileInboundLocationData(with: fresh)
            isOffline = false
            presenceOverride = nil
            if enterHome || phase == .home || phase == .handle || phase == .phone {
                routeAfterAuth(onboardingComplete: fresh.you.onboardingComplete)
            }
            syncLocationSharing()
            syncHomeMonitoring()
            await flushIngestQueue()
            refreshVisibleHistoryIfStale()
        } catch TrustClientError.unauthorized {
            signOut()
        } catch let error as TrustClientError where error.isConnectivity {
            if snapshot == nil, let cached = client.cachedCircle() {
                snapshot = cached
            }
            isOffline = snapshot != nil
            if snapshot == nil {
                showToast(error.localizedDescription)
            }
            syncLocationSharing()
            if enterHome, auth.isAuthenticated {
                routeAfterAuth(onboardingComplete: fallbackOnboardingComplete ?? snapshot?.you.onboardingComplete ?? false)
            }
        } catch {
            showToast(plainMessage(for: error))
            syncLocationSharing()
            if enterHome, auth.isAuthenticated {
                routeAfterAuth(onboardingComplete: fallbackOnboardingComplete ?? snapshot?.you.onboardingComplete ?? false)
            }
        }
    }

    private func reconcileInboundLocationData(with fresh: CircleSnapshot) {
        let members = Dictionary(uniqueKeysWithValues: fresh.members.map { ($0.id, $0) })

        // A server-confirmed Off or removed relationship revokes cached snapshots too.
        for id in Array(openedSnapshots.keys) {
            guard let member = members[id], member.inboundPresentation?.isOff != true else {
                openedSnapshots[id] = nil
                continue
            }
        }

        // History is only available while the current inbound mode is Always. Drop both
        // its rows and load markers when that entitlement is no longer present.
        let cachedHistoryIDs = Set(historyByPerson.keys)
            .union(historyLoadedIDs)
            .union(historyErrors)
        for id in cachedHistoryIDs where members[id]?.isAvailable != true {
            historyByPerson[id] = nil
            historyLoadedIDs.remove(id)
            historyErrors.remove(id)
            historyFetchedAt[id] = nil
        }
    }

    private func refreshVisibleHistoryIfStale() {
        guard case let .person(personID)? = circlePath.last,
              member(personID)?.isAvailable == true,
              historyFetchedAt[personID].map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        Task { await loadHistory(for: personID) }
    }

    /// Offline is a state, not a screen. Mutations need the server; reads use the cache.
    private func requireOnline() -> Bool {
        guard isOffline, !isDemoMode else { return true }
        showToast(TrustCopy.offlineAction)
        return false
    }

    // MARK: Toast

    func showToast(_ message: String) {
        if isScreenshotLaunch { return }
        toastTask?.cancel()
        toast = TrustToast(message: message)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Look (Sealed) — notify first, one snapshot

    func openLook(_ member: TrustedPerson) {
        guard requireOnline() else { return }
        if member.isAvailable {
            openView(member)
            return
        }
        lookSubject = member
    }

    func cancelLook() {
        lookSubject = nil
    }

    func confirmLook() {
        guard let subject = lookSubject, !isLooking else { return }
        isLooking = true
        Task {
            defer { isLooking = false }
            do {
                let session: LookSession
                if let demo {
                    session = try demo.look(confirmed: true, subjectID: subject.id)
                    publishDemoSnapshot()
                } else {
                    session = try await client.look(subjectID: subject.id, confirmed: true)
                }
                openedSnapshots[subject.id] = session
                lookSubject = nil
                // Let the sheet finish dismissing before pushing D1 View.
                try? await Task.sleep(for: .milliseconds(320))
                selectedTab = .circle
                circlePath = [.view(subject.id)]
                showToast(TrustCopy.lookSaved(name: subject.firstName))
                if demo == nil { await refresh() }
            } catch {
                lookSubject = nil
                if error.isLookRequiresSealed {
                    openView(subject)
                    return
                }
                showToast(plainMessage(for: error))
            }
        }
    }

    // MARK: View (Available) — no sheet, logged, no push

    func openView(_ member: TrustedPerson) {
        if member.isSealed, let _ = openedSnapshot(for: member.id) {
            selectedTab = .circle
            circlePath = [.view(member.id)]
            return
        }
        guard member.isAvailable else {
            openLook(member)
            return
        }
        selectedTab = .circle
        circlePath = [.view(member.id)]
        guard !isOffline || isDemoMode else { return }
        Task {
            do {
                let logged: Bool
                if let demo {
                    logged = try demo.view(subjectID: member.id) != nil
                    publishDemoSnapshot()
                } else {
                    logged = try await client.view(subjectID: member.id).logged
                }
                if logged {
                    showToast(TrustCopy.viewLogged(name: member.firstName))
                    if demo == nil { await refresh() }
                }
            } catch where error.isViewRequiresAvailable {
                // Their share sealed between refreshes — fall back to the notify-first Look.
                circlePath = []
                await refresh()
                if let current = self.member(member.id) { lookSubject = current }
            } catch {
                showToast(plainMessage(for: error))
            }
        }
    }

    /// Person screen: status, with history only for Always shares.
    func openPerson(_ member: TrustedPerson) {
        selectedTab = .circle
        circlePath = [.person(member.id)]
        guard member.isAvailable, !isDemoMode else { return }
        Task { await loadHistory(for: member.id) }
    }

    func loadHistory(for personID: UUID) async {
        let historyIsFresh = historyFetchedAt[personID].map { Date().timeIntervalSince($0) < 60 } ?? false
        guard !isDemoMode, member(personID)?.isAvailable == true,
              !historyLoadingIDs.contains(personID),
              !historyLoadedIDs.contains(personID) || !historyIsFresh else { return }
        historyLoadingIDs.insert(personID)
        historyErrors.remove(personID)
        defer { historyLoadingIDs.remove(personID) }
        do {
            let points = try await client.history(personID: personID)
            guard member(personID)?.isAvailable == true else {
                historyByPerson[personID] = nil
                historyLoadedIDs.remove(personID)
                historyErrors.remove(personID)
                historyFetchedAt[personID] = nil
                return
            }
            historyByPerson[personID] = points.map {
                LocationVisit(label: TrustCopy.location, at: $0.timestamp, point: $0)
            }
            historyLoadedIDs.insert(personID)
            historyFetchedAt[personID] = Date()
        } catch {
            if member(personID)?.isAvailable == true {
                historyErrors.insert(personID)
                historyByPerson[personID] = nil
                historyLoadedIDs.remove(personID)
                historyFetchedAt[personID] = nil
            } else {
                historyByPerson[personID] = nil
                historyLoadedIDs.remove(personID)
                historyErrors.remove(personID)
                historyFetchedAt[personID] = nil
            }
        }
    }

    /// Newest first. Free is 24 hours. Plus is 30 days. Empty when they are not sharing.
    func locationHistory(for member: TrustedPerson) -> [LocationVisit] {
        guard member.isAvailable else { return [] }
        if ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] == "empty" {
            return []
        }
        let source = isDemoMode ? member.locationHistory : (historyByPerson[member.id] ?? [])
        let hours = TimeInterval(TrustProductRules.historyWindowHours(viewerHasPlus: coverage.isCovered) * 3600)
        let now = Date()
        return source
            .filter { $0.at <= now && now.timeIntervalSince($0.at) <= hours }
            .sorted { $0.at > $1.at }
    }

    func openMap() {
        selectedTab = .circle
        circlePath = [.map]
    }

    func closeSnapshot(for personID: UUID) {
        openedSnapshots[personID] = nil
        if let demo {
            demo.closeLook(subjectID: personID)
            publishDemoSnapshot()
        }
    }

    /// While-Using location only when View / Map needs “miles from you”.
    func prepareMapLocation() {
        location.setMapActive(true)
        if !isScreenshotLaunch, !isUITestLaunch {
            location.requestWhenInUse()
        }
    }

    func releaseMapLocation() {
        location.setMapActive(false)
    }

    // MARK: Sharing (outbound)

    func shareState(for personID: UUID) -> PersonShareState {
        if let demo { return demo.shareState(for: personID) }
        return member(personID)?.share ?? PersonShareState()
    }

    func setResting(_ mode: ShareRestingMode, for personID: UUID, toast override: String? = nil) {
        guard requireOnline() else { return }
        let name = member(personID)?.firstName ?? TrustCopy.them
        Task {
            do {
                if let demo {
                    switch mode {
                    case .off: demo.setOff(personID: personID)
                    case .untilTheyLook: demo.setUntilTheyLook(personID: personID)
                    case .always: try demo.setAlways(personID: personID)
                    case .paused: break
                    }
                    publishDemoSnapshot()
                } else {
                    try await client.setShare(personID: personID, resting: mode, pause: nil)
                    await refresh()
                }
                if let override {
                    showToast(override)
                } else {
                    switch mode {
                    case .off:
                        showToast(TrustCopy.sharingStopped(name: name))
                    case .untilTheyLook:
                        showToast(TrustCopy.modeUpdated(name: name, mode: TrustCopy.sealed))
                        afterFirstShare()
                    case .always:
                        showToast(TrustCopy.modeUpdated(name: name, mode: TrustCopy.always))
                        afterFirstShare()
                    case .paused:
                        break
                    }
                }
            } catch {
                handleShareError(error)
            }
        }
    }

    /// Pause is stored on the server and restores the previous mode when it ends.
    func pauseSharing(personID: UUID, duration: PauseDuration) {
        guard requireOnline() else { return }
        let until = duration.endDate(from: Date())
        let clock = until.formatted(date: .omitted, time: .shortened)
        let modeName = restoreMode(for: personID) == .always ? TrustCopy.always : TrustCopy.sealed
        Task {
            do {
                if let demo {
                    try demo.pauseSharing(personID: personID, duration: duration)
                    publishDemoSnapshot()
                } else {
                    try await client.setShare(personID: personID, resting: nil, pause: duration)
                    await refresh()
                }
                showToast(TrustCopy.pauseUntil(time: clock, mode: modeName))
                syncLocationSharing()
            } catch {
                handleShareError(error)
            }
        }
    }

    func stopSharing(personID: UUID) {
        setResting(.off, for: personID)
    }

    /// Drops the pair. Not the same as Stop, which leaves them on the list as not sharing.
    func removePerson(personID: UUID) {
        guard requireOnline() else { return }
        let name = member(personID)?.firstName ?? TrustCopy.them
        Task {
            do {
                if let demo {
                    demo.revoke(personID: personID)
                    publishDemoSnapshot()
                } else {
                    try await client.revoke(personID: personID)
                    await refresh()
                }
                circlePath.removeAll { route in
                    switch route {
                    case .person(let id), .view(let id): return id == personID
                    case .map: return false
                    }
                }
                showToast(TrustCopy.logYouRemoved(name: name))
            } catch {
                showToast(plainMessage(for: error))
            }
        }
    }

    func restoreMode(for personID: UUID) -> ShareRestingMode {
        switch shareState(for: personID).presentation(at: Date()) {
        case .always: return .always
        case .paused(_, let reverts): return reverts == .always ? .always : .untilTheyLook
        case .untilTheyLook, .off: return .untilTheyLook
        }
    }


    func stopAll() {
        guard requireOnline() else { return }
        Task {
            if let demo {
                demo.stopAll()
                publishDemoSnapshot()
            } else {
                for member in circle where !member.share.presentation(at: Date()).isOff {
                    try? await client.setShare(personID: member.id, resting: .off, pause: nil)
                }
                await refresh()
            }
            showToast(TrustCopy.stopAllToast)
        }
    }

    /// Always / For a while without Plus → intent-triggered paywall placement.
    private func handleShareError(_ error: Error) {
        if error.isProRequired {
            showingPaywall = true
            return
        }
        showToast(plainMessage(for: error))
    }

    /// First non-Off share: your location is now in the product → Always explainer → system prompt.
    private func afterFirstShare() {
        syncLocationSharing()
        guard !location.hasAlways else { return }
        if location.isDenied || location.needsSystemSettings || location.authorization == .notDetermined
            || location.authorization == .authorizedWhenInUse {
            showingAlwaysExplainer = true
        }
    }

    func allowAlwaysFromExplainer() {
        showingAlwaysExplainer = false
        if location.needsSystemSettings {
            openSystemSettings()
        } else {
            location.requestAlways()
        }
    }

    // MARK: Presence triad (global, free)

    func setPresence(_ kind: HomePresenceKind) {
        guard kind != .unknown, kind != myPresence else { return }
        if let demo {
            demo.setMyPresence(kind)
            publishDemoSnapshot()
            showToast(kind == .hidden ? TrustCopy.presenceHiddenToast : TrustCopy.presenceSetToast(label: kind.label))
            return
        }
        guard requireOnline() else { return }
        presenceOverride = kind
        Task {
            do {
                try await client.postHomePresence(state: kind)
                showToast(kind == .hidden ? TrustCopy.presenceHiddenToast : TrustCopy.presenceSetToast(label: kind.label))
                await refresh()
            } catch {
                presenceOverride = nil
                showToast(plainMessage(for: error))
            }
        }
    }

    // MARK: Invite

    func addPersonByPhone() {
        let phone = addPhoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !isAddingByPhone else { return }
        guard requireOnline() else { return }
        if isDemoMode {
            inviteNotice = TrustCopy.phoneAddNeedsAccount
            return
        }
        phoneInviteCode = nil
        isAddingByPhone = true
        Task {
            defer { isAddingByPhone = false }
            do {
                let result = try await client.addPersonByPhone(phone)
                addPhoneDraft = ""
                switch result.outcome {
                case "invited":
                    phoneInviteCode = result.developmentCode
                    inviteNotice = result.developmentCode == nil
                        ? "Invite created. Share the invite link; they must accept before joining."
                        : "Invite ready. Share the link; they must accept before joining."
                case "already":
                    inviteNotice = TrustCopy.alreadyAdded
                    await refresh()
                default:
                    inviteNotice = TrustCopy.personAdded
                    await refresh()
                }
            } catch {
                inviteNotice = plainMessage(for: error)
            }
        }
    }

    func createInvite() {
        guard requireOnline() else { return }
        if let demo {
            demo.createInvite()
            publishDemoSnapshot()
            return
        }
        Task {
            do {
                _ = try await client.createInvite()
                inviteNotice = nil
                await refresh()
            } catch {
                inviteNotice = plainMessage(for: error)
            }
        }
    }

    func joinInvite() {
        let code = inviteCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isJoining else { return }
        guard requireOnline() else { return }
        if let demo {
            do {
                try demo.joinInvite(code: code)
                inviteCodeDraft = ""
                inviteNotice = nil
                publishDemoSnapshot()
                showToast(TrustCopy.joined)
                selectedTab = .sharing
            } catch {
                inviteNotice = plainMessage(for: error)
            }
            return
        }
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                try await client.acceptInvite(code: code)
                inviteCodeDraft = ""
                inviteNotice = nil
                await refresh(enterHome: true)
                showToast(TrustCopy.joined)
                selectedTab = .sharing
                await receipts.requestPermission()
            } catch {
                inviteNotice = plainMessage(for: error)
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        let candidate: String?
        if url.scheme == "https",
           url.host == "jointrust.app",
           url.pathComponents.count == 3,
           url.pathComponents[1] == "i" {
            candidate = url.pathComponents[2]
        } else if url.scheme == "trust" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if url.host == "invite", parts.count == 1 {
                candidate = parts.first
            } else if parts.first == "invite", parts.count == 2 {
                candidate = parts[1]
            } else {
                candidate = nil
            }
        } else {
            candidate = nil
        }
        guard let candidate else { return }
        let code = candidate.uppercased()
        guard code.range(of: "^[A-HJ-NP-Z2-9]{6}$", options: .regularExpression) != nil else { return }
        inviteCodeDraft = code
        if auth.isAuthenticated, phase == .home {
            selectedTab = .sharing
        }
    }

    // MARK: Handle (A2)

    var onboardingHandleIsValid: Bool {
        if case .valid = TrustHandle.status(of: onboardingHandle) { return true }
        return false
    }

    func setOnboardingHandle(_ raw: String) {
        let next = TrustHandle.sanitizeDraft(raw)
        guard next != onboardingHandle else { return }
        onboardingHandle = next
        handleAvailability = nil
        onboardingNotice = nil
        scheduleHandleAvailabilityCheck()
    }

    func completeOnboarding() async {
        onboardingNotice = nil
        switch TrustHandle.status(of: onboardingHandle) {
        case .invalid:
            onboardingNotice = TrustCopy.enterHandle
            return
        case .reserved:
            onboardingNotice = TrustCopy.handleReserved
            return
        case .valid(let handle):
            isOnboardingBusy = true
            defer { isOnboardingBusy = false }
            do {
                try await client.setHandle(handle)
                await finishOnboardingIfComplete()
                if phase != .home {
                    onboardingNotice = TrustCopy.enterHandle
                }
            } catch {
                onboardingNotice = plainMessage(for: error)
            }
        }
    }

    private func scheduleHandleAvailabilityCheck() {
        handleCheckTask?.cancel()
        guard case .valid(let handle) = TrustHandle.status(of: onboardingHandle) else { return }
        handleCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.checkHandleAvailability(handle)
        }
    }

    private func checkHandleAvailability(_ handle: String) async {
        do {
            let payload = try await client.handleAvailability(handle)
            guard handle == TrustHandle.normalize(onboardingHandle) else { return }
            handleAvailability = payload.available
            if payload.available {
                onboardingNotice = nil
            }
        } catch {
            guard handle == TrustHandle.normalize(onboardingHandle) else { return }
            handleAvailability = nil
        }
    }

    private func finishOnboardingIfComplete() async {
        await refresh()
        let complete = snapshot?.you.onboardingComplete == true
        if complete {
            routeAfterAuth(onboardingComplete: true)
        }
    }

    private func routeAfterAuth(onboardingComplete: Bool) {
        #if DEBUG
        if !(ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] ?? "").isEmpty {
            phase = .home
            if !inviteCodeDraft.isEmpty { selectedTab = .sharing }
            return
        }
        #endif
        let next: AppPhase
        if let you = snapshot?.you {
            next = Self.phase(for: you)
        } else {
            next = onboardingComplete ? .home : .handle
        }
        if next == .handle {
            if phase != .handle {
                beginOnboarding()
            } else {
                phase = .handle
            }
        } else {
            phase = next
        }
        if phase == .home, !inviteCodeDraft.isEmpty {
            selectedTab = .sharing
        }
    }

    /// Handle first, then a verified phone, then Home. A missing phone never lands on Home.
    private static func phase(for you: Person) -> AppPhase {
        let handleReady: Bool
        if let handle = you.handle, case .valid = TrustHandle.status(of: handle) {
            handleReady = true
        } else {
            handleReady = false
        }
        if !handleReady { return .handle }
        if !you.phoneVerified { return .phone }
        return .home
    }

    func sendPhoneCode() async {
        phoneNotice = nil
        guard phoneConsentChecked else { return }
        let phone = phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !isSendingPhone else {
            if phone.isEmpty { phoneNotice = TrustCopy.enterPhone }
            return
        }
        guard requireOnline() else { return }
        isSendingPhone = true
        defer { isSendingPhone = false }
        do {
            let sent = try await client.sendPhoneCode(phone: phone)
            phoneCodeSent = true
            phoneNotice = sent.developmentCode.map(TrustCopy.developmentPhoneCode)
        } catch {
            phoneNotice = plainMessage(for: error)
        }
    }

    func verifyPhoneCode() async {
        let phone = phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = phoneCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !code.isEmpty, !isSendingPhone else {
            if code.isEmpty { phoneNotice = TrustCopy.enterPhoneCode }
            return
        }
        guard requireOnline() else { return }
        isSendingPhone = true
        defer { isSendingPhone = false }
        do {
            try await client.verifyPhoneCode(phone: phone, code: code)
            phoneNotice = nil
            await finishOnboardingIfComplete()
        } catch {
            phoneNotice = plainMessage(for: error)
        }
    }

    private func resetPhoneDraft() {
        phoneDraft = ""
        phoneConsentChecked = false
        phoneCodeDraft = ""
        phoneNotice = nil
        phoneCodeSent = false
        isSendingPhone = false
    }

    private func beginOnboarding() {
        if let existing = snapshot?.you.handle, case .valid(let handle) = TrustHandle.status(of: existing) {
            onboardingHandle = handle
        } else if let suggestion = TrustHandle.suggest(from: snapshot?.you.displayName ?? auth.account?.displayName ?? "") {
            onboardingHandle = suggestion
            scheduleHandleAvailabilityCheck()
        }
        phase = .handle
    }

    private func resetOnboardingDraft() {
        handleCheckTask?.cancel()
        onboardingHandle = ""
        onboardingNotice = nil
        handleAvailability = nil
        isOnboardingBusy = false
        resetPhoneDraft()
    }

    // MARK: Plus (StoreKit 2 — SubscriptionStoreView submits JWS here)

    func syncCircleEntitlement(signedTransactionInfo: String? = nil) async {
        do {
            if let signed = signedTransactionInfo, !signed.isEmpty {
                try await client.verifyStoreKitTransaction(signed)
                await refresh()
                return
            }
            if store.reviewUnlocked, snapshot?.allowsReviewUnlock == true {
                try await client.grantCircle(reviewUnlock: true, productID: nil, signedTransactionInfo: nil)
                await refresh()
            }
        } catch {
            if error.trustAPICode == "storekit_account_mismatch" {
                store.linkedToAnotherAccount = true
            }
            showToast(plainMessage(for: error))
        }
    }

    func refreshStoreKitToken() async {
        do {
            let token = try await client.storeKitAccountToken()
            store.setAppAccountToken(token)
            if let signed = await store.refreshEntitlement() {
                await syncCircleEntitlement(signedTransactionInfo: signed)
            }
        } catch {
            store.setAppAccountToken(nil)
        }
    }

    func purchase(_ product: Product) async {
        if let signed = await store.purchase(product) {
            await syncCircleEntitlement(signedTransactionInfo: signed)
            if coverage.isCovered { showingPaywall = false }
        }
    }

    func handleStorePurchase(_ result: Result<Product.PurchaseResult, Error>) async {
        if let signed = await store.ingestPurchaseResult(result) {
            await syncCircleEntitlement(signedTransactionInfo: signed)
            if coverage.isCovered { showingPaywall = false }
        }
    }

    func restorePurchases() async {
        if let signed = await store.restorePurchases() {
            await syncCircleEntitlement(signedTransactionInfo: signed)
            if coverage.isCovered { showingPaywall = false }
        }
    }

    func unlockPlusForReview() {
        guard snapshot?.allowsReviewUnlock == true else { return }
        store.unlockForReview()
        Task { await syncCircleEntitlement() }
    }

    // MARK: System

    func requestAlwaysLocation() {
        location.requestAlways()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func requestNotifications() async {
        await receipts.requestPermission()
    }

    // MARK: View log export

    var lookLogExportText: String {
        let youID = you.id
        return lookLog.map { event in
            TrustCopy.lookLogExportRow(
                timestamp: event.at.ISO8601Format(),
                line: event.logLine(youID: youID),
                kind: event.logKindLabel
            )
        }
        .joined(separator: "\n")
    }

    // MARK: Errors → plain copy

    func plainMessage(for error: Error) -> String {
        if let lookError = error as? LookError {
            switch lookError {
            case .confirmationRequired: return TrustCopy.apiError(code: "confirmation_required", fallback: nil)
            case .pairInactive: return TrustCopy.apiError(code: "pair_inactive", fallback: nil)
            case .noPartner: return TrustCopy.apiError(code: "no_location", fallback: nil)
            case .shareOff: return TrustCopy.apiError(code: "share_off", fallback: nil)
            case .lookRequiresSealed: return TrustCopy.apiError(code: "look_requires_sealed", fallback: nil)
            case .viewRequiresAvailable: return TrustCopy.apiError(code: "view_requires_available", fallback: nil)
            }
        }
        if let circleError = error as? CircleError {
            switch circleError {
            case .proRequired: return TrustCopy.apiError(code: "pro_required", fallback: nil)
            case .seatLimitReached: return TrustCopy.apiError(code: "seat_limit", fallback: nil)
            }
        }
        if let pairing = error as? PairingError {
            switch pairing {
            case .invalidCode: return TrustCopy.apiError(code: "invalid_code", fallback: nil)
            case .alreadyPaired: return TrustCopy.apiError(code: "not_connected", fallback: nil)
            }
        }
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty {
            return described
        }
        return TrustCopy.requestFailed
    }

    // MARK: Plumbing

    private func bind() {
        auth.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.onVerifiedJWS = { [weak self] jws in
            await self?.syncCircleEntitlement(signedTransactionInfo: jws)
        }
        location.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        receipts.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        location.onLocations = { [weak self] points in
            self?.enqueueLocations(points)
        }
        location.onHomePresence = { [weak self] kind in
            self?.postGeofencePresence(kind)
        }
        syncHomeMonitoring()
    }

    /// Home geofence drives Home/Away when a place is set and Always is granted.
    /// Desire monitoring whenever Home is set — region monitoring starts when Always arrives.
    /// Manual triad remains an override. Hidden is never posted from the geofence.
    func syncHomeMonitoring() {
        location.setHomeMonitoring(location.homeIsSet)
    }

    private func postGeofencePresence(_ kind: HomePresenceKind) {
        guard kind == .home || kind == .away else { return }
        if myPresence == .hidden { return }
        if isDemoMode {
            demo?.setMyPresence(kind)
            publishDemoSnapshot()
            return
        }
        guard !isOffline else { return }
        presenceOverride = kind
        Task {
            do {
                try await client.postHomePresence(state: kind)
                await refresh()
            } catch {
                presenceOverride = nil
            }
        }
    }

    func setHomeFromCurrentLocation() {
        guard requireOnline() || isDemoMode else { return }
        location.requestWhenInUse()
        guard let saved = location.setHomeFromCurrentFix(label: "Home") else {
            showToast(TrustCopy.homeNeedsLocation)
            return
        }
        if isDemoMode {
            showToast(TrustCopy.homeSetToast)
            syncHomeMonitoring()
            if !location.hasAlways { showingAlwaysExplainer = true }
            return
        }
        Task {
            do {
                try await client.setHomePlace(placeID: saved.placeID, label: saved.label)
                showToast(TrustCopy.homeSetToast)
                syncHomeMonitoring()
                if !location.hasAlways {
                    showingAlwaysExplainer = true
                }
                await refresh()
            } catch {
                location.clearHome()
                showToast(plainMessage(for: error))
            }
        }
    }

    func clearHomePlace() {
        location.clearHome()
        location.setHomeMonitoring(false)
        showToast(TrustCopy.homeClearedToast)
    }

    private func syncLocationSharing() {
        let tier = locationSharingTier
        location.setSharingTier(tier)
        if tier != .off, let point = location.lastFix {
            enqueueLocations([point])
        } else if tier == .off {
            ingestStore.clear()
        }
    }

    private func enqueueLocations(_ points: [LocationPoint]) {
        guard isSharingLocation, location.hasAccess, !points.isEmpty else { return }
        ingestStore.append(points)
        ingestFlushTask?.cancel()
        ingestFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushIngestQueue()
        }
    }

    private func flushIngestQueue() async {
        guard isSharingLocation, location.hasAccess, auth.isAuthenticated, !isDemoMode, !isFlushingIngest else { return }
        let pending = ingestStore.points
        guard !pending.isEmpty else { return }
        isFlushingIngest = true
        defer { isFlushingIngest = false }
        let device = UIDevice.current
        do {
            try await client.ingest(
                points: pending,
                battery: Int(device.batteryLevel * 100),
                charging: device.batteryState == .charging || device.batteryState == .full
            )
            ingestStore.removePrefix(pending.count)
        } catch TrustClientError.unauthorized {
            signOut()
        } catch {
            // Keep pending points; the next fix or refresh retries.
        }
    }
}

extension Error {
    var trustAPICode: String? { (self as? TrustClientError)?.apiCode }

    var isProRequired: Bool {
        trustAPICode == "pro_required" || (self as? CircleError) == .proRequired
    }

    var isShareOff: Bool {
        trustAPICode == "share_off" || (self as? LookError) == .shareOff
    }

    var isLookRequiresSealed: Bool {
        trustAPICode == "look_requires_sealed" || (self as? LookError) == .lookRequiresSealed
    }

    var isViewRequiresAvailable: Bool {
        trustAPICode == "view_requires_available" || (self as? LookError) == .viewRequiresAvailable
    }
}
