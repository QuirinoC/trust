using Npgsql;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Postgres;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

[Collection("Postgres integration")]
public sealed class PostgresAgeAssuranceRevocationCleanupTests
{
    private static readonly string Connection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task FailedFirstBatchIsBackedOffSoLaterDatabaseJobsAreClaimed()
    {
        const int batchSize = 50;
        await PostgresMigrator.ApplyAsync(Connection);
        var transactionId = $"postgres-cleanup-fairness-{Guid.NewGuid():N}";
        var transaction = new VerifiedStoreKitAppTransaction(
            transactionId,
            "com.collapsetechnologies.trust",
            "Sandbox");
        var hash = AppTransactionIdentifier.Hash(transactionId);
        var notificationId = Guid.NewGuid();
        var accountIds = Enumerable.Range(0, batchSize + 5).Select(_ => Guid.NewGuid()).ToArray();
        var store = new PostgresAgeAssuranceAccountStore(Connection);
        var testTime = new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero);

        try
        {
            foreach (var accountId in accountIds)
                Assert.Equal(AppTransactionLinkResult.Linked, await store.TryRegisterAppTransactionLinkAsync(
                    accountId, transaction, CancellationToken.None));
            Assert.Equal(accountIds.Length, (await store.RecordConsentRevocationAsync(
                notificationId, transaction, testTime, CancellationToken.None)).Count);
            await SetDueTimeAsync(accountIds, testTime.AddYears(-1));

            var firstBatch = await store.ClaimPendingAccountDeletionsAsync(
                batchSize, testTime, TimeSpan.FromMinutes(5), CancellationToken.None);
            Assert.Equal(batchSize, firstBatch.Count);
            foreach (var claim in firstBatch)
                await store.RecordAccountDeletionRetryAsync(claim, testTime.AddSeconds(30), CancellationToken.None);

            // The remaining five are still due at the original time, while the failed
            // first 50 are in backoff. They must be claimed ahead of unrelated rows.
            var laterBatch = await store.ClaimPendingAccountDeletionsAsync(
                batchSize, testTime, TimeSpan.FromMinutes(5), CancellationToken.None);
            Assert.Equal(5, laterBatch.Count);
            Assert.DoesNotContain(laterBatch.Select(item => item.AccountId), firstBatch.Select(item => item.AccountId).Contains);

            foreach (var claim in laterBatch)
                await store.CompleteAccountDeletionAsync(claim.AccountId, CancellationToken.None);

            var retried = await store.ClaimPendingAccountDeletionsAsync(
                batchSize, testTime.AddSeconds(31), TimeSpan.FromMinutes(5), CancellationToken.None);
            Assert.Equal(batchSize, retried.Count);
            Assert.Equal(firstBatch.Select(item => item.AccountId).Order(), retried.Select(item => item.AccountId).Order());
        }
        finally
        {
            foreach (var accountId in accountIds)
                await store.CompleteAccountDeletionAsync(accountId, CancellationToken.None);

            await using var connection = new NpgsqlConnection(Connection);
            await connection.OpenAsync();
            foreach (var table in new[]
            {
                "age_assurance_notifications",
                "age_assurance_revoked_app_transactions"
            })
            {
                await using var command = new NpgsqlCommand(
                    $"DELETE FROM trust.{table} WHERE app_transaction_hash = $1;",
                    connection);
                command.Parameters.AddWithValue(hash);
                await command.ExecuteNonQueryAsync();
            }
        }

        async Task SetDueTimeAsync(IReadOnlyList<Guid> ids, DateTimeOffset dueAt)
        {
            await using var connection = new NpgsqlConnection(Connection);
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand(
                "UPDATE trust.age_assurance_cleanup_jobs SET next_attempt_at = $1 WHERE account_id = ANY($2::uuid[]);",
                connection);
            command.Parameters.AddWithValue(dueAt);
            command.Parameters.AddWithValue(ids.ToArray());
            Assert.Equal(ids.Count, await command.ExecuteNonQueryAsync());
        }
    }
}
