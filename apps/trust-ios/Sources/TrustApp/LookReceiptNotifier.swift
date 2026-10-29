import Foundation
import TrustCore
import UIKit
import UserNotifications

@MainActor
final class LookReceiptNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var authorization: UNAuthorizationStatus = .notDetermined

    private let installationKey = "trust.push.installation-id"
    private var client: TrustClient?
    private var sessionToken: String?
    private var registeredToken: String?
    private var lastUploadedToken: String?
    private var lastUploadedInstallation: UUID?
    private var sessionGeneration: UInt64 = 0
    private var authorizationReadGeneration: UInt64 = 0
    private var pushDeviceMutationTail: Task<Void, Never>?
    var onNotificationTap: ((TrustPushDestination) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshStatus()
    }

    func prepare(client: TrustClient) {
        refreshAuthorizationAndRegisterIfAllowed(client: client)
    }

    /// Refreshes permission without prompting, and re-registers with APNs only
    /// when the current authorization already allows notifications.
    func refreshAuthorizationAndRegisterIfAllowed(client: TrustClient) {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let authorizedToken = client.token
        self.client = client
        if sessionToken != authorizedToken {
            lastUploadedToken = nil
            lastUploadedInstallation = nil
        }
        sessionToken = authorizedToken
        Task {
            await registerForPushIfAllowed()
            await uploadTokenIfNeeded(generation: generation, authorizedToken: authorizedToken)
        }
    }

    func refreshStatus() {
        Task { await loadAuthorization() }
    }

    /// The published status is filled in asynchronously, so a check right after
    /// `requestAuthorization` still sees `.notDetermined` and never registers.
    /// Read settings (or the grant) before asking APNs for a device token.
    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await loadAuthorization()
        if granted || Self.canRegister(authorization) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func registerForPushIfAllowed() async {
        await loadAuthorization()
        guard Self.canRegister(authorization) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func loadAuthorization() async {
        authorizationReadGeneration &+= 1
        let readGeneration = authorizationReadGeneration
        let generationBeforeRead = sessionGeneration
        let clientBeforeRead = client
        let tokenBeforeRead = sessionToken
        let installationBeforeRead = clientBeforeRead == nil ? nil : installationId
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard readGeneration == authorizationReadGeneration else { return }
        authorization = settings.authorizationStatus
        guard settings.authorizationStatus == .denied,
              generationBeforeRead == sessionGeneration,
              let clientBeforeRead,
              self.client === clientBeforeRead,
              let tokenBeforeRead,
              sessionToken == tokenBeforeRead,
              clientBeforeRead.token == tokenBeforeRead,
              let installationBeforeRead else { return }

        // Denial revokes delivery permission. Invalidate any in-flight upload before
        // removing this account's old registration; a later allow action can upload
        // the retained device token under the same current session.
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let registeredClient = clientBeforeRead
        lastUploadedToken = nil
        lastUploadedInstallation = nil
        await enqueuePushDeviceMutation {
            // A new status read may have observed a grant while this DELETE waited
            // behind an older registration. Honor the latest OS state at dispatch.
            guard self.authorization == .denied else { return }
            try? await registeredClient.removePushDevice(
                installationId: installationBeforeRead,
                authorizedToken: tokenBeforeRead
            )
            guard generation == self.sessionGeneration,
                  self.client === registeredClient,
                  self.sessionToken == tokenBeforeRead,
                  registeredClient.token == tokenBeforeRead else { return }
            self.lastUploadedToken = nil
            self.lastUploadedInstallation = nil
        }
    }

    private static func canRegister(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    func unregister(authorizedToken: String? = nil) async {
        let previousClient = client
        let previousToken = authorizedToken ?? previousClient?.token
        let previousInstallation = installationId
        sessionGeneration &+= 1
        // Detach this session before awaiting the server. A sign-in that happens
        // while DELETE is in flight may prepare a new account and must keep its state.
        client = nil
        sessionToken = nil
        registeredToken = nil
        lastUploadedToken = nil
        lastUploadedInstallation = nil
        if let previousClient, let previousToken, let previousInstallation {
            await enqueuePushDeviceMutation {
                try? await previousClient.removePushDevice(
                    installationId: previousInstallation,
                    authorizedToken: previousToken
                )
            }
        }
    }

    nonisolated func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            registeredToken = token
            await uploadTokenIfNeeded(generation: sessionGeneration, authorizedToken: client?.token)
        }
    }

    /// APNs can deliver the token before sign-in has a client. Keep the token and upload
    /// once both exist, including when the installation id changes under the same token.
    private func uploadTokenIfNeeded(generation: UInt64, authorizedToken: String?) async {
        guard generation == sessionGeneration,
              Self.canRegister(authorization),
              let client,
              let authorizedToken,
              sessionToken == authorizedToken,
              client.token == authorizedToken,
              let token = registeredToken,
              let installationId else { return }
        guard token != lastUploadedToken || installationId != lastUploadedInstallation else { return }
        await enqueuePushDeviceMutation {
            guard generation == self.sessionGeneration,
                  Self.canRegister(self.authorization),
                  self.client === client,
                  self.sessionToken == authorizedToken,
                  client.token == authorizedToken,
                  self.registeredToken == token else { return }
            do {
                try await client.registerPushDevice(
                    installationId: installationId,
                    token: token,
                    environment: Self.apnsEnvironment,
                    authorizedToken: authorizedToken
                )
                guard generation == self.sessionGeneration,
                      self.client === client,
                      self.sessionToken == authorizedToken,
                      client.token == authorizedToken else { return }
                self.lastUploadedToken = token
                self.lastUploadedInstallation = installationId
            } catch {
                guard generation == self.sessionGeneration,
                      self.client === client,
                      self.sessionToken == authorizedToken else { return }
                self.lastUploadedToken = nil
                self.lastUploadedInstallation = nil
            }
        }
    }

    private func enqueuePushDeviceMutation(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = pushDeviceMutationTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        pushDeviceMutationTail = task
        await task.value
    }

    nonisolated func didFailToRegister(error: Error) {
        Task { @MainActor in
            registeredToken = nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let destination = TrustPushDestination(userInfo: response.notification.request.content.userInfo)
        completionHandler()
        guard let destination else { return }
        Task { @MainActor [weak self] in
            self?.onNotificationTap?(destination)
        }
    }

    private var installationId: UUID? {
        if let raw = UserDefaults.standard.string(forKey: installationKey),
           let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: installationKey)
        return id
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

final class TrustAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        LookReceiptNotifier.shared?.didRegister(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        LookReceiptNotifier.shared?.didFailToRegister(error: error)
    }
}

extension LookReceiptNotifier {
    static var shared: LookReceiptNotifier?
}
