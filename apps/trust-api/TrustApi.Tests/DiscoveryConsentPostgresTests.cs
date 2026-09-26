using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

public sealed class DiscoveryConsentPostgresTests
{
    private static readonly string Connection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task ConsentIsPersistedAndLegacyHandleUpdatesPreserveIt()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", $"discovery-{Guid.NewGuid():N}", "Sam", CancellationToken.None);
        var handle = $"d{Guid.NewGuid():N}"[..20];
        try
        {
            await engine.SetHandleAsync(account.Id, handle, CancellationToken.None);
            Assert.False((await store.FindAccountAsync(account.Id, CancellationToken.None))!.DiscoveryEnabled);

            await engine.SetHandleAsync(account.Id, handle, 1, CancellationToken.None);
            Assert.True((await store.FindAccountAsync(account.Id, CancellationToken.None))!.DiscoveryEnabled);

            await engine.SetHandleAsync(account.Id, handle, CancellationToken.None);
            Assert.True((await store.FindAccountAsync(account.Id, CancellationToken.None))!.DiscoveryEnabled);

            await engine.SetDiscoveryConsentAsync(account.Id, false, 1, CancellationToken.None);
            Assert.False((await store.FindAccountAsync(account.Id, CancellationToken.None))!.DiscoveryEnabled);
        }
        finally
        {
            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }
    }
}
