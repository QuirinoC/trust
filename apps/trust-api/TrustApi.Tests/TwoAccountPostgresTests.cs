using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

/// Two real accounts on the local Trust Postgres (port 5433). Not two phones.
public sealed class TwoAccountPostgresTests
{
    private static readonly string Connection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task TwoAccountsCoverShareHistoryPauseStopRemoveAndDelete()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 1, 18, 0, 0, TimeSpan.Zero) };
        var engine = new TrustEngine(store, time);
        var suffix = Guid.NewGuid().ToString("N");
        var sam = await engine.SignInAsync("development", $"e2e-sam-{suffix}", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", $"e2e-jordan-{suffix}", "Jordan", CancellationToken.None);

        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);

        var joined = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var samRow = joined.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(joined.Coverage.IsCovered);
        Assert.Equal(ShareResting.Off, samRow.InboundShare.Effective(time.UtcNow));
        Assert.Null(samRow.Live);

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(time.UtcNow, 37.750, -122.410),
            80,
            false,
            CancellationToken.None);
        var look = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        Assert.Equal(LookKind.Look, look.Session.Event.Kind);
        Assert.Equal(0, look.Session.Event.HistoryWindowHours);
        Assert.Single(look.Session.Trail);

        var afterLook = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var sealedSam = afterLook.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(sealedSam.InboundLive);
        Assert.Null(sealedSam.Live);
        Assert.Contains(afterLook.LookLog, item => item.Kind == LookKind.Look && item.SubjectId == sam.Id);

        await engine.SetShareAsync(sam.Id, jordan.Id, null, PauseDuration.OneHour, CancellationToken.None);
        var duringPause = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var paused = duringPause.Members.Single(member => member.Person.Id == sam.Id);
        Assert.Equal(ShareResting.Paused, paused.InboundShare.Effective(time.UtcNow));
        Assert.Equal(ShareResting.UntilTheyLook, paused.InboundShare.RestoresTo);
        Assert.Null(paused.Live);
        Assert.DoesNotContain(duringPause.LookLog, item => item.Kind == LookKind.Removed);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(time.UtcNow, 37.900, -122.900),
            80,
            false,
            CancellationToken.None);
        Assert.Equal(37.750, (await store.LatestLocationAsync(sam.Id, CancellationToken.None))!.Latitude, 3);

        time.UtcNow = time.UtcNow.AddHours(2);
        var restored = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var restoredShare = restored.Members.Single(member => member.Person.Id == sam.Id).InboundShare;
        Assert.Equal(ShareResting.UntilTheyLook, restoredShare.Effective(time.UtcNow));
        Assert.Equal(ShareResting.UntilTheyLook, restoredShare.Resting);

        await engine.IngestAsync(sam.Id, new LocationFix(time.UtcNow.AddDays(-20), 37.100, -122.100), 70, false, CancellationToken.None);
        await engine.IngestAsync(sam.Id, new LocationFix(time.UtcNow.AddHours(-30), 37.200, -122.200), 70, false, CancellationToken.None);
        await engine.IngestAsync(sam.Id, new LocationFix(time.UtcNow.AddMinutes(-30), 37.300, -122.300), 70, false, CancellationToken.None);

        var sealedHistory = await Assert.ThrowsAsync<TrustException>(() =>
            engine.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None));
        Assert.Equal("share_off", sealedHistory.Code);

        await engine.GrantCircleAsync(jordan.Id, "test", CancellationToken.None);
        var stillSealed = await Assert.ThrowsAsync<TrustException>(() =>
            engine.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None));
        Assert.Equal("share_off", stillSealed.Code);

        var samStillFree = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.False(samStillFree.Coverage.IsCovered);
        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None));
        Assert.Equal("pro_required", blocked.Code);

        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        var plusHistory = await engine.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Equal(new[] { 37.300, 37.750, 37.200, 37.100 }, plusHistory.Select(point => point.Latitude).ToArray());
        await engine.IngestAsync(sam.Id, new LocationFix(time.UtcNow, 37.770, -122.420), 90, false, CancellationToken.None);
        var always = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var liveSam = always.Members.Single(member => member.Person.Id == sam.Id);
        Assert.True(liveSam.InboundLive);
        Assert.NotNull(liveSam.Live);
        Assert.Equal(37.770, liveSam.Live!.Latitude, 3);
        var view = await engine.ViewAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Equal(LookKind.View, view!.Kind);
        Assert.Contains(
            (await engine.GetCircleAsync(sam.Id, CancellationToken.None)).LookLog,
            item => item.Kind == LookKind.View && item.ViewerId == jordan.Id);

        var ada = await engine.SignInAsync("development", $"e2e-ada-{suffix}", "Ada", CancellationToken.None);
        var adaInvite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(ada.Id, adaInvite.Code, CancellationToken.None);
        var adaCircle = await engine.GetCircleAsync(ada.Id, CancellationToken.None);
        Assert.False(adaCircle.Coverage.IsCovered);
        Assert.Equal(TrustRules.FreeSeats, adaCircle.Coverage.SeatLimit);
        var adaSeesSam = adaCircle.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(adaSeesSam.InboundLive);
        Assert.Null(adaSeesSam.Live);

        await engine.SetShareAsync(sam.Id, ada.Id, ShareResting.Always, null, CancellationToken.None);
        var adaAlways = await engine.GetCircleAsync(ada.Id, CancellationToken.None);
        Assert.False(adaAlways.Coverage.IsCovered);
        var adaLive = adaAlways.Members.Single(member => member.Person.Id == sam.Id);
        Assert.True(adaLive.InboundLive);
        Assert.Null(adaLive.Live);

        await engine.SetShareAsync(sam.Id, ada.Id, ShareResting.Off, null, CancellationToken.None);
        var stopped = await engine.GetCircleAsync(ada.Id, CancellationToken.None);
        var stoppedSam = stopped.Members.Single(member => member.Person.Id == sam.Id);
        Assert.Equal(ShareResting.Off, stoppedSam.InboundShare.Effective(time.UtcNow));
        Assert.Null(stoppedSam.Live);
        Assert.DoesNotContain(stopped.LookLog, item => item.Kind == LookKind.Removed && item.SubjectId == sam.Id);

        await engine.RevokeAsync(sam.Id, ada.Id, CancellationToken.None);
        var removed = await engine.GetCircleAsync(ada.Id, CancellationToken.None);
        Assert.DoesNotContain(removed.Members, member => member.Person.Id == sam.Id);
        Assert.Contains(removed.LookLog, item => item.Kind == LookKind.Removed && item.ViewerId == sam.Id && item.SubjectId == ada.Id);

        await engine.SetHomePlaceAsync(sam.Id, Guid.NewGuid(), "Home", CancellationToken.None);
        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Away, null, CancellationToken.None);
        Assert.NotNull(await store.GetCurrentHomePresenceAsync(sam.Id, CancellationToken.None));
        await engine.DeleteAccountAsync(sam.Id, CancellationToken.None);
        Assert.Null(await store.FindAccountAsync(sam.Id, CancellationToken.None));
        Assert.Null(await store.GetCurrentHomePresenceAsync(sam.Id, CancellationToken.None));

        await engine.DeleteAccountAsync(jordan.Id, CancellationToken.None);
        await engine.DeleteAccountAsync(ada.Id, CancellationToken.None);
    }
}
