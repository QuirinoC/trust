using Microsoft.Extensions.Options;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class ReviewEntitlementReceiveTests
{
    [Fact]
    public async Task AllowedReviewGrantCanAuthorizeFreeRecipientWithoutFiniteExpiry()
    {
        var now = new DateTimeOffset(2026, 11, 1, 18, 0, 0, TimeSpan.Zero);
        var time = new MutableTimeProvider { UtcNow = now };
        var store = new MemoryTrustStore();
        var entitlements = new MemoryStoreKitEntitlementStore(store);
        var engine = new TrustEngine(store, time, entitlements: entitlements,
            storeKitOptions: Options.Create(new StoreKitOptions { AllowReviewUnlock = true }));
        var owner = await engine.SignInAsync("apple", "review-owner", "Owner", CancellationToken.None);
        var viewer = await engine.SignInAsync("apple", "review-viewer", "Viewer", CancellationToken.None);
        var invite = await engine.CreateInviteAsync(owner.Id, CancellationToken.None);
        await engine.AcceptInviteAsync(viewer.Id, invite.Code, CancellationToken.None);

        await engine.GrantCircleAsync(owner.Id, "storekit-review", CancellationToken.None);
        await engine.SetShareAsync(owner.Id, viewer.Id, ShareResting.Always, null, CancellationToken.None);
        await engine.IngestAsync(owner.Id, new LocationFix(now, 37.77, -122.42), 80, false, CancellationToken.None);

        var received = (await engine.GetCircleAsync(viewer.Id, CancellationToken.None)).Members
            .Single(member => member.Person.Id == owner.Id);

        Assert.True(received.InboundLive);
        Assert.Equal(1, received.ReceiveAuthorizationVersion);
        Assert.Null(received.LiveAccessExpiresAt);
        Assert.Null(received.LiveUnavailableReason);
        Assert.Equal(37.77, received.Live!.Latitude, 3);
    }

}
