using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;
using Npgsql;

namespace TrustApi.Tests;

[Collection("Postgres integration")]
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

        var sealedHistory = await Assert.ThrowsAsync<TrustException>(() =>
            afterRestart.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None));
        Assert.Equal("share_off", sealedHistory.Code);
        await afterRestart.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await afterRestart.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        Assert.Equal(4, (await afterRestart.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None)).Count);
        await afterRestart.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);

        var receipts = await restarted.ListLooksAsync(sam.Id, time.UtcNow.AddDays(-1), CancellationToken.None);
        Assert.Contains(receipts, item => item.Id == look.Event.Id && item.IncludedLive && item.Kind == LookKind.Look);

        // Returning to Sealed closes the live pin after the Always history read.
        var sealedView = await afterRestart.GetCircleAsync(jordan.Id, CancellationToken.None);
        Assert.Null(sealedView.Members.Single(member => member.Person.Id == sam.Id).Live);
        Assert.False(sealedView.Members.Single(member => member.Person.Id == sam.Id).InboundLive);
        Assert.Null(sealedView.ActiveSession);
        var subjectView = await afterRestart.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.Null(subjectView.BeingWatched);

        await afterRestart.DeleteAccountAsync(sam.Id, CancellationToken.None);
        await afterRestart.DeleteAccountAsync(jordan.Id, CancellationToken.None);
    }

    [Fact]
    public async Task StopAllSerializesPostgresIngestAndInvalidatesPreStopRevisionsAfterReenable()
    {
        try
        {
            await PostgresMigrator.ApplyAsync(Connection);
        }
        catch (Exception exception)
        {
            Console.WriteLine($"Skipping Postgres Stop All race test; docker Postgres is not on 5433 ({exception.Message}).");
            return;
        }

        var store = new PostgresTrustStore(Connection);
        var engine = new TrustEngine(store, TimeProvider.System);
        var suffix = Guid.NewGuid().ToString("N");
        var sam = await engine.SignInAsync("development", $"pg-stop-sam-{suffix}", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", $"pg-stop-jordan-{suffix}", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);

        var beforeStop = await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None);
        var observed = new Dictionary<Guid, long> { [jordan.Id] = beforeStop.Revision };
        var point = new LocationFix(DateTimeOffset.UtcNow, 37.3, -122.0);
        Assert.True(await store.TryIngestLocationWhileSharingAsync(sam.Id, point, DateTimeOffset.UtcNow, observed, CancellationToken.None));

        await engine.StopAllOutboundSharingAsync(sam.Id, CancellationToken.None);
        var stopped = await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None);
        var connectionId = await store.GetActiveMembershipIdAsync(sam.Id, jordan.Id, CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, connectionId, stopped.Revision, ShareResting.Always, null, CancellationToken.None);

        Assert.False(await store.TryIngestLocationWhileSharingAsync(
            sam.Id, point with { Timestamp = point.Timestamp.AddSeconds(1) }, DateTimeOffset.UtcNow, observed, CancellationToken.None));
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
        Assert.Equal(ShareResting.Always, (await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None)).Resting);
        Assert.True(await store.AreConnectedAsync(sam.Id, jordan.Id, CancellationToken.None));
        Assert.True(stopped.Revision > beforeStop.Revision);
    }

    [Fact]
    public async Task StopAllAdvancesAnAlreadyOffDirectionAndCreatesMissingActiveDirectionRows()
    {
        try
        {
            await PostgresMigrator.ApplyAsync(Connection);
        }
        catch (Exception exception)
        {
            Console.WriteLine($"Skipping Postgres missing-share Stop All test; local Postgres is unavailable ({exception.Message}).");
            return;
        }

        var store = new PostgresTrustStore(Connection);
        var engine = new TrustEngine(store, TimeProvider.System);
        var suffix = Guid.NewGuid().ToString("N");
        var sam = await engine.SignInAsync("development", $"pg-off-stop-sam-{suffix}", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", $"pg-off-stop-jordan-{suffix}", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        var connectionId = await store.GetActiveMembershipIdAsync(sam.Id, jordan.Id, CancellationToken.None);

        await using (var connection = new NpgsqlConnection(Connection))
        {
            await connection.OpenAsync();
            await using var delete = new NpgsqlCommand(
                "DELETE FROM trust.shares WHERE grantor_id = $1 AND grantee_id = $2;", connection);
            delete.Parameters.AddWithValue(sam.Id);
            delete.Parameters.AddWithValue(jordan.Id);
            await delete.ExecuteNonQueryAsync();
        }
        var observedOffRevision = await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None);
        Assert.Equal(ShareState.Default.Revision, observedOffRevision.Revision);

        await engine.StopAllOutboundSharingAsync(sam.Id, CancellationToken.None);

        var stopped = await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None);
        Assert.Equal(ShareResting.Off, stopped.Resting);
        Assert.True(stopped.Revision > observedOffRevision.Revision);
        var staleEnable = await Assert.ThrowsAsync<TrustException>(() =>
            engine.SetShareAsync(sam.Id, jordan.Id, connectionId, observedOffRevision.Revision, ShareResting.Always, null, CancellationToken.None));
        Assert.Equal("share_state_changed", staleEnable.Code);
        Assert.True(await store.AreConnectedAsync(sam.Id, jordan.Id, CancellationToken.None));
    }

    [Fact]
    public async Task PostgresDelayedIngestCannotRestorePointsAfterRemovingTheLastPeer()
    {
        try
        {
            await PostgresMigrator.ApplyAsync(Connection);
        }
        catch (Exception exception)
        {
            Console.WriteLine($"Skipping Postgres remove/ingest race test; local Postgres is unavailable ({exception.Message}).");
            return;
        }

        var store = new PostgresTrustStore(Connection);
        var engine = new TrustEngine(store, TimeProvider.System);
        var suffix = Guid.NewGuid().ToString("N");
        var sam = await engine.SignInAsync("development", $"pg-remove-sam-{suffix}", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", $"pg-remove-jordan-{suffix}", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        var revision = (await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None)).Revision;
        var observed = new Dictionary<Guid, long> { [jordan.Id] = revision };
        var point = new LocationFix(DateTimeOffset.UtcNow, 37.3, -122.0);
        Assert.True(await store.TryIngestLocationWhileSharingAsync(sam.Id, point, DateTimeOffset.UtcNow, observed, CancellationToken.None));

        await engine.RevokeAsync(sam.Id, jordan.Id, CancellationToken.None);

        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
        Assert.False(await store.TryIngestLocationWhileSharingAsync(
            sam.Id, point with { Timestamp = point.Timestamp.AddSeconds(1) }, DateTimeOffset.UtcNow, observed, CancellationToken.None));
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
        Assert.False(await store.AreConnectedAsync(sam.Id, jordan.Id, CancellationToken.None));
    }

    [Fact]
    public async Task SmsBudgetReservationsAndOtpFailuresAreAtomicAcrossConcurrentCalls()
    {
        try
        {
            await PostgresMigrator.ApplyAsync(Connection);
        }
        catch (Exception exception)
        {
            Console.WriteLine($"Skipping Postgres SMS atomicity test; docker Postgres is not on 5433 ({exception.Message}).");
            return;
        }

        var store = new PostgresTrustStore(Connection);
        var now = DateTimeOffset.UtcNow;
        var suffix = Guid.NewGuid().ToString("N");
        var accountId = Guid.NewGuid();
        var budgets = new[]
        {
            new SmsSendBudget($"account:{accountId:N}", now, 0, null),
            new SmsSendBudget($"phone:+1555{suffix[..7]}", now, 0, null),
            new SmsSendBudget($"account-day:{accountId:N}", now, 0, null),
            new SmsSendBudget($"test-global-day:{suffix}", now, 0, null)
        };
        var reservations = await Task.WhenAll(Enumerable.Range(0, 12).Select(_ =>
            store.TryReserveSmsAsync(budgets, now, CancellationToken.None)));
        Assert.Single(reservations, reserved => reserved);

        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", $"otp-concurrent-{suffix}", "Sam", CancellationToken.None);
        var phone = $"+1555{suffix[..7]}";
        await store.UpsertPhoneChallengeAsync(new PhoneChallenge(
            account.Id,
            phone,
            "not-the-code",
            now.AddMinutes(10),
            0,
            now,
            1,
            now), CancellationToken.None);
        var failures = await Task.WhenAll(Enumerable.Range(0, 12).Select(_ =>
            store.IncrementPhoneChallengeFailureAsync(account.Id, phone, "not-the-code", now, 5, CancellationToken.None)));
        Assert.Equal(new int?[] { 1, 2, 3, 4, 5 }, failures.Where(value => value is not null).Order().ToArray());
        Assert.Equal(7, failures.Count(value => value is null));
        Assert.Null(await store.GetPhoneChallengeAsync(account.Id, CancellationToken.None));
        await store.DeleteAccountAsync(account.Id, CancellationToken.None);
    }
}
