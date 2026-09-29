using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.StoreKit;
using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure;

namespace TrustApi.Tests;

public sealed class AgeAssuranceAccountStoreTests
{
    [Fact]
    public async Task PendingRevocationCleanupHidesAccountLocationHistoryAndViewLogsFromConnectedPeople()
    {
        var trustStore = new MemoryTrustStore();
        var ageStore = new MemoryAgeAssuranceAccountStore();
        var engine = new TrustEngine(trustStore, TimeProvider.System, ageStore);
        var subject = await engine.SignInAsync("development", "subject-child", "Child", CancellationToken.None);
        var viewer = await engine.SignInAsync("development", "viewer-parent", "Parent", CancellationToken.None);
        await engine.ConnectAccountsAsync(viewer.Id, subject.Id, CancellationToken.None);
        await engine.GrantCircleAsync(subject.Id, "test", CancellationToken.None);
        await engine.GrantCircleAsync(viewer.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(subject.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.IngestAsync(
            subject.Id,
            new LocationFix(DateTimeOffset.UtcNow, 37.77, -122.42),
            80,
            false,
            CancellationToken.None);
        await engine.ViewAsync(viewer.Id, subject.Id, CancellationToken.None);

        var beforeRevocation = await engine.GetCircleAsync(viewer.Id, CancellationToken.None);
        Assert.Single(beforeRevocation.Members);
        Assert.Single(beforeRevocation.LookLog);
        Assert.Single(await engine.HistoryAsync(viewer.Id, subject.Id, CancellationToken.None));

        var appTransaction = new VerifiedStoreKitAppTransaction(
            "child-app-transaction-cleanup-pending",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var notificationId = Guid.NewGuid();
        Assert.Equal(AppTransactionLinkResult.Linked, await ageStore.TryRegisterAppTransactionLinkAsync(
            subject.Id,
            appTransaction,
            CancellationToken.None));
        Assert.Equal(new[] { subject.Id }, await ageStore.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            DateTimeOffset.UtcNow,
            CancellationToken.None));

        // Simulate failed account cleanup: the account and its stored location still exist,
        // so every read path must honor the durable block until deletion completes.
        var afterRevocation = await engine.GetCircleAsync(viewer.Id, CancellationToken.None);
        Assert.Empty(afterRevocation.Members);
        Assert.Empty(afterRevocation.LookLog);

        var historyError = await Assert.ThrowsAsync<TrustException>(() =>
            engine.HistoryAsync(viewer.Id, subject.Id, CancellationToken.None));
        Assert.Equal("not_connected", historyError.Code);
        var viewError = await Assert.ThrowsAsync<TrustException>(() =>
            engine.ViewAsync(viewer.Id, subject.Id, CancellationToken.None));
        Assert.Equal("not_connected", viewError.Code);
    }

    [Fact]
    public async Task RevocationReturnsLinkedAccountsUntilTheyAreDeletedAndIsIdempotent()
    {
        var store = new MemoryAgeAssuranceAccountStore();
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-123",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountId = Guid.NewGuid();
        var otherAccountId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();
        Assert.Equal(AppTransactionLinkResult.Linked, await store.TryRegisterAppTransactionLinkAsync(accountId, appTransaction, CancellationToken.None));
        Assert.Equal(AppTransactionLinkResult.Linked, await store.TryRegisterAppTransactionLinkAsync(otherAccountId, appTransaction, CancellationToken.None));

        var first = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            DateTimeOffset.UtcNow.AddHours(-1),
            CancellationToken.None);

        Assert.Equal(new[] { accountId, otherAccountId }.Order(), first.Order());

        await store.RemoveAppTransactionLinkAsync(accountId, appTransaction, CancellationToken.None);
        var retry = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            DateTimeOffset.UtcNow.AddHours(-1),
            CancellationToken.None);

        Assert.Equal(new[] { otherAccountId }, retry);

        await store.RemoveAppTransactionLinkAsync(otherAccountId, appTransaction, CancellationToken.None);
        var completedRetry = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            DateTimeOffset.UtcNow.AddHours(-1),
            CancellationToken.None);

