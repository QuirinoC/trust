/// Captures the account and age authorization that must still be current before the
/// resolved StoreKit transaction can be sent to the server.
public struct TrustAppTransactionAuthorization {
    private let accountOperation: TrustAccountOperation
    private let ageAuthorizationGeneration: UInt64

    public init(accountOperation: TrustAccountOperation, ageAuthorizationGeneration: UInt64) {
        self.accountOperation = accountOperation
        self.ageAuthorizationGeneration = ageAuthorizationGeneration
    }

    public func permitsRegistration(
        currentAccountToken: String?,
        currentAccountGeneration: UInt64,
        ageIsAuthorized: Bool,
        currentAgeAuthorizationGeneration: UInt64
    ) -> Bool {
        ageIsAuthorized
            && ageAuthorizationGeneration == currentAgeAuthorizationGeneration
            && accountOperation.authorizationToken(
                currentToken: currentAccountToken,
                generation: currentAccountGeneration
            ) != nil
    }
}

/// Resolves Apple's current app transaction, refreshing only after an explicit retry
/// encounters an unavailable or unverified shared result.
public enum TrustAppTransactionResolution {
    public static func resolve<Value>(
        retryRequested: Bool,
        isVerified: (Value) -> Bool,
        shared: () async throws -> Value,
        refresh: () async throws -> Value
    ) async throws -> Value {
        let value: Value
        do {
            value = try await shared()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard retryRequested else { throw error }
            try Task.checkCancellation()
            return try await refresh()
        }
        guard retryRequested, !isVerified(value) else { return value }
        try Task.checkCancellation()
        return try await refresh()
    }
}
