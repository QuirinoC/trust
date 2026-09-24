using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using TrustApi.Api.V1;
using TrustApi.Infrastructure.Notifications;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using TrustApi.Application;
using TrustApi.Contracts.V1;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.Identity;

namespace TrustApi.Tests;

public sealed class TrustEngineTests
{
    [Fact]
    public void DevelopmentSignInFlagIsRejectedOutsideDevelopment()
    {
        Assert.Throws<InvalidOperationException>(() =>
            AuthOptionsGuard.EnsureDevelopmentSignInIsSafe(new AuthOptions { AllowDevelopmentSignIn = true }, isDevelopment: false));
        AuthOptionsGuard.EnsureDevelopmentSignInIsSafe(new AuthOptions { AllowDevelopmentSignIn = true }, isDevelopment: true);
        AuthOptionsGuard.EnsureDevelopmentSignInIsSafe(new AuthOptions { AllowDevelopmentSignIn = false }, isDevelopment: false);
    }

    [Fact]
    public async Task LookRequiresConfirmAndDoesNotLeakSealedCoordinates()
    {
        var engine = NewEngine(out _);
        var you = await engine.SignInAsync("development", "you", "Sam", CancellationToken.None);
        await engine.EnsureReviewCircleAsync(you.Id, CancellationToken.None);
        var circle = await engine.GetCircleAsync(you.Id, CancellationToken.None);
        var alex = circle.Members.Single(member => member.Person.DisplayName == "Alex");
        var jordan = circle.Members.Single(member => member.Person.DisplayName == "Jordan");

        Assert.False(alex.InboundLive);
        Assert.Null(alex.Live);
        Assert.True(jordan.InboundLive);
        Assert.Null(jordan.Live);

        await Assert.ThrowsAsync<TrustException>(() =>
            engine.LookAsync(you.Id, alex.Person.Id, confirmed: false, CancellationToken.None));

        var lookResult = await engine.LookAsync(you.Id, alex.Person.Id, confirmed: true, CancellationToken.None);
        var session = lookResult.Session;
        // Snapshot semantics: Look returns the latest point only, not a windowed trail.
        Assert.Equal(0, session.Event.HistoryWindowHours);
        Assert.Equal(LookKind.Look, session.Event.Kind);
        Assert.True(session.Event.IncludedLive);
        Assert.Single(session.Trail);
        Assert.All(session.Trail, point =>
        {
            Assert.InRange(point.Latitude, 37, 38);
            Assert.InRange(point.Longitude, -123, -122);
        });

        var after = await engine.GetCircleAsync(you.Id, CancellationToken.None);
        var alexAfter = after.Members.Single(member => member.Person.DisplayName == "Alex");
        // A Look is one snapshot. It does not open a session or flip Sealed to live.
        Assert.False(alexAfter.InboundLive);
        Assert.Null(alexAfter.Live);
        Assert.Null(after.ActiveSession);
        Assert.Null(after.BeingWatched);
        Assert.Contains(after.LookLog, look => look.SubjectName == "Alex" && look.Kind == LookKind.Look);
    }

