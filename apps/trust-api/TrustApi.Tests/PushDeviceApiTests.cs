using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Notifications;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

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
    public async Task LookPushDescribesTheLatestAvailableLocationWithoutClaimingItIsCurrent()
    {
        var accountId = Guid.NewGuid();
        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var handler = new RecordingPushHandler();
        using var httpClient = new HttpClient(handler);
        var apns = new ApnsClient(httpClient, Options.Create(new ApnsOptions
        {
            Enabled = true,
            KeyId = "unit-test-key",
            TeamId = "unit-test-team",
            PrivateKey = Convert.ToBase64String(ecdsa.ExportPkcs8PrivateKey()),
            BundleId = BundleId
        }));
        var publisher = new LookReceiptPublisher(
            new SinglePushDeviceStore(accountId),
            new MemoryTrustStore(),
            apns,
            NullLogger<LookReceiptPublisher>.Instance);

        await publisher.NotifyLookAsync(new LookEvent(
            Guid.NewGuid(), Guid.NewGuid(), "Viewer", accountId, "Subject",
            DateTimeOffset.UtcNow, 0, true), CancellationToken.None);

        Assert.NotNull(handler.Body);
        using var payload = JsonDocument.Parse(handler.Body);
        Assert.Equal(
            "One snapshot of the latest location available to Trust.",
            payload.RootElement.GetProperty("aps").GetProperty("alert").GetProperty("body").GetString());
    }

    [Fact]
    public async Task RevokedAccountDoesNotReceiveLookOrQuietNotificationsOrTriggerHomeAlerts()
    {
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var subjectId = Guid.NewGuid();
        var transaction = new TrustApi.Infrastructure.StoreKit.VerifiedStoreKitAppTransaction(
            "notification-subject-revoked",
            BundleId,
            "Sandbox");
        await ageAssurance.TryRegisterAppTransactionLinkAsync(subjectId, transaction, CancellationToken.None);
        await ageAssurance.RecordConsentRevocationAsync(
            Guid.NewGuid(), transaction, DateTimeOffset.UtcNow, CancellationToken.None);

        var devices = new CountingPushDeviceStore();
        var publisher = new LookReceiptPublisher(
            devices,
            new MemoryTrustStore(),
            new ApnsClient(new HttpClient(), Options.Create(new ApnsOptions())),
            NullLogger<LookReceiptPublisher>.Instance,
            ageAssurance);
        var look = new LookEvent(
            Guid.NewGuid(), Guid.NewGuid(), "Viewer", subjectId, "Child",
            DateTimeOffset.UtcNow, 0, true, LookKind.Look);

        await publisher.NotifyLookAsync(look, CancellationToken.None);
        await publisher.NotifyQuietAsync(subjectId, "Title", "Body", "quiet", CancellationToken.None);
        await publisher.NotifyHomeArrivalAsync(subjectId, CancellationToken.None);

        Assert.Empty(devices.LookupAccountIds);
    }

    [Fact]
    public async Task ConfirmedLookInvokesNotificationPublisherWithSubjectAndViewer()
    {
        var receipts = new RecordingReceipts();
        using var factory = _factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<ILookReceiptPublisher>();
            services.AddSingleton<ILookReceiptPublisher>(receipts);
        }));
        using var client = factory.CreateClient();

        async Task<TestSession> CreateAccountAsync(string name)
        {
            var response = await client.PostAsJsonAsync("/api/v1/session/development", new
            {
                displayName = name,
                deviceId = Guid.NewGuid().ToString("N")
            });
            response.EnsureSuccessStatusCode();
            var payload = await response.Content.ReadFromJsonAsync<SessionPayload>(Json);
            Assert.NotNull(payload?.Token);
            return new TestSession(payload!.You.Id, payload.Token);
        }

        static HttpRequestMessage Authorized(HttpMethod method, string path, string token) =>
            new(method, path)
            {
                Headers = { Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token) }
            };

        var subject = await CreateAccountAsync("Look subject");
        var viewer = await CreateAccountAsync("Look viewer");

        using var inviteRequest = Authorized(HttpMethod.Post, "/api/v1/invites", subject.Token);
        var inviteResponse = await client.SendAsync(inviteRequest);
        inviteResponse.EnsureSuccessStatusCode();
        using var inviteJson = JsonDocument.Parse(await inviteResponse.Content.ReadAsStringAsync());
        var inviteCode = inviteJson.RootElement.GetProperty("code").GetString();
        Assert.False(string.IsNullOrWhiteSpace(inviteCode));

        using var acceptRequest = Authorized(HttpMethod.Post, "/api/v1/invites/accept", viewer.Token);
        acceptRequest.Content = JsonContent.Create(new { code = inviteCode });
        (await client.SendAsync(acceptRequest)).EnsureSuccessStatusCode();

        var trustStore = factory.Services.GetRequiredService<ITrustStore>();
        var connectionId = await trustStore.GetActiveMembershipIdAsync(subject.AccountId, viewer.AccountId, CancellationToken.None);
        Assert.NotNull(connectionId);
        var revision = (await trustStore.GetShareAsync(subject.AccountId, viewer.AccountId, CancellationToken.None)).Revision;
        using var shareRequest = Authorized(HttpMethod.Patch, $"/api/v1/people/{viewer.AccountId}/share", subject.Token);
        shareRequest.Content = JsonContent.Create(new { connectionId, revision, resting = "untilTheyLook" });
        (await client.SendAsync(shareRequest)).EnsureSuccessStatusCode();

        using var locationRequest = Authorized(HttpMethod.Post, "/api/v1/location", subject.Token);
        locationRequest.Content = JsonContent.Create(new
        {
            timestamp = DateTimeOffset.UtcNow,
            latitude = 47.6062,
            longitude = -122.3321
        });
        (await client.SendAsync(locationRequest)).EnsureSuccessStatusCode();

        using var lookRequest = Authorized(HttpMethod.Post, "/api/v1/looks", viewer.Token);
        lookRequest.Content = JsonContent.Create(new { subjectId = subject.AccountId, confirmed = true });
        var lookResponse = await client.SendAsync(lookRequest);
        lookResponse.EnsureSuccessStatusCode();

        var notificationEvent = Assert.Single(receipts.Looks);
        Assert.Equal(viewer.AccountId, notificationEvent.ViewerId);
        Assert.Equal(subject.AccountId, notificationEvent.SubjectId);
        Assert.Equal("Look viewer", notificationEvent.ViewerName);
        Assert.Equal("Look subject", notificationEvent.SubjectName);
        Assert.Equal(LookKind.Look, notificationEvent.Kind);
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
        await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None);

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
        Assert.Empty(devices.LookupAccountIds); // Share permission alone is not a presence grant.

        await SetGrantAsync(engine, store, subject.Id, viewer.Id, true);
        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds);

        await SetGrantAsync(engine, store, subject.Id, viewer.Id, false);
        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds); // Revoked presence grant blocks arrival alerts.
        await SetGrantAsync(engine, store, subject.Id, viewer.Id, true);

        await engine.SetShareAsync(subject.Id, viewer.Id, null, PauseDuration.OneHour, CancellationToken.None);
        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds); // Paused blocks the notification.

        await engine.SetShareAsync(subject.Id, viewer.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Hidden, null, CancellationToken.None);
        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds); // Hidden is not an arrival signal.
    }

    [Fact]
    public async Task DelayedHomeNotificationCannotReuseANewerHomeTransition()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var subject = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Subject", CancellationToken.None);
        var viewer = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Viewer", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(subject.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
        await engine.SetShareAsync(subject.Id, viewer.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await SetGrantAsync(engine, store, subject.Id, viewer.Id, true);

        var firstHome = await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None);
        Assert.True(firstHome.ArrivedHome);
        await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Away, null, CancellationToken.None);
        var latestHome = await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None);
        Assert.True(latestHome.ArrivedHome);

        var devices = new CountingPushDeviceStore();
        var publisher = new LookReceiptPublisher(
            devices,
            store,
            new ApnsClient(new HttpClient(), Options.Create(new ApnsOptions())),
            NullLogger<LookReceiptPublisher>.Instance);

        await publisher.NotifyHomeArrivalAsync(subject.Id, firstHome.TransitionId, CancellationToken.None);
        Assert.Empty(devices.LookupAccountIds);
        await publisher.NotifyHomeArrivalAsync(subject.Id, latestHome.TransitionId, CancellationToken.None);
        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds);
    }

    [Fact]
    public async Task HomeNotificationStopsFanOutWhenSubjectConsentIsRevokedMidDelivery()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var subject = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Subject", CancellationToken.None);
        var firstViewer = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "First viewer", CancellationToken.None);
        var secondViewer = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Second viewer", CancellationToken.None);

        foreach (var viewer in new[] { firstViewer, secondViewer })
        {
            var invite = await engine.CreateInviteAsync(subject.Id, CancellationToken.None);
            await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
            await engine.SetShareAsync(subject.Id, viewer.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
            await SetGrantAsync(engine, store, subject.Id, viewer.Id, true);
        }
        await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None);

        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var transaction = new TrustApi.Infrastructure.StoreKit.VerifiedStoreKitAppTransaction(
            "home-arrival-mid-delivery-revocation",
            BundleId,
            "Sandbox");
        await ageAssurance.TryRegisterAppTransactionLinkAsync(subject.Id, transaction, CancellationToken.None);
        var devices = new RevokingPushDeviceStore(ageAssurance, transaction);
        var publisher = new LookReceiptPublisher(
            devices,
            store,
            new ApnsClient(new HttpClient(), Options.Create(new ApnsOptions())),
            NullLogger<LookReceiptPublisher>.Instance,
            ageAssurance);

        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);

        Assert.Single(devices.LookupAccountIds);
        Assert.Contains(devices.LookupAccountIds[0], new[] { firstViewer.Id, secondViewer.Id });
    }

    [Theory]
    [InlineData("share")]
    [InlineData("presence-grant")]
    [InlineData("hidden")]
    [InlineData("removed")]
    public async Task HomeNotificationRechecksOrdinaryConsentAfterDeviceLookup(string change)
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var subject = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Subject", CancellationToken.None);
        var viewer = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Viewer", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(subject.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
        var connectionId = await store.GetActiveMembershipIdAsync(subject.Id, viewer.Id, CancellationToken.None);
        Assert.NotNull(connectionId);
        await engine.SetShareAsync(subject.Id, viewer.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
        await SetGrantAsync(engine, store, subject.Id, viewer.Id, true);
        await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None);

        async Task RevokeConsentAsync(Guid _, CancellationToken token)
        {
            switch (change)
            {
                case "share":
                    await store.UpsertShareAsync(subject.Id, viewer.Id, ShareState.Default, token);
                    break;
                case "presence-grant":
                    await store.SetPresenceGrantAsync(
                        subject.Id, viewer.Id, connectionId!.Value, false, null, DateTimeOffset.UtcNow, token);
                    break;
                case "hidden":
                    await store.UpsertCurrentHomePresenceAsync(
                        new CurrentHomePresence(subject.Id, null, HomePresenceState.Hidden, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow),
                        token);
                    break;
                case "removed":
                    await store.RevokeMembershipAsync(subject.Id, viewer.Id, token);
                    break;
                default:
                    throw new InvalidOperationException($"Unknown consent change '{change}'.");
            }
        }

        var devices = new ConsentRevokingPushDeviceStore(viewer.Id, RevokeConsentAsync);
        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var handler = new RecordingPushHandler();
        using var httpClient = new HttpClient(handler);
        var apns = new ApnsClient(httpClient, Options.Create(new ApnsOptions
        {
            Enabled = true,
            KeyId = "unit-test-key",
            TeamId = "unit-test-team",
            PrivateKey = Convert.ToBase64String(ecdsa.ExportPkcs8PrivateKey()),
            BundleId = BundleId
        }));
        var publisher = new LookReceiptPublisher(
            devices,
            store,
            apns,
            NullLogger<LookReceiptPublisher>.Instance);

        await publisher.NotifyHomeArrivalAsync(subject.Id, CancellationToken.None);

        Assert.Equal(new[] { viewer.Id }, devices.LookupAccountIds);
        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task OnlyTransitionIntoHomeQualifiesForAnArrivalNotification()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var subject = await engine.SignInAsync("development", Guid.NewGuid().ToString(), "Subject", CancellationToken.None);

        Assert.True((await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None)).ArrivedHome);
        Assert.False((await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None)).ArrivedHome);
        Assert.False((await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Away, null, CancellationToken.None)).ArrivedHome);
        Assert.True((await engine.PostHomePresenceAsync(subject.Id, HomePresenceState.Home, null, CancellationToken.None)).ArrivedHome);
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

    private static async Task SetGrantAsync(TrustEngine engine, ITrustStore store, Guid subjectId, Guid trusteeId, bool enabled)
    {
        var connectionId = await store.GetActiveMembershipIdAsync(subjectId, trusteeId, CancellationToken.None)
            ?? throw new InvalidOperationException("Test relationship is not active.");
        var revision = (await store.GetPresenceGrantAsync(subjectId, trusteeId, CancellationToken.None))?.Revision ?? 0;
        await engine.SetPresenceGrantAsync(subjectId, trusteeId, connectionId, enabled, enabled ? revision : null, CancellationToken.None);
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

    private sealed class SinglePushDeviceStore(Guid accountId) : IPushDeviceStore
    {
        public Task RegisterAsync(Guid accountId, Guid installationId, string token, string environment, string bundleId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task InvalidateTokenAsync(string token, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid requestedAccountId, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<PushDevice>>([
                new PushDevice(Guid.NewGuid(), accountId, "test-device-token", "sandbox", BundleId, true)
            ]);
    }

    private sealed class ConsentRevokingPushDeviceStore(
        Guid accountId,
        Func<Guid, CancellationToken, Task> revokeConsent) : IPushDeviceStore
    {
        public List<Guid> LookupAccountIds { get; } = [];
        public Task RegisterAsync(Guid accountId, Guid installationId, string token, string environment, string bundleId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task InvalidateTokenAsync(string token, CancellationToken cancellationToken) => Task.CompletedTask;

        public async Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid requestedAccountId, CancellationToken cancellationToken)
        {
            LookupAccountIds.Add(requestedAccountId);
            Assert.Equal(accountId, requestedAccountId);
            await revokeConsent(requestedAccountId, cancellationToken);
            return [new PushDevice(Guid.NewGuid(), accountId, "test-device-token", "sandbox", BundleId, true)];
        }
    }

    private sealed class RecordingPushHandler : HttpMessageHandler
    {
        public int RequestCount { get; private set; }
        public string? Body { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            RequestCount++;
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK);
        }
    }

    private sealed class RevokingPushDeviceStore(
        MemoryAgeAssuranceAccountStore ageAssurance,
        TrustApi.Infrastructure.StoreKit.VerifiedStoreKitAppTransaction transaction) : IPushDeviceStore
    {
        public List<Guid> LookupAccountIds { get; } = [];

        public Task RegisterAsync(Guid accountId, Guid installationId, string token, string environment, string bundleId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task InvalidateTokenAsync(string token, CancellationToken cancellationToken) => Task.CompletedTask;

        public async Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid accountId, CancellationToken cancellationToken)
        {
            LookupAccountIds.Add(accountId);
            if (LookupAccountIds.Count == 1)
            {
                await ageAssurance.RecordConsentRevocationAsync(
                    Guid.NewGuid(), transaction, DateTimeOffset.UtcNow, cancellationToken);
            }
            return [];
        }
    }
}
