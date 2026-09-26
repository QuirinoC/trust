using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure;

namespace TrustApi.Tests;

public sealed class ConnectionRequestEngineTests
{
    [Fact]
    public async Task HandleLookupRequiresVerifiedOnboarding()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var unverified = await engine.SignInAsync("development", Guid.NewGuid().ToString("N"), "Sam", CancellationToken.None);
        await engine.SetHandleAsync(unverified.Id, "samtest", CancellationToken.None);
        var failure = await Assert.ThrowsAsync<TrustException>(() => engine.LookupPersonAsync(unverified.Id, "jordan", CancellationToken.None));
        Assert.Equal("verification_required", failure.Code);
    }

    [Fact]
    public async Task LookupCreateReciprocalAndAcceptKeepSharingOffAndReplayDoesNotReset()
    {
        var store = new MemoryTrustStore();
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.Parse("2026-09-01T18:00:00Z") };
        var engine = new TrustEngine(store, time);
        var (sam, samHandle) = await ReadyAccount(engine, store, "sam");
        var (jordan, jordanHandle) = await ReadyAccount(engine, store, "jordan");

        var lookup = await engine.LookupPersonAsync(sam.Id, $"@{jordanHandle.ToUpperInvariant()}", CancellationToken.None);
        Assert.Equal(jordan.Id, lookup!.AccountId);
        Assert.Equal(jordanHandle, lookup.Handle);
        Assert.Equal(ConnectionRelationship.None, lookup.Relationship);

        var request = await engine.CreateConnectionRequestAsync(sam.Id, jordan.Id, CancellationToken.None);
        var duplicate = await engine.CreateConnectionRequestAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.Equal(request.Id, duplicate.Id);
        Assert.Equal(ConnectionRelationship.Incoming,
            (await engine.LookupPersonAsync(jordan.Id, samHandle, CancellationToken.None))!.Relationship);
        var sent = await engine.ListConnectionRequestsAsync(sam.Id, CancellationToken.None);
        Assert.Single(sent.Sent);
        Assert.Empty(sent.Incoming);
        Assert.Single((await engine.ListConnectionRequestsAsync(jordan.Id, CancellationToken.None)).Incoming);

        await engine.AcceptConnectionRequestAsync(jordan.Id, request.Id, CancellationToken.None);
        var joined = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
        var other = Assert.Single(joined.Members);
        Assert.Equal(jordan.Id, other.Person.Id);
        Assert.Equal(ShareResting.Off, other.OutboundShare.Effective(time.UtcNow));
        Assert.Equal(ShareResting.Off, other.InboundShare.Effective(time.UtcNow));

        await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.AcceptConnectionRequestAsync(jordan.Id, request.Id, CancellationToken.None);
        Assert.Equal(ShareResting.UntilTheyLook,
            (await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members.Single().OutboundShare.Effective(time.UtcNow));

        await engine.RevokeAsync(sam.Id, jordan.Id, CancellationToken.None);
        await engine.AcceptConnectionRequestAsync(jordan.Id, request.Id, CancellationToken.None);
        Assert.Empty((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members);
    }

    [Fact]
    public async Task DeclineCooldownIsDirectionalAndCancelAndExpiryReleasePendingPair()
    {
        var store = new MemoryTrustStore();
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.Parse("2026-09-01T18:00:00Z") };
        var engine = new TrustEngine(store, time);
        var (sam, _) = await ReadyAccount(engine, store, "sam");
        var (jordan, jordanHandle) = await ReadyAccount(engine, store, "jordan");

        var declined = await engine.CreateConnectionRequestAsync(sam.Id, jordan.Id, CancellationToken.None);
        await engine.DeclineConnectionRequestAsync(jordan.Id, declined.Id, CancellationToken.None);
        var blocked = await Assert.ThrowsAsync<TrustException>(() => engine.CreateConnectionRequestAsync(sam.Id, jordan.Id, CancellationToken.None));
        Assert.Equal("request_declined_recently", blocked.Code);
        var reverse = await engine.CreateConnectionRequestAsync(jordan.Id, sam.Id, CancellationToken.None);
        Assert.NotEqual(declined.Id, reverse.Id);
        await engine.CancelConnectionRequestAsync(jordan.Id, reverse.Id, CancellationToken.None);
        Assert.Empty((await engine.ListConnectionRequestsAsync(sam.Id, CancellationToken.None)).Incoming);

        time.UtcNow = time.UtcNow.AddDays(8);
        var afterCooldown = await engine.CreateConnectionRequestAsync(sam.Id, jordan.Id, CancellationToken.None);
        time.UtcNow = time.UtcNow.AddDays(8);
        Assert.Empty((await engine.ListConnectionRequestsAsync(sam.Id, CancellationToken.None)).Sent);
        Assert.Equal(ConnectionRelationship.None,
            (await engine.LookupPersonAsync(sam.Id, jordanHandle, CancellationToken.None))!.Relationship);
        var replacement = await engine.CreateConnectionRequestAsync(sam.Id, jordan.Id, CancellationToken.None);
        Assert.NotEqual(afterCooldown.Id, replacement.Id);
    }

    [Fact]
    public async Task CapacityFailureLeavesIncomingRequestPending()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var (sender, _) = await ReadyAccount(engine, store, "sender");
        var (recipient, _) = await ReadyAccount(engine, store, "recipient");
        var request = await engine.CreateConnectionRequestAsync(sender.Id, recipient.Id, CancellationToken.None);
        for (var i = 0; i < TrustRules.FreeSeats; i++)
        {
            var (member, _) = await ReadyAccount(engine, store, $"member{i}");
            await store.InsertMembershipAsync(recipient.Id, member.Id, CancellationToken.None);
        }

        var failure = await Assert.ThrowsAsync<TrustException>(() => engine.AcceptConnectionRequestAsync(recipient.Id, request.Id, CancellationToken.None));
        Assert.Equal("seat_limit", failure.Code);
        Assert.Single((await engine.ListConnectionRequestsAsync(recipient.Id, CancellationToken.None)).Incoming);
    }

    [Fact]
    public async Task LegacyConnectionPathsResolvePendingHandleRequest()
    {
        var store = new MemoryTrustStore();
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.Parse("2026-09-01T18:00:00Z") };
        var engine = new TrustEngine(store, time);
        var (directSender, _) = await ReadyAccount(engine, store, "directsender");
        var (directRecipient, directHandle) = await ReadyAccount(engine, store, "directrecipient");
        await engine.CreateConnectionRequestAsync(directSender.Id, directRecipient.Id, CancellationToken.None);
        await engine.ConnectAccountsAsync(directSender.Id, directRecipient.Id, CancellationToken.None);
        Assert.Empty((await engine.ListConnectionRequestsAsync(directSender.Id, CancellationToken.None)).Sent);
        Assert.Empty((await engine.ListConnectionRequestsAsync(directRecipient.Id, CancellationToken.None)).Incoming);
        Assert.Equal(ConnectionRelationship.Connected,
            (await engine.LookupPersonAsync(directSender.Id, directHandle, CancellationToken.None))!.Relationship);

        var (inviteSender, _) = await ReadyAccount(engine, store, "invitesender");
        var (inviteRecipient, inviteHandle) = await ReadyAccount(engine, store, "inviterecipient");
        await engine.CreateConnectionRequestAsync(inviteSender.Id, inviteRecipient.Id, CancellationToken.None);
        var invite = await engine.CreateInviteAsync(inviteSender.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(inviteRecipient.Id, invite.Code, CancellationToken.None);
        Assert.Empty((await engine.ListConnectionRequestsAsync(inviteSender.Id, CancellationToken.None)).Sent);
        Assert.Empty((await engine.ListConnectionRequestsAsync(inviteRecipient.Id, CancellationToken.None)).Incoming);
        Assert.Equal(ConnectionRelationship.Connected,
            (await engine.LookupPersonAsync(inviteSender.Id, inviteHandle, CancellationToken.None))!.Relationship);
    }

    private static async Task<(Account Account, string Handle)> ReadyAccount(TrustEngine engine, MemoryTrustStore store, string prefix)
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var account = await engine.SignInAsync("development", $"{prefix}-{suffix}", prefix, CancellationToken.None);
        var handle = $"{prefix[..Math.Min(4, prefix.Length)]}{suffix}";
        await engine.SetHandleAsync(account.Id, handle, CancellationToken.None);
        await store.SetVerifiedPhoneAsync(account.Id, $"+1555{RandomNumberGenerator.GetInt32(1000000, 9999999)}", DateTimeOffset.UtcNow, CancellationToken.None);
        return ((await store.FindAccountAsync(account.Id, CancellationToken.None))!, handle);
    }
}

