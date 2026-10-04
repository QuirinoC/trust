using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.Phone;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

[Collection("Postgres integration")]
public sealed class PhoneCorrectionTests
{
    private static string Connection => Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";
    private static async Task<ITrustStore> Store(bool postgres)
    {
        if (!postgres) return new MemoryTrustStore();
        await PostgresMigrator.ApplyAsync(Connection);
        return new PostgresTrustStore(Connection);
    }
    private static async Task<Account> Account(ITrustStore store, Clock clock) =>
        await new TrustEngine(store, clock).SignInAsync("development", Guid.NewGuid().ToString(), "Synthetic", default);
    private static string Phone() => "+1" + Random.Shared.Next(200, 800) + "555" + Random.Shared.Next(1000, 9999);
    private static PhoneVerificationService Service(ITrustStore store, Clock clock, ISmsOtpSender? sender = null) => new(store,
        new TrustEngine(store, clock), sender ?? new Sender(), new AuthOptions { SigningKey = "phone-correction-tests-only-signing-key-at-least-32" },
        clock, new Env(), NullLogger<PhoneVerificationService>.Instance);

    [Theory][InlineData(false)][InlineData(true)]
    public async Task ThreeDistinctThenExactCooldownAndPersistence(bool postgres)
    {
        var store = await Store(postgres); var clock = new Clock(); var account = await Account(store, clock);
        try
        {
            var phones = Enumerable.Range(0, 4).Select(_ => Phone()).ToArray();
            var service = Service(store, clock);
            for (var i = 0; i < 3; i++)
            {
                var sent = await service.SendAsync(account.Id, phones[i], default, "send_code", 1);
                Assert.Equal(2-i, sent.Retry.ImmediateNumberAttemptsRemaining);
            }
            var persisted = postgres ? new PostgresTrustStore(Connection) : store;
            var blocked = await Assert.ThrowsAsync<TrustException>(() => Service(persisted, clock).SendAsync(account.Id, phones[3], default));
            Assert.Equal(clock.UtcNow.AddSeconds(180), blocked.PhoneRetry!.RetryAt);
            Assert.Equal(180, blocked.PhoneRetry.RetryAfterSeconds);
            Assert.Equal(3, (await persisted.GetSmsSendBudgetAsync(SmsSendBudget.AccountKey(account.Id), default))!.PhoneAttempts!.Length);
            Assert.Equal(3, (await persisted.ListPhoneSmsConsentEventsAsync(account.Id, default)).Count);
            clock.UtcNow = clock.UtcNow.AddSeconds(179);
            var almost = await Assert.ThrowsAsync<TrustException>(() => service.SendAsync(account.Id, phones[3], default));
            Assert.Equal(1, almost.PhoneRetry!.RetryAfterSeconds);
            clock.UtcNow = clock.UtcNow.AddSeconds(1);
            await service.SendAsync(account.Id, phones[3], default);
        }
        finally { await store.DeleteAccountAsync(account.Id, default); }
    }

    [Theory][InlineData(false)][InlineData(true)]
    public async Task RevisitsAndFormattingDoNotCreateGraceAndOtherAccountsKeepDestinationPacing(bool postgres)
    {
        var store = await Store(postgres); var clock = new Clock(); var a = await Account(store, clock); var b = await Account(store, clock);
        try
        {
            var first = Phone(); var second = Phone(); var service = Service(store, clock);
            await service.SendAsync(a.Id, first, default);
            var format = first.Insert(2, " (").Insert(7, ") ");
            var denied = await Assert.ThrowsAsync<TrustException>(() => service.SendAsync(a.Id, format, default));
            Assert.Equal(45, denied.PhoneRetry!.RetryAfterSeconds);
            await service.SendAsync(a.Id, second, default);
            var revisit = await Assert.ThrowsAsync<TrustException>(() => service.SendAsync(a.Id, first, default));
            Assert.Equal(90, revisit.PhoneRetry!.RetryAfterSeconds);
            var destination = await Assert.ThrowsAsync<TrustException>(() => service.SendAsync(b.Id, first, default));
            Assert.Equal(45, destination.PhoneRetry!.RetryAfterSeconds);
            Assert.Equal(1, revisit.PhoneRetry.ImmediateNumberAttemptsRemaining);
        }
        finally { await store.DeleteAccountAsync(a.Id, default); await store.DeleteAccountAsync(b.Id, default); }
    }