    [Fact]
    public async Task PauseRestoresPreviousModeOnTheServer()
    {
        var start = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var time = new MutableTimeProvider { UtcNow = start };
        var engine = NewEngine(out var store, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, null, PauseDuration.OneHour, CancellationToken.None);

        var paused = await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None);
        Assert.Equal(ShareResting.Paused, paused.Effective(time.UtcNow));
        Assert.False(paused.RevealsLive(time.UtcNow));
        Assert.False(paused.AcceptsLocation(time.UtcNow));
        Assert.True(paused.KeepsTrail(time.UtcNow));

        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 37.70, -122.40), 80, false, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));

        time.UtcNow = start.AddHours(1).AddMinutes(1);
        var restored = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        var outbound = restored.Members.Single(member => member.Person.Id == jordan.Id).OutboundShare;
        Assert.Equal(ShareResting.UntilTheyLook, outbound.Effective(time.UtcNow));
        Assert.True(outbound.AcceptsLocation(time.UtcNow));
    }

    [Fact]
    public async Task IngestPersistsForSealedAndAlwaysButNotPauseOrOff()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero) };
        var engine = NewEngine(out var store, time);
        var (sam, jordan) = await PairAsync(engine);

        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 9.87, -122.40), 80, false, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 37.71, -122.40), 80, false, CancellationToken.None);
        Assert.Equal(37.71, (await store.LatestLocationAsync(sam.Id, CancellationToken.None))!.Latitude);

        var look = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        Assert.False((await engine.GetCircleAsync(jordan.Id, CancellationToken.None)).Coverage.IsCovered);
        Assert.Equal(37.71, look.Session.Live.Latitude, 3);

        await engine.SetShareAsync(sam.Id, jordan.Id, null, PauseDuration.OneHour, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 1.23, -122.40), 80, false, CancellationToken.None);
        Assert.Equal(37.71, (await store.LatestLocationAsync(sam.Id, CancellationToken.None))!.Latitude);

        time.UtcNow = time.UtcNow.AddHours(2);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Off, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 6.66, -122.40), 80, false, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));

        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None));
        Assert.Equal("pro_required", blocked.Code);

        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);
        var free = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var freeSam = free.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(free.Coverage.IsCovered);
        Assert.True((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Coverage.IsCovered);
        Assert.True(freeSam.InboundLive);
        Assert.Null(freeSam.Live);

        await engine.GrantCircleAsync(jordan.Id, "test", CancellationToken.None);
        var plus = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var plusSam = plus.Members.Single(member => member.Person.Id == sam.Id);
        Assert.True(plus.Coverage.IsCovered);
        Assert.NotNull(plusSam.Live);
        Assert.Equal(37.77, plusSam.Live!.Latitude, 3);
    }

    [Fact]
    public async Task PauseFromAlwaysRestoresAlways()
    {
        var start = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var time = new MutableTimeProvider { UtcNow = start };
        var engine = NewEngine(out _, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, null, PauseDuration.EightHours, CancellationToken.None);
        time.UtcNow = start.AddHours(8).AddSeconds(1);
        var circle = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var inbound = circle.Members.Single(member => member.Person.Id == sam.Id).InboundShare;
        Assert.True(inbound.RevealsLive(time.UtcNow));
    }

    [Fact]
    public void PauseDurationsAreOneHourEightHoursAndOneTwoThreeDays()
    {
        var now = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        Assert.Equal(now.AddHours(1), PauseShare.EndAt(PauseDuration.OneHour, now));
        Assert.Equal(now.AddHours(8), PauseShare.EndAt(PauseDuration.EightHours, now));
        Assert.Equal(now.AddDays(1), PauseShare.EndAt(PauseDuration.OneDay, now));
        Assert.Equal(now.AddDays(2), PauseShare.EndAt(PauseDuration.TwoDays, now));
        Assert.Equal(now.AddDays(3), PauseShare.EndAt(PauseDuration.ThreeDays, now));
        Assert.Equal(PauseDuration.OneHour, ContractMap.ParsePause("1h"));
        Assert.Equal(PauseDuration.EightHours, ContractMap.ParsePause("8h"));
        Assert.Equal(PauseDuration.OneDay, ContractMap.ParsePause("1d"));
        Assert.Equal(PauseDuration.TwoDays, ContractMap.ParsePause("2d"));
        Assert.Equal(PauseDuration.ThreeDays, ContractMap.ParsePause("3d"));
    }

    [Fact]
    public async Task InviteJoinsTwoRealAccounts()
    {
        var engine = NewEngine(out _);
        var sam = await engine.SignInAsync("development", "sam", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", "jordan", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        var circle = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.Contains(circle.Members, member => member.Person.DisplayName == "Jordan");
        var jordanView = circle.Members.Single(member => member.Person.DisplayName == "Jordan");
        Assert.Null(jordanView.Live);
        Assert.False(jordanView.InboundLive);
    }

    [Fact]
    public async Task PlusReadsTrailInAlwaysAndLookRemainsASealedSnapshot()
    {
        var engine = NewEngine(out _);
        var you = await engine.SignInAsync("development", "you", "Sam", CancellationToken.None);
        await engine.EnsureReviewCircleAsync(you.Id, CancellationToken.None);
        await engine.GrantCircleAsync(you.Id, "test", CancellationToken.None);
        var circle = await engine.GetCircleAsync(you.Id, CancellationToken.None);
        Assert.True(circle.Coverage.IsCovered);
        Assert.True(circle.Coverage.ActingIsSponsor);
        var alex = circle.Members.Single(member => member.Person.DisplayName == "Alex");
        await engine.GrantCircleAsync(alex.Person.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(alex.Person.Id, you.Id, ShareResting.Always, null, CancellationToken.None);
        var history = await engine.HistoryAsync(you.Id, alex.Person.Id, CancellationToken.None);
        Assert.True(history.Count > 1);
        Assert.True(history[0].Timestamp >= history[^1].Timestamp);
        await engine.SetShareAsync(alex.Person.Id, you.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        var lookResult = await engine.LookAsync(you.Id, alex.Person.Id, true, CancellationToken.None);
        Assert.Single(lookResult.Session.Trail);
        Assert.Equal(0, lookResult.Session.Event.HistoryWindowHours);
        await engine.PlacePingAsync(you.Id, CancellationToken.None);
    }

    [Fact]
    public async Task IngestIsIgnoredWhenNotSharing()
    {
        var engine = NewEngine(out var store);
        var you = await engine.SignInAsync("development", "you", "Sam", CancellationToken.None);
        await engine.IngestAsync(
            you.Id,
            new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42),
            80,
            false,
            CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(you.Id, CancellationToken.None));
    }

    [Fact]
    public async Task IngestStoresWhenSharing()
    {
        var engine = NewEngine(out var store);
        var sam = await engine.SignInAsync("development", "sam", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", "jordan", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        // Join is Off/Off by default — Sam must explicitly seal sharing toward Jordan first.
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        var fix = new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42);
        await engine.IngestAsync(sam.Id, fix, 70, false, CancellationToken.None);
        var latest = await store.LatestLocationAsync(sam.Id, CancellationToken.None);
        Assert.NotNull(latest);
        Assert.Equal(37.76, latest!.Latitude);
        Assert.Equal(-122.42, latest.Longitude);
    }

    [Fact]
    public async Task OffIsTheJoinDefaultAndIngestSkipsWhenAllOutboundIsOff()
    {
        var engine = NewEngine(out var store);
        var (sam, jordan) = await PairAsync(engine);

        var outbound = await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None);
        var inbound = await store.GetShareAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Equal(ShareResting.Off, outbound.Resting);
        Assert.Equal(ShareResting.Off, inbound.Resting);
        Assert.False(outbound.RevealsLive(DateTimeOffset.UtcNow));

        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42), 80, false, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));

        // Turning sharing on stores; turning back Off wipes what was stored.
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42), 80, false, CancellationToken.None);
        Assert.NotNull(await store.LatestLocationAsync(sam.Id, CancellationToken.None));

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Off, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow, 37.77, -122.43), 80, false, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
    }

    [Fact]
    public async Task CirclePayloadIncludesInboundSharePresentationIncludingOff()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        var snapshot = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        var jordanRow = snapshot.Members.Single(member => member.Person.Id == jordan.Id);
        Assert.Equal(ShareResting.Off, jordanRow.InboundShare.Resting);
        Assert.False(jordanRow.InboundLive);

        var now = DateTimeOffset.UtcNow;
        var wire = ContractMap.Circle(snapshot, false, false, now)
            .Members.Single(member => member.Person.Id == jordan.Id);
        Assert.Equal("off", wire.InboundShare.Presentation);
        Assert.Equal("off", wire.InboundShare.Resting);
    }

    [Fact]
    public async Task LookReturnsOnlyTheLatestPointAsASnapshot()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 8, 30, 18, 0, 0, TimeSpan.Zero) };
        var engine = NewEngine(out _, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        for (var i = 0; i < 5; i++)
        {
            time.UtcNow = time.UtcNow.AddMinutes(20);
            await engine.IngestAsync(
                sam.Id,
                new LocationFix(time.UtcNow, 37.750 + (i * 0.001), -122.410),
                80,
                false,
                CancellationToken.None);
        }

        var sealedCircle = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var sealedSam = sealedCircle.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(sealedSam.InboundLive);
        Assert.Null(sealedSam.Live);

        // Snapshot semantics: Look returns the single latest point, not the ingested history.
        var lookResult = await engine.LookAsync(jordan.Id, sam.Id, confirmed: true, CancellationToken.None);
        var session = lookResult.Session;
        Assert.Equal(0, session.Event.HistoryWindowHours);
        Assert.Single(session.Trail);
        Assert.Equal(37.754, session.Trail[0].Latitude, 3);
        Assert.Equal(session.Trail[0].Latitude, session.Live.Latitude);
        Assert.Equal(LookKind.Look, session.Event.Kind);

        var after = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        // Snapshot semantics: even after a fresh Look, Sam is not "live" for Jordan.
        Assert.Null(after.Members.Single(member => member.Person.Id == sam.Id).Live);
        Assert.False(after.Members.Single(member => member.Person.Id == sam.Id).InboundLive);
        Assert.Null(after.ActiveSession);
        Assert.Contains(after.LookLog, look => look.SubjectId == sam.Id && look.IncludedLive && look.Kind == LookKind.Look);
    }

    [Fact]
    public async Task IngestPrunesPointsOlderThanRetention()
    {
        var start = new DateTimeOffset(2026, 8, 30, 12, 0, 0, TimeSpan.Zero);
        var time = new MutableTimeProvider { UtcNow = start };
        var engine = NewEngine(out var store, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(start, 37.75, -122.41),
            80,
            false,
            CancellationToken.None);
        // Retention is 30 days (Plus trail capacity), not a 3-hour prune.
        Assert.Equal(TimeSpan.FromDays(TrustRules.ProHistoryDays), TrustRules.LocationRetention);
        Assert.Equal(24, TrustRules.FreeHistoryHours);
        time.UtcNow = start.Add(TrustRules.LocationRetention).AddHours(1);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(time.UtcNow, 37.76, -122.42),
            80,
            false,
            CancellationToken.None);
        var kept = await store.UnlockLocationsAsync(
            sam.Id,
            start.AddDays(-2),
            time.UtcNow.AddMinutes(1),
            CancellationToken.None);
        Assert.Single(kept);
        Assert.Equal(37.76, kept[0].Latitude);
    }

    [Fact]
    public async Task SealedShareKeepsHistoryInsideRetentionAndDropsItAfter()
    {
        var start = new DateTimeOffset(2026, 8, 30, 12, 0, 0, TimeSpan.Zero);
        var time = new MutableTimeProvider { UtcNow = start };
        var engine = NewEngine(out var store, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(start, 37.75, -122.41),
            80,
            false,
            CancellationToken.None);

        time.UtcNow = start.AddDays(1);
        await store.PruneAllLocationsAsync(time.UtcNow - TrustRules.LocationRetention, CancellationToken.None);
        var latest = await store.LatestLocationAsync(sam.Id, CancellationToken.None);
        Assert.NotNull(latest);
        Assert.Equal(37.75, latest!.Latitude);

        var look = await engine.LookAsync(jordan.Id, sam.Id, confirmed: true, CancellationToken.None);
        Assert.Equal(37.75, look.Session.Live.Latitude);

        time.UtcNow = start.Add(TrustRules.LocationRetention).AddHours(1);
        await store.PruneAllLocationsAsync(time.UtcNow - TrustRules.LocationRetention, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
    }

    [Fact]
    public async Task HistoryWindowIs24HoursFreeAnd30DaysPlus()
    {
        var start = new DateTimeOffset(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);
        var time = new MutableTimeProvider { UtcNow = start };
        var engine = NewEngine(out _, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);

        await engine.IngestAsync(sam.Id, new LocationFix(start, 37.70, -122.40), 80, false, CancellationToken.None);
        time.UtcNow = start.AddHours(30);
        await engine.IngestAsync(sam.Id, new LocationFix(time.UtcNow, 37.80, -122.50), 80, false, CancellationToken.None);

        var free = await engine.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Single(free);
        Assert.Equal(37.80, free[0].Latitude);

        await engine.GrantCircleAsync(jordan.Id, "test", CancellationToken.None);
        var plus = await engine.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Equal(2, plus.Count);
        Assert.Equal(37.80, plus[0].Latitude);
        Assert.Equal(37.70, plus[1].Latitude);

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        var look = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        Assert.Single(look.Session.Trail);
        Assert.Equal(37.80, look.Session.Live.Latitude);
    }

    [Fact]
    public async Task PlusDoesNotLeakAcrossTheCircle()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.GrantCircleAsync(jordan.Id, "test", CancellationToken.None);

        var samCircle = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.False(samCircle.Coverage.IsCovered);
        Assert.Equal(TrustRules.FreeSeats, samCircle.Coverage.SeatLimit);

        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None));
        Assert.Equal("pro_required", blocked.Code);

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow.AddHours(-2), 37.71, -122.41), 80, false, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow, 37.72, -122.42), 80, false, CancellationToken.None);

        var sealedHistory = await Assert.ThrowsAsync<TrustException>(() =>
            engine.HistoryAsync(jordan.Id, sam.Id, CancellationToken.None));
        Assert.Equal("share_off", sealedHistory.Code);

        var third = await engine.SignInAsync("development", "plus-isolation-ada", "Ada", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(third.Id, invite.Code, CancellationToken.None);
        var ada = await engine.GetCircleAsync(third.Id, CancellationToken.None);
        Assert.False(ada.Coverage.IsCovered);
        Assert.Equal(TrustRules.FreeSeats, ada.Coverage.SeatLimit);
    }

    [Fact]
    public async Task RevokeClearsLocationWhenCircleIsEmpty()
    {
        var engine = NewEngine(out var store);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42),
            70,
            false,
            CancellationToken.None);
        Assert.NotNull(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
        await engine.RevokeAsync(sam.Id, jordan.Id, CancellationToken.None);
        Assert.Null(await store.LatestLocationAsync(sam.Id, CancellationToken.None));
        Assert.Null(await store.LatestLocationAsync(jordan.Id, CancellationToken.None));
        var log = await store.ListLooksAsync(sam.Id, DateTimeOffset.MinValue, CancellationToken.None);
        Assert.Contains(log, look => look.Kind == LookKind.Removed && look.SubjectId == jordan.Id);
        var jordanCircle = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        Assert.DoesNotContain(jordanCircle.Members, member => member.Person.Id == sam.Id);
        Assert.Contains(jordanCircle.LookLog, look => look.Kind == LookKind.Removed);
    }

    [Fact]
    public async Task DeleteAccountRemovesLocationAndLooks()
    {
        var engine = NewEngine(out var store);
        var you = await engine.SignInAsync("development", "you", "Sam", CancellationToken.None);
        await engine.EnsureReviewCircleAsync(you.Id, CancellationToken.None);
        var circle = await engine.GetCircleAsync(you.Id, CancellationToken.None);
        var alex = circle.Members.Single(member => member.Person.DisplayName == "Alex");
        await engine.LookAsync(you.Id, alex.Person.Id, true, CancellationToken.None);
        await engine.DeleteAccountAsync(you.Id, CancellationToken.None);
        Assert.Null(await store.FindAccountAsync(you.Id, CancellationToken.None));
    }

    [Fact]
    public async Task DeleteAccountRemovesPresenceRows()
    {
        var engine = NewEngine(out var store);
        var (sam, jordan) = await PairAsync(engine);
        var placeId = Guid.NewGuid();
        await engine.SetHomePlaceAsync(sam.Id, placeId, "Home", CancellationToken.None);
        await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, true, CancellationToken.None);
        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Away, null, CancellationToken.None);
        await engine.CreatePromiseAsync(sam.Id, jordan.Id, DateTimeOffset.UtcNow.AddHours(2), CancellationToken.None);

        Assert.NotNull(await store.GetHomePlaceAsync(sam.Id, CancellationToken.None));
        Assert.NotNull(await store.GetPresenceGrantAsync(sam.Id, jordan.Id, CancellationToken.None));
        Assert.NotNull(await store.GetCurrentHomePresenceAsync(sam.Id, CancellationToken.None));

        await engine.DeleteAccountAsync(sam.Id, CancellationToken.None);

        Assert.Null(await store.FindAccountAsync(sam.Id, CancellationToken.None));
        Assert.Null(await store.GetHomePlaceAsync(sam.Id, CancellationToken.None));
        Assert.Null(await store.GetPresenceGrantAsync(sam.Id, jordan.Id, CancellationToken.None));
        Assert.Null(await store.GetCurrentHomePresenceAsync(sam.Id, CancellationToken.None));
        Assert.Null(await store.GetActivePromiseAsync(sam.Id, jordan.Id, CancellationToken.None));
    }

    [Fact]
    public async Task SealedMemberDoesNotLeakPresenceWithoutGrant()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42),
            42,
            true,
            CancellationToken.None);
        var jordanView = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var sealedSam = jordanView.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(sealedSam.InboundLive);
        Assert.Null(sealedSam.Presence);
        Assert.Null(sealedSam.HomePresence);
        Assert.False(sealedSam.InboundPresenceGranted);

        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Away, null, CancellationToken.None);
        jordanView = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        sealedSam = jordanView.Members.Single(member => member.Person.Id == sam.Id);
        Assert.Equal(HomePresenceState.Away, sealedSam.HomePresence!.State);
        Assert.Null(sealedSam.Live);
    }

    [Fact]
    public async Task PresenceGrantShowsHomeAwayWithoutCoordinates()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        var placeId = Guid.NewGuid();
        await engine.SetHomePlaceAsync(sam.Id, placeId, "Home", CancellationToken.None);
        await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, true, CancellationToken.None);
        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Away, null, CancellationToken.None);

        var jordanView = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var samMember = jordanView.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(samMember.InboundLive);
        Assert.Null(samMember.Presence);
        Assert.Null(samMember.Live);
        Assert.True(samMember.InboundPresenceGranted);
        Assert.NotNull(samMember.HomePresence);
        Assert.Equal(HomePresenceState.Away, samMember.HomePresence!.State);
        Assert.Equal("Home", samMember.HomePresence.PlaceLabel);

        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Home, null, CancellationToken.None);
        jordanView = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        samMember = jordanView.Members.Single(member => member.Person.Id == sam.Id);
        Assert.Equal(HomePresenceState.Home, samMember.HomePresence!.State);
    }

    [Fact]
    public async Task LookDoesNotOpenAWatchedSession()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 2, 12, 0, 0, TimeSpan.Zero) };
        var engine = NewEngine(out _, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(time.UtcNow, 37.76, -122.42),
            80,
            false,
            CancellationToken.None);
        var opened = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        Assert.True(opened.IsNew);
        Assert.Single(opened.Session.Trail);

        var viewer = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var samMember = viewer.Members.Single(member => member.Person.Id == sam.Id);
        Assert.False(samMember.InboundLive);
        Assert.Null(samMember.Live);
        Assert.Null(viewer.ActiveSession);
        Assert.Contains(viewer.LookLog, look => look.SubjectId == sam.Id && look.Kind == LookKind.Look);

        var subject = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.Null(subject.BeingWatched);
        Assert.Contains(subject.LookLog, look => look.ViewerId == jordan.Id && look.Kind == LookKind.Look);
    }

    [Fact]
    public async Task EachConfirmedLookIsANewReceipt()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id,
            new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42),
            80,
            false,
            CancellationToken.None);
        var first = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        var second = await engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None);
        Assert.True(first.IsNew);
        Assert.True(second.IsNew);
        Assert.NotEqual(first.Session.Event.Id, second.Session.Event.Id);
        Assert.Single(second.Session.Trail);
    }

    [Fact]
    public async Task LookIsRejectedWhenShareIsOffOrAlreadyAvailable()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);

        var offException = await Assert.ThrowsAsync<TrustException>(() =>
            engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None));
        Assert.Equal("share_off", offException.Code);

        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        var availableException = await Assert.ThrowsAsync<TrustException>(() =>
            engine.LookAsync(jordan.Id, sam.Id, true, CancellationToken.None));
        Assert.Equal("look_requires_sealed", availableException.Code);
    }

    [Fact]
    public async Task ViewRequiresInboundAvailableAndDoesNotArmAnActiveLook()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow, 37.76, -122.42), 80, false, CancellationToken.None);

        // Sealed, not Available — View must be rejected (Look is the right action here).
        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            engine.ViewAsync(jordan.Id, sam.Id, CancellationToken.None));
        Assert.Equal("view_requires_available", exception.Code);

        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        var view = await engine.ViewAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.NotNull(view);
        Assert.Equal(LookKind.View, view!.Kind);

        // View never opens a watched session and never pushes.
        var samCircle = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.Null(samCircle.BeingWatched);
        Assert.Null(samCircle.ActiveSession);
    }

    [Fact]
    public async Task LookNotifiesOncePerConfirmAndViewDoesNot()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(DateTimeOffset.UtcNow, 37.71, -122.41), 80, false, CancellationToken.None);

        var receipts = new RecordingReceipts();
        var jordanPrincipal = TestPrincipals.Principal(jordan.Id);
        var look = await TrustEndpoints.LookAsync(
            new LookRequest(sam.Id, true),
            jordanPrincipal,
            engine,
            receipts,
            CancellationToken.None);
        var notified = Assert.Single(receipts.Looks);
        Assert.Equal(LookKind.Look, notified.Kind);
        Assert.Equal(sam.Id, notified.SubjectId);
        Assert.Equal(jordan.DisplayName, notified.ViewerName);

        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        var beforeView = receipts.Looks.Count;
        await TrustEndpoints.ViewAsync(
            new ViewRequest(sam.Id),
            jordanPrincipal,
            engine,
            CancellationToken.None);
        Assert.Equal(beforeView, receipts.Looks.Count);
        Assert.NotNull(look);
    }

    [Fact]
    public async Task ViewDedupesWithinThirtyMinutes()
    {
        var time = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 2, 12, 0, 0, TimeSpan.Zero) };
        var engine = NewEngine(out _, time);
        var (sam, jordan) = await PairAsync(engine);
        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.IngestAsync(
            sam.Id, new LocationFix(time.UtcNow, 37.76, -122.42), 80, false, CancellationToken.None);

        var first = await engine.ViewAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.NotNull(first);

        time.UtcNow = time.UtcNow.AddMinutes(10);
        var deduped = await engine.ViewAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Null(deduped);

        time.UtcNow = time.UtcNow.AddMinutes(25); // 35 minutes after the first View
        var freshAgain = await engine.ViewAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.NotNull(freshAgain);
    }

    [Fact]
    public async Task PlusGatesAlwaysButPauseAndSealedStayFree()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);

        var alwaysBlocked = await Assert.ThrowsAsync<TrustException>(() =>
            engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None));
        Assert.Equal("pro_required", alwaysBlocked.Code);

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, null, PauseDuration.OneDay, CancellationToken.None);
        var paused = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        Assert.Equal(
            ShareResting.Paused,
            paused.Members.Single(member => member.Person.Id == jordan.Id).OutboundShare.Effective(DateTimeOffset.UtcNow));

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Off, null, CancellationToken.None);

        await engine.GrantCircleAsync(sam.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.Always, null, CancellationToken.None);
        var circle = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        var jordanShare = circle.Members.Single(member => member.Person.Id == jordan.Id).OutboundShare;
        Assert.True(jordanShare.RevealsLive(DateTimeOffset.UtcNow));
    }

    [Fact]
    public async Task FreeSeatLimitIsFiveConnections()
    {
        var engine = NewEngine(out _);
        var you = await engine.SignInAsync("development", "seat-you", "You", CancellationToken.None);
        for (var i = 0; i < TrustRules.FreeSeats; i++)
        {
            var friend = await engine.SignInAsync("development", $"seat-friend-{i}", $"Friend{i}", CancellationToken.None);
            var invite = await engine.CreateInviteAsync(you.Id, CancellationToken.None);
            await engine.AcceptInviteAsync(friend.Id, invite.Code, CancellationToken.None);
        }

        var overflow = await engine.SignInAsync("development", "seat-overflow", "Overflow", CancellationToken.None);
        var overflowInvite = await engine.CreateInviteAsync(you.Id, CancellationToken.None);
        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            engine.AcceptInviteAsync(overflow.Id, overflowInvite.Code, CancellationToken.None));
        Assert.Equal("seat_limit", exception.Code);
    }

    [Fact]
    public async Task PlusRaisesSeatLimitToTwenty()
    {
        var engine = NewEngine(out _);
        var you = await engine.SignInAsync("development", "seat-plus-you", "You", CancellationToken.None);
        await engine.GrantCircleAsync(you.Id, "test", CancellationToken.None);

        for (var i = 0; i < TrustRules.FreeSeats + 1; i++)
        {
            var friend = await engine.SignInAsync(
                "development", $"seat-plus-friend-{i}", $"Friend{i}", CancellationToken.None);
            var invite = await engine.CreateInviteAsync(you.Id, CancellationToken.None);
            await engine.AcceptInviteAsync(friend.Id, invite.Code, CancellationToken.None);
        }

        var circle = await engine.GetCircleAsync(you.Id, CancellationToken.None);
        Assert.Equal(TrustRules.FreeSeats + 1, circle.Members.Count);
        Assert.Equal(TrustRules.ProSeats, circle.Coverage.SeatLimit);
    }

    [Fact]
    public async Task HiddenPresenceIsOmittedFromCircleEvenWithGrant()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, true, CancellationToken.None);
        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Hidden, null, CancellationToken.None);

        var jordanView = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var samMember = jordanView.Members.Single(member => member.Person.Id == sam.Id);
        Assert.True(samMember.InboundPresenceGranted);
        Assert.Null(samMember.HomePresence);
    }

    [Fact]
    public async Task PresenceCanBeSetManuallyWithoutAHomePlace()
    {
        var engine = NewEngine(out _);
        var (sam, jordan) = await PairAsync(engine);
        await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, true, CancellationToken.None);

        // No SetHomePlaceAsync call at all — the triad doesn't require Home to be set.
        await engine.PostHomePresenceAsync(sam.Id, HomePresenceState.Away, null, CancellationToken.None);

        var jordanView = await engine.GetCircleAsync(jordan.Id, CancellationToken.None);
        var samMember = jordanView.Members.Single(member => member.Person.Id == sam.Id);
        Assert.NotNull(samMember.HomePresence);
        Assert.Equal(HomePresenceState.Away, samMember.HomePresence!.State);
        Assert.Null(samMember.HomePresence.PlaceLabel);
    }

    private static TrustEngine NewEngine(out MemoryTrustStore store, TimeProvider? time = null)
    {
        store = new MemoryTrustStore();
        return new TrustEngine(store, time ?? TimeProvider.System);
    }

    private static async Task<(Account Sam, Account Jordan)> PairAsync(TrustEngine engine)
    {
        var sam = await engine.SignInAsync("development", $"sam-{Guid.NewGuid():N}", "Sam", CancellationToken.None);
        var jordan = await engine.SignInAsync("development", $"jordan-{Guid.NewGuid():N}", "Jordan", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(sam.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(jordan.Id, invite.Code, CancellationToken.None);
        return (sam, jordan);
    }
}

internal sealed class MutableTimeProvider : TimeProvider
{
    public DateTimeOffset UtcNow { get; set; } = DateTimeOffset.UtcNow;

    public override DateTimeOffset GetUtcNow() => UtcNow;
}

public sealed class TrustApiFactory : WebApplicationFactory<Program>
{
    public TrustApiFactory()
    {
        Environment.SetEnvironmentVariable("Trust__Store", "memory");
        Environment.SetEnvironmentVariable("Trust__SeedReviewCircle", "true");
        Environment.SetEnvironmentVariable("Auth__SigningKey", "development-signing-key-32bytes-min!!");
        Environment.SetEnvironmentVariable("Auth__AllowDevelopmentSignIn", "true");
        Environment.SetEnvironmentVariable("StoreKit__AllowReviewUnlock", "true");
    }
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.UseSetting("Trust:Store", "memory");
        builder.UseSetting("Trust:SeedReviewCircle", "true");
        builder.UseSetting("Auth:SigningKey", "development-signing-key-32bytes-min!!");
        builder.UseSetting("Auth:AllowDevelopmentSignIn", "true");
        builder.UseSetting("StoreKit:AllowReviewUnlock", "true");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Trust:Store"] = "memory",
                ["Trust:SeedReviewCircle"] = "true",
                ["Auth:SigningKey"] = "development-signing-key-32bytes-min!!",
                ["Auth:AllowDevelopmentSignIn"] = "true",
                ["StoreKit:AllowReviewUnlock"] = "true"
            });
        });
    }
}