        Assert.Empty(completedRetry);
    }

    [Fact]
    public async Task AppTransactionReplayAfterRevocationDoesNotRelinkOrRestoreConsent()
    {
        var store = new MemoryAgeAssuranceAccountStore();
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-456",
            "com.collapsetechnologies.trust",
            "Production");
        var originalAccountId = Guid.NewGuid();
        var replayAccountId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();
        var revokedAt = DateTimeOffset.UtcNow.AddHours(-1);
        Assert.Equal(AppTransactionLinkResult.Linked, await store.TryRegisterAppTransactionLinkAsync(
            originalAccountId,
            appTransaction,
            CancellationToken.None));

        var affected = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            revokedAt,
            CancellationToken.None);
        Assert.Equal(new[] { originalAccountId }, affected);

        await store.CompleteAccountDeletionAsync(originalAccountId, CancellationToken.None);
        Assert.Equal(AppTransactionLinkResult.ConsentRevoked, await store.TryRegisterAppTransactionLinkAsync(
            replayAccountId,
            appTransaction,
            CancellationToken.None));

        var laterRescind = await store.RecordConsentRevocationAsync(
            Guid.NewGuid(),
            appTransaction,
            revokedAt.AddMinutes(-1),
            CancellationToken.None);
        Assert.Equal(new[] { replayAccountId }, laterRescind);

        await store.CompleteAccountDeletionAsync(replayAccountId, CancellationToken.None);

        var duplicate = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            revokedAt,
            CancellationToken.None);

        Assert.Empty(duplicate);
    }

    [Fact]
    public async Task StaleAppTransactionRegistrationCannotClearConsentRevocation()
    {
        var store = new MemoryAgeAssuranceAccountStore();
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-stale-link",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();
        var revokedAt = DateTimeOffset.UtcNow;

        Assert.Equal(AppTransactionLinkResult.Linked, await store.TryRegisterAppTransactionLinkAsync(
            accountId,
            appTransaction,
            CancellationToken.None));
        var affected = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            revokedAt,
            CancellationToken.None);
        Assert.Equal(new[] { accountId }, affected);

        await store.RemoveAppTransactionLinkAsync(accountId, appTransaction, CancellationToken.None);
        var staleAccountId = Guid.NewGuid();
        Assert.Equal(AppTransactionLinkResult.ConsentRevoked, await store.TryRegisterAppTransactionLinkAsync(
            staleAccountId,
            appTransaction,
            CancellationToken.None));

        var replay = await store.RecordConsentRevocationAsync(
            notificationId,
            appTransaction,
            revokedAt,
            CancellationToken.None);

        Assert.Equal(new[] { staleAccountId }, replay);
    }

    [Fact]
    public async Task StaleRescindStillRevokesAnAccountRegisteredAfterItsSignedAt()
    {
        var store = new MemoryAgeAssuranceAccountStore();
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-789",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountId = Guid.NewGuid();
        var signedAt = DateTimeOffset.UtcNow.AddHours(-1);
        await store.TryRegisterAppTransactionLinkAsync(
            accountId,
            appTransaction,
            CancellationToken.None);

        var result = await store.RecordConsentRevocationAsync(
            Guid.NewGuid(),
            appTransaction,
            signedAt,
            CancellationToken.None);

        Assert.Equal(new[] { accountId }, result);
    }

    [Fact]
    public async Task RevokedRegistrationCreatesDurableBlockAndNotificationRetryFindsItUntilCleanupCompletes()
    {
        var store = new MemoryAgeAssuranceAccountStore();
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-blocked-retry",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var originalAccountId = Guid.NewGuid();
        var recreatedAccountId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();

        Assert.Equal(AppTransactionLinkResult.Linked, await store.TryRegisterAppTransactionLinkAsync(originalAccountId, appTransaction, CancellationToken.None));
        await store.RecordConsentRevocationAsync(notificationId, appTransaction, DateTimeOffset.UtcNow, CancellationToken.None);
        Assert.True(await store.IsAccountBlockedAsync(originalAccountId, CancellationToken.None));

        Assert.Equal(AppTransactionLinkResult.ConsentRevoked, await store.TryRegisterAppTransactionLinkAsync(recreatedAccountId, appTransaction, CancellationToken.None));
        Assert.True(await store.IsAccountBlockedAsync(recreatedAccountId, CancellationToken.None));
        Assert.Equal(
            new[] { originalAccountId, recreatedAccountId }.Order(),
            (await store.RecordConsentRevocationAsync(notificationId, appTransaction, DateTimeOffset.UtcNow, CancellationToken.None)).Order());

        await store.CompleteAccountDeletionAsync(recreatedAccountId, CancellationToken.None);
        Assert.False(await store.IsAccountBlockedAsync(recreatedAccountId, CancellationToken.None));
        Assert.True(await store.IsAccountBlockedAsync(originalAccountId, CancellationToken.None));
    }
}
