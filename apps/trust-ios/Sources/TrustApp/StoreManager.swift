import StoreKit
import SwiftUI
import TrustCore

@MainActor
final class StoreManager: ObservableObject {
    enum TrialEligibility: Equatable {
        case unknown
        case eligible
        case unavailable
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isWorking = false
    @Published private(set) var trialEligibility: TrialEligibility = .unknown
    @Published private(set) var activeProductID: String?
    @Published var errorMessage: String?
    @Published var reviewUnlocked: Bool {
        didSet { UserDefaults.standard.set(reviewUnlocked, forKey: Self.reviewKey) }
    }
    @Published var linkedToAnotherAccount = false

    static let manageSubscriptionsURL = AppConfiguration.manageSubscriptionsURL
    private static let reviewKey = "trust.reviewUnlocked"

    var hasCircleAccess: Bool { activeProductID != nil || reviewUnlocked }

    /// Set by `AppModel` so `Transaction.updates` (restore / renew) still submit JWS.
    var onVerifiedJWS: ((String) async -> Void)?

    /// The server-issued token SubscriptionStoreView attaches via `inAppPurchaseOptions`.
    private(set) var appAccountToken: UUID?

    private let productIDs = [
        AppConfiguration.monthlyProductID,
        AppConfiguration.annualProductID
    ]
    private var updatesTask: Task<Void, Never>?

    init() {
        reviewUnlocked = UserDefaults.standard.bool(forKey: Self.reviewKey)
        startTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func setAppAccountToken(_ token: UUID?) {
        appAccountToken = token
    }

    func startTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.handle(result)
            }
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
            products = loaded
            guard let subscription = loaded.first?.subscription,
                  subscription.introductoryOffer != nil else {
                trialEligibility = .unavailable
                return
            }
            trialEligibility = await subscription.isEligibleForIntroOffer
                ? .eligible
                : .unavailable
        } catch {
            trialEligibility = .unavailable
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async -> String? {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            return await latestSignedTransaction()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func purchase(_ product: Product) async -> String? {
        isWorking = true
        defer { isWorking = false }
        do {
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case let .success(verification):
                return await acceptVerifiedPurchase(verification)
            case .userCancelled, .pending:
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// `SubscriptionStoreView` purchase / restore completion → same JWS path as `purchase(_:)`.
    func ingestPurchaseResult(_ result: Result<Product.PurchaseResult, Error>) async -> String? {
        switch result {
        case let .success(purchaseResult):
            switch purchaseResult {
            case let .success(verification):
                return await acceptVerifiedPurchase(verification)
            case .userCancelled, .pending:
                return nil
            @unknown default:
                return nil
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func refreshEntitlement() async -> String? {
        linkedToAnotherAccount = false
        return await latestSignedTransaction()
    }

    func unlockForReview() {
        reviewUnlocked = true
    }

    func clearAfterSignOut() {
        activeProductID = nil
        appAccountToken = nil
        reviewUnlocked = false
        linkedToAnotherAccount = false
    }

    private func latestSignedTransaction() async -> String? {
        var found: String?
        var signed: String?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                continue
            }
            if tokenMismatched(transaction) {
                linkedToAnotherAccount = true
                continue
            }
            found = transaction.productID
            signed = result.jwsRepresentation
            break
        }
        activeProductID = found
        return signed
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard let jws = await acceptVerifiedPurchase(result) else { return }
        await onVerifiedJWS?(jws)
    }

    /// Accept a signed transaction. A missing `appAccountToken` is not a lock failure —
    /// SubscriptionStoreView may omit it; the server still binds the JWS to this session.
    /// A *different* token is another Trust account.
    private func acceptVerifiedPurchase(_ result: VerificationResult<StoreKit.Transaction>) async -> String? {
        do {
            let transaction = try verified(result)
            guard productIDs.contains(transaction.productID) else { return nil }
            if tokenMismatched(transaction) {
                linkedToAnotherAccount = true
                await transaction.finish()
                return nil
            }
            await transaction.finish()
            activeProductID = transaction.productID
            errorMessage = nil
            return result.jwsRepresentation
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func tokenMismatched(_ transaction: StoreKit.Transaction) -> Bool {
        guard let expected = appAccountToken, let actual = transaction.appAccountToken else {
            return false
        }
        return actual != expected
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            TrustCopy.storeKitVerificationFailed
        }
    }
}
