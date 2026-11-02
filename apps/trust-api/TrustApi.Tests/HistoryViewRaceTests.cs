using Microsoft.Extensions.Options;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class HistoryViewRaceTests
{
    [Fact]
    public async Task HistoryRejectsRemovedAndReaddedConnectionEvenWhenShareRevisionMatches()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);

        var originalConnection = await store.GetActiveMembershipIdAsync(owner.Id, viewer.Id, CancellationToken.None);
        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 3);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingHistory = engine.HistoryAsync(viewer.Id, owner.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await store.RevokeMembershipAsync(owner.Id, viewer.Id, CancellationToken.None);
        Assert.True(await store.ConnectAccountsWithOffSharesAsync(owner.Id, viewer.Id, time.UtcNow, CancellationToken.None));
        var replacementConnection = await store.GetActiveMembershipIdAsync(owner.Id, viewer.Id, CancellationToken.None);
        Assert.NotEqual(originalConnection, replacementConnection);
        await engine.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);

        gate.Release.TrySetResult();
        var denied = await Assert.ThrowsAsync<TrustException>(() => pendingHistory);
        Assert.Equal("share_off", denied.Code);
    }

    [Fact]
    public async Task ViewChecksPrivacyHoldAfterPointReadAndDoesNotInsertReceipt()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);
        var receiptsBefore = await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None);

        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 2);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingView = engine.ViewAsync(viewer.Id, owner.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await ageAssurance.PlaceAccountPrivacyHoldAsync(owner.Id, time.UtcNow, CancellationToken.None);
        gate.Release.TrySetResult();

        var denied = await Assert.ThrowsAsync<TrustException>(() => pendingView);
        Assert.Equal("not_connected", denied.Code);
        Assert.Equal(receiptsBefore.Count,
            (await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None)).Count);
    }

    [Fact]
    public async Task ViewChecksConsentRevocationAfterPointReadAndDoesNotInsertReceipt()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);
        var receiptsBefore = await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None);
        var appTransaction = new VerifiedStoreKitAppTransaction(
            $"revoked-app-transaction-{Guid.NewGuid():N}", "com.collapsetechnologies.trust", "Sandbox");
        Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
            owner.Id, appTransaction, CancellationToken.None));

        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 2);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingView = engine.ViewAsync(viewer.Id, owner.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        var blocked = await ageAssurance.RecordConsentRevocationAsync(
            Guid.NewGuid(), appTransaction, time.UtcNow, CancellationToken.None);
        Assert.Contains(owner.Id, blocked);
        gate.Release.TrySetResult();

        var denied = await Assert.ThrowsAsync<TrustException>(() => pendingView);
        Assert.Equal("not_connected", denied.Code);
        Assert.Equal(receiptsBefore.Count,
            (await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None)).Count);
    }

    [Fact]
    public async Task ViewRejectsRemovedAndReaddedConnectionWithSameShareRevisionWithoutReceipt()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);
        var originalConnection = await store.GetActiveMembershipIdAsync(owner.Id, viewer.Id, CancellationToken.None);
        var receiptsBefore = await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None);

        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 2);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingView = engine.ViewAsync(viewer.Id, owner.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await store.RevokeMembershipAsync(owner.Id, viewer.Id, CancellationToken.None);
        Assert.True(await store.ConnectAccountsWithOffSharesAsync(owner.Id, viewer.Id, time.UtcNow, CancellationToken.None));
        var replacementConnection = await store.GetActiveMembershipIdAsync(owner.Id, viewer.Id, CancellationToken.None);
        Assert.NotEqual(originalConnection, replacementConnection);
        await engine.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);

        gate.Release.TrySetResult();
        var denied = await Assert.ThrowsAsync<TrustException>(() => pendingView);
        Assert.Equal("view_requires_available", denied.Code);
        Assert.Equal(receiptsBefore.Count,
            (await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None)).Count);
    }

    [Fact]
    public async Task CircleDropsSubjectWhenPrivacyHoldArrivesAfterLocationRead()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);

        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 3);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingCircle = engine.GetCircleAsync(viewer.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await ageAssurance.PlaceAccountPrivacyHoldAsync(owner.Id, time.UtcNow, CancellationToken.None);
        gate.Release.TrySetResult();

        var circle = await pendingCircle;
        Assert.DoesNotContain(circle.Members, member => member.Person.Id == owner.Id);
    }

    [Fact]
    public async Task CircleFailsClosedWhenViewerPrivacyHoldArrivesAfterMemberRead()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);

        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 4);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingCircle = engine.GetCircleAsync(viewer.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        await ageAssurance.PlaceAccountPrivacyHoldAsync(viewer.Id, time.UtcNow, CancellationToken.None);
        gate.Release.TrySetResult();

        var denied = await Assert.ThrowsAsync<TrustException>(() => pendingCircle);
        Assert.Equal("not_connected", denied.Code);
    }

    [Fact]
    public async Task CircleDropsSubjectWhenConsentRevocationArrivesAfterLocationRead()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var innerEntitlements = new MemoryStoreKitEntitlementStore(store);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, innerEntitlements, options);
        var (owner, viewer) = await PairAsync(setup);
        await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await setup.IngestAsync(owner.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);
        var appTransaction = new VerifiedStoreKitAppTransaction(
            $"circle-revoked-app-transaction-{Guid.NewGuid():N}", "com.collapsetechnologies.trust", "Sandbox");
        Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
            owner.Id, appTransaction, CancellationToken.None));

        var gate = new EntitlementRefreshBarrier(innerEntitlements, blockAtRefresh: 3);
        var engine = new TrustEngine(store, time, ageAssurance, gate, options);
        var pendingCircle = engine.GetCircleAsync(viewer.Id, CancellationToken.None);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        var blocked = await ageAssurance.RecordConsentRevocationAsync(
            Guid.NewGuid(), appTransaction, time.UtcNow, CancellationToken.None);
        Assert.Contains(owner.Id, blocked);
        gate.Release.TrySetResult();

        var circle = await pendingCircle;
        Assert.DoesNotContain(circle.Members, member => member.Person.Id == owner.Id);
    }

    private static async Task<(Account Owner, Account Viewer)> PairAsync(TrustEngine engine)
    {
        var suffix = Guid.NewGuid().ToString("N");
        var owner = await engine.SignInAsync("development", $"race-owner-{suffix}", "Owner", CancellationToken.None);
        var viewer = await engine.SignInAsync("development", $"race-viewer-{suffix}", "Viewer", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(owner.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
        return (owner, viewer);
    }

    internal sealed class EntitlementRefreshBarrier(
        IStoreKitEntitlementStore inner,
        int blockAtRefresh) : IStoreKitEntitlementStore
    {
        private int _refreshCount;
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<Guid> GetOrCreateAccountTokenAsync(Guid accountId, CancellationToken cancellationToken) =>
            inner.GetOrCreateAccountTokenAsync(accountId, cancellationToken);
        public Task<StoreKitApplyOutcome> ApplyAsync(Guid accountId, VerifiedStoreKitTransaction transaction, CancellationToken cancellationToken) =>
            inner.ApplyAsync(accountId, transaction, cancellationToken);
        public Task<bool> ApplyNotificationAsync(VerifiedStoreKitTransaction transaction, CancellationToken cancellationToken) =>
            inner.ApplyNotificationAsync(transaction, cancellationToken);
        public Task RefreshExpiredCoveragesAsync(CancellationToken cancellationToken) =>
            inner.RefreshExpiredCoveragesAsync(cancellationToken);
        public async Task RefreshAccountCoverageAsync(Guid accountId, DateTimeOffset now, CancellationToken cancellationToken)
        {
            if (Interlocked.Increment(ref _refreshCount) == blockAtRefresh)
            {
                Entered.TrySetResult();
                await Release.Task.WaitAsync(cancellationToken);
            }
            await inner.RefreshAccountCoverageAsync(accountId, now, cancellationToken);
        }
        public Task<DateTimeOffset?> GetActiveEntitlementExpiryAsync(Guid accountId, CancellationToken cancellationToken) =>
            inner.GetActiveEntitlementExpiryAsync(accountId, cancellationToken);
        public Task<Guid> CreateRecoveryRequestAsync(Guid targetAccountId, VerifiedStoreKitTransaction transaction, string? reason, DateTimeOffset createdAt, CancellationToken cancellationToken) =>
            inner.CreateRecoveryRequestAsync(targetAccountId, transaction, reason, createdAt, cancellationToken);
        public Task<Guid> CreatePhoneOwnershipRecoveryRequestAsync(Guid targetAccountId, string? reason, DateTimeOffset createdAt, CancellationToken cancellationToken) =>
            inner.CreatePhoneOwnershipRecoveryRequestAsync(targetAccountId, reason, createdAt, cancellationToken);
        public Task<bool> HasApprovedAliasAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId, CancellationToken cancellationToken) =>
            inner.HasApprovedAliasAsync(originalTransactionId, oldAppAccountToken, targetAccountId, cancellationToken);
        public Task<StoreKitRecoveryRequest?> FindRecoveryRequestAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId, CancellationToken cancellationToken) =>
            inner.FindRecoveryRequestAsync(originalTransactionId, oldAppAccountToken, targetAccountId, cancellationToken);
        public Task<Guid> ApproveRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId,
            Func<StoreKitRecoveryRequest, CancellationToken, Task<VerifiedStoreKitTransaction>> getAuthoritativeCurrentTransaction,
            DateTimeOffset approvedAt, CancellationToken cancellationToken) =>
            inner.ApproveRecoveryAsync(originalTransactionId, oldAppAccountToken, targetAccountId,
                getAuthoritativeCurrentTransaction, approvedAt, cancellationToken);
        public Task BlockRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId,
            string reason, DateTimeOffset updatedAt, CancellationToken cancellationToken) =>
            inner.BlockRecoveryAsync(originalTransactionId, oldAppAccountToken, targetAccountId, reason, updatedAt, cancellationToken);
    }
}
