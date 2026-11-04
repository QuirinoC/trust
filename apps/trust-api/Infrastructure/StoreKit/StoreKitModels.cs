namespace TrustApi.Infrastructure.StoreKit;

public sealed record VerifiedStoreKitTransaction(
    string TransactionId,
    string OriginalTransactionId,
    string ProductId,
    Guid AppAccountToken,
    string Environment,
    DateTimeOffset SignedAt,
    DateTimeOffset ExpiresAt,
    DateTimeOffset? RevokedAt);

public sealed record StoreKitVerificationResult(
    VerifiedStoreKitTransaction? Transaction,
    string? Error)
{
    public bool IsValid => Transaction is not null;
}

public sealed record VerifiedStoreKitAppTransaction(
    string AppTransactionId,
    string BundleId,
    string Environment);

public sealed record StoreKitAppTransactionVerificationResult(
    VerifiedStoreKitAppTransaction? AppTransaction,
    string? Error)
{
    public bool IsValid => AppTransaction is not null;
}

public sealed record StoreKitNotificationVerificationResult(
    bool IsValid,
    Guid? NotificationId,
    string? NotificationType,
    VerifiedStoreKitTransaction? Transaction,
    string? Error,
    VerifiedStoreKitAppTransaction? RevokedAppTransaction = null,
    DateTimeOffset? SignedAt = null);

public enum StoreKitApplyOutcome
{
    Applied,
    LinkedToAnotherAccount,
    NotApplied
}

public sealed record StoreKitRecoveryRequest(Guid Id, Guid TargetAccountId, string OriginalTransactionId,
    Guid OldAppAccountToken, string TransactionId, string ProductId, string? Environment, DateTimeOffset ExpiresAt,
    DateTimeOffset? RevokedAt, string Status, DateTimeOffset CreatedAt, string? BlockedReason = null);

public sealed record PhoneOwnershipRecoveryRequest(Guid Id, Guid TargetAccountId, string Status,
    DateTimeOffset CreatedAt, string? Reason);

public interface IStoreKitTransactionVerifier
{
    StoreKitVerificationResult Verify(string signedTransaction);

    StoreKitAppTransactionVerificationResult VerifyAppTransaction(string signedAppTransaction);

    StoreKitNotificationVerificationResult VerifyNotification(string signedPayload);
}

public interface IStoreKitEntitlementStore
{
    Task<Guid> GetOrCreateAccountTokenAsync(Guid accountId, CancellationToken cancellationToken);

    Task<StoreKitApplyOutcome> ApplyAsync(
        Guid accountId,
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken);

    Task<bool> ApplyNotificationAsync(
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken);

    /// Recompute has_circle from the latest StoreKit row's expires_at so a missed
    /// EXPIRED notification cannot leave Plus sticky forever. Accounts with no
    /// StoreKit history (review unlock, test grants) are left alone.
    Task RefreshExpiredCoveragesAsync(CancellationToken cancellationToken);

    /// Same expiry check for one account — call on circle / share reads so Plus
    /// does not stick until the next sweep.
    Task RefreshAccountCoverageAsync(Guid accountId, DateTimeOffset now, CancellationToken cancellationToken);
    Task<DateTimeOffset?> GetActiveEntitlementExpiryAsync(Guid accountId, CancellationToken cancellationToken);
    Task<Guid> CreateRecoveryRequestAsync(Guid targetAccountId, VerifiedStoreKitTransaction transaction,
        string? reason, DateTimeOffset createdAt, CancellationToken cancellationToken);
    Task<Guid> CreatePhoneOwnershipRecoveryRequestAsync(Guid targetAccountId, string? reason,
        DateTimeOffset createdAt, CancellationToken cancellationToken);
    Task<bool> HasApprovedAliasAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId, CancellationToken cancellationToken);
    Task<StoreKitRecoveryRequest?> FindRecoveryRequestAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId, CancellationToken cancellationToken);
    Task<Guid> ApproveRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId,
        Func<StoreKitRecoveryRequest, CancellationToken, Task<VerifiedStoreKitTransaction>> getAuthoritativeCurrentTransaction,
        DateTimeOffset approvedAt, CancellationToken cancellationToken);
    Task BlockRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId,
        string reason, DateTimeOffset updatedAt, CancellationToken cancellationToken);
}