public sealed class TrustApiTests : IClassFixture<TrustApiFactory>
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _client;
    private readonly TrustApiFactory _factory;

    public TrustApiTests(TrustApiFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task SealedHttpFlowDeniesHistoryAndReturnsSingleConfirmedSnapshot()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        async Task<(string Token, Guid Id)> CreateAccount(string name)
        {
            var response = await client.PostAsJsonAsync("/api/v1/session/development", new
            {
                displayName = name,
                deviceId = Guid.NewGuid().ToString("N")
            });
            response.EnsureSuccessStatusCode();
            using var json = System.Text.Json.JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return (json.RootElement.GetProperty("token").GetString()!,
                json.RootElement.GetProperty("you").GetProperty("id").GetGuid());
        }

        var sam = await CreateAccount("Sealed Sam");
        var jordan = await CreateAccount("Sealed Jordan");
        using var inviteRequest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/invites");
        inviteRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sam.Token);
        var inviteResponse = await client.SendAsync(inviteRequest);
        inviteResponse.EnsureSuccessStatusCode();
        using var inviteJson = System.Text.Json.JsonDocument.Parse(await inviteResponse.Content.ReadAsStringAsync());
        var code = inviteJson.RootElement.GetProperty("code").GetString();

        using var accept = new HttpRequestMessage(HttpMethod.Post, "/api/v1/invites/accept");
        accept.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", jordan.Token);
        accept.Content = JsonContent.Create(new { code });
        (await client.SendAsync(accept)).EnsureSuccessStatusCode();

        using var share = new HttpRequestMessage(HttpMethod.Patch, $"/api/v1/people/{jordan.Id}/share");
        share.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sam.Token);
        share.Content = JsonContent.Create(new { resting = "untilTheyLook" });
        (await client.SendAsync(share)).EnsureSuccessStatusCode();

        using var ingest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/location");
        ingest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sam.Token);
        ingest.Content = JsonContent.Create(new { timestamp = DateTimeOffset.UtcNow, latitude = 37.75, longitude = -122.41 });
        (await client.SendAsync(ingest)).EnsureSuccessStatusCode();

        using var history = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/people/{sam.Id}/history");
        history.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", jordan.Token);
        var denied = await client.SendAsync(history);
        Assert.Equal(System.Net.HttpStatusCode.Conflict, denied.StatusCode);

        using var look = new HttpRequestMessage(HttpMethod.Post, "/api/v1/looks");
        look.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", jordan.Token);
        look.Content = JsonContent.Create(new { subjectId = sam.Id, confirmed = true });
        var looked = await client.SendAsync(look);
        looked.EnsureSuccessStatusCode();
        using var lookJson = System.Text.Json.JsonDocument.Parse(await looked.Content.ReadAsStringAsync());
        Assert.Equal("look", lookJson.RootElement.GetProperty("event").GetProperty("kind").GetString());
        Assert.Single(lookJson.RootElement.GetProperty("trail").EnumerateArray());
        Assert.Equal(37.75, lookJson.RootElement.GetProperty("live").GetProperty("latitude").GetDouble());
    }

    [Fact]
    public async Task DisabledStoreKitRejectsTransactionsEvenWithEmbeddedAppleRoots()
    {
        using var factory = _factory.WithWebHostBuilder(builder => builder.ConfigureAppConfiguration((_, config) =>
            config.AddInMemoryCollection(new Dictionary<string, string?> { ["StoreKit:Enabled"] = "false" })));
        using var client = factory.CreateClient();
        var session = await client.PostAsJsonAsync("/api/v1/session/development", new
        {
            displayName = "StoreKit test",
            deviceId = Guid.NewGuid().ToString("N")
        });
        session.EnsureSuccessStatusCode();
        using var sessionJson = System.Text.Json.JsonDocument.Parse(await session.Content.ReadAsStringAsync());
        var token = sessionJson.RootElement.GetProperty("token").GetString();
        using var transaction = new HttpRequestMessage(HttpMethod.Post, "/api/v1/storekit/transactions");
        transaction.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        transaction.Content = JsonContent.Create(new { signedTransactionInfo = "invalid" });
        var response = await client.SendAsync(transaction);
        Assert.Equal(System.Net.HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task DevelopmentSessionSeedsCircleWithoutLeakingSealedGps()
    {
        var session = await _client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "Sam", provider = "development" });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionWire>(Json);
        Assert.False(string.IsNullOrWhiteSpace(payload?.Token));

        using var circleRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/circle");
        circleRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload!.Token);
        var circleResponse = await _client.SendAsync(circleRequest);
        circleResponse.EnsureSuccessStatusCode();
        var circle = await circleResponse.Content.ReadFromJsonAsync<CircleWire>(Json);
        Assert.NotNull(circle);
        Assert.Equal(3, circle!.Members.Count);
        var alex = circle.Members.Single(member => member.Person.DisplayName == "Alex");
        var jordan = circle.Members.Single(member => member.Person.DisplayName == "Jordan");
        Assert.False(alex.InboundLive);
        Assert.Null(alex.Live);
        Assert.Equal("untilTheyLook", alex.InboundShare!.Presentation);
        Assert.True(jordan.InboundLive);
        Assert.Null(jordan.Live);
        Assert.Equal("always", jordan.InboundShare!.Presentation);

        using var lookRequest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/looks");
        lookRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        lookRequest.Content = JsonContent.Create(new { subjectId = alex.Person.Id, confirmed = true });
        var lookResponse = await _client.SendAsync(lookRequest);
        lookResponse.EnsureSuccessStatusCode();
        var look = await lookResponse.Content.ReadFromJsonAsync<LookWire>(Json);
        Assert.NotNull(look?.Live);
        // Snapshot semantics: Look returns the latest point only.
        Assert.Single(look!.Trail);
        Assert.Equal(0, look.Event.HistoryWindowHours);
    }

    [Fact]
    public async Task IngestAppendsHistoryReleasedOnLook()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.WithWebHostBuilder(builder =>
        {
            builder.UseSetting("Trust:SeedReviewCircle", "false");
            builder.ConfigureAppConfiguration((_, config) =>
            {
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Trust:SeedReviewCircle"] = "false"
                });
            });
        }).CreateClient();

        var samSession = await client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "Sam", provider = "development", deviceId = Guid.NewGuid().ToString("N") });
        samSession.EnsureSuccessStatusCode();
        var sam = await samSession.Content.ReadFromJsonAsync<SessionWire>(Json);
        var jordanSession = await client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "Jordan", provider = "development", deviceId = Guid.NewGuid().ToString("N") });
        jordanSession.EnsureSuccessStatusCode();
        var jordan = await jordanSession.Content.ReadFromJsonAsync<SessionWire>(Json);

        using var inviteRequest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/invites");
        inviteRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sam!.Token);
        var inviteResponse = await client.SendAsync(inviteRequest);
        inviteResponse.EnsureSuccessStatusCode();
        var invite = await inviteResponse.Content.ReadFromJsonAsync<InviteWire>(Json);

        using var accept = new HttpRequestMessage(HttpMethod.Post, "/api/v1/invites/accept");
        accept.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", jordan!.Token);
        accept.Content = JsonContent.Create(new { code = invite!.Code });
        (await client.SendAsync(accept)).EnsureSuccessStatusCode();

        // Join is Off/Off by default — Sam must explicitly seal sharing toward Jordan first.
        using var shareRequest = new HttpRequestMessage(HttpMethod.Patch, $"/api/v1/people/{jordan.You.Id}/share");
        shareRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sam.Token);
        shareRequest.Content = JsonContent.Create(new { resting = "untilTheyLook" });
        (await client.SendAsync(shareRequest)).EnsureSuccessStatusCode();

        var now = DateTimeOffset.UtcNow;
        for (var i = 0; i < 3; i++)
        {
            using var ingest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/location");
            ingest.Headers.Authorization =
                new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", sam.Token);
            ingest.Content = JsonContent.Create(new
            {
                timestamp = now.AddMinutes(-40 + (i * 15)),
                latitude = 37.75 + (i * 0.002),
                longitude = -122.41
            });
            (await client.SendAsync(ingest)).EnsureSuccessStatusCode();
        }

        using var lookRequest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/looks");
        lookRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", jordan.Token);
        lookRequest.Content = JsonContent.Create(new { subjectId = sam.You.Id, confirmed = true });
        var lookResponse = await client.SendAsync(lookRequest);
        lookResponse.EnsureSuccessStatusCode();
        var look = await lookResponse.Content.ReadFromJsonAsync<LookWire>(Json);
        Assert.NotNull(look?.Live);
        // Snapshot semantics: Look returns the latest ingested point only.
        Assert.Single(look!.Trail);
        Assert.Equal(0, look.Event.HistoryWindowHours);
        Assert.Equal(37.75 + (2 * 0.002), look.Live.Latitude, 3);
    }

    [Fact]
    public async Task DeleteAccountRequiresAuthAndRemovesSessionSubject()
    {
        var session = await _client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "Sam", provider = "development" });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionWire>(Json);

        using var delete = new HttpRequestMessage(HttpMethod.Delete, "/api/v1/account");
        delete.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload!.Token);
        var deleted = await _client.SendAsync(delete);
        deleted.EnsureSuccessStatusCode();

        using var circleRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/circle");
        circleRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        var circleResponse = await _client.SendAsync(circleRequest);
        Assert.Equal(System.Net.HttpStatusCode.Unauthorized, circleResponse.StatusCode);
    }

    [Fact]
    public async Task LegalPagesRedirectToCanonicalWebsite()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        foreach (var (path, destination) in new[]
        {
            ("/Privacy", "https://jointrust.app/privacy"),
            ("/Terms", "https://jointrust.app/terms"),
            ("/Support", "https://jointrust.app/support")
        })
        {
            var response = await client.GetAsync(path);
            Assert.Equal(System.Net.HttpStatusCode.MovedPermanently, response.StatusCode);
            Assert.Equal(destination, response.Headers.Location?.ToString());
        }
    }

    [Fact]
    public async Task LiveHealthDoesNotRequireAuth()
    {
        var response = await _client.GetAsync("/health/live");
        response.EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task AppleSessionMintsAccountWhenIdentityValidates()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddSingleton<IAppleIdentityValidator>(new StubAppleValidator());
            });
        }).CreateClient();

        var response = await client.PostAsJsonAsync(
            "/api/v1/session/apple",
            new { identityToken = "verified", displayName = "Juan" });
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<SessionWire>(Json);
        Assert.False(string.IsNullOrWhiteSpace(payload?.Token));
        Assert.Equal("Juan", payload!.You.DisplayName);
    }

    [Fact]
    public async Task AppleSessionFallsBackInDevelopmentWhenTokenIsUnverified()
    {
        var token = AppleShapedJwt.Sign("001234.unverified", "juan@privaterelay.appleid.com");
        var response = await _client.PostAsJsonAsync(
            "/api/v1/session/apple",
            new { identityToken = token, displayName = "Juan" });
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<SessionWire>(Json);
        Assert.False(string.IsNullOrWhiteSpace(payload?.Token));
        Assert.Equal("Juan", payload!.You.DisplayName);
    }

    private sealed record SessionWire(string Token, PersonWire You);
    private sealed record PersonWire(Guid Id, string DisplayName, bool HasCircle);
    private sealed record LocationWire(DateTimeOffset Timestamp, double Latitude, double Longitude);
    private sealed record ShareWire(string Resting, string Presentation);
    private sealed record MemberWire(PersonWire Person, bool InboundLive, LocationWire? Live, ShareWire InboundShare);
    private sealed record CircleWire(IReadOnlyList<MemberWire> Members);
    private sealed record LookEventWire(int HistoryWindowHours);
    private sealed record LookWire(LookEventWire Event, LocationWire Live, IReadOnlyList<LocationWire> Trail);
    private sealed record InviteWire(string Code);

    [Fact]
    public async Task AppleSessionReturnsUnavailableWhenAppleDirectoryTimesOut()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.AddSingleton<IAppleIdentityValidator>(new CancelledAppleValidator());
            });
        }).CreateClient();

        var response = await client.PostAsJsonAsync(
            "/api/v1/session/apple",
            new { identityToken = "not-a-jwt", displayName = "Juan" });
        Assert.Equal(System.Net.HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    private sealed class StubAppleValidator : IAppleIdentityValidator
    {
        public Task<ExternalIdentity> ValidateAsync(string identityToken, CancellationToken cancellationToken) =>
            Task.FromResult(new ExternalIdentity("apple", "apple-user-1", "Apple Name"));
    }

    private sealed class CancelledAppleValidator : IAppleIdentityValidator
    {
        public Task<ExternalIdentity> ValidateAsync(string identityToken, CancellationToken cancellationToken) =>
            Task.FromException<ExternalIdentity>(new TaskCanceledException("Apple JWKS timed out."));
    }
}

