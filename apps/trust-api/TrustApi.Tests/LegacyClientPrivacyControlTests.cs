using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using TrustApi.Api.V1;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Notifications;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class LegacyClientPrivacyControlTests
{
    [Fact]
    public async Task UnlinkedBuild32CanTurnSharingOffRemoveRelationshipAndDeleteAccount()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();

        using var off = api.Authorized(HttpMethod.Patch, $"/api/v1/people/{bob.Id}/share", alice.Id);
        off.Content = JsonContent.Create(new { resting = "off", pause = (string?)null });
        using var offResponse = await api.Client.SendAsync(off);
        Assert.Equal(HttpStatusCode.NoContent, offResponse.StatusCode);
        Assert.Equal(ShareResting.Off, (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Resting);

        using var remove = api.Authorized(HttpMethod.Post, $"/api/v1/people/{bob.Id}/revoke", alice.Id);
        remove.Content = JsonContent.Create(new { });
        using var removeResponse = await api.Client.SendAsync(remove);
        Assert.Equal(HttpStatusCode.NoContent, removeResponse.StatusCode);
        Assert.False(await api.Store.AreConnectedAsync(alice.Id, bob.Id, CancellationToken.None));

        var disposable = await api.CreateAccountAsync("Legacy Delete");
        using var delete = api.Authorized(HttpMethod.Delete, "/api/v1/account", disposable.Id);
        using var deleteResponse = await api.Client.SendAsync(delete);
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);
        Assert.Null(await api.Store.FindAccountAsync(disposable.Id, CancellationToken.None));
    }

    [Fact]
    public async Task UnlinkedStopAllIsAuthenticatedAtomicIdempotentAndOnlyStopsOutboundDirections()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        var (carol, _) = await api.CreateConnectedPairAsync();
        var (dave, _) = await api.CreateConnectedPairAsync();
        var (erin, _) = await api.CreateConnectedPairAsync();
        await api.Store.UpsertShareAsync(alice.Id, bob.Id,
            new ShareState(ShareResting.Paused, DateTimeOffset.UtcNow.AddHours(1), ShareResting.Always, 4), CancellationToken.None);
        await api.Store.UpsertShareAsync(alice.Id, carol.Id,
            new ShareState(ShareResting.UntilTheyLook, Revision: 2), CancellationToken.None);
        await api.Store.UpsertShareAsync(alice.Id, dave.Id,
            new ShareState(ShareResting.Always, Revision: 8), CancellationToken.None);
        await api.Store.UpsertShareAsync(alice.Id, erin.Id,
            new ShareState(ShareResting.Off, Revision: 11), CancellationToken.None);
        await api.Store.UpsertShareAsync(bob.Id, alice.Id,
            new ShareState(ShareResting.Always, Revision: 7), CancellationToken.None);
        await api.Store.IngestLocationAsync(alice.Id, new LocationFix(DateTimeOffset.UtcNow, 37.3, -122.0), CancellationToken.None);
        var pausedBeforeStop = await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None);
        var alwaysBeforeStop = await api.Store.GetShareAsync(alice.Id, dave.Id, CancellationToken.None);
        var inboundBeforeStop = await api.Store.GetShareAsync(bob.Id, alice.Id, CancellationToken.None);

        using var unauthenticated = new HttpRequestMessage(HttpMethod.Post, "/api/v1/me/sharing/stop-all");
        using var unauthenticatedResponse = await api.Client.SendAsync(unauthenticated);
        Assert.Equal(HttpStatusCode.Unauthorized, unauthenticatedResponse.StatusCode);

        using var stop = api.Authorized(HttpMethod.Post, "/api/v1/me/sharing/stop-all", alice.Id);
        using var response = await api.Client.SendAsync(stop);
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        var stopped = await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None);
        Assert.Equal(ShareResting.Off, stopped.Resting);
        Assert.Equal(pausedBeforeStop.Revision + 1, stopped.Revision);
        Assert.Null(stopped.PauseUntil);
        Assert.Null(stopped.RestoresTo);
        Assert.Equal(ShareResting.Off, (await api.Store.GetShareAsync(alice.Id, carol.Id, CancellationToken.None)).Resting);
        Assert.Equal(ShareResting.Off, (await api.Store.GetShareAsync(alice.Id, dave.Id, CancellationToken.None)).Resting);
        Assert.Equal(alwaysBeforeStop.Revision + 1, (await api.Store.GetShareAsync(alice.Id, dave.Id, CancellationToken.None)).Revision);
        Assert.Equal(ShareResting.Off, (await api.Store.GetShareAsync(alice.Id, erin.Id, CancellationToken.None)).Resting);
        Assert.Equal(12, (await api.Store.GetShareAsync(alice.Id, erin.Id, CancellationToken.None)).Revision);
        Assert.Equal(inboundBeforeStop.Revision, (await api.Store.GetShareAsync(bob.Id, alice.Id, CancellationToken.None)).Revision);
        Assert.True(await api.Store.AreConnectedAsync(alice.Id, bob.Id, CancellationToken.None));
        Assert.Null(await api.Store.LatestLocationAsync(alice.Id, CancellationToken.None));

        using var secondStop = api.Authorized(HttpMethod.Post, "/api/v1/me/sharing/stop-all", alice.Id);
        using var secondResponse = await api.Client.SendAsync(secondStop);
        Assert.Equal(HttpStatusCode.NoContent, secondResponse.StatusCode);
        Assert.Equal(stopped.Revision + 1, (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Revision);
    }

    [Fact]
    public async Task StopAllOnMissingLinkDoesNotBypassHoldOrRevocationOrEnableWrites()
    {
        await using var api = await ProductionApi.StartAsync();
        var (unlinked, peer) = await api.CreateConnectedPairAsync();
        using var read = api.Authorized(HttpMethod.Get, "/api/v1/circle", unlinked.Id);
        using var readResponse = await api.Client.SendAsync(read);
        Assert.Equal("age_assurance_link_required", await ProductionApi.ErrorCodeAsync(readResponse));
        using var enable = api.Authorized(HttpMethod.Patch, $"/api/v1/people/{peer.Id}/share", unlinked.Id);
        enable.Content = JsonContent.Create(new { resting = "always", pause = (string?)null });
        using var enableResponse = await api.Client.SendAsync(enable);
        Assert.Equal("age_assurance_link_required", await ProductionApi.ErrorCodeAsync(enableResponse));
        await api.AgeAssurance.PlaceAccountPrivacyHoldAsync(unlinked.Id, DateTimeOffset.UtcNow, CancellationToken.None);
        using var heldStop = api.Authorized(HttpMethod.Post, "/api/v1/me/sharing/stop-all", unlinked.Id);
        using var heldResponse = await api.Client.SendAsync(heldStop);
        Assert.Equal((HttpStatusCode)423, heldResponse.StatusCode);

        var (revoked, revokedPeer) = await api.CreateConnectedPairAsync();
        var transaction = new VerifiedStoreKitAppTransaction("stop-all-revoked", "com.collapsetechnologies.trust", "Sandbox");
        await api.AgeAssurance.TryRegisterAppTransactionLinkAsync(revoked.Id, transaction, CancellationToken.None);
        await api.AgeAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, DateTimeOffset.UtcNow, CancellationToken.None);
        using var revokedStop = api.Authorized(HttpMethod.Post, "/api/v1/me/sharing/stop-all", revoked.Id);
        using var revokedResponse = await api.Client.SendAsync(revokedStop);
        Assert.Equal(HttpStatusCode.Conflict, revokedResponse.StatusCode);
        Assert.Equal("consent_revoked", await ProductionApi.ErrorCodeAsync(revokedResponse));
        Assert.True(await api.Store.AreConnectedAsync(revoked.Id, revokedPeer.Id, CancellationToken.None));
    }

    [Fact]
    public async Task StopAllWinsRaceWithStalePerPersonEnable()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        await api.Engine.GrantCircleAsync(alice.Id, "test", CancellationToken.None);
        var connection = await api.ConnectionIdAsync(alice.Id, bob.Id);
        var revision = (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Revision;
        var staleEnable = api.Engine.SetShareAsync(alice.Id, bob.Id, connection, revision, ShareResting.Always, null, CancellationToken.None);
        using var stop = api.Authorized(HttpMethod.Post, "/api/v1/me/sharing/stop-all", alice.Id);
        var stopRequest = api.Client.SendAsync(stop);
        try { await staleEnable; }
        catch (TrustException exception) { Assert.Equal("share_state_changed", exception.Code); }
        using var response = await stopRequest;
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(ShareResting.Off, (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Resting);
    }

    [Fact]
    public async Task StopAllInvalidatesAnEnableThatObservedAnAlreadyOffDirection()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        await api.Engine.GrantCircleAsync(alice.Id, "test", CancellationToken.None);
        var connection = await api.ConnectionIdAsync(alice.Id, bob.Id);
        var observedOffRevision = (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Revision;

        await api.Engine.StopAllOutboundSharingAsync(alice.Id, CancellationToken.None);

        var staleEnable = await Assert.ThrowsAsync<TrustException>(() =>
            api.Engine.SetShareAsync(alice.Id, bob.Id, connection, observedOffRevision, ShareResting.Always, null, CancellationToken.None));
        Assert.Equal("share_state_changed", staleEnable.Code);
        var after = await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None);
        Assert.Equal(ShareResting.Off, after.Resting);
        Assert.True(after.Revision > observedOffRevision);
    }

    [Fact]
    public async Task DelayedLocationIngestCannotRecreatePointsAfterStopAll()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        await api.Store.UpsertShareAsync(alice.Id, bob.Id, new ShareState(ShareResting.Always, Revision: 2), CancellationToken.None);
        await api.Engine.GrantCircleAsync(alice.Id, "test", CancellationToken.None);
        var delayedPoint = new LocationFix(DateTimeOffset.UtcNow, 37.3, -122.0);
        var beforeStopRevision = (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Revision;
        var observedShares = new Dictionary<Guid, long> { [bob.Id] = beforeStopRevision };
        Assert.True(await api.Store.TryIngestLocationWhileSharingAsync(alice.Id, delayedPoint, DateTimeOffset.UtcNow, observedShares, CancellationToken.None));

        await api.Engine.StopAllOutboundSharingAsync(alice.Id, CancellationToken.None);
        var stopped = await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None);
        var connectionId = await api.ConnectionIdAsync(alice.Id, bob.Id);
        await api.Engine.SetShareAsync(alice.Id, bob.Id, connectionId, stopped.Revision, ShareResting.Always, null, CancellationToken.None);

        // This is the write stage of an ingest that observed the prior Always revision.
        // Re-enabling is a new consent revision and cannot revive its delayed point.
        Assert.False(await api.Store.TryIngestLocationWhileSharingAsync(
            alice.Id,
            delayedPoint with { Timestamp = delayedPoint.Timestamp.AddSeconds(1) },
            DateTimeOffset.UtcNow,
            observedShares,
            CancellationToken.None));
        Assert.Null(await api.Store.LatestLocationAsync(alice.Id, CancellationToken.None));
        Assert.Equal(ShareResting.Always, (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Resting);
    }

    [Fact]
    public async Task DelayedLocationIngestCannotRecreatePointsAfterRemovingTheLastPeer()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        await api.Store.UpsertShareAsync(alice.Id, bob.Id, new ShareState(ShareResting.Always), CancellationToken.None);
        var oldRevision = (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Revision;
        var observed = new Dictionary<Guid, long> { [bob.Id] = oldRevision };
        var delayedPoint = new LocationFix(DateTimeOffset.UtcNow, 37.3, -122.0);
        Assert.True(await api.Store.TryIngestLocationWhileSharingAsync(alice.Id, delayedPoint, DateTimeOffset.UtcNow, observed, CancellationToken.None));

        await api.Engine.RevokeAsync(alice.Id, bob.Id, CancellationToken.None);

        Assert.Null(await api.Store.LatestLocationAsync(alice.Id, CancellationToken.None));
        Assert.False(await api.Store.TryIngestLocationWhileSharingAsync(
            alice.Id, delayedPoint with { Timestamp = delayedPoint.Timestamp.AddSeconds(1) }, DateTimeOffset.UtcNow, observed, CancellationToken.None));
        Assert.Null(await api.Store.LatestLocationAsync(alice.Id, CancellationToken.None));
        Assert.False(await api.Store.AreConnectedAsync(alice.Id, bob.Id, CancellationToken.None));
    }

    [Fact]
    public async Task UnlinkedAccountStillNeedsLinkForReadsEnablingPauseAndMalformedModes()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        var connectionId = await api.ConnectionIdAsync(alice.Id, bob.Id);
        var revision = (await api.Store.GetShareAsync(alice.Id, bob.Id, CancellationToken.None)).Revision;

        using var read = api.Authorized(HttpMethod.Get, "/api/v1/circle", alice.Id);
        using var readResponse = await api.Client.SendAsync(read);
        Assert.Equal(HttpStatusCode.Conflict, readResponse.StatusCode);
        Assert.Equal("age_assurance_link_required", await ProductionApi.ErrorCodeAsync(readResponse));

        foreach (var body in new object[]
        {
            new { connectionId, revision, resting = "sealed", pause = (string?)null },
            new { connectionId, revision, resting = "always", pause = (string?)null },
            new { connectionId, revision, resting = (string?)null, pause = "1h" },
            new { connectionId, revision, resting = "off", pause = "1h" },
            new { connectionId, revision, resting = "unknown", pause = (string?)null },
            new { connectionId, revision, resting = (string?)null, pause = "unknown" }
        })
        {
            using var change = api.Authorized(HttpMethod.Patch, $"/api/v1/people/{bob.Id}/share", alice.Id);
            change.Content = JsonContent.Create(body);
            using var response = await api.Client.SendAsync(change);
            Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
            Assert.Equal("age_assurance_link_required", await ProductionApi.ErrorCodeAsync(response));
        }

        using var wrongMethod = api.Authorized(HttpMethod.Post, $"/api/v1/people/{bob.Id}/share", alice.Id);
        using var wrongMethodResponse = await api.Client.SendAsync(wrongMethod);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, wrongMethodResponse.StatusCode);

        using var wrongPath = api.Authorized(HttpMethod.Patch, $"/api/v1/people/{bob.Id}/history", alice.Id);
        using var wrongPathResponse = await api.Client.SendAsync(wrongPath);
        Assert.Equal(HttpStatusCode.NotFound, wrongPathResponse.StatusCode);
    }

    [Fact]
    public async Task StaleConnectionIdCannotRemoveReconnectedRelationship()
    {
        await using var api = await ProductionApi.StartAsync();
        var (alice, bob) = await api.CreateConnectedPairAsync();
        var staleConnectionId = await api.ConnectionIdAsync(alice.Id, bob.Id);

        using var firstRemove = api.Authorized(HttpMethod.Post, $"/api/v1/people/{bob.Id}/revoke", alice.Id);
        firstRemove.Content = JsonContent.Create(new { connectionId = staleConnectionId });
        using var firstResponse = await api.Client.SendAsync(firstRemove);
        Assert.Equal(HttpStatusCode.NoContent, firstResponse.StatusCode);
        Assert.True(await api.Store.ConnectAccountsWithOffSharesAsync(alice.Id, bob.Id, DateTimeOffset.UtcNow, CancellationToken.None));
        var newConnectionId = await api.ConnectionIdAsync(alice.Id, bob.Id);
        Assert.NotEqual(staleConnectionId, newConnectionId);

        using var staleRemove = api.Authorized(HttpMethod.Post, $"/api/v1/people/{bob.Id}/revoke", alice.Id);
        staleRemove.Content = JsonContent.Create(new { connectionId = staleConnectionId });
        using var staleResponse = await api.Client.SendAsync(staleRemove);
        Assert.Equal(HttpStatusCode.Conflict, staleResponse.StatusCode);
        Assert.True(await api.Store.AreConnectedAsync(alice.Id, bob.Id, CancellationToken.None));
    }

    [Fact]
    public async Task PrivacyHoldAndConsentRevocationStillBlockOffAndRemove()
    {
        await using var api = await ProductionApi.StartAsync();
        var (held, heldPeer) = await api.CreateConnectedPairAsync();
        await api.AgeAssurance.PlaceAccountPrivacyHoldAsync(held.Id, DateTimeOffset.UtcNow, CancellationToken.None);

        using var heldOff = api.Authorized(HttpMethod.Patch, $"/api/v1/people/{heldPeer.Id}/share", held.Id);
        heldOff.Content = JsonContent.Create(new { resting = "off", pause = (string?)null });
        using var heldOffResponse = await api.Client.SendAsync(heldOff);
        Assert.Equal((HttpStatusCode)423, heldOffResponse.StatusCode);

        using var heldRemove = api.Authorized(HttpMethod.Post, $"/api/v1/people/{heldPeer.Id}/revoke", held.Id);
        heldRemove.Content = JsonContent.Create(new { });
        using var heldRemoveResponse = await api.Client.SendAsync(heldRemove);
        Assert.Equal((HttpStatusCode)423, heldRemoveResponse.StatusCode);

        var (revoked, revokedPeer) = await api.CreateConnectedPairAsync();
        var transaction = new VerifiedStoreKitAppTransaction("legacy-revoked", "com.collapsetechnologies.trust", "Sandbox");
        Assert.Equal(AppTransactionLinkResult.Linked, await api.AgeAssurance.TryRegisterAppTransactionLinkAsync(revoked.Id, transaction, CancellationToken.None));
        await api.AgeAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, DateTimeOffset.UtcNow, CancellationToken.None);

        using var revokedOff = api.Authorized(HttpMethod.Patch, $"/api/v1/people/{revokedPeer.Id}/share", revoked.Id);
        revokedOff.Content = JsonContent.Create(new { resting = "off", pause = (string?)null });
        using var revokedOffResponse = await api.Client.SendAsync(revokedOff);
        Assert.Equal(HttpStatusCode.Conflict, revokedOffResponse.StatusCode);
        Assert.Equal("consent_revoked", await ProductionApi.ErrorCodeAsync(revokedOffResponse));

        using var revokedRemove = api.Authorized(HttpMethod.Post, $"/api/v1/people/{revokedPeer.Id}/revoke", revoked.Id);
        revokedRemove.Content = JsonContent.Create(new { });
        using var revokedRemoveResponse = await api.Client.SendAsync(revokedRemove);
        Assert.Equal(HttpStatusCode.Conflict, revokedRemoveResponse.StatusCode);
        Assert.Equal("consent_revoked", await ProductionApi.ErrorCodeAsync(revokedRemoveResponse));
    }

    private sealed class ProductionApi : IAsyncDisposable
    {
        private readonly WebApplication _app;

        private ProductionApi(WebApplication app)
        {
            _app = app;
            Client = app.GetTestClient();
            Store = app.Services.GetRequiredService<ITrustStore>();
            AgeAssurance = app.Services.GetRequiredService<IAgeAssuranceAccountStore>();
            Engine = app.Services.GetRequiredService<TrustEngine>();
        }

        public HttpClient Client { get; }
        public ITrustStore Store { get; }
        public IAgeAssuranceAccountStore AgeAssurance { get; }
        public TrustEngine Engine { get; }

        public static async Task<ProductionApi> StartAsync()
        {
            var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Production" });
            builder.WebHost.UseTestServer();
            builder.Services.AddAuthentication(TestBearerHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestBearerHandler>(TestBearerHandler.SchemeName, _ => { });
            builder.Services.AddAuthorization();
            builder.Services.Configure<AuthOptions>(options => options.AllowDevelopmentSignIn = false);
            builder.Services.Configure<StoreKitOptions>(_ => { });
            builder.Services.AddSingleton<ITrustStore, MemoryTrustStore>();
            builder.Services.AddSingleton<IPushDeviceStore, MemoryPushDeviceStore>();
            builder.Services.AddSingleton<IAgeAssuranceAccountStore, MemoryAgeAssuranceAccountStore>();
            builder.Services.AddSingleton(TimeProvider.System);
            builder.Services.AddSingleton<TrustEngine>();
            builder.Services.AddScoped<RevokedAccountEndpointFilter>();
            var app = builder.Build();
            app.UseAuthentication();
            app.UseAuthorization();
            var api = app.MapGroup("/api/v1")
                .RequireAuthorization()
                .AddEndpointFilter<RevokedAccountEndpointFilter>();
            Func<ClaimsPrincipal, TrustEngine, IOptions<AuthOptions>, IOptions<StoreKitOptions>, HttpContext, CancellationToken, Task<IResult>> getCircle =
                TrustEndpoints.GetCircleAsync;
            Func<Guid, ShareRequest, ClaimsPrincipal, TrustEngine, CancellationToken, Task<IResult>> setShare =
                TrustEndpoints.SetShareAsync;
            Func<ClaimsPrincipal, TrustEngine, CancellationToken, Task<IResult>> stopAll =
                TrustEndpoints.StopAllSharingAsync;
            Func<Guid, RevokeRequest, ClaimsPrincipal, TrustEngine, CancellationToken, Task<IResult>> revoke =
                TrustEndpoints.RevokeAsync;
            Func<ClaimsPrincipal, TrustEngine, IPushDeviceStore, IAgeAssuranceAccountStore, CancellationToken, Task<IResult>> deleteAccount =
                TrustEndpoints.DeleteAccountAsync;
            api.MapGet("/circle", getCircle);
            api.MapPost("/me/sharing/stop-all", stopAll);
            api.MapPatch("/people/{personId:guid}/share", setShare);
            api.MapPost("/people/{personId:guid}/revoke", revoke);
            api.MapDelete("/account", deleteAccount);
            await app.StartAsync();
            return new ProductionApi(app);
        }

        public async Task<(Account Account, Account Peer)> CreateConnectedPairAsync()
        {
            var first = await CreateAccountAsync("Legacy Alice");
            var second = await CreateAccountAsync("Legacy Bob");
            Assert.True(await Store.ConnectAccountsWithOffSharesAsync(first.Id, second.Id, DateTimeOffset.UtcNow, CancellationToken.None));
            return (first, second);
        }

        public async Task<Account> CreateAccountAsync(string name)
        {
            var id = Guid.NewGuid();
            return await Store.UpsertAccountAsync(
                new Account(id, "apple", $"legacy-{id:N}", name, false, null, DateTimeOffset.UtcNow),
                CancellationToken.None);
        }

        public async Task<Guid> ConnectionIdAsync(Guid first, Guid second) =>
            await Store.GetActiveMembershipIdAsync(first, second, CancellationToken.None)
                ?? throw new InvalidOperationException("Expected an active test relationship.");

        public HttpRequestMessage Authorized(HttpMethod method, string path, Guid accountId)
        {
            var request = new HttpRequestMessage(method, path);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accountId.ToString());
            return request;
        }

        public static async Task<string?> ErrorCodeAsync(HttpResponseMessage response)
        {
            using var json = await response.Content.ReadFromJsonAsync<JsonDocument>();
            return json?.RootElement.TryGetProperty("code", out var code) == true ? code.GetString() : null;
        }

        public async ValueTask DisposeAsync()
        {
            Client.Dispose();
            await _app.DisposeAsync();
        }
    }

    private sealed class TestBearerHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        public const string SchemeName = "LegacyPrivacyControlTest";

        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var raw = Request.Headers.Authorization.ToString();
            if (!AuthenticationHeaderValue.TryParse(raw, out var header)
                || !string.Equals(header.Scheme, "Bearer", StringComparison.OrdinalIgnoreCase)
                || !Guid.TryParse(header.Parameter, out var accountId))
            {
                return Task.FromResult(AuthenticateResult.NoResult());
            }

            var identity = new ClaimsIdentity([new Claim("sub", accountId.ToString())], Scheme.Name);
            var principal = new ClaimsPrincipal(identity);
            return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme.Name)));
        }
    }
}