    [Theory][InlineData(false)][InlineData(true)]
    public async Task ConcurrentCorrectionsCommitExactlyThreeAndLatestChallengeAndConsent(bool postgres)
    {
        var store = await Store(postgres); var clock = new Clock(); var account = await Account(store, clock);
        try
        {
            var results = await Task.WhenAll(Enumerable.Range(0, 4).Select(async i =>
            {
                var phone = Phone();
                try { return (phone, result: await Service(postgres ? new PostgresTrustStore(Connection) : store, clock).SendAsync(account.Id, phone, default, "send_code", 1)); }
                catch (TrustException ex) when (ex.Code == "otp_cooldown") { return (phone, result: (PhoneCodeSendResult?)null); }
            }));
            Assert.Equal(3, results.Count(result => result.result != null));
            var last = results.Single(result => result.result?.Retry.ImmediateNumberAttemptsRemaining == 0);
            Assert.Equal(last.phone, (await store.GetPhoneChallengeAsync(account.Id, default))!.PhoneE164);
            Assert.Equal(3, (await store.ListPhoneSmsConsentEventsAsync(account.Id, default)).Count);
            await Service(store, clock).VerifyAsync(account.Id, last.phone, last.result!.DevelopmentCode, default);
        }
        finally { await store.DeleteAccountAsync(account.Id, default); }
    }

    [Theory][InlineData(false)][InlineData(true)]
    public async Task SameNumberConcurrencyAcceptsOneAndOldWrongCodeCannotConsumeReplacement(bool postgres)
    {
        var store = await Store(postgres); var clock = new Clock(); var account = await Account(store, clock); var phone = Phone();
        try
        {
            var results = await Task.WhenAll(Enumerable.Range(0, 4).Select(async _ =>
            {
                try { return await Service(store, clock).SendAsync(account.Id, phone, default); }
                catch (TrustException ex) when (ex.Code == "otp_cooldown") { return null; }
            }));
            Assert.Single(results, x => x != null);
            var old = (await store.GetPhoneChallengeAsync(account.Id, default))!;
            clock.UtcNow = clock.UtcNow.AddSeconds(45);
            var replacement = await Service(store, clock).SendAsync(account.Id, phone, default);
            Assert.Null(await store.IncrementPhoneChallengeFailureAsync(account.Id, phone, old.CodeHash, clock.UtcNow, 5, default));
            Assert.Equal(0, (await store.GetPhoneChallengeAsync(account.Id, default))!.Attempts);
            await Service(store, clock).VerifyAsync(account.Id, phone, replacement.DevelopmentCode, default);
        }
        finally { await store.DeleteAccountAsync(account.Id, default); }
    }

    [Theory][InlineData(false)][InlineData(true)]
    public async Task LegacyBudgetsGrantNoGraceUntilWindowRollsAndDestinationMinimumSurvives(bool postgres)
    {
        var store = await Store(postgres); var clock = new Clock(); var account = await Account(store, clock); var phone = Phone();
        try
        {
            var start = clock.UtcNow.AddMinutes(-59).AddSeconds(-50);
            await store.UpsertSmsSendBudgetAsync(new(SmsSendBudget.AccountKey(account.Id), start, 3, clock.UtcNow), default);
            await store.UpsertSmsSendBudgetAsync(new(SmsSendBudget.PhoneKey(phone), start, 3, clock.UtcNow), default);
            var denied = await Assert.ThrowsAsync<TrustException>(() => Service(store, clock).SendAsync(account.Id, Phone(), default));
            Assert.Equal(0, denied.PhoneRetry!.ImmediateNumberAttemptsRemaining);
            Assert.Equal(10, denied.PhoneRetry.RetryAfterSeconds);
            clock.UtcNow = clock.UtcNow.AddSeconds(10);
            await Service(store, clock).SendAsync(account.Id, Phone(), default);
            var destination = await Assert.ThrowsAsync<TrustException>(() => Service(store, clock).SendAsync(account.Id, phone, default));
            Assert.Equal(35, destination.PhoneRetry!.RetryAfterSeconds);
            clock.UtcNow = clock.UtcNow.AddSeconds(35);
            await Service(store, clock).SendAsync(account.Id, phone, default);
        }
        finally { await store.DeleteAccountAsync(account.Id, default); }
    }

