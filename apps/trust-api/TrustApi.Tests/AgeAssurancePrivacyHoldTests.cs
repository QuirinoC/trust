using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TrustApi.Api.V1;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Notifications;

namespace TrustApi.Tests;

public sealed class AgeAssurancePrivacyHoldTests
{
    [Fact]
    public async Task EndpointHoldsOnlyAuthenticatedAccountAndIsIdempotentWithFixedMinimalReason()
    {
        var callerId = Guid.NewGuid();
        var otherId = Guid.NewGuid();
        var accounts = new MemoryTrustStore();
        await accounts.UpsertAccountAsync(Account(callerId), CancellationToken.None);
        await accounts.UpsertAccountAsync(Account(otherId), CancellationToken.None);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var principal = Principal(callerId);
        var now = new DateTimeOffset(2026, 9, 28, 12, 0, 0, TimeSpan.Zero);
        var timeProvider = new FrozenTimeProvider(now);

        var first = await TrustEndpoints.PlaceAccountPrivacyHoldAsync(
            principal, accounts, ageAssurance, timeProvider, CancellationToken.None);
        var storedFirst = await ageAssurance.FindAccountPrivacyHoldAsync(callerId, CancellationToken.None);
        var second = await TrustEndpoints.PlaceAccountPrivacyHoldAsync(
            principal, accounts, ageAssurance, timeProvider, CancellationToken.None);
        var storedSecond = await ageAssurance.FindAccountPrivacyHoldAsync(callerId, CancellationToken.None);

        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(first).StatusCode);
        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(second).StatusCode);
        Assert.Equal(storedFirst, storedSecond);
        Assert.Equal(callerId, storedFirst!.AccountId);
        Assert.Equal(now, storedFirst.HeldAt);
        Assert.Equal(AccountPrivacyHoldPolicy.Version, storedFirst.PolicyVersion);
        Assert.Equal("client_reported_age_restriction", storedFirst.Reason);
        Assert.False(await ageAssurance.IsAccountPrivacyHeldAsync(otherId, CancellationToken.None));

        // The endpoint takes no target, age-range or reason argument, so extra fields
        // cannot redirect a hold to another account or supply evidence.
        Assert.False(await ageAssurance.IsAccountPrivacyHeldAsync(Guid.NewGuid(), CancellationToken.None));
    }

    [Fact]
    public async Task PrivacyHoldBlocksAccountAndViewerDataWithoutRevocationDeletionOrPush()
    {
        var store = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var engine = new TrustEngine(store, TimeProvider.System, ageAssurance);
        var held = await engine.SignInAsync("development", "hold-subject", "Held", CancellationToken.None);
        var viewer = await engine.SignInAsync("development", "hold-viewer", "Viewer", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(held.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);
        await engine.GrantCircleAsync(held.Id, "test", CancellationToken.None);
        await engine.GrantCircleAsync(viewer.Id, "test", CancellationToken.None);
        await engine.SetShareAsync(held.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.SetShareAsync(viewer.Id, held.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.IngestAsync(held.Id, new LocationFix(DateTimeOffset.UtcNow, 37.77, -122.42), 80, false, CancellationToken.None);
        await engine.IngestAsync(viewer.Id, new LocationFix(DateTimeOffset.UtcNow, 37.78, -122.43), 80, false, CancellationToken.None);
        await engine.ViewAsync(viewer.Id, held.Id, CancellationToken.None);
        var heldViewerLook = await engine.ViewAsync(held.Id, viewer.Id, CancellationToken.None);
        Assert.NotNull(heldViewerLook);
        await ageAssurance.PlaceAccountPrivacyHoldAsync(held.Id, DateTimeOffset.UtcNow, CancellationToken.None);

        var viewerCircle = await engine.GetCircleAsync(viewer.Id, CancellationToken.None);
        Assert.DoesNotContain(viewerCircle.Members, member => member.Person.Id == held.Id);
        Assert.DoesNotContain(viewerCircle.LookLog, look => look.SubjectId == held.Id || look.ViewerId == held.Id);
        var history = await Assert.ThrowsAsync<TrustException>(() => engine.HistoryAsync(viewer.Id, held.Id, CancellationToken.None));
        Assert.Equal("not_connected", history.Code);
        var look = await Assert.ThrowsAsync<TrustException>(() => engine.ViewAsync(viewer.Id, held.Id, CancellationToken.None));
        Assert.Equal("not_connected", look.Code);

        var filter = new RevokedAccountEndpointFilter(ageAssurance, store, new TestHostEnvironment("Production"));
        Assert.True(await filter.ShouldBlockForPrivacyHoldAsync(held.Id, "GET", "/api/v1/circle", CancellationToken.None));
        Assert.True(await filter.ShouldBlockForPrivacyHoldAsync(held.Id, "POST", "/api/v1/location", CancellationToken.None));
        Assert.False(await filter.ShouldBlockForPrivacyHoldAsync(held.Id, "DELETE", "/api/v1/account", CancellationToken.None));
        Assert.False(await filter.ShouldBlockForPrivacyHoldAsync(held.Id, "DELETE", $"/api/v1/push/devices/{Guid.NewGuid()}", CancellationToken.None));
        Assert.False(await filter.ShouldBlockForPrivacyHoldAsync(held.Id, "POST", "/api/v1/age-assurance/privacy-hold", CancellationToken.None));
        Assert.True(await filter.ShouldBlockForPrivacyHoldAsync(held.Id, "PUT", "/api/v1/age-assurance/app-transaction", CancellationToken.None));

        var pushDevices = new CountingPushDeviceStore();
        var publisher = new LookReceiptPublisher(
            pushDevices,
            store,
            new ApnsClient(new HttpClient(), Options.Create(new ApnsOptions())),
            NullLogger<LookReceiptPublisher>.Instance,
            ageAssurance);
        await publisher.NotifyQuietAsync(held.Id, "Title", "Body", "quiet", CancellationToken.None);
        await publisher.NotifyHomeArrivalAsync(held.Id, CancellationToken.None);
        await publisher.NotifyLookAsync(heldViewerLook!, CancellationToken.None);
        Assert.Empty(pushDevices.LookupAccountIds);

        Assert.NotNull(await store.FindAccountAsync(held.Id, CancellationToken.None));
        Assert.False(await ageAssurance.IsAccountBlockedAsync(held.Id, CancellationToken.None));
        Assert.Empty(await ageAssurance.ClaimPendingAccountDeletionsAsync(10, DateTimeOffset.UtcNow.AddHours(1), TimeSpan.FromMinutes(5), CancellationToken.None));
    }

    [Fact]
    public async Task HoldRemainsAfterAppTransactionRelinkAndOnlyAccountDeletionRemovesIt()
    {
        var accountId = Guid.NewGuid();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var transaction = new TrustApi.Infrastructure.StoreKit.VerifiedStoreKitAppTransaction(
            "privacy-hold-relink",
            "com.collapsetechnologies.trust",
            "Sandbox");
        await ageAssurance.PlaceAccountPrivacyHoldAsync(accountId, DateTimeOffset.UtcNow, CancellationToken.None);
        Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
            accountId, transaction, CancellationToken.None));
        Assert.True(await ageAssurance.IsAccountPrivacyHeldAsync(accountId, CancellationToken.None));

        await ageAssurance.CompleteAccountDeletionAsync(accountId, CancellationToken.None);
        Assert.False(await ageAssurance.IsAccountPrivacyHeldAsync(accountId, CancellationToken.None));
    }

    private static Account Account(Guid id) => new(
        id, "apple", $"privacy-hold-{id:N}", "Test", false, null, DateTimeOffset.UtcNow);

    private static ClaimsPrincipal Principal(Guid accountId) => new(new ClaimsIdentity(
        [new Claim("sub", accountId.ToString())],
        "test"));

    private sealed class FrozenTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class TestHostEnvironment(string environmentName) : Microsoft.Extensions.Hosting.IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "TrustApi.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = new Microsoft.Extensions.FileProviders.NullFileProvider();
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
