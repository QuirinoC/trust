import Foundation
import TrustCore
import UIKit
import UserNotifications

@MainActor
final class LookReceiptNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var authorization: UNAuthorizationStatus = .notDetermined

    private let installationKey = "trust.push.installation-id"
    private var client: TrustClient?
    private var registeredToken: String?
    private var lastUploadedToken: String?
    private var lastUploadedInstallation: UUID?
    private var sessionGeneration: UInt64 = 0
    var onNotificationTap: ((TrustPushDestination) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshStatus()
    }

    func prepare(client: TrustClient) {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let authorizedToken = client.token
        self.client = client
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
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
        registeredToken = nil
        lastUploadedToken = nil
        lastUploadedInstallation = nil
        if let previousClient, let previousToken, let previousInstallation {
            try? await previousClient.removePushDevice(
                installationId: previousInstallation,
                authorizedToken: previousToken
            )
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
              let client,
              let authorizedToken,
              let token = registeredToken,
              let installationId else { return }
        guard token != lastUploadedToken || installationId != lastUploadedInstallation else { return }
        do {
            try await client.registerPushDevice(
                installationId: installationId,
                token: token,
                environment: Self.apnsEnvironment,
                authorizedToken: authorizedToken
            )
            guard generation == sessionGeneration, self.client === client else { return }
            lastUploadedToken = token
            lastUploadedInstallation = installationId
        } catch {
            guard generation == sessionGeneration, self.client === client else { return }
            lastUploadedToken = nil
            lastUploadedInstallation = nil
        }
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
