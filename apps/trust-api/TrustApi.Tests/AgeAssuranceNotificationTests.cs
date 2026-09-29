using System.Security.Claims;
using System.Reflection;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using TrustApi.Api.V1;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.AgeAssurance;
using TrustApi.Infrastructure.Notifications;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class AgeAssuranceNotificationTests
{
    [Fact]
    public async Task AuthenticatedApiRequiresVerifiedAppTransactionLinkBeforeOrdinaryAccess()
    {
        var accountId = Guid.NewGuid();
        var transaction = new VerifiedStoreKitAppTransaction(
            "api-link-required-test",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accounts = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        await accounts.UpsertAccountAsync(
            new Account(accountId, "apple", "api-link-required-test", "Test", false, null, DateTimeOffset.UtcNow),
            CancellationToken.None);
        var filter = new RevokedAccountEndpointFilter(ageAssurance, accounts, new TestHostEnvironment("Production"));

        Assert.True(await filter.ShouldBlockForMissingLinkAsync(
            accountId, "GET", "/api/v1/circle", CancellationToken.None));
        Assert.True(await filter.ShouldBlockForMissingLinkAsync(
            accountId, "POST", "/api/v1/location", CancellationToken.None));
        Assert.False(await filter.ShouldBlockForMissingLinkAsync(
            accountId, "PUT", "/api/v1/age-assurance/app-transaction", CancellationToken.None));
        Assert.False(await filter.ShouldBlockForMissingLinkAsync(
            accountId, "DELETE", "/api/v1/account", CancellationToken.None));
        Assert.False(await filter.ShouldBlockForMissingLinkAsync(
            accountId, "DELETE", $"/api/v1/push/devices/{Guid.NewGuid()}", CancellationToken.None));

        Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(
            accountId, transaction, CancellationToken.None));
        Assert.False(await filter.ShouldBlockForMissingLinkAsync(
            accountId, "GET", "/api/v1/circle", CancellationToken.None));

        await ageAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, DateTimeOffset.UtcNow, CancellationToken.None);
        Assert.True(await filter.ShouldBlockAsync(accountId, "GET", "/api/v1/circle", CancellationToken.None));
    }

    [Fact]
    public async Task RevocationNotificationReturnsRetryableFailureUntilAccountCleanupSucceeds()
    {
        var accountId = Guid.NewGuid();
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-notification-retry",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var notificationId = Guid.NewGuid();
        var verifier = new StubStoreKitVerifier(new StoreKitNotificationVerificationResult(
            true,
            notificationId,
            "RESCIND_CONSENT",
            null,
            null,
            appTransaction,
            DateTimeOffset.UtcNow));
        var memoryAccounts = new MemoryTrustStore();
        var accounts = DispatchProxy.Create<ITrustStore, FailingDeleteTrustStore>();
        var deleteProxy = (FailingDeleteTrustStore)(object)accounts;
        deleteProxy.Inner = memoryAccounts;
        deleteProxy.FailDeletes = true;
        await memoryAccounts.UpsertAccountAsync(
            new Account(accountId, "apple", "subject-notification-retry", "Test", false, null, DateTimeOffset.UtcNow),
            CancellationToken.None);
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(accountId, appTransaction, CancellationToken.None));
        var devices = new MemoryPushDeviceStore();
        var storeKit = new MemoryStoreKitEntitlementStore(memoryAccounts);
        var request = new StoreKitNotificationRequest("signed-revocation");

        var first = await TrustEndpoints.StoreKitNotificationAsync(
            request,
            verifier,
            storeKit,
            ageAssurance,
            devices,
            accounts,
            Options.Create(new StoreKitOptions { Enabled = false }),
            NullLoggerFactory.Instance,
            CancellationToken.None);

        Assert.Equal(StatusCodes.Status503ServiceUnavailable, Assert.IsAssignableFrom<IStatusCodeHttpResult>(first).StatusCode);
        Assert.Equal("consent_cleanup_pending", Assert.IsType<ApiError>(Assert.IsAssignableFrom<IValueHttpResult>(first).Value).Code);
        Assert.NotNull(await memoryAccounts.FindAccountAsync(accountId, CancellationToken.None));
        Assert.True(await ageAssurance.IsAccountBlockedAsync(accountId, CancellationToken.None));

        deleteProxy.FailDeletes = false;
        var retry = await TrustEndpoints.StoreKitNotificationAsync(
            request,
            verifier,
            storeKit,
            ageAssurance,
            devices,
            accounts,
            Options.Create(new StoreKitOptions { Enabled = false }),
            NullLoggerFactory.Instance,
            CancellationToken.None);

        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(retry).StatusCode);
        Assert.Null(await memoryAccounts.FindAccountAsync(accountId, CancellationToken.None));
        Assert.False(await ageAssurance.IsAccountBlockedAsync(accountId, CancellationToken.None));
    }

    [Fact]
    public async Task FailedRevocationDeletionLeavesAuthenticatedRoutesBlockedUntilCleanupRetrySucceeds()
    {
        var accountId = Guid.NewGuid();
        var transaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-delete-retry",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accounts = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var devices = new MemoryPushDeviceStore();
        await accounts.UpsertAccountAsync(
            new Account(accountId, "apple", "subject-delete-retry", "Test", false, null, DateTimeOffset.UtcNow),
            CancellationToken.None);
        Assert.Equal(AppTransactionLinkResult.Linked, await ageAssurance.TryRegisterAppTransactionLinkAsync(accountId, transaction, CancellationToken.None));
        await ageAssurance.RecordConsentRevocationAsync(Guid.NewGuid(), transaction, DateTimeOffset.UtcNow, CancellationToken.None);

        var filter = new RevokedAccountEndpointFilter(ageAssurance, accounts, new TestHostEnvironment("Production"));
        Assert.True(await filter.ShouldBlockAsync(accountId, "GET", "/api/v1/circle", CancellationToken.None));
        Assert.False(await filter.ShouldBlockAsync(accountId, "PUT", "/api/v1/age-assurance/app-transaction", CancellationToken.None));

        var deleted = await TrustEndpoints.TryDeleteRevokedAccountAsync(
            accountId,
            _ => throw new IOException("Injected account-store failure"),
            devices,
            ageAssurance,
            NullLogger<TrustEngine>.Instance,
            CancellationToken.None);
        Assert.False(deleted);
        Assert.NotNull(await accounts.FindAccountAsync(accountId, CancellationToken.None));
        Assert.True(await filter.ShouldBlockAsync(accountId, "GET", "/api/v1/circle", CancellationToken.None));

        deleted = await TrustEndpoints.TryDeleteRevokedAccountAsync(
            accountId,
            token => accounts.DeleteAccountAsync(accountId, token),
            devices,
            ageAssurance,
            NullLogger<TrustEngine>.Instance,
            CancellationToken.None);
        Assert.True(deleted);
        Assert.Null(await accounts.FindAccountAsync(accountId, CancellationToken.None));
        Assert.False(await ageAssurance.IsAccountBlockedAsync(accountId, CancellationToken.None));
    }

    [Fact]
    public async Task ConsentRevocationRemovesPushDevicesAndDeletesEveryLinkedAccountEvenWhenStoreKitBillingIsDisabled()
    {
        var now = DateTimeOffset.UtcNow;
        var appTransaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-revoke",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var notificationId = Guid.NewGuid();
        var verifier = new StubStoreKitVerifier(new StoreKitNotificationVerificationResult(
            true,
            notificationId,
            "RESCIND_CONSENT",
            null,
            null,
            appTransaction,
            now.AddMinutes(-1)));
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var accounts = new MemoryTrustStore();
        var devices = new MemoryPushDeviceStore();
        var storeKit = new MemoryStoreKitEntitlementStore(accounts);
        var accountIds = new[] { Guid.NewGuid(), Guid.NewGuid() };

        foreach (var accountId in accountIds)
        {
            await accounts.UpsertAccountAsync(
                new Account(accountId, "apple", $"subject-{accountId:N}", "Test", false, null, now),
                CancellationToken.None);
            await devices.RegisterAsync(
                accountId,
                Guid.NewGuid(),
                new string('a', 64),
                "sandbox",
                appTransaction.BundleId,
                CancellationToken.None);
            await ageAssurance.TryRegisterAppTransactionLinkAsync(
                accountId,
                appTransaction,
                CancellationToken.None);
        }

        var result = await TrustEndpoints.StoreKitNotificationAsync(
            new StoreKitNotificationRequest("signed-notification"),
            verifier,
            storeKit,
            ageAssurance,
            devices,
            accounts,
            Options.Create(new StoreKitOptions { Enabled = false }),
            NullLoggerFactory.Instance,
            CancellationToken.None);

        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);
        foreach (var accountId in accountIds)
        {
            Assert.Null(await accounts.FindAccountAsync(accountId, CancellationToken.None));
            Assert.Empty(await devices.ListActiveAsync(accountId, CancellationToken.None));
        }

        var duplicate = await TrustEndpoints.StoreKitNotificationAsync(
            new StoreKitNotificationRequest("signed-notification"),
            verifier,
            storeKit,
            ageAssurance,
            devices,
            accounts,
            Options.Create(new StoreKitOptions { Enabled = false }),
            NullLoggerFactory.Instance,
            CancellationToken.None);
        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(duplicate).StatusCode);
    }

    [Fact]
    public async Task RegistrationLinksVerifiedAppTransactionToAuthenticatedAccount()
    {
        var accountId = Guid.NewGuid();
        var transaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-link",
            "com.collapsetechnologies.trust",
            "Production");
        var verifier = new StubStoreKitVerifier(appTransaction: new StoreKitAppTransactionVerificationResult(transaction, null));
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var accounts = new MemoryTrustStore();
        await accounts.UpsertAccountAsync(
            new Account(accountId, "apple", "subject-age-link", "Test", false, null, DateTimeOffset.UtcNow),
            CancellationToken.None);
        var principal = new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", accountId.ToString())], "test"));

        var result = await TrustEndpoints.RegisterAgeAssuranceAppTransactionAsync(
            new RegisterAgeAssuranceAppTransactionRequest("signed-app-transaction"),
            principal,
            verifier,
            ageAssurance,
            accounts,
            new MemoryPushDeviceStore(),
            NullLogger<TrustEngine>.Instance,
            CancellationToken.None);

        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);
        var notificationId = Guid.NewGuid();
        var linked = await ageAssurance.RecordConsentRevocationAsync(
            notificationId,
            transaction,
            DateTimeOffset.UtcNow.AddMinutes(-1),
            CancellationToken.None);
        Assert.Equal(new[] { accountId }, linked);
    }

    [Fact]
    public async Task ReplayedAppTransactionCannotRestoreConsentAndOlderRescindStillDeletesLinkedAccount()
    {
        var accountId = Guid.NewGuid();
        var transaction = new VerifiedStoreKitAppTransaction(
            "apple-app-transaction-replay-after-revocation",
            "com.collapsetechnologies.trust",
            "Sandbox");
        var accounts = new MemoryTrustStore();
        var ageAssurance = new MemoryAgeAssuranceAccountStore();
        var devices = new MemoryPushDeviceStore();
        var storeKit = new MemoryStoreKitEntitlementStore(accounts);
        var now = DateTimeOffset.UtcNow;
        var registerVerifier = new StubStoreKitVerifier(
            appTransaction: new StoreKitAppTransactionVerificationResult(transaction, null));

        await accounts.UpsertAccountAsync(
            new Account(accountId, "apple", "subject-age-replay", "Test", false, null, now),
            CancellationToken.None);
        var principal = new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", accountId.ToString())], "test"));
        var registration = await TrustEndpoints.RegisterAgeAssuranceAppTransactionAsync(
            new RegisterAgeAssuranceAppTransactionRequest("signed-app-transaction"),
            principal,
            registerVerifier,
            ageAssurance,
            accounts,
            devices,
            NullLogger<TrustEngine>.Instance,
            CancellationToken.None);
        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(registration).StatusCode);

        var notificationId = Guid.NewGuid();
        var rescindVerifier = new StubStoreKitVerifier(new StoreKitNotificationVerificationResult(
            true,
            notificationId,
            "RESCIND_CONSENT",
            null,
            null,
            transaction,
            now.AddMinutes(-1)));
        var result = await TrustEndpoints.StoreKitNotificationAsync(
            new StoreKitNotificationRequest("signed-rescind"),
            rescindVerifier,
            storeKit,
            ageAssurance,
            devices,
            accounts,
            Options.Create(new StoreKitOptions { Enabled = false }),
            NullLoggerFactory.Instance,
            CancellationToken.None);
        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);
        Assert.Null(await accounts.FindAccountAsync(accountId, CancellationToken.None));

        var replayAccountId = Guid.NewGuid();
        await accounts.UpsertAccountAsync(
            new Account(replayAccountId, "apple", "subject-age-replay-2", "Replay", false, null, now),
            CancellationToken.None);
        var replayPrincipal = new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub", replayAccountId.ToString())], "test"));
        var replay = await TrustEndpoints.RegisterAgeAssuranceAppTransactionAsync(
            new RegisterAgeAssuranceAppTransactionRequest("signed-app-transaction"),
            replayPrincipal,
            registerVerifier,
            ageAssurance,
            accounts,
            devices,
            NullLogger<TrustEngine>.Instance,
            CancellationToken.None);
        Assert.Equal(StatusCodes.Status409Conflict, Assert.IsAssignableFrom<IStatusCodeHttpResult>(replay).StatusCode);
        Assert.Equal("consent_revoked", Assert.IsType<ApiError>(Assert.IsAssignableFrom<IValueHttpResult>(replay).Value).Code);
        Assert.Null(await accounts.FindAccountAsync(replayAccountId, CancellationToken.None));

        var repeatedRescindVerifier = new StubStoreKitVerifier(new StoreKitNotificationVerificationResult(
            true,
            Guid.NewGuid(),
            "RESCIND_CONSENT",
            null,
            null,
            transaction,
            now.AddHours(-1)));
        await TrustEndpoints.StoreKitNotificationAsync(
            new StoreKitNotificationRequest("signed-stale-rescind"),
            repeatedRescindVerifier,
            storeKit,
            ageAssurance,
            devices,
            accounts,
            Options.Create(new StoreKitOptions { Enabled = false }),
            NullLoggerFactory.Instance,
            CancellationToken.None);
        Assert.Null(await accounts.FindAccountAsync(replayAccountId, CancellationToken.None));
    }

    private sealed class StubStoreKitVerifier(
        StoreKitNotificationVerificationResult? notification = null,
        StoreKitAppTransactionVerificationResult? appTransaction = null) : IStoreKitTransactionVerifier
    {
        public StoreKitVerificationResult Verify(string signedTransaction) => new(null, "unused");

        public StoreKitAppTransactionVerificationResult VerifyAppTransaction(string signedAppTransaction) =>
            appTransaction ?? new StoreKitAppTransactionVerificationResult(null, "unused");

        public StoreKitNotificationVerificationResult VerifyNotification(string signedPayload) =>
            notification ?? new StoreKitNotificationVerificationResult(false, null, null, null, "unused");
    }

    public class FailingDeleteTrustStore : DispatchProxy
    {
        public ITrustStore Inner { get; set; } = null!;
        public bool FailDeletes { get; set; }

        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
        {
            if (targetMethod?.Name == nameof(ITrustStore.DeleteAccountAsync) && FailDeletes)
            {
                throw new IOException("Injected account-store failure");
            }
            return targetMethod!.Invoke(Inner, args);
        }
    }

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "TrustApi.Tests";
        public string ContentRootPath { get; set; } = Directory.GetCurrentDirectory();
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
