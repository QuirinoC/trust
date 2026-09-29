using Npgsql;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

public sealed class PostgresAgeAssurancePrivacyHoldTests
{
    private static readonly string Connection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task PrivacyHoldPersistsOnlyFixedMinimalFieldsAndDoesNotChangeOnReplay()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var accountId = Guid.NewGuid();
        var store = new PostgresAgeAssuranceAccountStore(Connection);
        var originalTime = new DateTimeOffset(2026, 9, 28, 12, 0, 0, TimeSpan.Zero);
        try
        {
            var first = await store.PlaceAccountPrivacyHoldAsync(accountId, originalTime, CancellationToken.None);
            var replay = await store.PlaceAccountPrivacyHoldAsync(accountId, originalTime.AddHours(5), CancellationToken.None);
            Assert.Equal(first, replay);
            Assert.True(await store.IsAccountPrivacyHeldAsync(accountId, CancellationToken.None));
            Assert.Equal(AccountPrivacyHoldPolicy.Version, first.PolicyVersion);
            Assert.Equal(AccountPrivacyHoldPolicy.Reason, first.Reason);

            await using var connection = new NpgsqlConnection(Connection);
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand(
                "SELECT column_name FROM information_schema.columns WHERE table_schema = 'trust' AND table_name = 'age_assurance_privacy_holds' ORDER BY ordinal_position;",
                connection);
            await using var reader = await command.ExecuteReaderAsync();
            var columns = new List<string>();
            while (await reader.ReadAsync()) columns.Add(reader.GetString(0));
            Assert.Equal(new[] { "account_id", "held_at", "policy_version", "reason" }, columns);
        }
        finally
        {
            await store.CompleteAccountDeletionAsync(accountId, CancellationToken.None);
        }
    }
}
