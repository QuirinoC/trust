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
        }

        public HttpClient Client { get; }
        public ITrustStore Store { get; }
        public IAgeAssuranceAccountStore AgeAssurance { get; }

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
            Func<Guid, RevokeRequest, ClaimsPrincipal, TrustEngine, CancellationToken, Task<IResult>> revoke =
                TrustEndpoints.RevokeAsync;
            Func<ClaimsPrincipal, TrustEngine, IPushDeviceStore, IAgeAssuranceAccountStore, CancellationToken, Task<IResult>> deleteAccount =
                TrustEndpoints.DeleteAccountAsync;
            api.MapGet("/circle", getCircle);
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
