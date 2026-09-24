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

public sealed record StoreKitNotificationVerificationResult(
    bool IsValid,
    Guid? NotificationId,
    string? NotificationType,
    VerifiedStoreKitTransaction? Transaction,
    string? Error);

public enum StoreKitApplyOutcome
{
    Applied,
    LinkedToAnotherAccount,
    NotApplied
}

public interface IStoreKitTransactionVerifier
{
    StoreKitVerificationResult Verify(string signedTransaction);

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
    Task RefreshAccountCoverageAsync(Guid accountId, CancellationToken cancellationToken);
}
