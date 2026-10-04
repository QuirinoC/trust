import Combine
import Foundation
import OSLog
import PermissionKit
import StoreKit
import SwiftUI
import TrustCore
import UIKit

enum AgeUnavailableStopAllState: Equatable {
    case idle
    case confirming
    case pending
    case success
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

enum AppPhase: Equatable {
    case ageChecking
    case ageGate
    case ageCheckUnavailable
    case ageRangeSharingDeclined
    case ageRangeBlocked
    case ageWaitingForParent
    case ageBlocked
    case ageConsentRevoked
    case agePrivacyHoldPending
    case agePrivacyHeld
    case appTransactionChecking
    case appTransactionUnavailable
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
    var isHomePresence = false
    let at = Date()
}

@MainActor
final class AppModel: ObservableObject {
    private struct PendingPresenceGrant {
        let mutationID: UUID
        let connectionID: UUID
        var enabled: Bool
        var preserveOptimisticValue = true
    }

    private let ageAssuranceLogger = Logger(subsystem: "com.collapsetechnologies.trust", category: "AgeAssurance")
    let client = TrustClient()
    let store: StoreManager
    let location: LocationCoordinator
    let receipts: LookReceiptNotifier
    let auth: AuthSession
    private let ageAssurance: AgeAssuranceCoordinator
    private let ingestStore: LocationIngestStore
    private var isFlushingIngest = false
    private var ingestFlushTask: Task<Void, Never>?
    private var pendingPrivacyHoldOperation: TrustAccountOperation?

    @Published var phase: AppPhase {
        didSet {
            if oldValue == .phone && phase != .phone { cancelPendingPhoneSend() }
            if Self.isUnavailableVerificationPhase(oldValue), !Self.isUnavailableVerificationPhase(phase) {
                ageUnavailableStopAllState = .idle
            }
        }
    }
    @Published var selectedTab: MainTab = .circle {
        didSet { traceUIInteraction("tab assigned: \(selectedTab.rawValue)") }
    }
    @Published var pendingPushDestination: TrustPushDestination?
    @Published var circlePath: [CircleRoute] = []
    @Published var snapshot: CircleSnapshot?
    @Published private(set) var isOffline = false
    @Published private(set) var privacyHoldSubmission = TrustAccountPrivacyHoldState()
    @Published private(set) var ageUnavailableStopAllState: AgeUnavailableStopAllState = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSettingHome = false
    @Published var toast: TrustToast?

    /// Look confirm sheet subject (Sealed rows only).
    @Published var lookSubject: TrustedPerson?
    @Published private(set) var isLooking = false
    /// Snapshots opened this session, by subject. A Look never flips a Sealed row Available.
    @Published private(set) var openedSnapshots: [UUID: LookSession] = [:]
    private var openedSnapshotConnectionIDs: [UUID: UUID] = [:]
    private var pendingLookRequests: [UUID: (connectionID: UUID?, validity: TrustRequestValidity)] = [:]
    /// Location history is only fetched for Always shares.
    @Published private(set) var historyByPerson: [UUID: [LocationVisit]] = [:]
    @Published private(set) var historyLoadingIDs: Set<UUID> = []
    @Published private(set) var historyLoadedIDs: Set<UUID> = []
    @Published private(set) var historyErrors: Set<UUID> = []
    private var historyFetchedAt: [UUID: Date] = [:]
    private var historyConnectionIDs: [UUID: UUID] = [:]
    private var historyRequestIDs: [UUID: UUID] = [:]
    private var historyRequestConnectionIDs: [UUID: UUID] = [:]

    @Published var showingViewLog = false
    @Published var showingPaywall = false
    @Published var showingAlwaysExplainer = false
    /// Pause sheet. Set from Sharing, or from a screenshot launch.
    @Published var pauseSheetPersonID: UUID? {
        didSet { tracePausePresentation(pauseSheetPersonID == nil ? "selection cleared" : "selection assigned") }
    }

    /// Fixed control/state labels only; active solely in DEBUG UI-test launches.
    func traceUIInteraction(_ event: String) {
        #if DEBUG
        guard isUITestLaunch else { return }
        Logger(subsystem: "com.collapsetechnologies.trust", category: "InteractionFlow")
            .notice("UI interaction: \(event, privacy: .public)")
        #endif
    }

    func tracePausePresentation(_ event: String) {
        #if DEBUG
        guard isUITestLaunch else { return }
        Logger(subsystem: "com.collapsetechnologies.trust", category: "SharingFlow")
            .notice("Pause presentation: \(event, privacy: .public)")
        #endif
    }
    @Published var stopAllRequested = false

    @Published var inviteCodeDraft = ""
    @Published private(set) var linkedInviteCode: String?
    @Published var inviteNotice: String?
    @Published var phoneInviteCode: String?
    @Published private(set) var isJoining = false

    @Published var isSigningIn = false
    @Published var isDemoMode = false
    /// This server-side link is required before exposing an authenticated account. It is
    /// separate from `ageAccessState`: Apple's age decision may succeed while StoreKit
    /// cannot yet prove the signed app transaction needed for consent-revocation handling.
    private var isAppTransactionLinked = false
    @Published private(set) var isAgeAccessAllowed = false {
        didSet {
            location.setAgeAccessAllowed(isAgeAccessAllowed)
            location.setAppActive(isSceneActive && isAgeAccessAllowed)
        }
    }
    private var canAccessAccountData: Bool {
        var localFixture = isDemoMode
#if DEBUG
        localFixture = localFixture
            || ProcessInfo.processInfo.environment["TRUST_DEV_SESSION"] == "1"
#endif
        return TrustAccountAccessPolicy.canAccessAccountData(
            ageAssurancePassed: isAgeAccessAllowed && ageAccessState.isAllowed,
            accountAuthenticated: auth.isAuthenticated,
            appTransactionLinked: isAppTransactionLinked,
            localFixture: localFixture
        )
    }
    @Published private(set) var ageGateBlockedByParent = false
    // PermissionQuestion is iOS 26+, while Trust still supports older deployment targets.
    // Keep this type-erased here and cast only inside the availability-guarded view.
    @Published private(set) var ageUpdateQuestion: Any?
    private var ageUpdateResponseTask: Task<Void, Never>?

    /// Optimistic presence while the POST is in flight; falls back to the snapshot.
    @Published private var presenceOverride: HomePresenceKind?

    @Published var phoneDraft = ""
    @Published var phoneCodeDraft = ""
    @Published var phoneNotice: String?
    @Published var phoneNoticeIsConflict = false
    @Published var phoneCodeSent = false
    @Published var isSendingPhone = false
    private var phoneSendGeneration: UInt64 = 0
    @Published private(set) var challengedPhone = ""
    @Published private(set) var phoneRetry = TrustPhoneRetryState()
    private var phoneRetryAccountID: String?
    private var authenticatedPerson: Person?

    private func loadPhoneRetry() {
        guard let id = TrustSessionIdentity.accountID(from: auth.sessionToken)?.uuidString.lowercased() else { return }
        guard phoneRetryAccountID != id else { return }
        phoneRetryAccountID = id
        phoneRetry = UserDefaults.standard.data(forKey: "trust.phoneRetry.\(id)")
            .flatMap { try? JSONDecoder().decode(TrustPhoneRetryState.self, from: $0) } ?? TrustPhoneRetryState()
        if phoneRetry.showingCode == true, let number = phoneRetry.challengeNumber,
           let expiresAt = phoneRetry.challengeExpiresAt, expiresAt > Date() {
            challengedPhone = number
            phoneDraft = number
            phoneCodeSent = true
        }
    }

    private func clearPrivatePhoneRetry() {
        if let id = TrustSessionIdentity.accountID(from: auth.sessionToken)?.uuidString.lowercased() {
            UserDefaults.standard.removeObject(forKey: "trust.phoneRetry.\(id)")
        }
        phoneRetry = TrustPhoneRetryState()
    }

    private func savePhoneRetry() {
        guard let id = phoneRetryAccountID, let data = try? JSONEncoder().encode(phoneRetry) else { return }
        UserDefaults.standard.set(data, forKey: "trust.phoneRetry.\(id)")
    }

    func phoneRetrySeconds(at now: Date) -> Int {
        phoneRetry.secondsRemaining(for: phoneCodeSent ? challengedPhone : phoneDraft, now: now)
    }

    var phoneRetryDeadline: Date? { phoneRetry.deadline(for: phoneCodeSent ? challengedPhone : phoneDraft) }


    @Published var addPhoneDraft = ""
    @Published private(set) var isAddingByPhone = false

    @Published var showingAddPersonSheet = false {
        didSet {
            if !showingAddPersonSheet { clearConnectionLookup() }
        }
    }
    @Published var connectionHandleDraft = ""
    @Published private(set) var connectionLookup: PersonLookupPayload?
    @Published private(set) var isLookingUpConnection = false
    @Published private(set) var isSendingConnectionRequest = false
    @Published private(set) var connectionLookupNotice: String?
    @Published private(set) var connectionLookupHint: String?
    @Published private(set) var connectionLookupIsNoMatch = false
    @Published private(set) var connectionLookupCanInvite = false
    @Published private(set) var connectionRequiresPhoneVerification = false
    @Published private(set) var connectionRequests = ConnectionRequestsPayload(incoming: [], sent: [])
    @Published private(set) var isLoadingConnectionRequests = false
    @Published private(set) var connectionRequestsNotice: String?
    private var connectionRequestsRefreshTask: Task<Void, Never>?
    private var connectionRequestsRefreshQueued = false
    @Published private(set) var actingOnConnectionRequestIDs: Set<UUID> = []
    @Published private(set) var inviteShareText: String?
    @Published private(set) var isPreparingConnectionInvite = false
    @Published private(set) var isUpdatingDiscovery = false
    @Published private(set) var updatingShareConnectionIDs: Set<UUID> = []
    @Published private(set) var updatingPresenceGrantIDs: Set<UUID> = []
    @Published var canReturnFromPhoneVerification = false
    private var accountGeneration: UInt64 = 0
    private var connectionLookupGeneration: UInt64 = 0
    private var connectionLookupDebounceTask: Task<Void, Never>?
    private var connectionLookupTask: Task<Void, Never>?
    private let homePresenceMutationQueue = TrustAsyncSerialExecutor()
    private var pendingHomePresenceMutationID: UUID?
    private var latestHomePresenceMutationID: UUID?
    private let homeMutationQueue = TrustAsyncSerialExecutor()
    private let shareMutationQueue = TrustAsyncSerialExecutor()
    private var shareMutationGate = TrustShareMutationGate()
    private let presenceGrantMutationQueue = TrustAsyncSerialExecutor()
    private var presenceGrantMutationID: [UUID: UUID] = [:]
    private var pendingPresenceGrants: [UUID: PendingPresenceGrant] = [:]
    private var circleRefreshSequence: UInt64 = 0
    private var lastSuccessfulCircleRefreshSequence: UInt64 = 0
    private var confirmedCircleMutationBarrier = TrustCircleRefreshBarrier()
    private var ageUpdateWasInterrupted = false
    private var ageAccessState = TrustAgeAccessState()
    private var isSceneActive = true

    private func isCurrentAccount(generation: UInt64, token: String) -> Bool {
        TrustAccountOperation(token: token, generation: generation)
            .matches(token: auth.sessionToken, generation: accountGeneration)
    }

    private func currentAccountOperation() -> TrustAccountOperation? {
        guard canAccessAccountData, auth.isAuthenticated, let token = auth.sessionToken else { return nil }
        return TrustAccountOperation(token: token, generation: accountGeneration)
    }

    private func isCurrentAccount(operation: TrustAccountOperation) -> Bool {
        operation.matches(token: auth.sessionToken, generation: accountGeneration)
    }

    private func beginAccountSessionTransition(to token: String) {
        guard auth.sessionToken != token else { return }
        isAppTransactionLinked = false
        let previousAccountID = TrustSessionIdentity.accountID(from: auth.sessionToken)
        let nextAccountID = TrustSessionIdentity.accountID(from: token)
        let accountChanged = previousAccountID == nil || nextAccountID == nil || previousAccountID != nextAccountID
        ageAssurance.invalidatePendingUpdate()
        ageUpdateQuestion = nil
        let preservePendingInvite = auth.sessionToken == nil
        ageUnavailableStopAllState = .idle
        accountGeneration &+= 1
        cancelPendingPhoneSend()
        authenticatedPerson = nil
        phoneRetryAccountID = nil
        phoneRetry = TrustPhoneRetryState()
        lastRefreshAttemptAt = nil
        setAccountDataScope(nil)
        if accountChanged {
            client.clearCache()
            snapshot = nil
            openedSnapshots = [:]
            openedSnapshotConnectionIDs = [:]
            for id in Array(pendingLookRequests.keys) {
                pendingLookRequests[id]?.validity.invalidate()
            }
            pendingLookRequests = [:]
            historyByPerson = [:]
            historyLoadingIDs = []
            historyLoadedIDs = []
            historyErrors = []
            historyFetchedAt = [:]
            historyConnectionIDs = [:]
            historyRequestIDs = [:]
            historyRequestConnectionIDs = [:]
            lookSubject = nil
            isLooking = false
            circlePath = []
            selectedTab = .circle
            isOffline = false
        }
        pendingHomePresenceMutationID = nil
        presenceOverride = nil
        resetConnectionAndInviteState(preservingPendingInvite: preservePendingInvite)
    }

    private func setAccountDataScope(_ accountID: String?) {
        location.setHomeAccountScope(accountID)
        ingestStore.setAccountScope(accountID)
    }

    private func recordConfirmedCircleMutation() {
        confirmedCircleMutationBarrier.recordConfirmedMutation()
    }

    private func beginShareMutation(connectionID: UUID?) {
        guard let connectionID else { return }
        shareMutationGate.begin(connectionID: connectionID)
        updatingShareConnectionIDs = shareMutationGate.updatingConnectionIDs
    }

    private func finishShareMutation(connectionID: UUID?) {
        guard let connectionID else { return }
        shareMutationGate.finish(connectionID: connectionID)
        updatingShareConnectionIDs = shareMutationGate.updatingConnectionIDs
    }

