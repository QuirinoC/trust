using System.Net;
using System.Net.Http.Headers;
using TrustApi.Domain;
using TrustApi.Infrastructure.StoreKit;
using TrustApi.Application;
using TrustApi.Infrastructure;

namespace TrustApi.Tests;

public sealed class StoreKitSubscriptionAuthorityTests
{
    [Fact]
    public async Task CurrentActiveStatusMustMatchTheExactPurchaseAndValidAppleTransaction()
    {
        var now = DateTimeOffset.UtcNow;
        var token = Guid.NewGuid();
        var transaction = new VerifiedStoreKitTransaction("transaction-current", "original-current",
            "com.collapsetechnologies.trust.circle.monthly", token, "Sandbox", now.AddMinutes(-1), now.AddDays(20), null);
        var handler = new FixtureHandler(HttpStatusCode.OK,
            """{"data":[{"lastTransactions":[{"status":1,"signedTransactionInfo":"apple-signed-fixture"}]}]}""");
        var authority = new StoreKitSubscriptionAuthority(new HttpClient(handler), new FixtureVerifier(transaction), "short-lived-test-token");

        var current = await authority.GetCurrentActiveSubscriptionAsync(transaction.OriginalTransactionId, token,
            transaction.ProductId, transaction.Environment, now, CancellationToken.None);

        Assert.Equal(transaction, current);
        Assert.Equal("Bearer", handler.Authorization?.Scheme);
        Assert.Equal("short-lived-test-token", handler.Authorization?.Parameter);
        Assert.EndsWith("/inApps/v1/subscriptions/original-current", handler.RequestUri!.AbsoluteUri);
    }

    [Theory]
    [InlineData(2, "active")]
    [InlineData(1, "wrong-original")]
    [InlineData(1, "wrong-token")]
    [InlineData(1, "wrong-product")]
    [InlineData(1, "wrong-environment")]
    [InlineData(1, "revoked")]
    [InlineData(1, "expired")]
    [InlineData(1, "invalid-jws")]
    public async Task InactiveOrMismatchedAppleStatusCannotApproveRecovery(int status, string mismatch)
    {
        var now = DateTimeOffset.UtcNow;
        var token = Guid.NewGuid();
        var expected = new VerifiedStoreKitTransaction("transaction-current", "original-current",
            "com.collapsetechnologies.trust.circle.monthly", token, "Sandbox", now.AddMinutes(-1), now.AddDays(20), null);
        var actual = mismatch switch
        {
            "wrong-original" => expected with { OriginalTransactionId = "another-original" },
            "wrong-token" => expected with { AppAccountToken = Guid.NewGuid() },
            "wrong-product" => expected with { ProductId = "another.product" },
            "wrong-environment" => expected with { Environment = "Production" },
            "revoked" => expected with { RevokedAt = now.AddSeconds(-1) },
            "expired" => expected with { ExpiresAt = now.AddSeconds(-1) },
            _ => expected
        };
        var handler = new FixtureHandler(HttpStatusCode.OK,
            $$"""{"data":[{"lastTransactions":[{"status":{{status}},"signedTransactionInfo":"apple-signed-fixture"}]}]}""");
        var authority = new StoreKitSubscriptionAuthority(new HttpClient(handler),
            new FixtureVerifier(mismatch == "invalid-jws" ? null : actual), "short-lived-test-token");

        var error = await Assert.ThrowsAsync<TrustException>(() => authority.GetCurrentActiveSubscriptionAsync(
            expected.OriginalTransactionId, token, expected.ProductId, expected.Environment, now, CancellationToken.None));

        Assert.Equal("recovery_purchase_inactive", error.Code);
    }

    [Fact]
    public async Task AppleAuthorizationFailureIsRetryableAndFailsClosed()
    {
        var handler = new FixtureHandler(HttpStatusCode.Unauthorized, "{}");
        var authority = new StoreKitSubscriptionAuthority(new HttpClient(handler), new FixtureVerifier(null), "expired-test-token");

        var error = await Assert.ThrowsAsync<TrustException>(() => authority.GetCurrentActiveSubscriptionAsync(
            "original-current", Guid.NewGuid(), "product", "Sandbox", DateTimeOffset.UtcNow, CancellationToken.None));

        Assert.Equal("recovery_authority_unavailable", error.Code);
    }

    [Fact]
    public async Task VerifiedApprovalAddsOnlyExactTargetAliasAndDoesNotGrantUntilTransactionReplay()
    {
        var trust = new MemoryTrustStore();
        var engine = new TrustEngine(trust, TimeProvider.System);
        var target = await engine.SignInAsync("development", "storekit-recovery-target", "Target", CancellationToken.None);
        var other = await engine.SignInAsync("development", "storekit-recovery-other", "Other", CancellationToken.None);
        var entitlements = new MemoryStoreKitEntitlementStore(trust);
        _ = await entitlements.GetOrCreateAccountTokenAsync(target.Id, CancellationToken.None);
        var oldToken = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        var purchase = new VerifiedStoreKitTransaction("transaction-recovery", "original-recovery",
            "com.collapsetechnologies.trust.circle.monthly", oldToken, "Sandbox", now.AddMinutes(-1), now.AddDays(20), null);
        var requestId = await entitlements.CreateRecoveryRequestAsync(target.Id, purchase, null, now, CancellationToken.None);

        Assert.False((await trust.FindAccountAsync(target.Id, CancellationToken.None))!.HasCircle);
        var approved = await entitlements.ApproveRecoveryAsync(purchase.OriginalTransactionId, oldToken, target.Id,
            (_, _) => Task.FromResult(purchase), now, CancellationToken.None);
        Assert.Equal(requestId, approved);
        Assert.True(await entitlements.HasApprovedAliasAsync(purchase.OriginalTransactionId, oldToken, target.Id, CancellationToken.None));
        Assert.False(await entitlements.HasApprovedAliasAsync(purchase.OriginalTransactionId, oldToken, other.Id, CancellationToken.None));
        Assert.False((await trust.FindAccountAsync(target.Id, CancellationToken.None))!.HasCircle);

        Assert.Equal(StoreKitApplyOutcome.Applied, await entitlements.ApplyAsync(target.Id, purchase, CancellationToken.None));
        Assert.Equal(StoreKitApplyOutcome.NotApplied, await entitlements.ApplyAsync(other.Id, purchase, CancellationToken.None));
        Assert.True((await trust.FindAccountAsync(target.Id, CancellationToken.None))!.HasCircle);
    }

    private sealed class FixtureHandler(HttpStatusCode statusCode, string body) : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }
        public AuthenticationHeaderValue? Authorization { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            Authorization = request.Headers.Authorization;
            return Task.FromResult(new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(body)
            });
        }
    }

    private sealed class FixtureVerifier(VerifiedStoreKitTransaction? transaction) : IStoreKitTransactionVerifier
    {
        public StoreKitVerificationResult Verify(string signedTransaction) =>
            signedTransaction == "apple-signed-fixture"
                ? new(transaction, transaction is null ? "invalid fixture" : null)
                : new(null, "unexpected fixture");

        public StoreKitAppTransactionVerificationResult VerifyAppTransaction(string signedAppTransaction) => new(null, "unused");
        public StoreKitNotificationVerificationResult VerifyNotification(string signedPayload) => new(false, null, null, null, "unused");
    }
}