[CollectionDefinition("Connection request API", DisableParallelization = true)]
public sealed class ConnectionRequestApiCollection { }

[Collection("Connection request API")]
public sealed class ConnectionRequestApiTests : IClassFixture<TrustApiFactory>
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    private readonly HttpClient _client;
    private readonly ITrustStore _store;

    public ConnectionRequestApiTests(TrustApiFactory factory)
    {
        _client = factory.CreateClient();
        _store = factory.Services.GetRequiredService<ITrustStore>();
    }

    [Fact]
    public async Task LookupAndRequestDtosExposeOnlyHandleAndRequestMetadata()
    {
        var sam = await CreateReadySession("api-sam");
        var jordan = await CreateReadySession("api-jordan");
        var photoVersion = Guid.NewGuid();
        await _store.SetAvatarPhotoAsync(jordan.AccountId, photoVersion, new byte[] { 0xff, 0xd8, 0xff, 0xd9 }, CancellationToken.None);
        var lookup = await SendAuthorized(HttpMethod.Get, $"/api/v1/people/lookup?handle={jordan.Handle}", sam.Token);
        Assert.Equal(HttpStatusCode.OK, lookup.StatusCode);
        var body = await lookup.Content.ReadAsStringAsync();
        Assert.Contains("accountId", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("handle", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("displayName", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("phone", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("avatar", body, StringComparison.OrdinalIgnoreCase);
        var photoBeforeAccept = await SendAuthorized(HttpMethod.Get, $"/api/v1/people/{jordan.AccountId}/avatar/{photoVersion}", sam.Token);
        Assert.Equal(HttpStatusCode.NotFound, photoBeforeAccept.StatusCode);

        var create = await SendAuthorized(HttpMethod.Post, "/api/v1/connection-requests", sam.Token, new { recipientId = jordan.AccountId });
        Assert.Equal(HttpStatusCode.OK, create.StatusCode);
        var request = await create.Content.ReadFromJsonAsync<RequestWire>(Json);
        var incoming = await SendAuthorized(HttpMethod.Get, "/api/v1/connection-requests", jordan.Token);
        Assert.Equal(HttpStatusCode.OK, incoming.StatusCode);
        var lists = await incoming.Content.ReadFromJsonAsync<RequestListsWire>(Json);
        Assert.Equal(request!.Id, Assert.Single(lists!.Incoming).Id);

        var accepted = await SendAuthorized(HttpMethod.Post, $"/api/v1/connection-requests/{request.Id}/accept", jordan.Token);
        Assert.Equal(HttpStatusCode.NoContent, accepted.StatusCode);
        var after = await SendAuthorized(HttpMethod.Get, "/api/v1/circle", sam.Token);
        var circle = await after.Content.ReadFromJsonAsync<CircleWire>(Json);
        var member = Assert.Single(circle!.Members, member => member.Person.Id == jordan.AccountId);
        Assert.Equal("off", member.Share.Presentation);
        Assert.Equal("off", member.InboundShare.Presentation);
        var photoAfterAccept = await SendAuthorized(HttpMethod.Get, $"/api/v1/people/{jordan.AccountId}/avatar/{photoVersion}", sam.Token);
        Assert.Equal(HttpStatusCode.OK, photoAfterAccept.StatusCode);
    }

    [Fact]
    public async Task OnlyRecipientCanAcceptAndOnlySenderCanCancel()
    {
        var sam = await CreateReadySession("api-sam");
        var jordan = await CreateReadySession("api-jordan");
        var other = await CreateReadySession("api-other");
        var create = await SendAuthorized(HttpMethod.Post, "/api/v1/connection-requests", sam.Token, new { recipientId = jordan.AccountId });
        var request = await create.Content.ReadFromJsonAsync<RequestWire>(Json);
        var forbiddenAccept = await SendAuthorized(HttpMethod.Post, $"/api/v1/connection-requests/{request!.Id}/accept", sam.Token);
        Assert.Equal(HttpStatusCode.NotFound, forbiddenAccept.StatusCode);
        var forbiddenCancel = await SendAuthorized(HttpMethod.Delete, $"/api/v1/connection-requests/{request.Id}", other.Token);
        Assert.Equal(HttpStatusCode.NotFound, forbiddenCancel.StatusCode);
        var cancel = await SendAuthorized(HttpMethod.Delete, $"/api/v1/connection-requests/{request.Id}", sam.Token);
        Assert.Equal(HttpStatusCode.NoContent, cancel.StatusCode);
    }

    [Fact]
    public async Task LookupLimitsAreIndependentPerAccountAndPerIp()
    {
        var first = await CreateReadySession("limit-first");
        var second = await CreateReadySession("limit-second");
        for (var i = 0; i < 20; i++)
        {
            var response = await SendAuthorized(HttpMethod.Get, "/api/v1/people/lookup?handle=missinghandle", first.Token);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }
        var firstLimited = await SendAuthorized(HttpMethod.Get, "/api/v1/people/lookup?handle=missinghandle", first.Token);
        Assert.Equal(HttpStatusCode.TooManyRequests, firstLimited.StatusCode);
        var secondStillAllowed = await SendAuthorized(HttpMethod.Get, "/api/v1/people/lookup?handle=missinghandle", second.Token);
        Assert.Equal(HttpStatusCode.NotFound, secondStillAllowed.StatusCode);
    }

    [Fact]
    public async Task RequestListRefreshDoesNotConsumeLookupAccountBudget()
    {
        var session = await CreateReadySession("list-refresh-limit");
        for (var i = 0; i < 25; i++)
        {
            var refresh = await SendAuthorized(HttpMethod.Get, "/api/v1/connection-requests", session.Token);
            Assert.Equal(HttpStatusCode.OK, refresh.StatusCode);
        }

        for (var i = 0; i < 20; i++)
        {
            var lookup = await SendAuthorized(HttpMethod.Get, "/api/v1/people/lookup?handle=missinghandle", session.Token);
            Assert.Equal(HttpStatusCode.NotFound, lookup.StatusCode);
        }
    }

    private async Task<ReadySession> CreateReadySession(string seed)
    {
        var session = await _client.PostAsJsonAsync("/api/v1/session/development", new { displayName = seed, provider = "development", deviceId = Guid.NewGuid().ToString("N") });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionWire>(Json);
        var handle = $"h{Guid.NewGuid():N}"[..10];
        var setHandle = await SendAuthorized(HttpMethod.Put, "/api/v1/me/handle", payload!.Token, new { handle });
        setHandle.EnsureSuccessStatusCode();
        var phone = $"+447{RandomNumberGenerator.GetInt32(100000000, 999999999)}";
        await _store.SetVerifiedPhoneAsync(payload.You.Id, phone, DateTimeOffset.UtcNow, CancellationToken.None);
        return new ReadySession(payload.Token, payload.You.Id, handle);
    }

    private async Task<HttpResponseMessage> SendAuthorized(HttpMethod method, string path, string token, object? body = null)
    {
        using var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (body is not null) request.Content = JsonContent.Create(body);
        return await _client.SendAsync(request);
    }

    private sealed record ReadySession(string Token, Guid AccountId, string Handle);
    private sealed record SessionWire(string Token, PersonWire You);
    private sealed record PersonWire(Guid Id);
    private sealed record RequestWire(Guid Id, string Status, DateTimeOffset CreatedAt, DateTimeOffset ExpiresAt);
    private sealed record PartyWire(Guid AccountId, string Handle);
    private sealed record RequestDtoWire(Guid Id, PartyWire OtherParty, DateTimeOffset CreatedAt, DateTimeOffset ExpiresAt);
    private sealed record RequestListsWire(IReadOnlyList<RequestDtoWire> Incoming, IReadOnlyList<RequestDtoWire> Sent);
    private sealed record CircleWire(IReadOnlyList<MemberWire> Members);
    private sealed record MemberWire(PersonWire Person, ShareWire Share, ShareWire InboundShare);
    private sealed record ShareWire(string Presentation);
}