    func isUpdatingShare(personID: UUID) -> Bool {
        guard let connectionID = member(personID)?.connectionID else { return false }
        return updatingShareConnectionIDs.contains(connectionID)
    }

    private func resetConnectionAndInviteState(preservingPendingInvite: Bool = false) {
        let pendingInviteCode = preservingPendingInvite ? linkedInviteCode : nil
        let pendingInviteDraft = preservingPendingInvite ? inviteCodeDraft : ""
        connectionLookupGeneration &+= 1
        inviteNotice = nil
        inviteCodeDraft = ""
        linkedInviteCode = nil
        phoneInviteCode = nil
        isJoining = false
        showingAddPersonSheet = false
        connectionHandleDraft = ""
        connectionLookup = nil
        isLookingUpConnection = false
        isSendingConnectionRequest = false
        connectionLookupNotice = nil
        connectionLookupHint = nil
        connectionLookupIsNoMatch = false
        connectionLookupCanInvite = false
        inviteShareText = nil
        isPreparingConnectionInvite = false
        isUpdatingDiscovery = false
        connectionRequiresPhoneVerification = false
        connectionRequests = ConnectionRequestsPayload(incoming: [], sent: [])
        isLoadingConnectionRequests = false
        connectionRequestsNotice = nil
        connectionRequestsRefreshQueued = false
        actingOnConnectionRequestIDs = []
        canReturnFromPhoneVerification = false
        if let pendingInviteCode {
            linkedInviteCode = pendingInviteCode
            inviteCodeDraft = pendingInviteCode
        } else if preservingPendingInvite {
            inviteCodeDraft = pendingInviteDraft
        }
    }

    @Published var onboardingHandle = ""
    @Published var onboardingDiscoveryEnabled = false
    @Published var onboardingNotice: String?
    @Published var handleAvailability: Bool?
    @Published var isOnboardingBusy = false
    private var handleCheckTask: Task<Void, Never>?
    private var demo: DemoTrustService?
    private var demoTickTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var homeFixRequestState = TrustHomeFixRequestState()
    private var lastRefreshAttemptAt: Date?
    private var refreshQueued = false
    private var queuedRefreshEntersHome = false
    private var queuedRefreshFallback: Bool?
    private var refreshTask: Task<Void, Never>?

    private var cancellables: Set<AnyCancellable> = []

    var authNotice: String? { auth.notice }

    var canTryAppleAgeRangeAfterUnderage: Bool {
        ageAssurance.canTryAppleAgeRangeAfterUnderage
    }

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
        guard let session = openedSnapshots[id] else { return nil }
        if isDemoMode { return session }
        guard let current = member(id),
              openedSnapshotConnectionIDs[id] == current.connectionID,
              current.inboundPresentation?.isOff != true else { return nil }
        return session
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
        ageAssurance = AgeAssuranceCoordinator()
        store = StoreManager()
        location = LocationCoordinator()
        receipts = LookReceiptNotifier()
        LookReceiptNotifier.shared = receipts
        ingestStore = LocationIngestStore()
        client.token = auth.sessionToken
        #if DEBUG
        // Demo is opt-in only. When requested, hold on Login until start() seeds the
        // fixture so Circle never paints empty; otherwise Debug behaves exactly like Release.
        phase = Self.debugDemoRequested(sessionToken: auth.sessionToken) ? .login : .ageChecking
        #else
        phase = .ageChecking
        #endif
        client.onConsentRevoked = { [weak self] in
            self?.handleConsentRevocation()
        }
        client.onPrivacyHoldDetected = { [weak self] in
            self?.handleServerPrivacyHold()
        }
        ageAssurance.onAppleAccountChanged = { [weak self] in
            self?.handleAppleAccountChange()
        }
        receipts.onNotificationTap = { [weak self] destination in
            self?.pendingPushDestination = destination
        }
        bind()
    }

    func consumePendingPushDestination() -> TrustPushDestination? {
        guard phase == .home, let destination = pendingPushDestination else { return nil }
        pendingPushDestination = nil
        return destination
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
        beginObservingAgeUpdateResponses()
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        if isUITestLaunch, env["TRUST_UI_TEST_RESET_AUTH"] == "1" {
            // Paired account tests run repeatedly on shared simulators. Do not let a
            // previous test identity or its cached circle bypass fresh onboarding.
            // Keep the simulator's age fixture: this test resets the account, not
            // the separate age-assurance state machine.
            auth.signOut()
            client.token = nil
            client.clearCache()
            snapshot = nil
            setAccountDataScope(nil)
        }
        if env["TRUST_AGE_TEST_MODE"] == "1", env["TRUST_AGE_TEST_RESET_AUTH"] == "1" {
            // Age-gate UI fixtures run repeatedly on shared simulators. Clear only
            // this explicit debug fixture's prior Trust session before the durable
            // privacy-hold restoration check can intercept the test screen.
            auth.signOut()
            client.token = nil
        }
        if env["TRUST_AGE_TEST_MODE"] == "1", env["TRUST_AGE_TEST_AUTHENTICATED"] == "1" {
            auth.prepareAgeGateUITestSession(token: env["TRUST_AGE_TEST_SESSION_TOKEN"])
        }
#endif
        if auth.isCurrentSessionPrivacyHeld {
            client.token = auth.sessionToken
            isAgeAccessAllowed = false
            phase = .agePrivacyHeld
            return
        }
#if DEBUG
        if env["TRUST_AGE_TEST_MODE"] == "1",
           env["TRUST_AGE_TEST_APP_TRANSACTION_UNAVAILABLE"] == "1",
           auth.isAuthenticated {
            ageAccessState.setAllowedOutsideEvaluation(true)
            isAgeAccessAllowed = true
            client.token = auth.sessionToken
            _ = await registerCurrentAppTransactionForConsentRevocation()
            return
        }
        if env["TRUST_AGE_TEST_MODE"] == "1" {
            if env["TRUST_AGE_TEST_UNAVAILABLE"] == "1" {
                ageAccessState.setAllowedOutsideEvaluation(false)
                isAgeAccessAllowed = false
                phase = .ageCheckUnavailable
                return
            }
            if env["TRUST_AGE_TEST_CONSENT_REVOKED"] == "1" {
                isAgeAccessAllowed = false
                phase = .ageConsentRevoked
                return
            }
            if env["TRUST_AGE_TEST_PRIVACY_HELD"] == "1" {
                ageAccessState.setAllowedOutsideEvaluation(false)
                isAgeAccessAllowed = false
                phase = .agePrivacyHeld
                return
            }
            if env["TRUST_AGE_TEST_RESET_STATE"] == "1" {
                ageAssurance.resetAgeGateForDebugTest()
            } else if env["TRUST_AGE_TEST_RESET_PREFERENCES_ONLY"] == "1" {
                // Simulate a reinstall clearing app preferences while the device-only
                // Keychain age block remains in place.
                ageAssurance.resetAgeGatePreferencesForDebugTest()
            }
            switch ageAssurance.evaluateLocalAttestationForDebugTest() {
            case .permitted:
                ageAccessState.setAllowedOutsideEvaluation(true)
                isAgeAccessAllowed = true
                await continueAfterAgeGate()
            case .selfAttestationRequired:
                isAgeAccessAllowed = false
                phase = .ageGate
            case .underMinimumAge:
                isAgeAccessAllowed = false
                ageAssurance.resetAccountAttestations()
                clearAccountSession()
                phase = .ageBlocked
            case .ageRangeBelowMinimum:
                handleAppleAgeRangeRestriction()
            case .ageRangeSharingDeclined:
                phase = .ageRangeSharingDeclined
            case .parentApprovalRequired, .parentApprovalDenied, .unavailable:
                isAgeAccessAllowed = false
                phase = .ageCheckUnavailable
            }
            return
        }
        if isUITestLaunch || env["TRUST_DEV_SESSION"] == "1" || Self.debugDemoRequested(sessionToken: auth.sessionToken) {
            ageAccessState.setAllowedOutsideEvaluation(true)
            isAgeAccessAllowed = true
            await continueAfterAgeGate()
            return
        }
        #endif

        await checkAgeAndContinue()
    }

