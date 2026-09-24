using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.Phone;

namespace TrustApi.Tests;

public sealed class PhoneVerificationTests
{
    [Fact]
    public void PlaceholderNameIsNotOnboardingComplete()
    {
        var account = new Account(Guid.NewGuid(), "apple", "sub", "You", false, null, DateTimeOffset.UtcNow);
        Assert.False(account.HasChosenDisplayName);
        Assert.False(account.HasVerifiedPhone);
        Assert.False(account.HasHandle);
        Assert.False(account.OnboardingComplete);
    }

    [Fact]
    public void ChosenNameAndVerifiedPhoneWithoutHandleIsNotOnboardingComplete()
    {
        var account = new Account(
            Guid.NewGuid(),
            "apple",
            "sub",
            "Sam",
            false,
            null,
            DateTimeOffset.UtcNow,
            "+15555550100",
            DateTimeOffset.UtcNow);
        Assert.True(account.HasChosenDisplayName);
        Assert.True(account.HasVerifiedPhone);
        Assert.False(account.OnboardingComplete);
    }

    [Fact]
    public void HandleWithoutVerifiedPhoneIsNotOnboardingComplete()
    {
        var account = new Account(
            Guid.NewGuid(),
            "apple",
            "sub",
            "You",
            false,
            null,
            DateTimeOffset.UtcNow,
            Handle: "jordan");
        Assert.True(account.HasHandle);
        Assert.False(account.HasVerifiedPhone);
        Assert.False(account.OnboardingComplete);
        Assert.Equal("@jordan", account.PublicName);
    }

    [Fact]
    public void HandleAndVerifiedPhoneCompletesOnboarding()
    {
        var account = new Account(
            Guid.NewGuid(),
            "apple",
            "sub",
            "You",
            false,
            null,
            DateTimeOffset.UtcNow,
            "+15555550100",
            DateTimeOffset.UtcNow,
            "jordan");
        Assert.True(account.HasHandle);
        Assert.True(account.HasVerifiedPhone);
        Assert.True(account.OnboardingComplete);
        Assert.Equal("@jordan", account.PublicName);
    }

    [Fact]
    public void PhoneE164NormalizesUsNumbers()
    {
        Assert.True(PhoneE164.TryNormalize("4155550100", out var local));
        Assert.Equal("+14155550100", local);
        Assert.True(PhoneE164.TryNormalize("+44 7700 900123", out var intl));
        Assert.Equal("+447700900123", intl);
        Assert.False(PhoneE164.TryNormalize("123", out _));
        Assert.False(PhoneE164.TryNormalize("9005550100", out _));
        Assert.False(PhoneE164.TryNormalize("4159760100", out _));
        Assert.False(PhoneE164.TryNormalize("+881612345678", out _));
        Assert.False(PhoneE164.TryNormalize("not-a-phone", out _));
    }

    [Fact]
    public async Task DevelopmentBypassReturnsCodeAndDoesNotLogIt()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-dev", "Sam", CancellationToken.None);
        var logger = new ListLogger();
        var phones = NewPhones(store, new UnconfiguredSms(), logger, Environments.Development);

        var sent = await phones.SendAsync(account.Id, "+15555550123", CancellationToken.None);
        Assert.False(string.IsNullOrWhiteSpace(sent.DevelopmentCode));
        Assert.Equal(6, sent.DevelopmentCode!.Length);
        Assert.All(logger.Messages, message => Assert.DoesNotContain(sent.DevelopmentCode, message));

