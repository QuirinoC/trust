using Microsoft.Extensions.Logging.Abstractions;
using TrustApi.Domain;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.Notifications;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class AgeAssuranceRevocationCleanupWorkerTests
{
    [Fact]
    public async Task FailedFirstBatchDoesNotStarveLaterAccountsAndIsEventuallyRetried()
    {
        const int batchSize = 50;
        var now = new DateTimeOffset(2026, 9, 28, 12, 0, 0, TimeSpan.Zero);
        var clock = new ManualTimeProvider(now);
        var accounts = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var devices = new MemoryPushDeviceStore();
        var transaction = new VerifiedStoreKitAppTransaction(
            "worker-fairness-memory-test",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountIds = Enumerable.Range(0, batchSize + 5).Select(_ => Guid.NewGuid()).ToArray();
        foreach (var accountId in accountIds)
        {
            await accounts.UpsertAccountAsync(
                new Account(accountId, "apple", $"subject-{accountId:N}", "Test", false, null, now),
                CancellationToken.None);
            Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
                accountId, transaction, CancellationToken.None));
        }
        var affected = await ageAssurance.RecordConsentRevocationAsync(
            Guid.NewGuid(), transaction, now, CancellationToken.None);
        Assert.Equal(accountIds.Length, affected.Count);

        var worker = new AgeAssuranceRevocationCleanupWorker(
            ageAssurance,
            accounts,
            devices,
            NullLogger<AgeAssuranceRevocationCleanupWorker>.Instance,
            clock);
        var firstAttempted = new List<Guid>();
        Assert.Equal(0, await worker.RetryPendingAccountsAsync(
            (id, _) =>
            {
                firstAttempted.Add(id);
                throw new IOException("Simulated persistent account deletion failure");
            },
            CancellationToken.None));
        Assert.Equal(batchSize, firstAttempted.Count);
        foreach (var id in firstAttempted)
            Assert.True(await ageAssurance.IsAccountBlockedAsync(id, CancellationToken.None));

        // The failed batch is in backoff, so the next pass progresses to the other
        // due accounts instead of repeatedly selecting those same first 50 IDs.
        var laterAttempted = new List<Guid>();
        Assert.Equal(5, await worker.RetryPendingAccountsAsync(
            async (id, token) =>
            {
                laterAttempted.Add(id);
                await accounts.DeleteAccountAsync(id, token);
            },
            CancellationToken.None));
        Assert.Equal(5, laterAttempted.Count);
        Assert.DoesNotContain(laterAttempted, firstAttempted.Contains);
        foreach (var id in laterAttempted)
            Assert.Null(await accounts.FindAccountAsync(id, CancellationToken.None));

        var retriedAfterBackoff = new List<Guid>();
        clock.Advance(TimeSpan.FromSeconds(31));
        Assert.Equal(batchSize, await worker.RetryPendingAccountsAsync(
            async (id, token) =>
            {
                retriedAfterBackoff.Add(id);
                await accounts.DeleteAccountAsync(id, token);
            },
            CancellationToken.None));
        Assert.Equal(firstAttempted.Order(), retriedAfterBackoff.Order());
        foreach (var id in accountIds)
            Assert.Null(await accounts.FindAccountAsync(id, CancellationToken.None));
        Assert.Empty(await ageAssurance.ClaimPendingAccountDeletionsAsync(50, now.AddHours(1), TimeSpan.FromMinutes(5), CancellationToken.None));
    }

    [Fact]
    public async Task SlowDeletionUsesFreshLeaseForLaterClaimsAcrossWorkers()
    {
        var now = new DateTimeOffset(2026, 9, 28, 12, 0, 0, TimeSpan.Zero);
        var clock = new ManualTimeProvider(now);
        var accounts = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var devices = new MemoryPushDeviceStore();
        var transaction = new VerifiedStoreKitAppTransaction(
            "worker-fresh-lease-test",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountIds = new[] { Guid.NewGuid(), Guid.NewGuid() };
        foreach (var accountId in accountIds)
        {
            await accounts.UpsertAccountAsync(
                new Account(accountId, "apple", $"subject-{accountId:N}", "Test", false, null, now),
                CancellationToken.None);
            Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
                accountId, transaction, CancellationToken.None));
        }
        await ageAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, now, CancellationToken.None);

        var worker = CreateWorker(ageAssurance, accounts, devices, clock);
        var secondDeletionStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseSecondDeletion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var deletionCount = 0;
        var pass = worker.RetryPendingAccountsAsync(async (id, token) =>
        {
            if (Interlocked.Increment(ref deletionCount) == 1) clock.Advance(TimeSpan.FromMinutes(6));
            else
            {
                secondDeletionStarted.SetResult();
                await releaseSecondDeletion.Task.WaitAsync(token);
            }
            await accounts.DeleteAccountAsync(id, token);
        }, CancellationToken.None);

        await secondDeletionStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var competingWorker = CreateWorker(ageAssurance, accounts, devices, clock);
        var duplicateDeletes = new List<Guid>();
        Assert.Equal(0, await competingWorker.RetryPendingAccountsAsync((id, token) =>
        {
            duplicateDeletes.Add(id);
            return accounts.DeleteAccountAsync(id, token);
        }, CancellationToken.None));
        Assert.Empty(duplicateDeletes);

        releaseSecondDeletion.SetResult();
        Assert.Equal(2, await pass);
    }

    [Fact]
    public async Task FailedSlowDeletionSchedulesBackoffFromFailureTime()
    {
        var now = new DateTimeOffset(2026, 9, 28, 12, 0, 0, TimeSpan.Zero);
        var clock = new ManualTimeProvider(now);
        var accounts = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var devices = new MemoryPushDeviceStore();
        var transaction = new VerifiedStoreKitAppTransaction(
            "worker-fresh-backoff-test",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountId = Guid.NewGuid();
        await ageAssurance.TryRegisterAppTransactionLinkAsync(accountId, transaction, CancellationToken.None);
        await ageAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, now, CancellationToken.None);
        var worker = CreateWorker(ageAssurance, accounts, devices, clock);

        Assert.Equal(0, await worker.RetryPendingAccountsAsync((_, _) =>
        {
            clock.Advance(TimeSpan.FromMinutes(6));
            throw new IOException("Simulated slow deletion failure");
        }, CancellationToken.None));
        Assert.Empty(await ageAssurance.ClaimPendingAccountDeletionsAsync(
            1, clock.GetUtcNow(), TimeSpan.FromMinutes(5), CancellationToken.None));

        clock.Advance(TimeSpan.FromSeconds(31));
        Assert.Single(await ageAssurance.ClaimPendingAccountDeletionsAsync(
            1, clock.GetUtcNow(), TimeSpan.FromMinutes(5), CancellationToken.None));
    }

    private static AgeAssuranceRevocationCleanupWorker CreateWorker(
        IAgeAssuranceAccountStore ageAssurance,
        ITrustStore accounts,
        IPushDeviceStore devices,
        TimeProvider clock) =>
        new(
            ageAssurance,
            accounts,
            devices,
            NullLogger<AgeAssuranceRevocationCleanupWorker>.Instance,
            clock);

    private sealed class ManualTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset _utcNow = utcNow;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan by) => _utcNow += by;
    }

    [Fact]
    public async Task RevokedTransactionRegistrationAfterRevocationAlsoEnqueuesDeletion()
    {
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var transaction = new VerifiedStoreKitAppTransaction(
            "worker-late-registration-test",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var now = DateTimeOffset.UtcNow;
        Assert.Empty(await ageAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, now, CancellationToken.None));

        var lateAccount = Guid.NewGuid();
        Assert.Equal(AppTransactionLinkResult.ConsentRevoked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
            lateAccount, transaction, CancellationToken.None));
        var claims = await ageAssurance.ClaimPendingAccountDeletionsAsync(10, now, TimeSpan.FromMinutes(5), CancellationToken.None);
        Assert.Equal(new[] { lateAccount }, claims.Select(claim => claim.AccountId));
    }

    [Fact]
    public async Task LeasePreventsDuplicateClaimsAcrossWorkersAndStaleFailureCannotRescheduleNewLease()
    {
        var now = DateTimeOffset.UtcNow;
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var transaction = new VerifiedStoreKitAppTransaction(
            "worker-lease-test",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountId = Guid.NewGuid();
        await ageAssurance.TryRegisterAppTransactionLinkAsync(accountId, transaction, CancellationToken.None);
        await ageAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, now, CancellationToken.None);

        var first = Assert.Single(await ageAssurance.ClaimPendingAccountDeletionsAsync(1, now, TimeSpan.FromMinutes(1), CancellationToken.None));
        Assert.Empty(await ageAssurance.ClaimPendingAccountDeletionsAsync(1, now, TimeSpan.FromMinutes(1), CancellationToken.None));
        var reclaimed = Assert.Single(await ageAssurance.ClaimPendingAccountDeletionsAsync(1, now.AddMinutes(2), TimeSpan.FromMinutes(1), CancellationToken.None));
        Assert.NotEqual(first.LeaseToken, reclaimed.LeaseToken);

        await ageAssurance.RecordAccountDeletionRetryAsync(first, now.AddSeconds(1), CancellationToken.None);
        Assert.Empty(await ageAssurance.ClaimPendingAccountDeletionsAsync(1, now.AddMinutes(2), TimeSpan.FromMinutes(1), CancellationToken.None));
        await ageAssurance.RecordAccountDeletionRetryAsync(reclaimed, now.AddMinutes(3), CancellationToken.None);
        var due = Assert.Single(await ageAssurance.ClaimPendingAccountDeletionsAsync(1, now.AddMinutes(3), TimeSpan.FromMinutes(1), CancellationToken.None));
        Assert.Equal(1, due.AttemptCount);
    }
}