    private func continueAfterAgeGate(retryAppTransaction: Bool = false) async {
        let authorizationGeneration = ageAccessState.generation
        guard hasCurrentAgeAuthorization(generation: authorizationGeneration) else { return }
        await client.prepare()
        guard hasCurrentAgeAuthorization(generation: authorizationGeneration) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["TRUST_DEV_SESSION"] == "1" {
            await signInWithLocalAPI()
            guard hasCurrentAgeAuthorization(generation: authorizationGeneration) else { return }
            await store.loadProducts()
            guard hasCurrentAgeAuthorization(generation: authorizationGeneration) else { return }
            applyScreenshotLaunch()
            return
        }
        if Self.debugDemoRequested(sessionToken: auth.sessionToken) {
            enterDemo()
            await store.loadProducts()
            guard hasCurrentAgeAuthorization(generation: authorizationGeneration) else { return }
            applyScreenshotLaunch()
            return
        }
        #endif
        if auth.isAuthenticated {
            isAppTransactionLinked = false
            isAgeAccessAllowed = false
            phase = .appTransactionChecking
        }
        let restoredCredentialInvalidated = await auth.validateRestoredAppleCredential()
        guard hasCurrentAgeAuthorization(generation: authorizationGeneration) else { return }
        if restoredCredentialInvalidated {
            clearAccountSession()
        }
        client.token = auth.sessionToken
        if auth.isAuthenticated {
            guard await registerCurrentAppTransactionForConsentRevocation(retryRequested: retryAppTransaction) else { return }
            guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
            if !isDemoMode,
               let accountID = TrustSessionIdentity.accountID(from: auth.sessionToken),
               let cached = client.cachedCircle(forAccountID: accountID) {
                setAccountDataScope(cached.you.id.uuidString.lowercased())
                snapshot = cached
                phase = Self.phase(for: cached.you)
            }
            await refresh(enterHome: true)
            guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
        } else {
            isAgeAccessAllowed = true
            phase = .login
            if let warning = client.reachabilityNotice {
                auth.notice = warning
            }
        }
        await store.loadProducts()
        guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
        receipts.prepare(client: client)
        _ = await store.refreshEntitlement()
        guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
        if auth.isAuthenticated {
            await refreshStoreKitToken()
            guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
            await syncCircleEntitlement()
            guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
        }
        receipts.refreshStatus()
        UIDevice.current.isBatteryMonitoringEnabled = true
        if phase == .home, !circle.isEmpty, !isUITestLaunch, ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] == nil {
            await receipts.requestPermission()
            guard canContinueAgeAuthorizedFlow(generation: authorizationGeneration) else { return }
        }
        applyScreenshotLaunch()
    }

    private func checkAgeAndContinue(forceAppleAgeRange: Bool = false) async {
        let evaluationGeneration = ageAccessState.beginEvaluation()
        isAgeAccessAllowed = false
        ageGateBlockedByParent = false
        phase = .ageChecking
        let decision = await ageAssurance.evaluate(
            forceAppleAgeRange: forceAppleAgeRange,
            isCurrent: { [weak self] in
                self?.ageAccessState.isCurrentEvaluation(evaluationGeneration) == true
            }
        )
        guard ageAccessState.isCurrentEvaluation(evaluationGeneration) else { return }
        switch decision {
        case .permitted:
            guard ageAccessState.completeEvaluation(evaluationGeneration, permitted: true) else { return }
            isAgeAccessAllowed = true
            ageUpdateQuestion = nil
            await continueAfterAgeGate()
        case .selfAttestationRequired:
            phase = .ageGate
        case .underMinimumAge:
            ageAssurance.resetAccountAttestations()
            clearAccountSession()
            phase = .ageBlocked
        case .ageRangeBelowMinimum:
            handleAppleAgeRangeRestriction()
        case .ageRangeSharingDeclined:
            phase = .ageRangeSharingDeclined
        case .parentApprovalRequired:
            if #available(iOS 26.2, *) {
                ageUpdateQuestion = ageAssurance.updateQuestion()
            }
            phase = .ageWaitingForParent
        case .parentApprovalDenied:
            clearAccountSession()
            ageGateBlockedByParent = true
            phase = .ageBlocked
        case .unavailable:
            phase = .ageCheckUnavailable
        }
    }

    /// Links the authenticated Trust account to Apple's app transaction before loading
    /// account data. The server needs this link to apply a later RESCIND_CONSENT event.
    private func registerCurrentAppTransactionForConsentRevocation(retryRequested: Bool = false) async -> Bool {
        guard auth.isAuthenticated, !isDemoMode else { return true }
        guard ageAccessState.isAllowed,
              let token = auth.sessionToken else { return false }
        let ageAuthorizationGeneration = ageAccessState.generation
        let operation = TrustAccountOperation(token: token, generation: accountGeneration)
        let transactionAuthorization = TrustAppTransactionAuthorization(
            accountOperation: operation,
            ageAuthorizationGeneration: ageAuthorizationGeneration
        )
        isAppTransactionLinked = false
        isAgeAccessAllowed = false
        phase = .appTransactionChecking
        do {
            try await client.registerCurrentAppTransaction(
                authorizedToken: operation.token,
                retryRequested: retryRequested
            ) { [weak self] in
                guard let self else { return false }
                return transactionAuthorization.permitsRegistration(
                    currentAccountToken: self.auth.sessionToken,
                    currentAccountGeneration: self.accountGeneration,
                    ageIsAuthorized: self.ageAccessState.isAllowed,
                    currentAgeAuthorizationGeneration: self.ageAccessState.generation
                )
            }
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            isAppTransactionLinked = true
            isAgeAccessAllowed = true
            return true
        } catch let error as TrustClientError where TrustAgePolicy.isConsentRevocationResponse(apiCode: error.apiCode) {
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            handleConsentRevocation()
            return false
        } catch let error as TrustClientError where error.apiCode == "account_privacy_hold" {
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            privacyHoldSubmission.beginSubmission(for: operation)
            _ = privacyHoldSubmission.acknowledge(
                operation: operation,
                currentToken: auth.sessionToken,
                generation: accountGeneration)
            handleAcknowledgedPrivacyHold()
            return false
        } catch TrustClientError.appTransactionVerificationUnavailable {
            ageAssuranceLogger.error("Apple app transaction verification was unavailable.")
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            phase = .appTransactionUnavailable
            return false
        } catch TrustClientError.appTransactionUnverified {
            ageAssuranceLogger.error("Apple returned an unverified app transaction.")
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            phase = .appTransactionUnavailable
            return false
        } catch is CancellationError {
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            phase = .appTransactionUnavailable
            return false
        } catch {
            ageAssuranceLogger.error("App transaction server registration failed.")
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration),
                  hasCurrentAgeAuthorization(generation: ageAuthorizationGeneration) else { return false }
            phase = .appTransactionUnavailable
            return false
        }
    }

    private func hasCurrentAgeAuthorization(generation: UInt64) -> Bool {
        ageAccessState.isAllowed && ageAccessState.isCurrentEvaluation(generation)
    }

    private func canContinueAgeAuthorizedFlow(generation: UInt64) -> Bool {
        isAgeAccessAllowed
            && hasCurrentAgeAuthorization(generation: generation)
    }

    private func handleConsentRevocation() {
        guard auth.isAuthenticated else { return }
        clearPrivatePhoneRetry()
        clearAccountSession()
        isAgeAccessAllowed = false
        ageGateBlockedByParent = false
        ageUpdateQuestion = nil
        phase = .ageConsentRevoked
    }

    private func handleAppleAgeRangeRestriction() {
        ageAssurance.resetAccountAttestations()
        _ = ageAccessState.beginEvaluation()
        isAgeAccessAllowed = false
        clearAccountDataForLocalPrivacyHold()

        guard auth.isAuthenticated, let token = auth.sessionToken else {
            clearAccountSession()
            privacyHoldSubmission.restrictLocally()
            phase = .ageRangeBlocked
            return
        }

        client.token = token
        let operation = TrustAccountOperation(token: token, generation: accountGeneration)
        pendingPrivacyHoldOperation = operation
        privacyHoldSubmission.beginSubmission(for: operation)
        phase = .agePrivacyHoldPending
        Task { await submitAccountPrivacyHold(operation) }
    }

    /// Stop location, ingest, snapshots and cached account data synchronously before
    /// starting network I/O. The retained bearer token is used only to submit this hold.
    private func clearAccountDataForLocalPrivacyHold() {
        ageUnavailableStopAllState = .idle
        accountGeneration &+= 1
        client.clearCache()
        snapshot = nil
        pendingPushDestination = nil
        setAccountDataScope(nil)
        openedSnapshots = [:]
        openedSnapshotConnectionIDs = [:]
        pendingLookRequests = [:]
        historyByPerson = [:]
        historyLoadingIDs = []
        historyLoadedIDs = []
        historyErrors = []
        historyFetchedAt = [:]
        historyConnectionIDs = [:]
        historyRequestIDs = [:]
        historyRequestConnectionIDs = [:]
        homeFixRequestState.cancel()
        isSettingHome = false
        circlePath = []
        showingViewLog = false
        lookSubject = nil
        isLooking = false
        ingestFlushTask?.cancel()
        ingestFlushTask = nil
        isFlushingIngest = false
    }

    private func submitAccountPrivacyHold(_ operation: TrustAccountOperation) async {
        guard pendingPrivacyHoldOperation == operation,
              operation.matches(token: auth.sessionToken, generation: accountGeneration) else { return }
        privacyHoldSubmission.beginSubmission(for: operation)
        do {
            try await client.reportCurrentAccountAgePrivacyHold(authorizedToken: operation.token) { [weak self] in
                guard let self else { return false }
                return operation.authorizationToken(currentToken: self.auth.sessionToken, generation: self.accountGeneration) != nil
            }
            guard privacyHoldSubmission.acknowledge(
                operation: operation,
                currentToken: auth.sessionToken,
                generation: accountGeneration) else { return }
            pendingPrivacyHoldOperation = nil
            handleAcknowledgedPrivacyHold()
        } catch is CancellationError {
            return
        } catch {
            guard privacyHoldSubmission.failSubmission(
                operation: operation,
                currentToken: auth.sessionToken,
                generation: accountGeneration) else { return }
            phase = .agePrivacyHoldPending
        }
    }

    private func handleAcknowledgedPrivacyHold() {
        // Keep only the existing session credential so the person can invoke the
        // server's explicitly allowed account-deletion endpoint. The age/privacy
        // phase keeps the normal app surface inaccessible, and the API rejects all
        // other operations while this account remains held.
        auth.markCurrentSessionPrivacyHeld()
        clearPrivatePhoneRetry()
        clearAccountSession(preservingPrivacyHoldDeletionSession: true)
        isAgeAccessAllowed = false
        ageGateBlockedByParent = false
        phase = .agePrivacyHeld
    }

    /// A 423 is authoritative evidence that this active Trust account is already held
    /// (for example, from a second device). Wipe locally before the request's caller
    /// can enter generic offline/error handling or restore a cached circle.
    private func handleServerPrivacyHold() {
        guard let token = auth.sessionToken else { return }
        let operation = TrustAccountOperation(token: token, generation: accountGeneration)
        privacyHoldSubmission.beginSubmission(for: operation)
        guard privacyHoldSubmission.acknowledge(
            operation: operation,
            currentToken: auth.sessionToken,
            generation: accountGeneration) else { return }
        pendingPrivacyHoldOperation = nil
        handleAcknowledgedPrivacyHold()
    }

    var canRetryPrivacyHoldSubmission: Bool {
        phase == .agePrivacyHoldPending && pendingPrivacyHoldOperation != nil
    }

    func retryPrivacyHoldSubmission() {
        guard canRetryPrivacyHoldSubmission, let operation = pendingPrivacyHoldOperation else { return }
        Task { await submitAccountPrivacyHold(operation) }
    }

    func confirmBirthDate(isEligible: Bool) {
        guard phase == .ageGate else { return }
        guard isEligible else {
            ageAssurance.recordUnderMinimumAge(source: .localBirthDate)
            clearAccountSession()
            phase = .ageBlocked
            return
        }
        ageAssurance.recordSelfAttestation()
        ageAccessState.setAllowedOutsideEvaluation(true)
        isAgeAccessAllowed = true
        ageGateBlockedByParent = false
        Task { await continueAfterAgeGate() }
    }

    func retryAgeCheck() {
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["TRUST_AGE_TEST_MODE"] == "1", env["TRUST_AGE_TEST_RECHECK_UNAVAILABLE"] == "1" {
            phase = .ageChecking
            phase = .ageCheckUnavailable
            return
        }
        if env["TRUST_AGE_TEST_MODE"] == "1", env["TRUST_AGE_TEST_RECHECK_DECLINED"] == "1" {
            phase = .ageChecking
            phase = .ageRangeSharingDeclined
            return
        }
#endif
        Task { await checkAgeAndContinue(forceAppleAgeRange: canTryAppleAgeRangeAfterUnderage) }
    }

    func retryAppTransactionRegistration() {
        guard phase == .appTransactionUnavailable,
              auth.isAuthenticated,
              ageAccessState.isAllowed else { return }
        phase = .appTransactionChecking
        Task { [weak self] in
            guard let self else { return }
#if DEBUG
            if ProcessInfo.processInfo.environment["TRUST_AGE_TEST_MODE"] == "1",
               ProcessInfo.processInfo.environment["TRUST_AGE_TEST_APP_TRANSACTION_UNAVAILABLE"] == "1" {
                self.client.token = self.auth.sessionToken
                _ = await self.registerCurrentAppTransactionForConsentRevocation()
                return
            }
#endif
            await self.continueAfterAgeGate(retryAppTransaction: true)
        }
    }

    private static func isUnavailableVerificationPhase(_ phase: AppPhase) -> Bool {
        // Declining age-range disclosure must not require consent just to revoke
        // existing sharing. This enables only the confirmed restrictive action;
        // ageAccessState and account-feature authorization remain unchanged.
        phase == .ageCheckUnavailable || phase == .appTransactionUnavailable || phase == .ageRangeSharingDeclined
    }

    var canStopAllFromUnavailableVerification: Bool {
        Self.isUnavailableVerificationPhase(phase) && auth.isAuthenticated && auth.sessionToken != nil
    }

    func requestAgeUnavailableStopAll() {
        guard canStopAllFromUnavailableVerification,
              ageUnavailableStopAllState == .idle || ageUnavailableStopAllState.isError else { return }
        ageUnavailableStopAllState = .confirming
    }

    func cancelAgeUnavailableStopAll() {
        guard ageUnavailableStopAllState == .confirming else { return }
        ageUnavailableStopAllState = .idle
    }

    func confirmAgeUnavailableStopAll() {
        guard ageUnavailableStopAllState == .confirming,
              Self.isUnavailableVerificationPhase(phase),
              let token = auth.sessionToken else { return }
        let operation = TrustAccountOperation(token: token, generation: accountGeneration)
        client.token = operation.token
        ageUnavailableStopAllState = .pending
        Task { [weak self] in
            guard let self,
                  operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration),
                  Self.isUnavailableVerificationPhase(self.phase) else { return }
#if DEBUG
            if ProcessInfo.processInfo.environment["TRUST_AGE_TEST_STOP_ALL_HOLD"] == "1" {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                return
            }
            if ProcessInfo.processInfo.environment["TRUST_AGE_TEST_STOP_ALL_SUCCESS"] == "1" {
                self.ageUnavailableStopAllState = .success
                return
            }
            if ProcessInfo.processInfo.environment["TRUST_AGE_TEST_ACCOUNT_CHANGE_ON_STOP"] == "1" {
                self.handleAppleAccountChange(isForeground: false)
                return
            }
#endif
            do {
                try await self.client.stopAllSharing(authorizedToken: operation.token) { [weak self] in
                    guard let self else { return false }
                    return operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration)
                }
                guard operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration),
                      Self.isUnavailableVerificationPhase(self.phase) else { return }
                self.ageUnavailableStopAllState = .success
            } catch is CancellationError {
                return
            } catch {
                guard operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration),
                      Self.isUnavailableVerificationPhase(self.phase) else { return }
                self.ageUnavailableStopAllState = .error(self.plainMessage(for: error))
            }
        }
    }

    func retryAppleAgeRangeAfterUnderage() {
        guard phase == .ageBlocked || phase == .ageRangeBlocked,
              !ageGateBlockedByParent,
              canTryAppleAgeRangeAfterUnderage else { return }
        Task { await checkAgeAndContinue(forceAppleAgeRange: true) }
    }

    func retryParentApproval() {
        guard phase == .ageBlocked, ageGateBlockedByParent else { return }
        Task { await checkAgeAndContinue() }
    }

    private func beginObservingAgeUpdateResponses() {
        guard #available(iOS 26.2, *), ageUpdateResponseTask == nil else { return }
        ageUpdateResponseTask = Task { [weak self] in
            for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self) {
                guard !Task.isCancelled, let self else { return }
                await self.handleAgeUpdateResponse(response)
            }
        }
    }

    @available(iOS 26.2, *)
    private func handleAgeUpdateResponse(_ response: PermissionResponse<SignificantAppUpdateTopic>) async {
        guard let result = ageAssurance.handle(response) else { return }
        ageUpdateQuestion = nil
        switch result {
        case .approved:
            ageGateBlockedByParent = false
            ageUpdateWasInterrupted = false
            phase = .ageChecking
            // The approval satisfies this significant update only. Re-evaluate
            // Apple's current age and regulatory signals before reopening the
            // authenticated app or restoring location access.
            Task { await checkAgeAndContinue() }
        case .denied:
            clearAccountSession()
            ageGateBlockedByParent = true
            phase = .ageBlocked
        case .persistenceUnavailable:
            isAgeAccessAllowed = false
            phase = .ageCheckUnavailable
        }
    }

    func ageUpdateSceneDidEnterBackground() {
        guard phase == .ageWaitingForParent else { return }
        ageUpdateWasInterrupted = true
        phase = .ageCheckUnavailable
    }

    func ageUpdateSceneDidBecomeActive() {
        #if DEBUG
        // Explicit debug UI lanes use deterministic age fixtures. Do not turn a
        // simulator foreground transition into a live Apple age-service request.
        if isUITestLaunch || ProcessInfo.processInfo.environment["TRUST_AGE_TEST_MODE"] == "1" { return }
        #endif
        if ageAccessState.consumeForegroundRecheck() {
            Task { await checkAgeAndContinue() }
            return
        }
        if ageUpdateWasInterrupted {
            ageUpdateWasInterrupted = false
            Task { await checkAgeAndContinue() }
            return
        }
        guard phase != .ageChecking, isAgeAccessAllowed else { return }
        handleAppleAccountChange(isForeground: true)
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        location.setAppActive(active && isAgeAccessAllowed)
    }

    private func handleAppleAccountChange(isForeground foregroundHint: Bool? = nil) {
#if DEBUG
        // Explicit debug UI lanes model age/account state deterministically. Ignore
        // incidental simulator/iCloud notifications so they cannot replace a test
        // fixture with an Apple live-service request during the run.
        let ageTestAccountChange = ProcessInfo.processInfo.environment["TRUST_AGE_TEST_ACCOUNT_CHANGE_ON_STOP"] == "1"
        if isUITestLaunch || (ProcessInfo.processInfo.environment["TRUST_AGE_TEST_MODE"] == "1" && !ageTestAccountChange) { return }
#endif
        guard isAgeAccessAllowed
            || phase == .ageChecking
            || phase == .ageWaitingForParent
            || phase == .ageCheckUnavailable
            || phase == .ageRangeSharingDeclined
            || phase == .ageRangeBlocked
            || phase == .appTransactionChecking
            || phase == .appTransactionUnavailable else { return }
        let isForeground = foregroundHint ?? (UIApplication.shared.applicationState == .active)
        _ = ageAccessState.suspendForAppleAccountChange(isForeground: isForeground)
        isAgeAccessAllowed = false
        ageAssurance.resetPersonScopedStateForAppleAccountChange()
        ageUpdateQuestion = nil
        ageUnavailableStopAllState = .idle
        accountGeneration &+= 1
        lastRefreshAttemptAt = nil
        connectionLookupGeneration &+= 1
        connectionLookupTask?.cancel()
        connectionLookupDebounceTask?.cancel()
        location.setHomeMonitoring(false)
        phase = .ageChecking
        if isForeground {
            Task { await checkAgeAndContinue() }
        }
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
            if let demo,
               let sealed = circle.first(where: \.isSealed),
               let session = try? demo.look(confirmed: true, subjectID: sealed.id) {
                openedSnapshots[sealed.id] = session
                openedSnapshotConnectionIDs[sealed.id] = nil
                publishDemoSnapshot()
            }
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
            if let member = circle.first(where: \.isAvailable) ?? circle.first {
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
            if let demo,
               let mayaID = demo.members.first(where: { $0.displayName == "Maya Chen" })?.id,
               let leoID = demo.members.first(where: { $0.displayName == "Leo Park" })?.id {
                _ = try? demo.look(confirmed: true, subjectID: mayaID)
                _ = try? demo.view(subjectID: leoID)
                publishDemoSnapshot()
            }
            selectedTab = .log
        case "share":
            guard auth.isAuthenticated else { return }
            selectedTab = .sharing
        case "you", "settings":
            guard auth.isAuthenticated else { return }
            selectedTab = .you
        case "map":
            guard auth.isAuthenticated else { return }
            // Show a real one-time pin in the offline listing fixture. A fresh
            // Free demo has no live pins until a person is explicitly looked at.
            if let demo,
               let sealed = circle.first(where: \.isSealed),
               let session = try? demo.look(confirmed: true, subjectID: sealed.id) {
                openedSnapshots[sealed.id] = session
                openedSnapshotConnectionIDs[sealed.id] = nil
                publishDemoSnapshot()
            }
            openMap()
        case "invite":
            guard auth.isAuthenticated else { return }
            selectedTab = .sharing
            // The invite route now opens the handle-first Add sheet. It never creates
            // a request or invite as a side effect of a screenshot route.
            showingAddPersonSheet = true
        case "lookup":
            guard auth.isAuthenticated else { return }
            selectedTab = .sharing
            connectionHandleDraft = "+1 (202) 555-0134"
            connectionLookup = PersonLookupPayload(
                accountId: UUID(),
                handle: "morganlee",
                relationship: "none",
                avatar: .preset("fox")
            )
            showingAddPersonSheet = true
        default:
            break
        }
        #endif
    }

    func prepareLogin() async {
        guard isAgeAccessAllowed else { return }
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
        // The App Store View panel demonstrates a Plus viewer opening Leo's live
        // Always location. Keep every other screenshot on the Free fixture.
        if ProcessInfo.processInfo.environment["TRUST_SCREENSHOT"] == "view" {
            service.setPro(enabled: true)
        }
        demo = service
        isDemoMode = true
        beginAccountSessionTransition(to: "demo")
        auth.persist(
            // A login reached from a legacy invite must retain that explicit pending link.
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
        openedSnapshotConnectionIDs = [:]
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
            let deviceId: String
            if isUITestLaunch,
               let testDeviceID = ProcessInfo.processInfo.environment["TRUST_UI_TEST_DEVICE_ID"],
               !testDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deviceId = testDeviceID
            } else {
                deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "trust-debug-simulator"
            }
            let testDisplayName = isUITestLaunch
                ? ProcessInfo.processInfo.environment["TRUST_UI_TEST_DISPLAY_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let session = try await client.developmentSession(
                displayName: testDisplayName?.isEmpty == false ? testDisplayName! : "Dev",
                deviceId: deviceId
            )
            beginAccountSessionTransition(to: client.token ?? "")
            auth.persist(
                account: AuthAccount(
                    provider: .apple,
                    displayName: session.you.displayName,
                    appleUserID: nil
                ),
                token: client.token ?? ""
            )
            if session.you.onboardingComplete != true,
               session.you.handle == nil,
               !isUITestLaunch {
                try await claimDebugHandle(deviceId: deviceId)
            }
            authenticatedPerson = session.you.model
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
        guard isAgeAccessAllowed else {
            await checkAgeAndContinue()
            return
        }
        guard !isSigningIn else { return }
        let ageAuthorizationGeneration = ageAccessState.generation
        let accountGenerationAtStart = accountGeneration
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            switch provider {
            case .apple:
                let apple = try await auth.signInWithApple()
                guard canContinueSignIn(
                    ageAuthorizationGeneration: ageAuthorizationGeneration,
                    accountGenerationAtStart: accountGenerationAtStart
                ) else { return }
                await client.prepare()
                guard canContinueSignIn(
                    ageAuthorizationGeneration: ageAuthorizationGeneration,
                    accountGenerationAtStart: accountGenerationAtStart
                ) else { return }
                let session = try await client.appleSession(
                    identityToken: apple.identityToken,
                    displayName: apple.displayName,
                    nonce: apple.nonce
                )
                guard canContinueSignIn(
                    ageAuthorizationGeneration: ageAuthorizationGeneration,
                    accountGenerationAtStart: accountGenerationAtStart
                ) else {
                    client.token = nil
                    client.clearCache()
                    return
                }
                beginAccountSessionTransition(to: client.token ?? "")
                auth.persist(
                    account: AuthAccount(
                        provider: .apple,
                        displayName: apple.displayName ?? session.you.displayName,
                        appleUserID: apple.userID
                    ),
                    token: client.token ?? ""
                )
                authenticatedPerson = session.you.model
                guard await registerCurrentAppTransactionForConsentRevocation() else { return }
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

    private func canContinueSignIn(
        ageAuthorizationGeneration: UInt64,
        accountGenerationAtStart: UInt64
    ) -> Bool {
        isAgeAccessAllowed
            && ageAccessState.isAllowed
            && ageAccessState.isCurrentEvaluation(ageAuthorizationGeneration)
            && accountGeneration == accountGenerationAtStart
    }

    func signOut() {
        clearAccountSession()
        ageAssurance.resetAccountAttestations()
        ageUpdateQuestion = nil
        isAgeAccessAllowed = false
        ageGateBlockedByParent = false
        Task { await checkAgeAndContinue() }
    }

    private func clearAccountSession(preservingPrivacyHoldDeletionSession: Bool = false) {
        let pushRemovalToken = client.token ?? auth.sessionToken
        authenticatedPerson = nil
        phoneRetryAccountID = nil
        phoneRetry = TrustPhoneRetryState()
        accountGeneration &+= 1
        isAppTransactionLinked = false
        ageUnavailableStopAllState = .idle
        ageAssurance.resetAccountAttestations()
        Task { await receipts.unregister(authorizedToken: pushRemovalToken) }
        store.clearAfterSignOut()
        if preservingPrivacyHoldDeletionSession {
            client.token = auth.sessionToken
        } else {
            auth.signOut()
            client.token = nil
        }
        client.clearCache()
        stopDemo()
        snapshot = nil
        pendingPushDestination = nil
        setAccountDataScope(nil)
        openedSnapshots = [:]
        openedSnapshotConnectionIDs = [:]
        pendingLookRequests = [:]
        historyByPerson = [:]
        historyLoadingIDs = []
        historyLoadedIDs = []
        historyErrors = []
        historyFetchedAt = [:]
        historyConnectionIDs = [:]
        historyRequestIDs = [:]
        historyRequestConnectionIDs = [:]
        homeFixRequestState.cancel()
        isSettingHome = false
        pendingHomePresenceMutationID = nil
        presenceOverride = nil
        updatingPresenceGrantIDs = []
        presenceGrantMutationID = [:]
        pendingPresenceGrants = [:]
        updatingShareConnectionIDs = []
        shareMutationGate = TrustShareMutationGate()
        circleRefreshSequence = 0
        lastSuccessfulCircleRefreshSequence = 0
        isOffline = false
        lastRefreshAttemptAt = nil
        phase = .ageChecking
        selectedTab = .circle
        circlePath = []
        showingViewLog = false
        showingPaywall = false
        showingAlwaysExplainer = false
        lookSubject = nil
        isLooking = false
        resetConnectionAndInviteState()
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
        let deletingHeldAccount = phase == .agePrivacyHoldPending || phase == .agePrivacyHeld
        let deletingToken = auth.sessionToken
        guard !deletingHeldAccount || deletingToken != nil else {
            showToast(TrustCopy.requestFailed)
            return
        }
        do {
            try await client.deleteAccount(authorizedToken: deletingHeldAccount ? deletingToken : nil)
            guard deletingToken == auth.sessionToken else { return }
            accountGeneration &+= 1
            let deletedGeneration = accountGeneration
            cancelPendingPhoneSend()
            clearPrivatePhoneRetry()
            await receipts.unregister(authorizedToken: deletingToken)
            guard deletingToken == auth.sessionToken, accountGeneration == deletedGeneration else { return }
            store.clearAfterSignOut()
            signOut()
        } catch {
            showToast(plainMessage(for: error))
        }
    }

    func saveAvatar(presetID: String) async throws {
        if isDemoMode {
            demo?.setMyAvatar(.preset(presetID))
            publishDemoSnapshot()
            return
        }
        let avatar = try await client.setAvatarPreset(presetID)
        updateLocalAvatar(avatar)
        await refresh()
    }

    func saveAvatarPhoto(_ jpeg: Data) async throws {
        guard !isDemoMode else { throw TrustClientError.server("Profile pictures are unavailable in demo mode.") }
        let avatar = try await client.setAvatarPhoto(jpeg)
        updateLocalAvatar(avatar)
        await refresh()
    }

    func removeAvatar() async throws {
        if isDemoMode {
            demo?.setMyAvatar(nil)
            publishDemoSnapshot()
            return
        }
        try await client.removeAvatar()
        updateLocalAvatar(nil)
        await refresh()
    }

    private func updateLocalAvatar(_ avatar: AvatarDescriptor?) {
        guard var current = snapshot else { return }
        current.you.avatar = avatar
        snapshot = current
        setAccountDataScope(current.you.id.uuidString.lowercased())
        client.snapshot = current
    }

    // MARK: Refresh / offline

    /// Refresh circle and Requests data when returning to a tab or foregrounding,
    /// but avoid a request for every quick tab switch. Returns true when a full
    /// refresh will also cover Requests; false means callers may fetch only Requests.
    @discardableResult
    func refreshIfStale(minimumInterval: TimeInterval = 45) async -> Bool {
        guard phase == .home, auth.isAuthenticated, !isDemoMode else { return false }
        // Freshness-gated lifecycle callers join the in-flight owner without
        // forcing a second pass. Explicit refresh() calls still queue a follow-up
        // pass when a mutation or pull-to-refresh happens during the current one.
        if isRefreshing {
            guard let refreshTask else { return false }
            await refreshTask.value
            return true
        }
        let lastAttempt = lastRefreshAttemptAt ?? snapshot?.fetchedAt
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < minimumInterval { return false }
        await refresh()
        return true
    }

    func refresh(enterHome: Bool = false, fallbackOnboardingComplete: Bool? = nil) async {
        guard canAccessAccountData else { return }
        if isDemoMode {
            publishDemoSnapshot()
            if enterHome { phase = .home }
            return
        }
        if isRefreshing, let refreshTask {
            refreshQueued = true
            queuedRefreshEntersHome = queuedRefreshEntersHome || enterHome
            if fallbackOnboardingComplete != nil {
                queuedRefreshFallback = fallbackOnboardingComplete
            }
            await refreshTask.value
            return
        }

        isRefreshing = true
        // This is deliberately unstructured: Swift task cancellation from a
        // scene-bound caller must not cancel the shared network refresh for every
        // other caller waiting on it.
        let owner = Task { @MainActor [self] in
            await runRefreshOwner(enterHome: enterHome, fallbackOnboardingComplete: fallbackOnboardingComplete)
        }
        refreshTask = owner
        await owner.value
    }

    private func runRefreshOwner(enterHome: Bool, fallbackOnboardingComplete: Bool?) async {
        var nextEntersHome = enterHome
        var nextFallback = fallbackOnboardingComplete
        repeat {
            refreshQueued = false
            queuedRefreshEntersHome = false
            queuedRefreshFallback = nil
            await performRefresh(enterHome: nextEntersHome, fallbackOnboardingComplete: nextFallback)
            // Requests are an independent read, but part of the same refresh
            // completion. Keep ownership until it finishes so concurrent callers
            // cannot have their waiters drained by an older circle read.
            if phase == .home {
                await refreshConnectionRequests()
            }
            nextEntersHome = queuedRefreshEntersHome
            nextFallback = queuedRefreshFallback
        } while refreshQueued

        isRefreshing = false
        refreshTask = nil
    }

    private func performRefresh(enterHome: Bool, fallbackOnboardingComplete: Bool?) async {
        guard canAccessAccountData else { return }
        guard let refreshToken = auth.sessionToken else { return }
        circleRefreshSequence &+= 1
        let refreshSequence = circleRefreshSequence
        let readMutationGeneration = confirmedCircleMutationBarrier.capture()
        let refreshAccountGeneration = accountGeneration
        let operation = TrustAccountOperation(token: refreshToken, generation: refreshAccountGeneration)
        client.token = refreshToken
        lastRefreshAttemptAt = Date()
        do {
            let refreshResult = try await client.refreshCircle(operation: operation) { [weak self] in
                self?.currentAccountOperation()
            }
            guard refreshAccountGeneration == accountGeneration,
                  auth.sessionToken == refreshToken else { return }
            guard confirmedCircleMutationBarrier.permitsCommit(startedAt: readMutationGeneration) else {
                // A successful write completed after this GET began. Discard the
                // old response and immediately reconcile with a read started after it.
                refreshQueued = true
                return
            }
            guard client.commitCircleRefresh(refreshResult, operation: operation, currentOperation: { [weak self] in
                self?.currentAccountOperation()
            }) else { return }
            let fresh = refreshResult.snapshot
            setAccountDataScope(fresh.you.id.uuidString.lowercased())
            snapshot = fresh
            location.reconcileHomePlace(serverPlaceID: fresh.yourHomePlaceID)
            lastSuccessfulCircleRefreshSequence = refreshSequence
            for (personID, pending) in pendingPresenceGrants where pending.preserveOptimisticValue &&
                fresh.members.first(where: { $0.id == personID })?.connectionID == pending.connectionID {
                updateOutboundPresenceGrant(personID: personID, enabled: pending.enabled)
            }
            reconcileInboundLocationData(with: fresh)
            isOffline = false
            if pendingHomePresenceMutationID == nil {
                presenceOverride = nil
            }
            if enterHome || phase == .home || phase == .handle || phase == .phone {
                routeAfterAuth(onboardingComplete: fresh.you.onboardingComplete)
            }
            syncLocationSharing()
            syncHomeMonitoring()
            await flushIngestQueue()
            refreshVisibleHistoryIfStale()
        } catch TrustClientError.unauthorized {
            guard refreshAccountGeneration == accountGeneration,
                  auth.sessionToken == refreshToken else { return }
            signOut()
        } catch is CancellationError {
            return
        } catch let error as TrustClientError where error.isConnectivity {
            guard refreshAccountGeneration == accountGeneration,
                  auth.sessionToken == refreshToken else { return }
            if !confirmedCircleMutationBarrier.permitsCommit(startedAt: readMutationGeneration) {
                refreshQueued = true
            }
            if snapshot == nil,
               let accountID = TrustSessionIdentity.accountID(from: refreshToken),
               let cached = client.cachedCircle(forAccountID: accountID) {
                setAccountDataScope(cached.you.id.uuidString.lowercased())
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
            guard refreshAccountGeneration == accountGeneration,
                  auth.sessionToken == refreshToken else { return }
            if !confirmedCircleMutationBarrier.permitsCommit(startedAt: readMutationGeneration) {
                refreshQueued = true
            }
            showToast(plainMessage(for: error))
            syncLocationSharing()
            if enterHome, auth.isAuthenticated {
                routeAfterAuth(onboardingComplete: fallbackOnboardingComplete ?? snapshot?.you.onboardingComplete ?? false)
            }
        }
    }

    private func reconcileInboundLocationData(with fresh: CircleSnapshot) {
        let members = Dictionary(uniqueKeysWithValues: fresh.members.map { ($0.id, $0) })

        // A Stop observed while Look is in flight permanently invalidates that
        // response. Re-enabling Sealed on the same connection must require a new
        // confirmed Look rather than reviving a response started under old consent.
        for id in Array(pendingLookRequests.keys) {
            let current = members[id]
            guard let request = pendingLookRequests[id],
                  let current,
                  request.connectionID == current.connectionID,
                  current.inboundPresentation?.isOff != true else {
                pendingLookRequests[id]?.validity.invalidate()
                pendingLookRequests[id] = nil
                if lookSubject?.id == id {
                    lookSubject = nil
                    isLooking = false
                }
                continue
            }
        }

        // A stop, removal, or remove/re-add creates a new scope. Old snapshots must
        // not reappear just because their asynchronous Look request finishes later.
        for id in Array(openedSnapshots.keys) {
            guard let member = members[id],
                  openedSnapshotConnectionIDs[id] == member.connectionID,
                  member.inboundPresentation?.isOff != true else {
                openedSnapshots[id] = nil
                openedSnapshotConnectionIDs[id] = nil
                continue
            }
        }

        // History is only available while the current inbound mode is Always. Drop both
        // its rows and load markers when sharing stops or the relationship is replaced.
        let cachedHistoryIDs = Set(historyByPerson.keys)
            .union(historyLoadedIDs)
            .union(historyErrors)
            .union(historyConnectionIDs.keys)
        for id in cachedHistoryIDs {
            let current = members[id]
            let hasCachedResult = historyLoadedIDs.contains(id) || historyByPerson[id] != nil || historyErrors.contains(id)
            let connectionChanged = hasCachedResult && historyConnectionIDs[id] != current?.connectionID
            if current?.isAvailable != true || connectionChanged {
                clearHistoryCache(for: id)
            }
        }

        // A pending history response from a stopped or replaced relationship must
        // lose its request token before it can write into a later relationship.
        for id in Array(historyRequestIDs.keys) {
            let current = members[id]
            guard current?.isAvailable == true,
                  historyRequestConnectionIDs[id] == current?.connectionID else {
                historyRequestIDs[id] = nil
                historyRequestConnectionIDs[id] = nil
                historyLoadingIDs.remove(id)
                continue
            }
        }
    }

    private func clearHistoryCache(for personID: UUID) {
        historyByPerson[personID] = nil
        historyLoadedIDs.remove(personID)
        historyErrors.remove(personID)
        historyFetchedAt[personID] = nil
        historyConnectionIDs[personID] = nil
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

    func showToast(_ message: String, isHomePresence: Bool = false) {
        if isScreenshotLaunch { return }
        toastTask?.cancel()
        toast = TrustToast(message: message, isHomePresence: isHomePresence)
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
        if let id = lookSubject?.id {
            pendingLookRequests[id]?.validity.invalidate()
            pendingLookRequests[id] = nil
        }
        isLooking = false
        lookSubject = nil
    }

    func confirmLook() {
        guard let subject = lookSubject, !isLooking else { return }
        let operation = isDemoMode ? nil : currentAccountOperation()
        guard isDemoMode || operation != nil else { return }
        let currentSubject = member(subject.id)
        let scope = currentSubject.map(TrustRelationshipScope.init)
        guard isDemoMode || (scope?.matches(subject) == true && scope?.permitsLookSnapshot(currentSubject) == true) else {
            lookSubject = nil
            return
        }
        if let currentSubject, currentSubject.isAvailable {
            lookSubject = nil
            openView(currentSubject)
            return
        }
        var validity = TrustRequestValidity()
        let requestID = validity.begin()
        pendingLookRequests[subject.id] = (scope?.connectionID, validity)
        isLooking = true
        Task {
            defer {
                if pendingLookRequests[subject.id]?.validity.accepts(requestID) == true {
                    pendingLookRequests[subject.id] = nil
                    if let operation {
                        if isCurrentAccount(operation: operation) { isLooking = false }
                    } else {
                        isLooking = false
                    }
                }
            }
            do {
                let session: LookSession
                if let demo {
                    session = try demo.look(confirmed: true, subjectID: subject.id)
                    publishDemoSnapshot()
                } else {
                    guard let operation, isCurrentAccount(operation: operation) else { return }
                    session = try await client.look(subjectID: subject.id, confirmed: true, authorizedToken: operation.token)
                    guard isCurrentAccount(operation: operation) else { return }
                    // Re-read relationship consent before retaining or displaying the
                    // delayed response. A peer can Stop or remove this relationship
                    // while the Look request is in flight.
                    await refresh()
                    guard isCurrentAccount(operation: operation),
                          pendingLookRequests[subject.id]?.validity.accepts(requestID) == true else { return }
                    guard scope?.permitsLookSnapshot(member(subject.id)) == true else {
                        pendingLookRequests[subject.id]?.validity.invalidate()
                        pendingLookRequests[subject.id] = nil
                        if lookSubject?.id == subject.id {
                            lookSubject = nil
                            isLooking = false
                        }
                        return
                    }
                }
                openedSnapshots[subject.id] = session
                if isDemoMode {
                    openedSnapshotConnectionIDs[subject.id] = nil
                } else {
                    openedSnapshotConnectionIDs[subject.id] = scope?.connectionID
                }
                if lookSubject?.id == subject.id { lookSubject = nil }
                // Let the sheet finish dismissing before pushing D1 View.
                try? await Task.sleep(for: .milliseconds(320))
                if let operation, !isCurrentAccount(operation: operation) { return }
                guard pendingLookRequests[subject.id]?.validity.accepts(requestID) == true,
                      openedSnapshot(for: subject.id) != nil else { return }
                selectedTab = .circle
                circlePath = [.view(subject.id)]
                showToast(TrustCopy.lookSaved(name: subject.firstName))
            } catch {
                if let operation, !isCurrentAccount(operation: operation) { return }
                guard pendingLookRequests[subject.id]?.validity.accepts(requestID) == true else { return }
                if lookSubject?.id == subject.id { lookSubject = nil }
                guard isDemoMode || scope?.matches(member(subject.id)) == true else { return }
                if error.isLookRequiresSealed {
                    if let current = member(subject.id), current.isAvailable {
                        openView(current)
                    }
                    return
                }
                if let scope, !scope.permitsLookSnapshot(member(subject.id)) { return }
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
        let operation = isDemoMode ? nil : currentAccountOperation()
        guard isDemoMode || operation != nil else { return }
        Task {
            do {
                let logged: Bool
                if let demo {
                    logged = try demo.view(subjectID: member.id) != nil
                    publishDemoSnapshot()
                } else {
                    guard let operation, isCurrentAccount(operation: operation) else { return }
                    logged = try await client.view(subjectID: member.id, authorizedToken: operation.token).logged
                    guard isCurrentAccount(operation: operation) else { return }
                }
                if logged {
                    showToast(TrustCopy.viewLogged(name: member.firstName))
                    if demo == nil { await refresh() }
                }
            } catch where error.isViewRequiresAvailable {
                if let operation, !isCurrentAccount(operation: operation) { return }
                // Their share sealed between refreshes — fall back to the notify-first Look.
                circlePath = []
                await refresh()
                if let operation, !isCurrentAccount(operation: operation) { return }
                if let current = self.member(member.id) { lookSubject = current }
            } catch {
                if let operation, !isCurrentAccount(operation: operation) { return }
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
        guard !isDemoMode, let requestedMember = member(personID), requestedMember.isAvailable,
              !historyLoadingIDs.contains(personID),
              !historyLoadedIDs.contains(personID) || !historyIsFresh else { return }
        guard let operation = currentAccountOperation() else { return }
        let scope = TrustRelationshipScope(requestedMember)
        let requestID = UUID()
        historyRequestIDs[personID] = requestID
        historyRequestConnectionIDs[personID] = scope.connectionID
        historyLoadingIDs.insert(personID)
        historyErrors.remove(personID)
        defer {
            if historyRequestIDs[personID] == requestID {
                historyRequestIDs[personID] = nil
                historyRequestConnectionIDs[personID] = nil
                historyLoadingIDs.remove(personID)
            }
        }
        do {
            guard isCurrentAccount(operation: operation) else { return }
            let points = try await client.history(personID: personID, authorizedToken: operation.token)
            guard isCurrentAccount(operation: operation),
                  historyRequestIDs[personID] == requestID,
                  scope.permitsHistory(member(personID)) else { return }
            historyByPerson[personID] = points.map {
                LocationVisit(label: TrustCopy.location, at: $0.timestamp, point: $0)
            }
            historyConnectionIDs[personID] = scope.connectionID
            historyLoadedIDs.insert(personID)
            historyFetchedAt[personID] = Date()
        } catch {
            guard isCurrentAccount(operation: operation),
                  historyRequestIDs[personID] == requestID,
                  scope.permitsHistory(member(personID)) else { return }
            historyErrors.insert(personID)
            historyByPerson[personID] = nil
            historyLoadedIDs.remove(personID)
            historyFetchedAt[personID] = nil
            historyConnectionIDs[personID] = scope.connectionID
        }
    }

    /// Newest first. Free is 24 hours. Plus is 30 days. Empty when they are not sharing.
    func locationHistory(for member: TrustedPerson) -> [LocationVisit] {
        guard member.isAvailable else { return [] }
        if !isDemoMode {
            guard TrustRelationshipScope(member).permitsHistory(self.member(member.id)),
                  historyConnectionIDs[member.id] == member.connectionID else { return [] }
        }
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
        openedSnapshotConnectionIDs[personID] = nil
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

    @discardableResult
    private func applyConfirmedShareMutation(
        personID: UUID,
        connectionID: UUID,
        share: PersonShareState
    ) -> Bool {
        guard var current = snapshot,
              let members = TrustConfirmedRelationshipMutation.applyingShare(
                share,
                personID: personID,
                connectionID: connectionID,
                to: current.members
              ) else { return false }
        current.members = members
        snapshot = current
        client.snapshot = current
        recordConfirmedCircleMutation()
        client.persistConfirmedShareState(
            accountID: current.you.id,
            personID: personID,
            connectionID: connectionID,
            share: share
        )
        syncLocationSharing()
        return true
    }

    @discardableResult
    private func applyConfirmedRemoval(personID: UUID, connectionID: UUID) -> Bool {
        guard var current = snapshot,
              let members = TrustConfirmedRelationshipMutation.removing(
                personID: personID,
                connectionID: connectionID,
                from: current.members
              ) else { return false }
        current.members = members
        snapshot = current
        client.snapshot = current
        recordConfirmedCircleMutation()
        client.persistConfirmedRemoval(
            accountID: current.you.id,
            personID: personID,
            connectionID: connectionID
        )

        pendingLookRequests[personID]?.validity.invalidate()
        pendingLookRequests[personID] = nil
        openedSnapshots[personID] = nil
        openedSnapshotConnectionIDs[personID] = nil
        clearHistoryCache(for: personID)
        historyRequestIDs[personID] = nil
        historyRequestConnectionIDs[personID] = nil
        historyLoadingIDs.remove(personID)
        presenceGrantMutationID.removeValue(forKey: personID)
        pendingPresenceGrants.removeValue(forKey: personID)
        updatingPresenceGrantIDs.remove(personID)
        if lookSubject?.id == personID {
            lookSubject = nil
            isLooking = false
        }
        circlePath.removeAll { route in
            switch route {
            case .person(let id), .view(let id): return id == personID
            case .map: return false
            }
        }
        syncLocationSharing()
        return true
    }

    func setResting(_ mode: ShareRestingMode, for personID: UUID, toast override: String? = nil) {
        guard requireOnline() else { return }
        let currentMember = member(personID)
        let name = currentMember?.firstName ?? TrustCopy.them
        let connectionID = currentMember?.connectionID
        if mode != .off,
           let connectionID,
           shareMutationGate.blocksNonOffMutation(connectionID: connectionID) {
            return
        }
        let expectedRevision = currentMember?.share.revision
        let operation = isDemoMode ? nil : currentAccountOperation()
        guard isDemoMode || operation != nil else { return }
        if mode != .off, expectedRevision == nil, let operation {
            Task {
                await refresh()
                guard isCurrentAccount(operation: operation) else { return }
                guard let refreshed = member(personID),
                      refreshed.connectionID == connectionID,
                      refreshed.share.revision != nil else {
                    showToast(TrustCopy.apiError(code: "client_update_required", fallback: nil))
                    return
                }
                setResting(mode, for: personID, toast: override)
            }
            return
        }
        beginShareMutation(connectionID: connectionID)
        shareMutationQueue.enqueue { [weak self] in
            guard let self else { return }
            defer { finishShareMutation(connectionID: connectionID) }
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
                    guard let operation, isCurrentAccount(operation: operation) else { return }
                    guard let connectionID else {
                        showToast(TrustCopy.apiError(code: "connection_changed", fallback: nil))
                        await refresh()
                        return
                    }
                    guard member(personID)?.connectionID == connectionID else { return }
                    try await client.setShare(personID: personID, connectionID: connectionID, expectedRevision: expectedRevision, resting: mode, pause: nil, authorizedToken: operation.token)
                    guard isCurrentAccount(operation: operation) else { return }
                    guard member(personID)?.connectionID == connectionID else { return }
                    _ = applyConfirmedShareMutation(
                        personID: personID,
                        connectionID: connectionID,
                        share: PersonShareState(resting: mode, revision: nil)
                    )
                    await refresh()
                    guard isCurrentAccount(operation: operation) else { return }
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
                if let operation, !isCurrentAccount(operation: operation) { return }
                handleShareError(error)
            }
        }
    }

    /// Pause is stored on the server and restores the previous mode when it ends.
    func pauseSharing(personID: UUID, duration: PauseDuration) {
        guard requireOnline() else { return }
        let until = duration.endDate(from: Date())
        let clock = until.formatted(date: .omitted, time: .shortened)
        let restoresTo = restoreMode(for: personID)
        let modeName = restoresTo == .always ? TrustCopy.always : TrustCopy.sealed
        let operation = isDemoMode ? nil : currentAccountOperation()
        guard isDemoMode || operation != nil else { return }
        let currentMember = member(personID)
        let connectionID = currentMember?.connectionID
        if let connectionID, shareMutationGate.blocksNonOffMutation(connectionID: connectionID) {
            return
        }
        let expectedRevision = currentMember?.share.revision
        if !isDemoMode, expectedRevision == nil, let operation {
            Task {
                await refresh()
                guard isCurrentAccount(operation: operation) else { return }
                guard let refreshed = member(personID),
                      refreshed.connectionID == connectionID,
                      refreshed.share.revision != nil else {
                    showToast(TrustCopy.apiError(code: "client_update_required", fallback: nil))
                    return
                }
                pauseSharing(personID: personID, duration: duration)
            }
            return
        }
        beginShareMutation(connectionID: connectionID)
        shareMutationQueue.enqueue { [weak self] in
            guard let self else { return }
            defer { finishShareMutation(connectionID: connectionID) }
            do {
                if let demo {
                    try demo.pauseSharing(personID: personID, duration: duration)
                    publishDemoSnapshot()
                } else {
                    guard let operation, isCurrentAccount(operation: operation) else { return }
                    guard let connectionID else {
                        showToast(TrustCopy.apiError(code: "connection_changed", fallback: nil))
                        await refresh()
                        return
                    }
                    guard member(personID)?.connectionID == connectionID else { return }
                    try await client.setShare(personID: personID, connectionID: connectionID, expectedRevision: expectedRevision, resting: nil, pause: duration, authorizedToken: operation.token)
                    guard isCurrentAccount(operation: operation) else { return }
                    guard member(personID)?.connectionID == connectionID else { return }
                    _ = applyConfirmedShareMutation(
                        personID: personID,
                        connectionID: connectionID,
                        share: PersonShareState(resting: .paused, pauseUntil: until, restoresTo: restoresTo, revision: nil)
                    )
                    await refresh()
                    guard isCurrentAccount(operation: operation) else { return }
                }
                showToast(TrustCopy.pauseUntil(time: clock, mode: modeName))
                syncLocationSharing()
            } catch {
                if let operation, !isCurrentAccount(operation: operation) { return }
                handleShareError(error)
            }
        }
    }

    func stopSharing(personID: UUID) {
        setResting(.off, for: personID)
    }

    /// Per-connection consent to show coarse Home/Away status. Location share
    /// mode and the global Hidden state continue to gate what the peer can see.
    func togglePresenceGrant(personID: UUID) {
        guard let currentMember = member(personID) else { return }
        setPresenceGrant(personID: personID, enabled: !currentMember.outboundPresenceGranted)
    }

    func setPresenceGrant(personID: UUID, enabled: Bool) {
        guard !updatingPresenceGrantIDs.contains(personID) else { return }
        guard let currentMember = member(personID) else { return }
        if let demo {
            demo.setPresenceGrant(personID: personID, enabled: enabled)
            publishDemoSnapshot()
            return
        }
        guard let connectionID = currentMember.connectionID else {
            showToast(TrustCopy.apiError(code: "connection_changed", fallback: nil))
            Task { await refresh() }
            return
        }
        let expectedRevision = currentMember.outboundPresenceRevision
        if enabled, expectedRevision == nil {
            Task { await refresh() }
            return
        }
        guard requireOnline(), let operation = currentAccountOperation() else { return }
        let previousValue = currentMember.outboundPresenceGranted
        guard previousValue != enabled else { return }

        // Lock this control until the write and authoritative refresh finish. This
        // keeps repeated taps from building toggles on an unconfirmed optimistic
        // value, which would make rollback and stale refresh races ambiguous.
        let mutationID = UUID()
        presenceGrantMutationID[personID] = mutationID
        pendingPresenceGrants[personID] = PendingPresenceGrant(
            mutationID: mutationID,
            connectionID: connectionID,
            enabled: enabled
        )
        updatingPresenceGrantIDs.insert(personID)
        updateOutboundPresenceGrant(personID: personID, enabled: enabled)
        presenceGrantMutationQueue.enqueue { [weak self] in
            guard let self else { return }
            defer {
                if presenceGrantMutationID[personID] == mutationID {
                    presenceGrantMutationID.removeValue(forKey: personID)
                    pendingPresenceGrants.removeValue(forKey: personID)
                    updatingPresenceGrantIDs.remove(personID)
                }
            }
            guard isCurrentAccount(operation: operation) else { return }
            guard member(personID)?.connectionID == connectionID else {
                pendingPresenceGrants.removeValue(forKey: personID)
                await refresh()
                guard isCurrentAccount(operation: operation) else { return }
                showToast(TrustCopy.apiError(code: "connection_changed", fallback: nil))
                return
            }
            do {
                let committedRevision = try await client.setPresenceGrant(
                    personID: personID,
                    connectionID: connectionID,
                    revision: expectedRevision,
                    enabled: enabled,
                    authorizedToken: operation.token
                )
                guard isCurrentAccount(operation: operation), member(personID)?.connectionID == connectionID else { return }
                recordConfirmedCircleMutation()
                pendingPresenceGrants[personID]?.preserveOptimisticValue = false
                updateOutboundPresenceRevision(personID: personID, revision: committedRevision)
                let refreshSequenceBeforeReconcile = circleRefreshSequence
                await refresh()
                guard isCurrentAccount(operation: operation) else { return }
                if lastSuccessfulCircleRefreshSequence <= refreshSequenceBeforeReconcile,
                   member(personID)?.connectionID == connectionID {
                    // The PUT is confirmed even if an unrelated or follow-up circle
                    // read failed. Keep the acknowledged value until a later refresh.
                    updateOutboundPresenceGrant(personID: personID, enabled: enabled)
                    updateOutboundPresenceRevision(personID: personID, revision: committedRevision)
                }
                showToast(TrustCopy.presenceGrantUpdated)
            } catch {
                guard isCurrentAccount(operation: operation) else { return }
                pendingPresenceGrants[personID]?.preserveOptimisticValue = false
                if member(personID)?.connectionID == connectionID {
                    pendingPresenceGrants[personID]?.enabled = previousValue
                    updateOutboundPresenceGrant(personID: personID, enabled: previousValue)
                    updateOutboundPresenceRevision(personID: personID, revision: nil)
                } else {
                    pendingPresenceGrants.removeValue(forKey: personID)
                }
                let refreshSequenceBeforeReconcile = circleRefreshSequence
                await refresh()
                guard isCurrentAccount(operation: operation) else { return }
                if lastSuccessfulCircleRefreshSequence <= refreshSequenceBeforeReconcile,
                   member(personID)?.connectionID == connectionID {
                    updateOutboundPresenceGrant(personID: personID, enabled: previousValue)
                }
                showToast(plainMessage(for: error))
            }
        }
    }

    func isUpdatingPresenceGrant(personID: UUID) -> Bool {
        updatingPresenceGrantIDs.contains(personID)
    }

    private func updateOutboundPresenceGrant(personID: UUID, enabled: Bool) {
        guard var current = snapshot,
              let index = current.members.firstIndex(where: { $0.id == personID }) else { return }
        current.members[index].outboundPresenceGranted = enabled
        snapshot = current
    }

    private func updateOutboundPresenceRevision(personID: UUID, revision: Int64?) {
        guard var current = snapshot,
              let index = current.members.firstIndex(where: { $0.id == personID }) else { return }
        current.members[index].outboundPresenceRevision = revision
        snapshot = current
    }

    /// Drops the pair. Not the same as Stop, which leaves them on the list as not sharing.
    func removePerson(personID: UUID) {
        guard requireOnline() else { return }
        let currentMember = member(personID)
        let name = currentMember?.firstName ?? TrustCopy.them
        let connectionID = currentMember?.connectionID
        let operation = isDemoMode ? nil : currentAccountOperation()
        guard isDemoMode || operation != nil else { return }
        Task {
            do {
                if let demo {
                    demo.revoke(personID: personID)
                    publishDemoSnapshot()
                } else {
                    guard let operation, isCurrentAccount(operation: operation) else { return }
                    guard let connectionID else {
                        showToast(TrustCopy.apiError(code: "connection_changed", fallback: nil))
                        await refresh()
                        return
                    }
                    guard member(personID)?.connectionID == connectionID else { return }
                    try await client.revoke(personID: personID, connectionID: connectionID, authorizedToken: operation.token)
                    guard isCurrentAccount(operation: operation) else { return }
                    guard applyConfirmedRemoval(personID: personID, connectionID: connectionID) else {
                        await refresh()
                        return
                    }
                    await refresh()
                    guard isCurrentAccount(operation: operation) else { return }
                }
                circlePath.removeAll { route in
                    switch route {
                    case .person(let id), .view(let id): return id == personID
                    case .map: return false
                    }
                }
                showToast(TrustCopy.logYouRemoved(name: name))
            } catch {
                if let operation, !isCurrentAccount(operation: operation) { return }
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
        let demoAtInvocation = demo
        let isDemoAtInvocation = demoAtInvocation.map { _ in true } ?? false
        let operation: TrustAccountOperation?
        if isDemoAtInvocation { operation = nil }
        else { operation = currentAccountOperation() }
        guard isDemoAtInvocation || operation != nil else { return }
        // Include currently-Off members too: an earlier queued Sealed/Always
        // mutation may still be in flight and must be followed by an Off write.
        let membersToStop = circle
        membersToStop.forEach { beginShareMutation(connectionID: $0.connectionID) }
        shareMutationQueue.enqueue { [weak self] in
            guard let self else { return }
            defer { membersToStop.forEach { self.finishShareMutation(connectionID: $0.connectionID) } }
            if let demoAtInvocation {
                guard demo === demoAtInvocation else { return }
                demoAtInvocation.stopAll()
                publishDemoSnapshot()
            } else {
                guard let operation, isCurrentAccount(operation: operation) else { return }
                do {
                    try await client.stopAllSharing(authorizedToken: operation.token) { [weak self] in
                        guard let self else { return false }
                        return operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration)
                    }
                    guard isCurrentAccount(operation: operation) else { return }
                    for member in membersToStop {
                        guard let connectionID = member.connectionID else { continue }
                        _ = applyConfirmedShareMutation(
                            personID: member.id,
                            connectionID: connectionID,
                            share: PersonShareState(resting: .off, revision: nil)
                        )
                    }
                    syncLocationSharing()
                    await refresh()
                    guard isCurrentAccount(operation: operation) else { return }
                } catch {
                    guard isCurrentAccount(operation: operation) else { return }
                    showToast(plainMessage(for: error))
                    return
                }
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
            showToast(kind == .hidden ? TrustCopy.presenceHiddenToast : TrustCopy.presenceSetToast(label: kind.label), isHomePresence: true)
            return
        }
        guard requireOnline() else { return }
        submitHomePresence(kind, signaledAt: Date(), placeID: nil, toast: true)
    }

    // MARK: Invite

    func setConnectionHandleDraft(_ raw: String) {
        guard raw != connectionHandleDraft else { return }
        connectionHandleDraft = raw
        clearConnectionLookup(keepDraft: true)
        guard let query = PersonLookupQuery.parse(raw) else { return }
        connectionLookupCanInvite = ifPhoneQuery(query)
        let generation = connectionLookupGeneration
        connectionLookupDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.performConnectionLookup(query, generation: generation)
        }
    }

    func submitConnectionLookup() {
        let value = connectionHandleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, PersonLookupQuery.parse(value) == nil else { return }
        if value.first?.isNumber == true || value.first == "+" {
            connectionLookupHint = TrustCopy.phoneLookupCountryCodeHint
        } else {
            connectionLookupNotice = TrustCopy.handleInvalid
        }
    }

    private func ifPhoneQuery(_ query: PersonLookupQuery) -> Bool {
        if case .phone = query { return true }
        return false
    }

    private func clearConnectionLookup(keepDraft: Bool = false) {
        connectionLookupGeneration &+= 1
        connectionLookupDebounceTask?.cancel()
        connectionLookupTask?.cancel()
        connectionLookupDebounceTask = nil
        connectionLookupTask = nil
        connectionLookup = nil
        connectionLookupNotice = nil
        connectionLookupHint = nil
        connectionLookupIsNoMatch = false
        connectionLookupCanInvite = false
        connectionRequiresPhoneVerification = false
        isLookingUpConnection = false
        isPreparingConnectionInvite = false
        inviteShareText = nil
        if !keepDraft { connectionHandleDraft = "" }
    }

    private func performConnectionLookup(_ query: PersonLookupQuery, generation: UInt64) async {
        guard generation == connectionLookupGeneration, showingAddPersonSheet else { return }
        guard requireOnline() else { return }
        if isDemoMode {
            connectionLookupNotice = TrustCopy.connectionRequestsNeedAccount
            return
        }
        guard let sessionToken = auth.sessionToken else { return }
        let currentAccountGeneration = accountGeneration
        isLookingUpConnection = true
        connectionLookup = nil
        connectionLookupNotice = nil
        connectionLookupIsNoMatch = false
        connectionLookupTask = Task {
            defer {
                if generation == connectionLookupGeneration,
                   isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    isLookingUpConnection = false
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                let result = try await client.lookupPerson(query)
                guard generation == connectionLookupGeneration,
                      isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                connectionLookup = result
            } catch {
                guard generation == connectionLookupGeneration,
                      isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if (error as? TrustClientError)?.apiCode == "verification_required" {
                    connectionRequiresPhoneVerification = true
                    return
                }
                if let apiCode = (error as? TrustClientError)?.apiCode,
                   ["not_found", "person_not_found", "lookup_not_found"].contains(apiCode) {
                    connectionLookupIsNoMatch = true
                    return
                }
                if let apiCode = (error as? TrustClientError)?.apiCode,
                   ["invalid_phone", "invalid_phone_number", "invalid_search_query"].contains(apiCode),
                   ifPhoneQuery(query) {
                    connectionLookupHint = TrustCopy.phoneLookupCountryCodeHint
                    return
                }
                connectionLookupNotice = plainMessage(for: error)
            }
        }
    }

    func refreshConnectionRequests() async {
        guard phase == .home, auth.isAuthenticated, !isDemoMode else { return }
        guard auth.sessionToken != nil else { return }
        if let current = connectionRequestsRefreshTask {
            // Coalesce overlapping requests, but keep the caller waiting until the
            // owner completes the queued read as well. A refresh may be requested
            // after a mutation while an older, pre-mutation read is still in flight.
            connectionRequestsRefreshQueued = true
            await current.value
            return
        }
        isLoadingConnectionRequests = true
        let owner = Task { @MainActor [self] in
            await runConnectionRequestsRefreshOwner()
        }
        connectionRequestsRefreshTask = owner
        await owner.value
    }

    private func runConnectionRequestsRefreshOwner() async {
        while true {
            connectionRequestsRefreshQueued = false
            guard phase == .home, auth.isAuthenticated, !isDemoMode,
                  let sessionToken = auth.sessionToken else { break }
            let currentAccountGeneration = accountGeneration
            client.token = sessionToken
            do {
                let requests = try await client.connectionRequests()
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else {
                    if !connectionRequestsRefreshQueued { break }
                    continue
                }
                connectionRequests = requests
                connectionRequestsNotice = nil
            } catch TrustClientError.unauthorized {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else {
                    if !connectionRequestsRefreshQueued { break }
                    continue
                }
                signOut()
            } catch is CancellationError {
                break
            } catch {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else {
                    if !connectionRequestsRefreshQueued { break }
                    continue
                }
                // Request-list failures are local to this section and do not mark the circle offline.
                connectionRequestsNotice = plainMessage(for: error)
            }

            if !connectionRequestsRefreshQueued { break }
        }
        isLoadingConnectionRequests = false
        connectionRequestsRefreshTask = nil
    }

    func sendConnectionRequest() {
        guard let result = connectionLookup, result.relationship == "none", !isSendingConnectionRequest else { return }
        guard requireOnline() else { return }
        if isDemoMode {
            connectionLookupNotice = TrustCopy.connectionRequestsNeedAccount
            return
        }
        guard let sessionToken = auth.sessionToken else { return }
        let handle = result.handle
        let lookupGeneration = connectionLookupGeneration
        let currentAccountGeneration = accountGeneration
        isSendingConnectionRequest = true
        connectionLookupNotice = nil
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    isSendingConnectionRequest = false
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                _ = try await client.createConnectionRequest(recipientID: result.accountId)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                await refreshConnectionRequests()
                guard lookupGeneration == connectionLookupGeneration,
                      isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                await updateConnectionLookupAfterSend(
                    handle: handle,
                    lookupGeneration: lookupGeneration,
                    accountGeneration: currentAccountGeneration,
                    token: sessionToken
                )
            } catch {
                guard lookupGeneration == connectionLookupGeneration,
                      isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if (error as? TrustClientError)?.apiCode == "verification_required" {
                    connectionRequiresPhoneVerification = true
                    return
                }
                connectionLookupNotice = plainMessage(for: error)
            }
        }
    }

    func acceptConnectionRequest(_ request: ConnectionRequestDTO) {
        acceptConnectionRequest(id: request.id)
    }

    func acceptConnectionRequest(id: UUID) {
        guard actingOnConnectionRequestIDs.insert(id).inserted else { return }
        guard let sessionToken = auth.sessionToken else {
            actingOnConnectionRequestIDs.remove(id)
            return
        }
        let currentAccountGeneration = accountGeneration
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    actingOnConnectionRequestIDs.remove(id)
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                try await client.acceptConnectionRequest(id: id)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                recordConfirmedCircleMutation()
                await refresh()
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if showingAddPersonSheet { showingAddPersonSheet = false }
                showToast(TrustCopy.connectedSharingOff)
            } catch {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if (error as? TrustClientError)?.apiCode == "verification_required" {
                    connectionRequiresPhoneVerification = true
                    return
                }
                if showingAddPersonSheet {
                    connectionLookupNotice = plainMessage(for: error)
                } else {
                    connectionRequestsNotice = plainMessage(for: error)
                }
            }
        }
    }

    private func updateConnectionLookupAfterSend(
        handle: String,
        lookupGeneration: UInt64,
        accountGeneration: UInt64,
        token: String
    ) async {
        guard case .valid(let normalized) = TrustHandle.status(of: handle) else { return }
        do {
            let result = try await client.lookupPerson(.handle(normalized))
            guard lookupGeneration == connectionLookupGeneration,
                  isCurrentAccount(generation: accountGeneration, token: token) else { return }
            connectionLookup = result
            if result.relationship == "sent" { showToast(TrustCopy.requestSent) }
        } catch {
            guard lookupGeneration == connectionLookupGeneration,
                  isCurrentAccount(generation: accountGeneration, token: token) else { return }
            connectionLookupNotice = plainMessage(for: error)
        }
    }

    func declineConnectionRequest(_ request: ConnectionRequestDTO) {
        guard actingOnConnectionRequestIDs.insert(request.id).inserted else { return }
        guard let sessionToken = auth.sessionToken else {
            actingOnConnectionRequestIDs.remove(request.id)
            return
        }
        let currentAccountGeneration = accountGeneration
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    actingOnConnectionRequestIDs.remove(request.id)
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                try await client.declineConnectionRequest(id: request.id)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                await refreshConnectionRequests()
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
            } catch {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                connectionRequestsNotice = plainMessage(for: error)
            }
        }
    }

    func beginConnectionPhoneVerification() {
        showingAddPersonSheet = false
        canReturnFromPhoneVerification = false
        resetPhoneDraft()
        routeAfterAuth(onboardingComplete: false)
    }

    func returnFromConnectionPhoneVerification() {
        canReturnFromPhoneVerification = false
        routeAfterAuth(onboardingComplete: false)
    }

    func copyOwnHandle() {
        guard let handle = you.handle else { return }
        UIPasteboard.general.string = "@\(handle)"
        showToast(TrustCopy.handleCopied)
    }

    func cancelConnectionRequest(_ request: ConnectionRequestDTO) {
        guard actingOnConnectionRequestIDs.insert(request.id).inserted else { return }
        guard let sessionToken = auth.sessionToken else {
            actingOnConnectionRequestIDs.remove(request.id)
            return
        }
        let currentAccountGeneration = accountGeneration
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    actingOnConnectionRequestIDs.remove(request.id)
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                try await client.cancelConnectionRequest(id: request.id)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                await refreshConnectionRequests()
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
            } catch {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                connectionRequestsNotice = plainMessage(for: error)
            }
        }
    }

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
                    inviteNotice = TrustCopy.inviteReady
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
                if (error as? TrustClientError)?.apiCode == "verification_required" {
                    connectionRequiresPhoneVerification = true
                }
                inviteNotice = plainMessage(for: error)
            }
        }
    }

    /// Creates or reuses the short-lived invite only after the person taps Invite.
    func prepareConnectionInvite() {
        guard connectionLookupIsNoMatch, connectionLookupCanInvite,
              !isPreparingConnectionInvite else { return }
        guard requireOnline() else { return }
        guard !isDemoMode, let sessionToken = auth.sessionToken else {
            connectionLookupNotice = TrustCopy.connectionRequestsNeedAccount
            return
        }
        let lookupGeneration = connectionLookupGeneration
        let currentAccountGeneration = accountGeneration
        isPreparingConnectionInvite = true
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    isPreparingConnectionInvite = false
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                let invite = try await client.createInvite()
                guard lookupGeneration == connectionLookupGeneration,
                      isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                inviteShareText = TrustCopy.inviteMessage(code: invite)
            } catch {
                guard lookupGeneration == connectionLookupGeneration,
                      isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if (error as? TrustClientError)?.apiCode == "verification_required" {
                    connectionRequiresPhoneVerification = true
                    return
                }
                connectionLookupNotice = plainMessage(for: error)
            }
        }
    }

    func dismissConnectionInviteShare() {
        inviteShareText = nil
    }

    func setDiscoveryEnabled(_ enabled: Bool) {
        let previous = snapshot?.you.discoveryEnabled ?? false
        guard enabled != previous, !isUpdatingDiscovery else { return }
        guard requireOnline() else { return }
        guard !isDemoMode, let sessionToken = auth.sessionToken else {
            showToast(TrustCopy.connectionRequestsNeedAccount)
            return
        }
        guard var optimistic = snapshot else { return }
        let currentAccountGeneration = accountGeneration
        optimistic.you.discoveryEnabled = enabled
        snapshot = optimistic
        client.snapshot = optimistic
        isUpdatingDiscovery = true
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    isUpdatingDiscovery = false
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                try await client.setDiscoveryEnabled(enabled)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                await refresh()
            } catch {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if var current = snapshot {
                    current.you.discoveryEnabled = previous
                    snapshot = current
                    client.snapshot = current
                }
                showToast(plainMessage(for: error))
            }
        }
    }

    func joinInvite() {
        let code = linkedInviteCode ?? inviteCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !isJoining else { return }
        guard requireOnline() else { return }
        if let demo {
            do {
                try demo.joinInvite(code: code)
                inviteCodeDraft = ""
                linkedInviteCode = nil
                inviteNotice = nil
                publishDemoSnapshot()
                showToast(TrustCopy.joined)
                selectedTab = .sharing
            } catch {
                inviteNotice = plainMessage(for: error)
            }
            return
        }
        guard let sessionToken = auth.sessionToken else { return }
        let currentAccountGeneration = accountGeneration
        isJoining = true
        Task {
            defer {
                if isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) {
                    isJoining = false
                }
            }
            do {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                client.token = sessionToken
                try await client.acceptInvite(code: code)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                recordConfirmedCircleMutation()
                inviteCodeDraft = ""
                linkedInviteCode = nil
                inviteNotice = nil
                await refresh(enterHome: true)
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                showToast(TrustCopy.joined)
                selectedTab = .sharing
                await receipts.requestPermission()
            } catch {
                guard isCurrentAccount(generation: currentAccountGeneration, token: sessionToken) else { return }
                if (error as? TrustClientError)?.apiCode == "verification_required" {
                    connectionRequiresPhoneVerification = true
                }
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
        linkedInviteCode = code
        if auth.isAuthenticated, phase == .home {
            selectedTab = .sharing
        }
    }

    func dismissLinkedInvite() {
        linkedInviteCode = nil
        inviteCodeDraft = ""
        inviteNotice = nil
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
                try await client.setHandle(
                    handle,
                    discoveryConsentVersion: onboardingDiscoveryEnabled ? 1 : nil
                )
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
        guard canAccessAccountData else { return }
        loadPhoneRetry()
        let next: AppPhase
        if let you = snapshot?.you ?? authenticatedPerson {
            next = Self.phase(for: you)
        } else {
            next = .handle
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
        if phase == .home { canReturnFromPhoneVerification = false }
    }

    /// Handle first, then a verified phone, then Home. A missing phone never lands on Home.
    private static func phase(for you: Person) -> AppPhase {
        switch TrustPhoneSetupRoute.route(handle: you.handle, phoneVerified: you.phoneVerified) {
        case .handle: return .handle
        case .phone: return .phone
        case .home: return .home
        }
    }

    func sendPhoneCode(action: PhoneConsentAction) async {
        phoneNotice = nil
        phoneNoticeIsConflict = false
        loadPhoneRetry()
        let phone = (action == .resendCode ? challengedPhone : phoneDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !isSendingPhone, phoneRetry.secondsRemaining(for: phone, now: Date()) == 0 else {
            if phone.isEmpty { phoneNotice = TrustCopy.enterPhone }
            return
        }
        guard phase == .phone, let operation = currentAccountOperation(), requireOnline() else { return }
        let ageGeneration = ageAccessState.generation
        phoneSendGeneration &+= 1
        let generation = phoneSendGeneration
        isSendingPhone = true
        defer { if generation == phoneSendGeneration { isSendingPhone = false } }
        do {
            let sent = try await client.sendPhoneCode(phone: phone, consentAction: action)
            guard isCurrentAccount(operation: operation), canAccessAccountData,
                  hasCurrentAgeAuthorization(generation: ageGeneration) else { return }
            let now = Date()
            phoneRetry.apply(phone: sent.normalizedPhone ?? phone, serverTime: sent.serverTime,
                resendAt: sent.resendRetryAt ?? (sent.serverTime ?? now).addingTimeInterval(Double(sent.resendAfterSeconds)),
                correctionAt: sent.correctionRetryAt, remaining: sent.immediateNumberAttemptsRemaining, accepted: true, now: now,
                accountAt: sent.accountRetryAt, accountWindow: sent.accountWindowStartedAt, accountCount: sent.accountSendCount)
            savePhoneRetry()
            guard phoneOperationIsCurrent(operation, ageGeneration: ageGeneration, generation: generation),
                  action == .resendCode || phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines) == phone else { return }
            challengedPhone = sent.normalizedPhone ?? phone
            phoneRetry.challengeNumber = challengedPhone
            phoneRetry.challengeExpiresAt = now.addingTimeInterval(sent.expiresAt.timeIntervalSince(sent.serverTime ?? now))
            phoneRetry.showingCode = true
            savePhoneRetry()
            phoneCodeDraft = ""
            phoneCodeSent = true
            phoneNotice = sent.developmentCode.map(TrustCopy.developmentPhoneCode)
        } catch {
            guard isCurrentAccount(operation: operation), canAccessAccountData,
                  hasCurrentAgeAuthorization(generation: ageGeneration) else { return }
            if case TrustClientError.phoneRetry(let code, _, let details) = error {
                let now = Date()
                let retryAt = details.retryAt ?? (details.serverTime ?? now).addingTimeInterval(Double(details.retryAfterSeconds ?? 0))
                phoneRetry.apply(phone: details.normalizedPhone ?? phone, serverTime: details.serverTime,
                    resendAt: details.resendRetryAt, correctionAt: details.correctionRetryAt,
                    remaining: details.immediateNumberAttemptsRemaining, retryAt: retryAt,
                    accepted: code == "otp_send_failed", now: now,
                    accountAt: details.accountRetryAt, accountWindow: details.accountWindowStartedAt, accountCount: details.accountSendCount)
                if details.immediateNumberAttemptsRemaining == nil {
                    phoneRetry.globalDeadline = now.addingTimeInterval(retryAt.timeIntervalSince(details.serverTime ?? now))
                }
                savePhoneRetry()
            }
            guard phoneOperationIsCurrent(operation, ageGeneration: ageGeneration, generation: generation),
                  action == .resendCode || phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines) == phone else { return }
            phoneNotice = plainMessage(for: error)
            phoneNoticeIsConflict = ["phone_unavailable", "phone_in_use"].contains((error as? TrustClientError)?.apiCode ?? "")
        }
    }

    func editPhoneNumber() {
        cancelPendingPhoneSend()
        phoneCodeSent = false
        phoneCodeDraft = ""
        phoneNotice = nil
        phoneRetry.showingCode = false
        savePhoneRetry()
    }

    private func phoneOperationIsCurrent(_ operation: TrustAccountOperation, ageGeneration: UInt64, generation: UInt64) -> Bool {
        phase == .phone && generation == phoneSendGeneration && isCurrentAccount(operation: operation)
            && canAccessAccountData && hasCurrentAgeAuthorization(generation: ageGeneration)
    }

    /// Invalidates send and verify callbacks after editing, leaving setup, or changing account.
    func cancelPendingPhoneSend() {
        phoneSendGeneration &+= 1
        isSendingPhone = false
    }

    func verifyPhoneCode() async {
        phoneNoticeIsConflict = false
        let phone = challengedPhone
        let code = phoneCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !code.isEmpty, !isSendingPhone else {
            if code.isEmpty { phoneNotice = TrustCopy.enterPhoneCode }
            return
        }
        guard phase == .phone, let operation = currentAccountOperation(), requireOnline() else { return }
        let ageGeneration = ageAccessState.generation
        phoneSendGeneration &+= 1
        let generation = phoneSendGeneration
        isSendingPhone = true
        defer { if generation == phoneSendGeneration { isSendingPhone = false } }
        do {
            try await client.verifyPhoneCode(phone: phone, code: code)
            guard phoneOperationIsCurrent(operation, ageGeneration: ageGeneration, generation: generation), challengedPhone == phone else { return }
            phoneNotice = nil
            recordConfirmedCircleMutation()
            let mutationGeneration = confirmedCircleMutationBarrier.capture()
            let result = try await client.refreshCircle(operation: operation) { [weak self] in self?.currentAccountOperation() }
            guard phoneOperationIsCurrent(operation, ageGeneration: ageGeneration, generation: generation), challengedPhone == phone else { return }
            guard confirmedCircleMutationBarrier.permitsCommit(startedAt: mutationGeneration) else { return }
            guard client.commitCircleRefresh(result, operation: operation, currentOperation: { [weak self] in self?.currentAccountOperation() }) else { return }
            snapshot = result.snapshot
            setAccountDataScope(result.snapshot.you.id.uuidString.lowercased())
            phoneRetry.showingCode = false
            savePhoneRetry()
            routeAfterAuth(onboardingComplete: false)
        } catch {
            guard phoneOperationIsCurrent(operation, ageGeneration: ageGeneration, generation: generation), challengedPhone == phone else { return }
            phoneNotice = plainMessage(for: error)
            phoneNoticeIsConflict = ["phone_unavailable", "phone_in_use"].contains((error as? TrustClientError)?.apiCode ?? "")
        }
    }

    private func resetPhoneDraft() {
        cancelPendingPhoneSend()
        phoneDraft = ""
        challengedPhone = ""
        phoneCodeDraft = ""
        phoneNotice = nil
        phoneNoticeIsConflict = false
        phoneCodeSent = false
    }

    private func beginOnboarding() {
        onboardingDiscoveryEnabled = snapshot?.you.discoveryEnabled ?? false
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
        onboardingDiscoveryEnabled = false
        onboardingNotice = nil
        handleAvailability = nil
        isOnboardingBusy = false
        resetPhoneDraft()
    }

    // MARK: Plus (StoreKit 2 — SubscriptionStoreView submits JWS here)

    func syncCircleEntitlement(signedTransactionInfo: String? = nil) async {
        guard canAccessAccountData else { return }
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
        guard canAccessAccountData, auth.isAuthenticated else { return }
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
        guard canAccessAccountData else { return }
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
        if let clientError = error as? TrustClientError,
           let code = clientError.apiCode {
            return TrustCopy.apiError(code: code, fallback: clientError.localizedDescription)
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
        location.onHomePresence = { [weak self] kind, signaledAt, placeID in
            self?.postGeofencePresence(kind, signaledAt: signaledAt, placeID: placeID)
        }
        location.setHomeMonitoring(false)
    }

    /// Home geofence drives Home/Away when a place is set and Always is granted.
    /// Desire monitoring whenever Home is set — region monitoring starts when Always arrives.
    /// Manual triad remains an override. Hidden is never posted from the geofence.
    func syncHomeMonitoring() {
        location.setHomeMonitoring(canAccessAccountData && auth.isAuthenticated && location.homeIsSet)
    }

    private func postGeofencePresence(_ kind: HomePresenceKind, signaledAt: Date, placeID: UUID) {
        guard canAccessAccountData, auth.isAuthenticated, kind == .home || kind == .away else { return }
        if myPresence == .hidden { return }
        if isDemoMode {
            demo?.setMyPresence(kind)
            publishDemoSnapshot()
            return
        }
        guard !isOffline else { return }
        submitHomePresence(kind, signaledAt: signaledAt, placeID: placeID, toast: false)
    }

    private func submitHomePresence(_ kind: HomePresenceKind, signaledAt: Date, placeID: UUID?, toast: Bool) {
        guard let operation = currentAccountOperation() else { return }
        let mutationID = UUID()
        pendingHomePresenceMutationID = mutationID
        latestHomePresenceMutationID = mutationID
        // The new optimistic state supersedes only feedback owned by an older
        // presence choice. Other warnings remain visible; success still needs an ack.
        if self.toast?.isHomePresence == true {
            toastTask?.cancel()
            self.toast = nil
        }
        presenceOverride = kind
        homePresenceMutationQueue.enqueue { [weak self] in
            guard let self else { return }
            guard isCurrentAccount(operation: operation) else { return }
            do {
                try await client.postHomePresence(
                    state: kind,
                    signaledAt: signaledAt,
                    placeID: placeID,
                    token: operation.token
                )
                guard isCurrentAccount(operation: operation) else { return }
                guard pendingHomePresenceMutationID == mutationID else { return }
                recordConfirmedCircleMutation()
                pendingHomePresenceMutationID = nil
                if toast {
                    showToast(kind == .hidden ? TrustCopy.presenceHiddenToast : TrustCopy.presenceSetToast(label: kind.label), isHomePresence: true)
                }
                await refresh()
            } catch {
                guard isCurrentAccount(operation: operation) else { return }
                guard pendingHomePresenceMutationID == mutationID else { return }
                pendingHomePresenceMutationID = nil
                presenceOverride = nil
                await refresh()
                guard isCurrentAccount(operation: operation) else { return }
                guard latestHomePresenceMutationID == mutationID else { return }
                if toast { showToast(plainMessage(for: error), isHomePresence: true) }
            }
        }
    }

    func setHomeFromCurrentLocation() {
        guard requireOnline() || isDemoMode else { return }
        if isDemoMode {
            location.requestWhenInUse()
            guard let candidate = location.homeCandidateFromCurrentFix(label: "Home") else {
                showToast(TrustCopy.homeNeedsLocation)
                return
            }
            location.commitHome(candidate)
            showToast(TrustCopy.homeSetToast)
            syncHomeMonitoring()
            if !location.hasAlways { showingAlwaysExplainer = true }
            return
        }
        guard !isSettingHome, let operation = currentAccountOperation() else { return }
        let requestID = homeFixRequestState.begin()
        isSettingHome = true
        location.requestCurrentFix { [weak self] fix in
            guard let self, self.homeFixRequestState.accepts(requestID) else { return }
            self.homeFixRequestState.cancel()
            self.isSettingHome = false
            guard self.isCurrentAccount(operation: operation) else { return }
            guard let fix, let candidate = self.location.homeCandidate(from: fix, label: "Home") else {
                self.showToast(TrustCopy.homeNeedsLocation)
                return
            }
            self.homeMutationQueue.enqueue { [weak self] in
                guard let self, operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration) else { return }
                do {
                    try await self.client.setHomePlace(placeID: candidate.placeID, label: candidate.label, token: operation.token)
                    guard operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration) else { return }
                    self.recordConfirmedCircleMutation()
                    self.location.commitHome(candidate)
                    self.showToast(TrustCopy.homeSetToast)
                    self.syncHomeMonitoring()
                    if !self.location.hasAlways {
                        self.showingAlwaysExplainer = true
                    }
                    await self.refresh()
                } catch {
                    guard operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration) else { return }
                    self.showToast(self.plainMessage(for: error))
                }
            }
        }
    }

    func clearHomePlace() {
        guard requireOnline() || isDemoMode else { return }
        if isDemoMode {
            location.clearHome()
            location.setHomeMonitoring(false)
            showToast(TrustCopy.homeClearedToast)
            return
        }
        guard let token = auth.sessionToken else { return }
        // Clear supersedes any Set/Update still waiting for Core Location. If that
        // callback arrives later, it must not enqueue a new Home write after Clear.
        homeFixRequestState.cancel()
        isSettingHome = false
        let operation = TrustAccountOperation(token: token, generation: accountGeneration)
        homeMutationQueue.enqueue { [weak self] in
            guard let self, operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration) else { return }
            do {
                try await self.client.clearHomePlace(token: operation.token)
                guard operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration) else { return }
                self.recordConfirmedCircleMutation()
                self.location.clearHome()
                self.location.setHomeMonitoring(false)
                self.showToast(TrustCopy.homeClearedToast)
                await self.refresh()
            } catch {
                guard operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration) else { return }
                self.showToast(self.plainMessage(for: error))
            }
        }
    }

    private func syncLocationSharing() {
        guard canAccessAccountData, auth.isAuthenticated || isDemoMode else {
            location.setSharingTier(.off)
            return
        }
        let tier = locationSharingTier
        location.setSharingTier(tier)
        if tier != .off, let point = location.lastFix {
            enqueueLocations([point])
        } else if tier == .off {
            ingestStore.clear()
        }
    }

    private func enqueueLocations(_ points: [LocationPoint]) {
        guard canAccessAccountData, isSharingLocation, location.hasAccess, !points.isEmpty else { return }
        ingestStore.append(points)
        ingestFlushTask?.cancel()
        ingestFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushIngestQueue()
        }
    }

    private func flushIngestQueue() async {
        guard canAccessAccountData, isSharingLocation, location.hasAccess, !isDemoMode, !isFlushingIngest,
              let token = auth.sessionToken else { return }
        let operation = TrustAccountOperation(token: token, generation: accountGeneration)
        let queue = ingestStore
        let queueIdentity = queue.queueIdentity
        guard !queue.points.isEmpty else { return }
        isFlushingIngest = true
        defer {
            isFlushingIngest = false
            if ingestStore.queueIdentity != queueIdentity,
               canAccessAccountData, isSharingLocation, location.hasAccess,
               auth.isAuthenticated, !isDemoMode, !ingestStore.points.isEmpty {
                Task { await flushIngestQueue() }
            }
        }
        let device = UIDevice.current
        do {
            try await LocationIngestBatchDrain.run(
                canContinue: {
                    self.canAccessAccountData && self.isSharingLocation && self.location.hasAccess
                        && operation.matches(token: self.auth.sessionToken, generation: self.accountGeneration)
                        && queue.queueIdentity == queueIdentity
                        && self.ingestStore.queueIdentity == queueIdentity
                        && !Task.isCancelled
                },
                nextBatch: { queue.nextBatch() },
                send: { batch in
                try await client.ingest(
                    points: batch.points,
                    battery: Int(device.batteryLevel * 100),
                    charging: device.batteryState == .charging || device.batteryState == .full,
                    token: operation.token
                )
                self.recordConfirmedCircleMutation()
                },
                acknowledge: { queue.acknowledge($0) }
            )
        } catch is CancellationError {
            return
        } catch TrustClientError.unauthorized {
            guard operation.matches(token: auth.sessionToken, generation: accountGeneration) else { return }
            signOut()
        } catch {
            // Keep the failed batch and every later point; the next fix or refresh retries.
            return
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