        await phones.VerifyAsync(account.Id, "5555550123", sent.DevelopmentCode, CancellationToken.None);
        var updated = await store.FindAccountAsync(account.Id, CancellationToken.None);
        Assert.True(updated!.HasVerifiedPhone);
        Assert.False(updated.OnboardingComplete);
        Assert.Equal("+15555550123", updated.PhoneE164);
    }

    [Fact]
    public async Task ConfiguredSmsDoesNotReturnDevelopmentCode()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-sms", "Sam", CancellationToken.None);
        var sms = new RecordingSms();
        var phones = NewPhones(store, sms, NullLogger<PhoneVerificationService>.Instance, Environments.Development);

        var sent = await phones.SendAsync(account.Id, "+15555550124", CancellationToken.None);
        Assert.Null(sent.DevelopmentCode);
        Assert.Equal("+15555550124", sms.LastTo);
        Assert.False(string.IsNullOrWhiteSpace(sms.LastCode));

        await phones.VerifyAsync(account.Id, "+15555550124", sms.LastCode!, CancellationToken.None);
        Assert.True((await store.FindAccountAsync(account.Id, CancellationToken.None))!.HasVerifiedPhone);
    }

    [Fact]
    public async Task ProductionWithoutTwilioDoesNotBypass()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-prod", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Production);

        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(account.Id, "+15555550125", CancellationToken.None));
        Assert.Equal("otp_not_configured", exception.Code);
    }

    [Fact]
    public async Task WrongCodeIsRejectedWithoutCompleting()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-wrong", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development);
        var sent = await phones.SendAsync(account.Id, "+15555550126", CancellationToken.None);

        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            phones.VerifyAsync(account.Id, "+15555550126", "000000", CancellationToken.None));
        Assert.Equal("otp_invalid", exception.Code);
        Assert.NotEqual("000000", sent.DevelopmentCode);
        Assert.False((await store.FindAccountAsync(account.Id, CancellationToken.None))!.HasVerifiedPhone);
    }

    [Fact]
    public async Task PhoneCannotBeVerifiedOntoTwoAccounts()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var first = await engine.SignInAsync("development", "otp-a", "Sam", CancellationToken.None);
        var second = await engine.SignInAsync("development", "otp-b", "Jordan", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development);
        var sent = await phones.SendAsync(first.Id, "+15555550127", CancellationToken.None);
        await phones.VerifyAsync(first.Id, "+15555550127", sent.DevelopmentCode!, CancellationToken.None);

        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(second.Id, "+15555550127", CancellationToken.None));
        Assert.Equal("phone_in_use", exception.Code);
    }

    [Fact]
    public async Task ResendWaitsThenBacksOff()
    {
        var clock = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 21, 12, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, clock);
        var account = await engine.SignInAsync("development", "otp-backoff", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development, clock);

        var first = await phones.SendAsync(account.Id, "+15555550140", CancellationToken.None);
        Assert.Equal(PhoneVerificationService.ResendCooldownSeconds, first.ResendAfterSeconds);

        clock.UtcNow = clock.UtcNow.AddSeconds(PhoneVerificationService.ResendCooldownSeconds - 1);
        var early = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(account.Id, "+15555550140", CancellationToken.None));
        Assert.Equal("otp_cooldown", early.Code);

        clock.UtcNow = clock.UtcNow.AddSeconds(1);
        var second = await phones.SendAsync(account.Id, "+15555550140", CancellationToken.None);
        Assert.Equal(PhoneVerificationService.ResendCooldownSeconds * 2, second.ResendAfterSeconds);

        clock.UtcNow = clock.UtcNow.AddSeconds(PhoneVerificationService.ResendCooldownSeconds);
        var backedOff = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(account.Id, "+15555550140", CancellationToken.None));
        Assert.Equal("otp_cooldown", backedOff.Code);

        clock.UtcNow = clock.UtcNow.AddSeconds(PhoneVerificationService.ResendCooldownSeconds);
        var third = await phones.SendAsync(account.Id, "+15555550140", CancellationToken.None);
        Assert.False(string.IsNullOrWhiteSpace(third.DevelopmentCode));
    }

    [Fact]
    public async Task AccountSendCapHoldsAcrossPhoneNumbers()
    {
        var clock = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 21, 12, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, clock);
        var account = await engine.SignInAsync("development", "otp-account-cap", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development, clock);

        for (var i = 0; i < PhoneVerificationService.MaxSendsPerHour; i++)
        {
            var sent = await phones.SendAsync(account.Id, $"+155555501{i:D2}", CancellationToken.None);
            clock.UtcNow = clock.UtcNow.AddSeconds(sent.ResendAfterSeconds);
        }

        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(account.Id, "+15555550199", CancellationToken.None));
        Assert.Equal("otp_cooldown", blocked.Code);
    }

    [Fact]
    public async Task PhoneSendCapHoldsAcrossAccounts()
    {
        var clock = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 21, 12, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, clock);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development, clock);
        const string shared = "+15555550141";

        for (var i = 0; i < PhoneVerificationService.MaxSendsPerHour; i++)
        {
            var account = await engine.SignInAsync("development", $"otp-phone-cap-{i}", "Sam", CancellationToken.None);
            var sent = await phones.SendAsync(account.Id, shared, CancellationToken.None);
            clock.UtcNow = clock.UtcNow.AddSeconds(sent.ResendAfterSeconds);
        }

        var next = await engine.SignInAsync("development", "otp-phone-cap-next", "Jordan", CancellationToken.None);
        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(next.Id, shared, CancellationToken.None));
        Assert.Equal("otp_cooldown", blocked.Code);
    }

    [Fact]
    public async Task FiveWrongGuessesKillTheCode()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-guess", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development);
        var sent = await phones.SendAsync(account.Id, "+15555550142", CancellationToken.None);
        Assert.NotEqual("000000", sent.DevelopmentCode);

        for (var i = 0; i < PhoneVerificationService.MaxAttempts - 1; i++)
        {
            var invalid = await Assert.ThrowsAsync<TrustException>(() =>
                phones.VerifyAsync(account.Id, "+15555550142", "000000", CancellationToken.None));
            Assert.Equal("otp_invalid", invalid.Code);
        }

        var exhausted = await Assert.ThrowsAsync<TrustException>(() =>
            phones.VerifyAsync(account.Id, "+15555550142", "000000", CancellationToken.None));
        Assert.Equal("otp_exhausted", exhausted.Code);

        var after = await Assert.ThrowsAsync<TrustException>(() =>
            phones.VerifyAsync(account.Id, "+15555550142", sent.DevelopmentCode, CancellationToken.None));
        Assert.Equal("otp_expired", after.Code);
        Assert.False((await store.FindAccountAsync(account.Id, CancellationToken.None))!.HasVerifiedPhone);
    }

    [Fact]
    public async Task VerifiedPhoneConnectsWithoutSms()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var first = await engine.SignInAsync("development", "otp-lookup-a", "Sam", CancellationToken.None);
        var second = await engine.SignInAsync("development", "otp-lookup-b", "Jordan", CancellationToken.None);
        var sms = new RecordingSms();
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development);
        var sent = await phones.SendAsync(first.Id, "+15555550143", CancellationToken.None);
        await phones.VerifyAsync(first.Id, "+15555550143", sent.DevelopmentCode!, CancellationToken.None);

        var production = NewPhones(store, sms, NullLogger<PhoneVerificationService>.Instance, Environments.Production);
        var added = await production.AddPersonAsync(second.Id, "5555550143", CancellationToken.None);
        Assert.Equal("connected", added.Outcome);
        Assert.False(added.SmsSent);
        Assert.Null(added.DevelopmentCode);
        Assert.Equal(0, sms.Sends);
        Assert.True(await store.AreConnectedAsync(first.Id, second.Id, CancellationToken.None));
        Assert.Null(await store.FindPendingInviteAsync(second.Id, CancellationToken.None));
    }

    [Fact]
    public async Task UnknownPhoneReturnsInviteCodeWithoutSms()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-invite", "Sam", CancellationToken.None);
        var sms = new RecordingSms();
        var phones = NewPhones(store, sms, NullLogger<PhoneVerificationService>.Instance, Environments.Production);

        var invited = await phones.AddPersonAsync(account.Id, "+15555550144", CancellationToken.None);
        Assert.Equal("invited", invited.Outcome);
        Assert.False(invited.SmsSent);
        Assert.False(string.IsNullOrWhiteSpace(invited.DevelopmentCode));
        Assert.Equal(0, sms.Sends);
        var pending = await store.FindPendingInviteAsync(account.Id, CancellationToken.None);
        Assert.Equal(pending!.Code, invited.DevelopmentCode);
    }

    [Fact]
    public async Task DevelopmentInviteBypassReturnsCodeWithoutSms()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-invite-dev", "Sam", CancellationToken.None);
        var logger = new ListLogger();
        var phones = NewPhones(store, new UnconfiguredSms(), logger, Environments.Development);
        var invited = await phones.AddPersonAsync(account.Id, "+15555550146", CancellationToken.None);
        Assert.Equal("invited", invited.Outcome);
        Assert.False(invited.SmsSent);
        Assert.False(string.IsNullOrWhiteSpace(invited.DevelopmentCode));
        Assert.All(logger.Messages, message => Assert.DoesNotContain(invited.DevelopmentCode!, message));
        var pending = await store.FindPendingInviteAsync(account.Id, CancellationToken.None);
        Assert.Equal(pending!.Code, invited.DevelopmentCode);
    }

    [Fact]
    public async Task ProductionInviteWithoutTwilioDoesNotPretend()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-invite-prod", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Production);
        var invited = await phones.AddPersonAsync(account.Id, "+15555550147", CancellationToken.None);
        Assert.Equal("invited", invited.Outcome);
        Assert.False(invited.SmsSent);
        Assert.False(string.IsNullOrWhiteSpace(invited.DevelopmentCode));
        var pending = await store.FindPendingInviteAsync(account.Id, CancellationToken.None);
        Assert.Equal(pending!.Code, invited.DevelopmentCode);
    }

    [Fact]
    public async Task AccountDailyCapHoldsAfterTheHourResets()
    {
        var clock = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 21, 12, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, clock);
        var account = await engine.SignInAsync("development", "otp-day", "Sam", CancellationToken.None);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development, clock);

        for (var i = 0; i < PhoneVerificationService.MaxSendsPerDay; i++)
        {
            var sent = await phones.SendAsync(account.Id, $"+155555502{i:D2}", CancellationToken.None);
            clock.UtcNow = clock.UtcNow.AddSeconds(sent.ResendAfterSeconds);
        }

        clock.UtcNow = clock.UtcNow.AddHours(2);
        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(account.Id, "+15555550299", CancellationToken.None));
        Assert.Equal("otp_cooldown", blocked.Code);

        clock.UtcNow = clock.UtcNow.AddHours(24);
        var again = await phones.SendAsync(account.Id, "+15555550299", CancellationToken.None);
        Assert.False(string.IsNullOrWhiteSpace(again.DevelopmentCode));
    }

    [Fact]
    public async Task GlobalDailyCapStopsAnotherAccount()
    {
        var clock = new MutableTimeProvider { UtcNow = new DateTimeOffset(2026, 9, 21, 12, 0, 0, TimeSpan.Zero) };
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, clock);
        var phones = NewPhones(store, new UnconfiguredSms(), NullLogger<PhoneVerificationService>.Instance, Environments.Development, clock);

        for (var i = 0; i < PhoneVerificationService.MaxGlobalSendsPerDay; i++)
        {
            var account = await engine.SignInAsync("development", $"otp-global-{i}", "Sam", CancellationToken.None);
            await phones.SendAsync(account.Id, $"+1555556{i:D4}", CancellationToken.None);
        }

        var next = await engine.SignInAsync("development", "otp-global-next", "Jordan", CancellationToken.None);
        var blocked = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(next.Id, "+15555569999", CancellationToken.None));
        Assert.Equal("otp_cooldown", blocked.Code);
    }

    [Fact]
    public async Task ExpensiveNumberIsNotTexted()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "otp-junk", "Sam", CancellationToken.None);
        var sms = new RecordingSms();
        var phones = NewPhones(store, sms, NullLogger<PhoneVerificationService>.Instance, Environments.Development);
        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            phones.SendAsync(account.Id, "9005550100", CancellationToken.None));
        Assert.Equal("invalid_phone", exception.Code);
        Assert.Equal(0, sms.Sends);
    }

    private static PhoneVerificationService NewPhones(
        ITrustStore store,
        ISmsOtpSender sms,
        ILogger<PhoneVerificationService> logger,
        string environment,
        TimeProvider? time = null)
    {
        var clock = time ?? TimeProvider.System;
        return new PhoneVerificationService(
            store,
            new TrustEngine(store, clock),
            sms,
            new AuthOptions { SigningKey = "development-signing-key-32bytes-min!!" },
            clock,
            new TestHostEnvironment { EnvironmentName = environment },
            logger);
    }

    private sealed class UnconfiguredSms : ISmsOtpSender
    {
        public bool IsConfigured => false;

        public Task SendAsync(string e164, string code, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("SMS should not be called.");

        public Task SendTextAsync(string e164, string body, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("SMS should not be called.");
    }

    private sealed class RecordingSms : ISmsOtpSender
    {
        public bool IsConfigured => true;
        public int Sends { get; private set; }
        public string? LastTo { get; private set; }
        public string? LastCode { get; private set; }
        public string? LastBody { get; private set; }

        public Task SendAsync(string e164, string code, CancellationToken cancellationToken)
        {
            Sends++;
            LastTo = e164;
            LastCode = code;
            return Task.CompletedTask;
        }

        public Task SendTextAsync(string e164, string body, CancellationToken cancellationToken)
        {
            Sends++;
            LastTo = e164;
            LastBody = body;
            return Task.CompletedTask;
        }
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "TrustApi.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class ListLogger : ILogger<PhoneVerificationService>
    {
        public List<string> Messages { get; } = [];

        public IDisposable BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Messages.Add(formatter(state, exception));
        }

        private sealed class NullScope : IDisposable
        {
            public static readonly NullScope Instance = new();
            public void Dispose()
            {
            }
        }
    }
}

public sealed class PhoneVerificationApiTests : IClassFixture<TrustApiFactory>
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _client;

    public PhoneVerificationApiTests(TrustApiFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task HttpSendAndVerifyDoesNotCompleteOnboarding()
    {
        var deviceId = Guid.NewGuid().ToString("N");
        var session = await _client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "Sam", provider = "development", deviceId });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionOnboardingWire>(Json);
        Assert.False(payload!.You.OnboardingComplete);
        Assert.False(payload.You.PhoneVerified);

        var phone = UniquePhone();
        using var send = new HttpRequestMessage(HttpMethod.Post, "/api/v1/me/phone/send");
        send.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        send.Content = JsonContent.Create(new { phone });
        var sendResponse = await _client.SendAsync(send);
        sendResponse.EnsureSuccessStatusCode();
        var otp = await sendResponse.Content.ReadFromJsonAsync<SendWire>(Json);
        Assert.False(string.IsNullOrWhiteSpace(otp!.DevelopmentCode));

        using var verify = new HttpRequestMessage(HttpMethod.Post, "/api/v1/me/phone/verify");
        verify.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        verify.Content = JsonContent.Create(new { phone, code = otp.DevelopmentCode });
        var verifyResponse = await _client.SendAsync(verify);
        verifyResponse.EnsureSuccessStatusCode();

        using var circleRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/circle");
        circleRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        var circleResponse = await _client.SendAsync(circleRequest);
        circleResponse.EnsureSuccessStatusCode();
        var circle = await circleResponse.Content.ReadFromJsonAsync<CircleOnboardingWire>(Json);
        Assert.False(circle!.You.OnboardingComplete);
        Assert.True(circle.You.PhoneVerified);
    }

    [Fact]
    public async Task HttpPhoneSendRequiresSignIn()
    {
        var send = await _client.PostAsJsonAsync("/api/v1/me/phone/send", new { phone = "+15555550100" });
        Assert.Equal(HttpStatusCode.Unauthorized, send.StatusCode);
        var add = await _client.PostAsJsonAsync("/api/v1/people/phone", new { phone = "+15555550100" });
        Assert.Equal(HttpStatusCode.Unauthorized, add.StatusCode);
    }

    [Fact]
    public async Task HttpLookupConnectsVerifiedPhoneWithoutSms()
    {
        var sam = await DevelopmentSessionAsync("Sam");
        var phone = UniquePhone();
        var code = await SendCodeAsync(sam.Token, phone);
        await VerifyCodeAsync(sam.Token, phone, code);

        var jordan = await DevelopmentSessionAsync("Jordan");
        var added = await AddPersonAsync(jordan.Token, phone);
        Assert.Equal("connected", added.Outcome);
        Assert.False(added.SmsSent);
        Assert.True(string.IsNullOrWhiteSpace(added.DevelopmentCode));

        var circle = await CircleAsync(jordan.Token);
        Assert.Contains(circle.Members, member => member.Person.Id == sam.You.Id);
    }

    [Fact]
    public async Task HttpUnknownPhoneReturnsInviteCodeWithoutPretendingSms()
    {
        var sam = await DevelopmentSessionAsync("Sam");
        var invited = await AddPersonAsync(sam.Token, UniquePhone());
        Assert.Equal("invited", invited.Outcome);
        Assert.False(invited.SmsSent);
        Assert.False(string.IsNullOrWhiteSpace(invited.DevelopmentCode));

        var second = await AddPersonAsync(sam.Token, UniquePhone());
        Assert.Equal("invited", second.Outcome);
        Assert.False(second.SmsSent);
        Assert.False(string.IsNullOrWhiteSpace(second.DevelopmentCode));
    }

    [Fact]
    public async Task LookDoesNotSendSms()
    {
        var sms = new CountingSms();
        using var factory = new TrustApiFactory().WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                var existing = services.Single(service => service.ServiceType == typeof(ISmsOtpSender));
                services.Remove(existing);
                services.AddSingleton<ISmsOtpSender>(sms);
            });
        });
        using var client = factory.CreateClient();
        var session = await client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "Sam", provider = "development", deviceId = Guid.NewGuid().ToString("N") });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionOnboardingWire>(Json);

        using var circleRequest = Authorized(HttpMethod.Get, "/api/v1/circle", payload!.Token);
        var circleResponse = await client.SendAsync(circleRequest);
        circleResponse.EnsureSuccessStatusCode();
        var circle = await circleResponse.Content.ReadFromJsonAsync<CirclePeopleWire>(Json);
        var alex = circle!.Members.Single(member => member.Person.DisplayName == "Alex");

        using var lookRequest = Authorized(HttpMethod.Post, "/api/v1/looks", payload.Token);
        lookRequest.Content = JsonContent.Create(new { subjectId = alex.Person.Id, confirmed = true });
        var lookResponse = await client.SendAsync(lookRequest);
        lookResponse.EnsureSuccessStatusCode();
        Assert.Equal(0, sms.Sends);
    }

    private async Task<SessionOnboardingWire> DevelopmentSessionAsync(string name)
    {
        var session = await _client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = name, provider = "development", deviceId = Guid.NewGuid().ToString("N") });
        session.EnsureSuccessStatusCode();
        return (await session.Content.ReadFromJsonAsync<SessionOnboardingWire>(Json))!;
    }

    private async Task<string> SendCodeAsync(string token, string phone)
    {
        using var send = Authorized(HttpMethod.Post, "/api/v1/me/phone/send", token);
        send.Content = JsonContent.Create(new { phone });
        var response = await _client.SendAsync(send);
        response.EnsureSuccessStatusCode();
        var otp = await response.Content.ReadFromJsonAsync<SendWire>(Json);
        return otp!.DevelopmentCode!;
    }

    private async Task VerifyCodeAsync(string token, string phone, string code)
    {
        using var verify = Authorized(HttpMethod.Post, "/api/v1/me/phone/verify", token);
        verify.Content = JsonContent.Create(new { phone, code });
        var response = await _client.SendAsync(verify);
        response.EnsureSuccessStatusCode();
    }

    private async Task<AddWire> AddPersonAsync(string token, string phone)
    {
        using var request = Authorized(HttpMethod.Post, "/api/v1/people/phone", token);
        request.Content = JsonContent.Create(new { phone });
        var response = await _client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AddWire>(Json))!;
    }

    private async Task<CirclePeopleWire> CircleAsync(string token)
    {
        using var request = Authorized(HttpMethod.Get, "/api/v1/circle", token);
        var response = await _client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<CirclePeopleWire>(Json))!;
    }

    private static HttpRequestMessage Authorized(HttpMethod method, string path, string token)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private static string UniquePhone() =>
        $"+1555555{RandomNumberGenerator.GetInt32(1000, 10000)}";

    private sealed record SessionOnboardingWire(string Token, OnboardingPersonWire You);
    private sealed record OnboardingPersonWire(Guid Id, string DisplayName, bool HasCircle, bool OnboardingComplete, bool PhoneVerified);
    private sealed record SendWire(string? DevelopmentCode);
    private sealed record CircleOnboardingWire(OnboardingPersonWire You);
    private sealed record CirclePeopleWire(List<MemberWire> Members);
    private sealed record MemberWire(OnboardingPersonWire Person);
    private sealed record AddWire(string Outcome, bool SmsSent, string? DevelopmentCode);
    private sealed record ApiErrorWire(string Code);

    private sealed class CountingSms : ISmsOtpSender
    {
        public int Sends { get; private set; }
        public bool IsConfigured => true;

        public Task SendAsync(string e164, string code, CancellationToken cancellationToken)
        {
            Sends++;
            return Task.CompletedTask;
        }

        public Task SendTextAsync(string e164, string body, CancellationToken cancellationToken)
        {
            Sends++;
            return Task.CompletedTask;
        }
    }
}