public sealed class ExternalIdentityTokenTests
{
    [Fact]
    public void DefaultJwtHandlerHidesAppleSubClaim()
    {
        var (token, key) = AppleShapedJwt.SignWithKey("001234.abcdef", "juan@privaterelay.appleid.com");
        var parameters = AppleShapedJwt.Parameters(key);
        var mapped = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
        var principal = mapped.ValidateToken(token, parameters, out _);
        Assert.True(mapped.MapInboundClaims);
        Assert.Null(principal.FindFirst("sub"));
        Assert.Equal(
            "001234.abcdef",
            principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value);
    }

    [Fact]
    public void ReadKeepsAppleSubjectWhenInboundClaimsWouldMapItAway()
    {
        var (token, key) = AppleShapedJwt.SignWithKey("001234.abcdef", "juan@privaterelay.appleid.com");
        var identity = ExternalIdentityTokens.Read(token, AppleShapedJwt.Parameters(key), "apple");
        Assert.Equal("001234.abcdef", identity.Subject);
        Assert.Equal("juan", identity.DisplayName);
        Assert.Equal("apple", identity.Provider);
    }
}

internal static class AppleShapedJwt
{
    public static string Sign(string subject, string email) => SignWithKey(subject, email).Token;

    public static (string Token, RsaSecurityKey Key) SignWithKey(string subject, string email)
    {
        var rsa = RSA.Create(2048);
        var key = new RsaSecurityKey(rsa) { KeyId = "test-apple" };
        var credentials = new SigningCredentials(key, SecurityAlgorithms.RsaSha256);
        var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler { MapInboundClaims = false };
        var token = handler.WriteToken(new System.IdentityModel.Tokens.Jwt.JwtSecurityToken(
            issuer: "https://appleid.apple.com",
            audience: "com.collapsetechnologies.trust",
            claims:
            [
                new System.Security.Claims.Claim("sub", subject),
                new System.Security.Claims.Claim("email", email)
            ],
            notBefore: DateTime.UtcNow.AddMinutes(-1),
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials));
        return (token, key);
    }

    public static TokenValidationParameters Parameters(RsaSecurityKey key) => new()
    {
        ValidIssuer = "https://appleid.apple.com",
        ValidAudience = "com.collapsetechnologies.trust",
        IssuerSigningKey = key,
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        NameClaimType = "sub",
        ClockSkew = TimeSpan.FromMinutes(5)
    };
}

sealed class RecordingReceipts : ILookReceiptPublisher
{
    public List<LookEvent> Looks { get; } = [];

    public Task NotifyLookAsync(LookEvent look, CancellationToken cancellationToken)
    {
        Looks.Add(look);
        return Task.CompletedTask;
    }

    public Task NotifyQuietAsync(
        Guid accountId,
        string title,
        string body,
        string kind,
        CancellationToken cancellationToken) => Task.CompletedTask;

    public Task NotifyHomeArrivalAsync(Guid subjectId, CancellationToken cancellationToken) => Task.CompletedTask;
}

static class TestPrincipals
{
    public static ClaimsPrincipal Principal(Guid id) =>
        new(new ClaimsIdentity([new Claim("sub", id.ToString())], "test"));
}
