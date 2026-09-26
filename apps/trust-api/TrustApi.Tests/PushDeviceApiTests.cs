using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.Notifications;
using Microsoft.Extensions.DependencyInjection;

namespace TrustApi.Tests;

public sealed class PushDeviceApiTests : IClassFixture<TrustApiFactory>
{
    private const string BundleId = "com.collapsetechnologies.trust";
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    private readonly TrustApiFactory _factory;

    public PushDeviceApiTests(TrustApiFactory factory) => _factory = factory;

    [Fact]
    public async Task DeviceRegistrationRequiresAuthenticationAndRejectsAnotherBundle()
    {
        using var client = _factory.CreateClient();
        var installationId = Guid.NewGuid();
        var request = new PushDeviceRequest(installationId, "token-a", "sandbox", BundleId);

        var unauthenticatedRegister = await client.PostAsJsonAsync("/api/v1/push/devices", request);
        Assert.Equal(HttpStatusCode.Unauthorized, unauthenticatedRegister.StatusCode);

        var session = await CreateSessionAsync(client, "push-auth");
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", session.Token);

        var invalidBundle = await client.PostAsJsonAsync(
            "/api/v1/push/devices",
            request with { BundleId = "com.example.other" });
        Assert.Equal(HttpStatusCode.BadRequest, invalidBundle.StatusCode);

        var active = await _factory.Services.GetRequiredService<IPushDeviceStore>()
            .ListActiveAsync(session.AccountId, CancellationToken.None);
        Assert.Empty(active);
    }

    [Fact]
    public async Task RegistrationUpdatesAnInstallationAndDeleteIsOwnerScoped()
    {
        using var client = _factory.CreateClient();
        var first = await CreateSessionAsync(client, "push-owner");
        var second = await CreateSessionAsync(client, "push-other");
        var installationId = Guid.NewGuid();
        var store = _factory.Services.GetRequiredService<IPushDeviceStore>();

        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", first.Token);
        var create = await client.PostAsJsonAsync(
            "/api/v1/push/devices",
            new PushDeviceRequest(installationId, "  token-first  ", "sandbox", BundleId));
        Assert.Equal(HttpStatusCode.NoContent, create.StatusCode);

        var created = Assert.Single(await store.ListActiveAsync(first.AccountId, CancellationToken.None));
        Assert.Equal(installationId, created.InstallationId);
        Assert.Equal("token-first", created.Token);
        Assert.Equal("sandbox", created.Environment);
        Assert.Equal(BundleId, created.BundleId);

        var update = await client.PostAsJsonAsync(
            "/api/v1/push/devices",
            new PushDeviceRequest(installationId, "token-updated", "production", BundleId));
        Assert.Equal(HttpStatusCode.NoContent, update.StatusCode);

        var updated = Assert.Single(await store.ListActiveAsync(first.AccountId, CancellationToken.None));
        Assert.Equal("token-updated", updated.Token);
        Assert.Equal("production", updated.Environment);

        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", second.Token);
        var otherCannotRemove = await client.DeleteAsync($"/api/v1/push/devices/{installationId}");
        Assert.Equal(HttpStatusCode.NoContent, otherCannotRemove.StatusCode);
        Assert.Single(await store.ListActiveAsync(first.AccountId, CancellationToken.None));

        client.DefaultRequestHeaders.Authorization = null;
        var unauthenticatedDelete = await client.DeleteAsync($"/api/v1/push/devices/{installationId}");
        Assert.Equal(HttpStatusCode.Unauthorized, unauthenticatedDelete.StatusCode);

        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", first.Token);
        var remove = await client.DeleteAsync($"/api/v1/push/devices/{installationId}");
        Assert.Equal(HttpStatusCode.NoContent, remove.StatusCode);
        Assert.Empty(await store.ListActiveAsync(first.AccountId, CancellationToken.None));
    }

    [Fact]
    public async Task LookReceiptIsBestEffortWhenPushRegistrationLookupFails()
    {
        var publisher = new LookReceiptPublisher(
            new FailingPushDeviceStore(),
            new MemoryTrustStore(),
            new ApnsClient(new HttpClient(), Options.Create(new ApnsOptions())),
            NullLogger<LookReceiptPublisher>.Instance);
        var look = new LookEvent(
            Guid.NewGuid(), Guid.NewGuid(), "Viewer", Guid.NewGuid(), "Subject",
            DateTimeOffset.UtcNow, 0, true);

        var exception = await Record.ExceptionAsync(() => publisher.NotifyLookAsync(look, CancellationToken.None));
        Assert.Null(exception);
    }

    [Fact]
    public async Task HomeNotificationRespectsEachPersonsEffectiveShareMode()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var subject = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Subject", CancellationToken.None);
        var viewer = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Viewer", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(subject.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
        await engine.SetPresenceGrantAsync(subject.Id, viewer.Id, true, CancellationToken.None);

        var devices = new CountingPushDeviceStore();
        var publisher = new LookReceiptPublisher(
            devices,
            store,
            new ApnsClient(new HttpClient(), Options.Create(new ApnsOptions())),
            NullLogger<LookReceiptPublisher>.Instance);

        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Empty(devices.LookupAccountIds); // Both directions start Off.

        await engine.SetShareAsync(subject.Id, viewer.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds);

        await engine.SetShareAsync(subject.Id, viewer.Id, null, PauseDuration.OneHour, CancellationToken.None);
        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds); // Paused blocks the notification.
    }

    [Fact]
    public async Task OnlyTransitionIntoHomeQualifiesForAnArrivalNotification()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var subject = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Subject", CancellationToken.None);

        Assert.True(await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None));
        Assert.False(await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None));
        Assert.False(await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Away, null, CancellationToken.None));
        Assert.True(await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None));
    }

    private static async Task<TestSession> CreateSessionAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = name, deviceId = $"{name}-{Guid.NewGuid():N}" });
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<SessionPayload>(Json);
        Assert.NotNull(payload?.Token);
        return new TestSession(payload!.You.Id, payload.Token);
    }

    private sealed record TestSession(Guid AccountId, string Token);
    private sealed record SessionPayload(string Token, SessionPerson You);
    private sealed record SessionPerson(Guid Id);

    private sealed class FailingPushDeviceStore : IPushDeviceStore
    {
        public Task RegisterAsync(Guid accountId, Guid installationId, string token, string environment, string bundleId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task InvalidateTokenAsync(string token, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid accountId, CancellationToken cancellationToken) =>
            Task.FromException<IReadOnlyList<PushDevice>>(new InvalidOperationException("simulated store outage"));
    }

    private sealed class CountingPushDeviceStore : IPushDeviceStore
    {
        public List<Guid> LookupAccountIds { get; } = [];
        public Task RegisterAsync(Guid accountId, Guid installationId, string token, string environment, string bundleId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task InvalidateTokenAsync(string token, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid accountId, CancellationToken cancellationToken)
        {
            LookupAccountIds.Add(accountId);
            return Task.FromResult<IReadOnlyList<PushDevice>>([]);
        }
    }
}
