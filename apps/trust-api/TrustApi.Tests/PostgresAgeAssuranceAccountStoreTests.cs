using Npgsql;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Postgres;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class PostgresAgeAssuranceAccountStoreTests
{
    private static readonly string Connection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task LinksAndRevocationsPersistAndDeduplicateAcrossStoreInstances()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var appTransactionId = $"postgres-test-{Guid.NewGuid():N}";
        var hash = AppTransactionIdentifier.Hash(appTransactionId);
        var appTransaction = new VerifiedStoreKitAppTransaction(
            appTransactionId,
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accountId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();
        var signedAt = DateTimeOffset.UtcNow.AddMinutes(-1);

        try
        {
            await new PostgresAgeAssuranceAccountStore(Connection).TryRegisterAppTransactionLinkAsync(
                accountId,
                appTransaction,
                CancellationToken.None);

            var firstStore = new PostgresAgeAssuranceAccountStore(Connection);
            Assert.True(await firstStore.HasAppTransactionLinkAsync(accountId, CancellationToken.None));
            var first = await firstStore.RecordConsentRevocationAsync(
                notificationId,
                appTransaction,
                signedAt,
                CancellationToken.None);
            Assert.Equal(new[] { accountId }, first);
            Assert.Contains(accountId, await firstStore.ListAccountsPendingDeletionAsync(500, CancellationToken.None));

            var restartedStore = new PostgresAgeAssuranceAccountStore(Connection);
            var duplicate = await restartedStore.RecordConsentRevocationAsync(
                notificationId,
                appTransaction,
                signedAt,
                CancellationToken.None);
            Assert.Equal(new[] { accountId }, duplicate);

            await restartedStore.CompleteAccountDeletionAsync(accountId, CancellationToken.None);
            Assert.False(await new PostgresAgeAssuranceAccountStore(Connection)
                .HasAppTransactionLinkAsync(accountId, CancellationToken.None));
            var retriedAfterDelete = await new PostgresAgeAssuranceAccountStore(Connection).RecordConsentRevocationAsync(
                notificationId,
                appTransaction,
                signedAt,
                CancellationToken.None);
            Assert.Empty(retriedAfterDelete);

            var replayAccountId = Guid.NewGuid();
            await new PostgresAgeAssuranceAccountStore(Connection).TryRegisterAppTransactionLinkAsync(
                replayAccountId,
                appTransaction,
                CancellationToken.None);
            Assert.Contains(replayAccountId, await new PostgresAgeAssuranceAccountStore(Connection)
                .ListAccountsPendingDeletionAsync(500, CancellationToken.None));
            var laterRescind = await new PostgresAgeAssuranceAccountStore(Connection).RecordConsentRevocationAsync(
                Guid.NewGuid(),
                appTransaction,
                signedAt.AddMinutes(-1),
                CancellationToken.None);
            Assert.Equal(new[] { replayAccountId }, laterRescind);

            var oldNotificationReplay = await new PostgresAgeAssuranceAccountStore(Connection).RecordConsentRevocationAsync(
                notificationId,
                appTransaction,
                signedAt,
                CancellationToken.None);
            Assert.Equal(new[] { replayAccountId }, oldNotificationReplay);
            await new PostgresAgeAssuranceAccountStore(Connection).CompleteAccountDeletionAsync(replayAccountId, CancellationToken.None);
        }
        finally
        {
            await using var connection = new NpgsqlConnection(Connection);
            await connection.OpenAsync();
            foreach (var table in new[]
            {
                "age_assurance_notifications",
                "age_assurance_revoked_app_transactions",
                "age_assurance_blocked_accounts",
                "age_assurance_app_transactions"
            })
            {
                await using var command = new NpgsqlCommand(
                    $"DELETE FROM trust.{table} WHERE app_transaction_hash = $1;",
                    connection);
                command.Parameters.AddWithValue(hash);
                await command.ExecuteNonQueryAsync();
            }
        }
    }

    [Fact]
    public async Task StaleRescindAppliesAndReplayCannotRestoreRevokedRegistration()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var appTransactionId = $"postgres-stale-link-test-{Guid.NewGuid():N}";
        var hash = AppTransactionIdentifier.Hash(appTransactionId);
        var appTransaction = new VerifiedStoreKitAppTransaction(
            appTransactionId,
            "com.collapsetechnologies.trust",
            "Sandbox");
        var originalAccountId = Guid.NewGuid();
        var replayAccountId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();
        var revokedAt = DateTimeOffset.UtcNow;

        try
        {
            var store = new PostgresAgeAssuranceAccountStore(Connection);
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
            var staleRescind = await store.RecordConsentRevocationAsync(
                Guid.NewGuid(),
                appTransaction,
                revokedAt.AddMinutes(-1),
                CancellationToken.None);
            Assert.Equal(new[] { replayAccountId }, staleRescind);

            var duplicate = await store.RecordConsentRevocationAsync(
                notificationId,
                appTransaction,
                revokedAt,
                CancellationToken.None);
            Assert.Equal(new[] { replayAccountId }, duplicate);
            await store.CompleteAccountDeletionAsync(replayAccountId, CancellationToken.None);
        }
        finally
        {
            await using var connection = new NpgsqlConnection(Connection);
            await connection.OpenAsync();
            foreach (var table in new[]
            {
                "age_assurance_notifications",
                "age_assurance_revoked_app_transactions",
                "age_assurance_app_transactions"
            })
            {
                await using var command = new NpgsqlCommand(
                    $"DELETE FROM trust.{table} WHERE app_transaction_hash = $1;",
                    connection);
                command.Parameters.AddWithValue(hash);
                await command.ExecuteNonQueryAsync();
            }
        }
    }
}
