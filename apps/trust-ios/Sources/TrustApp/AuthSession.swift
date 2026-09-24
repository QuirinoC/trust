import AuthenticationServices
import CryptoKit
import Foundation
import TrustCore
import UIKit

enum AuthenticationProvider: String, Equatable {
    case apple
    case google
}

enum TrustAuthenticationError: LocalizedError {
    case appleAuthorizationFailed
    case appleAuthorizationTimedOut
    case invalidAppleCredential
    case presentationUnavailable
    case signInInProgress

    var errorDescription: String? {
        switch self {
        case .appleAuthorizationFailed:
            return TrustCopy.appleSignInFailed
        case .appleAuthorizationTimedOut:
            return TrustCopy.appleSignInTimedOut
        case .invalidAppleCredential:
            return TrustCopy.invalidAppleCredential
        case .presentationUnavailable:
            return TrustCopy.presentationUnavailable
        case .signInInProgress:
            return TrustCopy.signInInProgress
        }
    }
}

struct AuthAccount: Equatable {
    var provider: AuthenticationProvider
    var displayName: String
    var appleUserID: String?
}

struct AppleIdentity {
    var identityToken: String
    var userID: String
    var displayName: String?
    /// The value set on `ASAuthorizationAppleIDRequest.nonce` (SHA-256 of a fresh random
    /// string). Apple echoes it in the ID token's `nonce` claim; the API compares the two.
    var nonce: String
}

@MainActor
final class AuthSession: ObservableObject {
    @Published private(set) var account: AuthAccount?
    @Published var notice: String?
    @Published var sessionToken: String?

    private var isAuthorizing = false
    private var appleCoordinator: AppleAuthorizationCoordinator?

    private static let authenticatedKey = "trust.didAuthenticate"
    private static let providerKey = "trust.authProvider"
    private static let nameKey = "trust.displayName"
    private static let appleUserKey = "trust.appleUserID"
    private static let tokenKey = "trust.sessionToken"

    var isAuthenticated: Bool { sessionToken != nil && account != nil }

    init() {
        restore()
    }

    func signInWithApple() async throws -> AppleIdentity {
        notice = nil
        guard !isAuthorizing else { throw TrustAuthenticationError.signInInProgress }
        isAuthorizing = true
        defer { isAuthorizing = false }
        let coordinator = AppleAuthorizationCoordinator(anchor: try presentationAnchor())
        appleCoordinator = coordinator
        defer {
            if appleCoordinator === coordinator {
                appleCoordinator = nil
            }
        }
        let credential = try await coordinator.authorize()
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw TrustAuthenticationError.invalidAppleCredential
        }
        return AppleIdentity(
            identityToken: token,
            userID: credential.user,
            displayName: Self.displayName(from: credential),
            nonce: coordinator.hashedNonce
        )
    }

    func persist(account: AuthAccount, token: String) {
        self.account = account
        sessionToken = token
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.authenticatedKey)
        defaults.set(account.provider.rawValue, forKey: Self.providerKey)
        defaults.set(account.displayName, forKey: Self.nameKey)
        TrustKeychain.set(token, account: Self.tokenKey)
        defaults.removeObject(forKey: Self.tokenKey) // migrate off UserDefaults
        if let appleUserID = account.appleUserID {
            defaults.set(appleUserID, forKey: Self.appleUserKey)
        } else {
            defaults.removeObject(forKey: Self.appleUserKey)
        }
    }

    func signOut() {
        account = nil
        notice = nil
        sessionToken = nil
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: Self.authenticatedKey)
        defaults.removeObject(forKey: Self.providerKey)
        defaults.removeObject(forKey: Self.appleUserKey)
        defaults.removeObject(forKey: Self.nameKey)
        defaults.removeObject(forKey: Self.tokenKey)
        TrustKeychain.delete(account: Self.tokenKey)
    }

    func validateRestoredAppleCredential() async {
        guard account?.provider == .apple, let userID = account?.appleUserID else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state: ASAuthorizationAppleIDProvider.CredentialState = try await withCheckedThrowingContinuation { continuation in
                provider.getCredentialState(forUserID: userID) { state, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: state)
                    }
                }
            }
            switch state {
            case .revoked, .notFound:
                signOut()
            default:
                break
            }
        } catch {
            // Keep the local session if Apple is unreachable.
        }
    }

    private func restore() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.authenticatedKey),
              let raw = defaults.string(forKey: Self.providerKey),
              let provider = AuthenticationProvider(rawValue: raw) else {
            account = nil
            sessionToken = nil
            return
        }

        var token = TrustKeychain.get(account: Self.tokenKey)
        if token == nil, let legacy = defaults.string(forKey: Self.tokenKey), !legacy.isEmpty {
            TrustKeychain.set(legacy, account: Self.tokenKey)
            defaults.removeObject(forKey: Self.tokenKey)
            token = legacy
        }

        guard let token, !token.isEmpty else {
            account = nil
            sessionToken = nil
            return
        }

        let stored = defaults.string(forKey: Self.nameKey) ?? ""
        let name = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        account = AuthAccount(
            provider: provider,
            displayName: name.isEmpty ? "You" : name,
            appleUserID: defaults.string(forKey: Self.appleUserKey)
        )
        sessionToken = token
    }

    private func presentationAnchor() throws -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) else {
            throw TrustAuthenticationError.presentationUnavailable
        }
        return window
    }

    private static func displayName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        guard let name = credential.fullName else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: name).trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty { return formatted }
        if let given = name.givenName?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty {
            return given
        }
        return nil
    }
}

/// Apple's delegate callbacks are not guaranteed on the main actor. Keep this class off
/// `@MainActor` and hop explicitly so `performRequests()` runs on main and the
/// continuation always resumes (or times out) instead of hanging.
private final class AppleAuthorizationCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var authorizationController: ASAuthorizationController?
    private var timeoutWork: DispatchWorkItem?
    /// SHA-256 hex of a fresh 32-byte random nonce; set on the request and sent to the API.
    let hashedNonce: String

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        hashedNonce = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    func authorize() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self?.finish(throwing: TrustAuthenticationError.invalidAppleCredential)
                return
            }
            self?.finish(returning: credential)
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.finish(throwing: Self.mapAuthorizationError(error))
        }
    }

    private func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // Display name is captured once for the account. Apple email is never used or stored.
        request.requestedScopes = [.fullName]
        request.nonce = hashedNonce
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(throwing: TrustAuthenticationError.appleAuthorizationTimedOut)
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
        controller.performRequests()
    }

    private func finish(returning credential: ASAuthorizationAppleIDCredential) {
        resume { continuation in
            continuation.resume(returning: credential)
        }
    }

    private func finish(throwing error: Error) {
        resume { continuation in
            continuation.resume(throwing: error)
        }
    }

    private func resume(_ body: (CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        lock.lock()
        let pending = continuation
        continuation = nil
        timeoutWork?.cancel()
        timeoutWork = nil
        authorizationController = nil
        lock.unlock()
        if let pending {
            body(pending)
        }
    }

    private static func mapAuthorizationError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationError.errorDomain,
              let code = ASAuthorizationError.Code(rawValue: nsError.code) else {
            return error
        }
        switch code {
        case .canceled:
            return CancellationError()
        case .unknown, .failed, .invalidResponse, .notHandled, .notInteractive:
            return TrustAuthenticationError.appleAuthorizationFailed
        default:
            return error
        }
    }
}
