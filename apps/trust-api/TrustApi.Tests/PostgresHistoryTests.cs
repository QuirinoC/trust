using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

public sealed class PostgresHistoryTests
{
    private static readonly string Connection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task LocationTrailAndLookReceiptSurviveNewStoreInstance()
    {
        try
        {
            await PostgresMigrator.ApplyAsync(Connection);
        }
        catch (Exception exception)
        {
            Console.WriteLine($"Skipping Postgres history test; docker Postgres is not on 5433 ({exception.Message}).");
            return;
        }

        var store = new PostgresTrustStore(Connection);
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 8, 30, 19, 0, 0, TimeSpan.Zero) };
        var engine = new TrustEngine(store, time);
        var suffix = Guid.NewGuid().ToString("N");
        var sam = await engine.SignInAsync("development", $"pg-sam-{suffix}", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", $"pg-jordan-{suffix}", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        // Join defaults to Off/Off in M1 — Sam must explicitly seal sharing toward Jordan
        // before location ingest is allowed to persist anything.
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);

        for (var i = 0; i < 4; i++)
        {
            time.UtcNow = time.UtcNow.AddMinutes(12);
            await engine.IngestAsync(
                sam.Id,
                new LocationFix(time.UtcNow, 37.751 + (i * 0.001), -122.411),
                81,
                false,
                CancellationToken.None);
        }

        var lookResult = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        var look = lookResult.Session;
        // Snapshot semantics: Look returns the latest point only, not a trail.
        Assert.Single(look.Trail);
        Assert.Equal(0, look.Event.HistoryWindowHours);
        Assert.Equal(37.754, look.Live.Latitude, 3);

        var restarted = new PostgresTrustStore(Connection);
        var afterRestart = new TrustEngine(restarted, time);
        var trail = await restarted.UnlockLocationsAsync(
            sam.Id,
            time.UtcNow.AddHours(-2),
            time.UtcNow,
            CancellationToken.None);
        Assert.Equal(4, trail.Count);
        Assert.Equal(37.751, trail[0].Latitude, 3);
        Assert.Equal(37.754, trail[^1].Latitude, 3);

        var rebuiltResult = await afterRestart.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        var rebuilt = rebuiltResult.Session;
        Assert.NotEqual(look.Event.Id, rebuilt.Event.Id);
        Assert.Single(rebuilt.Trail);
        Assert.True(rebuiltResult.IsNew);

        var receipts = await restarted.ListLooksAsync(sam.Id, time.UtcNow.AddDays(-1), CancellationToken.None);
        Assert.Contains(receipts, item => item.Id == look.Event.Id && item.IncludedLive && item.Kind == LookKind.Look);

        // A Look does not open a session and does not dump the stored trail.
        var sealedView = await afterRestart.GetCircleAsync(jordan.Id, CancellationToken.None);
        Assert.Null(sealedView.Members.Single(member => member.Person.Id == sam.Id).Live);
        Assert.False(sealedView.Members.Single(member => member.Person.Id == sam.Id).InboundLive);
        Assert.Null(sealedView.ActiveSession);
        var subjectView = await afterRestart.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.Null(subjectView.BeingWatched);

        await afterRestart.DeleteAccountAsync(sam.Id, CancellationToken.None);
        await afterRestart.DeleteAccountAsync(jordan.Id, CancellationToken.None);
    }
}
