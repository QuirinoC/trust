using Microsoft.Extensions.Options;
using Npgsql;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Postgres;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

[Collection("Postgres integration")]
public sealed class PostgresConnectionIncarnationTests
{
    private static readonly string Connection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task ViewRejectsReaddedConnectionWithSameAlwaysRevisionWithoutReceipt()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var entitlements = new PostgresStoreKitEntitlementStore(Connection);
        var ageAssurance = new PostgresAgeAssuranceAccountStore(Connection);
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.UtcNow };
        var options = Options.Create(new StoreKitOptions { AllowReviewUnlock = true });
        var setup = new TrustEngine(store, time, ageAssurance, entitlements, options);
        var suffix = Guid.NewGuid().ToString("N");
        var owner = await setup.SignInAsync("development", $"incarnation-owner-{suffix}", "Owner", CancellationToken.None);
        var viewer = await setup.SignInAsync("development", $"incarnation-viewer-{suffix}", "Viewer", CancellationToken.None);
        try
        {
            var invite = await setup.CreateInviteAsync(owner.Id, CancellationToken.None);
            await setup.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
            await setup.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
            await setup.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
            await setup.IngestAsync(owner.Id,
                new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);

            var originalConnection = await store.GetActiveMembershipIdAsync(owner.Id, viewer.Id, CancellationToken.None);
            var originalShare = await store.GetShareAsync(owner.Id, viewer.Id, CancellationToken.None);
            var receiptsBefore = await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None);
            var gate = new HistoryViewRaceTests.EntitlementRefreshBarrier(entitlements, blockAtRefresh: 2);
            var engine = new TrustEngine(store, time, ageAssurance, gate, options);
            var pendingView = engine.ViewAsync(viewer.Id, owner.Id, CancellationToken.None);
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

            await store.RevokeMembershipAsync(owner.Id, viewer.Id, CancellationToken.None);
            Assert.True(await store.ConnectAccountsWithOffSharesAsync(owner.Id, viewer.Id, time.UtcNow, CancellationToken.None));
            var replacementConnection = await store.GetActiveMembershipIdAsync(owner.Id, viewer.Id, CancellationToken.None);
            Assert.NotEqual(originalConnection, replacementConnection);
            await using (var connection = new NpgsqlConnection(Connection))
            {
                await connection.OpenAsync();
                await using var restoreSameRevisionAlways = new NpgsqlCommand(
                    "UPDATE trust.shares SET resting='always', pause_until=NULL, restores_to=NULL, revision=$3 WHERE grantor_id=$1 AND grantee_id=$2;",
                    connection);
                restoreSameRevisionAlways.Parameters.AddWithValue(owner.Id);
                restoreSameRevisionAlways.Parameters.AddWithValue(viewer.Id);
                restoreSameRevisionAlways.Parameters.AddWithValue(originalShare.Revision);
                Assert.Equal(1, await restoreSameRevisionAlways.ExecuteNonQueryAsync());
            }
            var replacementShare = await store.GetShareAsync(owner.Id, viewer.Id, CancellationToken.None);
            Assert.Equal(ShareResting.Always, replacementShare.Resting);
            Assert.Equal(originalShare.Revision, replacementShare.Revision);

            gate.Release.TrySetResult();
            var denied = await Assert.ThrowsAsync<TrustException>(() => pendingView);
            Assert.Equal("view_requires_available", denied.Code);
            Assert.Equal(receiptsBefore.Count,
                (await store.ListLooksAsync(viewer.Id, DateTimeOffset.MinValue, CancellationToken.None)).Count);
        }
        finally
        {
            await store.DeleteAccountAsync(viewer.Id, CancellationToken.None);
            await store.DeleteAccountAsync(owner.Id, CancellationToken.None);
        }
    }
}