    [Theory][InlineData(false)][InlineData(true)]
    public async Task FailedProviderConsumesReservationAndResponseClockDoesNotExtendWait(bool postgres)
    {
        var store = await Store(postgres); var clock = new Clock(); var account = await Account(store, clock);
        try
        {
            // Keep the production global budget scoped to an isolated fake day.
            await store.UpsertSmsSendBudgetAsync(new(SmsSendBudget.GlobalDayKey(), clock.UtcNow, 0, null), default);
            var phone = Phone();
            var sender = new Sender { Configured = true, OnSend = () => { clock.UtcNow = clock.UtcNow.AddSeconds(10); throw new InvalidOperationException(); } };
            var failure = await Assert.ThrowsAsync<TrustException>(() => Service(store, clock, sender).SendAsync(account.Id, phone, default, "send_code", 1));
            Assert.Equal("otp_send_failed", failure.Code);
            Assert.Equal(35, failure.PhoneRetry!.RetryAfterSeconds);
            Assert.Equal(clock.UtcNow, failure.PhoneRetry.ServerTime);
            Assert.Equal(2, failure.PhoneRetry.ImmediateNumberAttemptsRemaining);
            Assert.Single(await store.ListPhoneSmsConsentEventsAsync(account.Id, default));
            Assert.Equal(1, (await store.GetSmsSendBudgetAsync(SmsSendBudget.AccountDayKey(account.Id), default))!.SendCount);
        }
        finally { await store.DeleteAccountAsync(account.Id, default); }
    }

    [Fact]
    public async Task PhoneRoute429IncludesRealLimiterRetryMetadata()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/v1/session/development", new { displayName = "Synthetic", deviceId = Guid.NewGuid().ToString() });
        var session = await login.Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new("Bearer", session.GetProperty("token").GetString());
        for (var i = 0; i < 5; i++)
            Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/me/phone/send", new { phone = "invalid" })).StatusCode);
        var blocked = await client.PostAsJsonAsync("/api/v1/me/phone/send", new { phone = "invalid" });
        Assert.Equal(HttpStatusCode.TooManyRequests, blocked.StatusCode);
        var body = await blocked.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("otp_cooldown", body.GetProperty("code").GetString());
        Assert.InRange(body.GetProperty("retryAfterSeconds").GetInt32(), 1, 60);
        Assert.NotNull(blocked.Headers.RetryAfter);
        Assert.True(body.GetProperty("retryAt").GetDateTimeOffset() > body.GetProperty("serverTime").GetDateTimeOffset());
    }

    [Fact]
    public async Task ConsumedProviderFailure503PreservesRetryContract()
    {
        using var factory = new TrustApiFactory().WithWebHostBuilder(builder => builder.ConfigureServices(services =>
            services.AddSingleton<ISmsOtpSender>(new Sender { Configured = true, OnSend = () => throw new InvalidOperationException() })));
        using var client = factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/v1/session/development", new { displayName = "Synthetic", deviceId = Guid.NewGuid().ToString() });
        var session = await login.Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new("Bearer", session.GetProperty("token").GetString());
        var failed = await client.PostAsJsonAsync("/api/v1/me/phone/send", new { phone = Phone(), consentAction = "send_code", consentVersion = 1 });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, failed.StatusCode);
        var body = await failed.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("otp_send_failed", body.GetProperty("code").GetString());
        Assert.Equal(2, body.GetProperty("immediateNumberAttemptsRemaining").GetInt32());
        Assert.Equal(1, body.GetProperty("accountSendCount").GetInt32());
        Assert.InRange(body.GetProperty("retryAfterSeconds").GetInt32(), 1, 45);
        Assert.True(body.GetProperty("resendRetryAt").GetDateTimeOffset() > body.GetProperty("serverTime").GetDateTimeOffset());
    }

    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = new(2034, 1, 1, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => UtcNow;
    }
    private sealed class Sender : ISmsOtpSender
    {
        public bool Configured; public Action? OnSend;
        public bool IsConfigured => Configured;
        public Task SendAsync(string e164, string code, CancellationToken cancellationToken) { OnSend?.Invoke(); return Task.CompletedTask; }
        public Task SendTextAsync(string e164, string body, CancellationToken cancellationToken) => Task.CompletedTask;
    }
    private sealed class Env : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "Tests";
        public string ContentRootPath { get; set; } = ".";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
