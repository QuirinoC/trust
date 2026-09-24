using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Phone;

namespace TrustApi.Application;

public sealed record PhoneCodeSendResult(
    DateTimeOffset ExpiresAt,
    int ResendAfterSeconds,
    string? DevelopmentCode);

public sealed record AddPersonByPhoneResult(string Outcome, bool SmsSent, string? DevelopmentCode);

public sealed class PhoneVerificationService(
    ITrustStore store,
    TrustEngine engine,
    ISmsOtpSender sms,
    AuthOptions auth,
    TimeProvider time,
    IHostEnvironment environment,
    ILogger<PhoneVerificationService> logger)
{
    public const int CodeTtlSeconds = 10 * 60;
    public const int ResendCooldownSeconds = 45;
    public const int MaxBackoffSeconds = 3 * 60;
    public const int MaxAttempts = 5;
    public const int MaxSendsPerHour = 8;
    public const int MaxSendsPerDay = 8;
    public const int MaxGlobalSendsPerDay = 40;

    public async Task<PhoneCodeSendResult> SendAsync(
        Guid accountId,
        string? rawPhone,
        CancellationToken cancellationToken)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        if (!PhoneE164.TryNormalize(rawPhone, out var e164))
        {
            throw TrustException.InvalidPhone();
        }

        var owner = await store.FindByVerifiedPhoneAsync(e164, cancellationToken);
        if (owner is not null && owner.Id != accountId)
        {
            throw TrustException.PhoneInUse();
        }

        var now = time.GetUtcNow();
        var existing = await store.GetPhoneChallengeAsync(accountId, cancellationToken);
        var samePhone = existing is not null
            && string.Equals(existing.PhoneE164, e164, StringComparison.Ordinal);
        var windowStarted = samePhone ? existing!.WindowStartedAt : now;
        var sendCount = samePhone ? existing!.SendCount : 0;
        if (now - windowStarted >= TimeSpan.FromHours(1))
        {
            windowStarted = now;
            sendCount = 0;
        }

        if (sendCount >= MaxSendsPerHour)
        {
            throw TrustException.OtpCooldown();
        }

        if (samePhone && now - existing!.SentAt < TimeSpan.FromSeconds(ResendCooldownSeconds))
        {
            throw TrustException.OtpCooldown();
        }

        var gate = await GateSmsAsync(accountId, e164, now, cancellationToken);
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var challenge = new PhoneChallenge(
            accountId,
            e164,
            Hash(accountId, e164, code),
            now.AddSeconds(CodeTtlSeconds),
            0,
            now,
            sendCount + 1,
            windowStarted);
        await store.UpsertPhoneChallengeAsync(challenge, cancellationToken);
        await CommitSmsAsync(gate, cancellationToken);

        if (!gate.Bypass)
        {
            await DeliverCodeAsync(e164, code, cancellationToken);
            logger.LogInformation(
                "Sent phone verification SMS to {Phone} for account {AccountId}.",
                PhoneE164.Mask(e164),
                accountId);
            return new PhoneCodeSendResult(challenge.ExpiresAt, NextResendSeconds(gate), null);
        }

        logger.LogInformation(
            "Development phone verification bypass for {Phone} account {AccountId}; SMS was not sent.",
            PhoneE164.Mask(e164),
            accountId);
        return new PhoneCodeSendResult(challenge.ExpiresAt, NextResendSeconds(gate), code);
    }

    /// Verified number: connect that account. Unknown number: create an invite and return the code. No invite text is sent.
    public async Task<AddPersonByPhoneResult> AddPersonAsync(
        Guid accountId,
        string? rawPhone,
        CancellationToken cancellationToken)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        if (!PhoneE164.TryNormalize(rawPhone, out var e164))
        {
            throw TrustException.InvalidPhone();
        }

        var owner = await store.FindByVerifiedPhoneAsync(e164, cancellationToken);
        if (owner is not null)
        {
            if (owner.Id == accountId)
            {
                throw TrustException.OwnPhone();
            }

            var added = await engine.ConnectAccountsAsync(accountId, owner.Id, cancellationToken);
            return new AddPersonByPhoneResult(added ? "connected" : "already", false, null);
        }

        var invite = await engine.CreateInviteAsync(accountId, cancellationToken);
        logger.LogInformation(
            "Created an invite for {Phone} account {AccountId}; no SMS was sent.",
            PhoneE164.Mask(e164),
            accountId);
        return new AddPersonByPhoneResult("invited", false, invite.Code);
    }

    public async Task VerifyAsync(
        Guid accountId,
        string? rawPhone,
        string? rawCode,
        CancellationToken cancellationToken)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        if (!PhoneE164.TryNormalize(rawPhone, out var e164))
        {
            throw TrustException.InvalidPhone();
        }

        var code = (rawCode ?? "").Trim();
        if (code.Length != 6 || !code.All(char.IsDigit))
        {
            throw TrustException.OtpInvalid();
        }

        var challenge = await store.GetPhoneChallengeAsync(accountId, cancellationToken);
        var now = time.GetUtcNow();
        if (challenge is null
            || !string.Equals(challenge.PhoneE164, e164, StringComparison.Ordinal)
            || challenge.ExpiresAt <= now)
        {
            throw TrustException.OtpExpired();
        }

        if (challenge.Attempts >= MaxAttempts)
        {
            await store.ClearPhoneChallengeAsync(accountId, cancellationToken);
            throw TrustException.OtpExhausted();
        }

        var expected = Hash(accountId, e164, code);
        if (!FixedEquals(challenge.CodeHash, expected))
        {
            var attempts = challenge.Attempts + 1;
            if (attempts >= MaxAttempts)
            {
                await store.ClearPhoneChallengeAsync(accountId, cancellationToken);
                throw TrustException.OtpExhausted();
            }

            await store.UpsertPhoneChallengeAsync(challenge with { Attempts = attempts }, cancellationToken);
            throw TrustException.OtpInvalid();
        }

        var owner = await store.FindByVerifiedPhoneAsync(e164, cancellationToken);
        if (owner is not null && owner.Id != accountId)
        {
            throw TrustException.PhoneInUse();
        }

        await store.SetVerifiedPhoneAsync(accountId, e164, now, cancellationToken);
        await store.ClearPhoneChallengeAsync(accountId, cancellationToken);
        logger.LogInformation(
            "Verified phone {Phone} for account {AccountId}.",
            PhoneE164.Mask(e164),
            accountId);
    }

    private async Task<Account> RequireAccount(Guid accountId, CancellationToken cancellationToken) =>
        await store.FindAccountAsync(accountId, cancellationToken)
        ?? throw TrustException.Unauthorized();

    private async Task<SmsGate> GateSmsAsync(
        Guid accountId,
        string e164,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var account = NormalizeBudget(
            await store.GetSmsSendBudgetAsync(SmsSendBudget.AccountKey(accountId), cancellationToken),
            SmsSendBudget.AccountKey(accountId),
            now,
            TimeSpan.FromHours(1));
        var phone = NormalizeBudget(
            await store.GetSmsSendBudgetAsync(SmsSendBudget.PhoneKey(e164), cancellationToken),
            SmsSendBudget.PhoneKey(e164),
            now,
            TimeSpan.FromHours(1));
        var accountDay = NormalizeBudget(
            await store.GetSmsSendBudgetAsync(SmsSendBudget.AccountDayKey(accountId), cancellationToken),
            SmsSendBudget.AccountDayKey(accountId),
            now,
            TimeSpan.FromHours(24));
        var globalDay = NormalizeBudget(
            await store.GetSmsSendBudgetAsync(SmsSendBudget.GlobalDayKey(), cancellationToken),
            SmsSendBudget.GlobalDayKey(),
            now,
            TimeSpan.FromHours(24));
        if (account.SendCount >= MaxSendsPerHour
            || phone.SendCount >= MaxSendsPerHour
            || accountDay.SendCount >= MaxSendsPerDay
            || globalDay.SendCount >= MaxGlobalSendsPerDay)
        {
            throw TrustException.OtpCooldown();
        }

        if (RemainingWait(account, now) > TimeSpan.Zero || RemainingWait(phone, now) > TimeSpan.Zero)
        {
            throw TrustException.OtpCooldown();
        }

        var bypass = environment.IsDevelopment() && !sms.IsConfigured;
        if (!sms.IsConfigured && !bypass)
        {
            throw TrustException.OtpNotConfigured();
        }

        return new SmsGate(now, account, phone, accountDay, globalDay, bypass);
    }

    private async Task CommitSmsAsync(SmsGate gate, CancellationToken cancellationToken)
    {
        await store.UpsertSmsSendBudgetAsync(Bump(gate.Account, gate.Now), cancellationToken);
        await store.UpsertSmsSendBudgetAsync(Bump(gate.Phone, gate.Now), cancellationToken);
        await store.UpsertSmsSendBudgetAsync(Bump(gate.AccountDay, gate.Now), cancellationToken);
        await store.UpsertSmsSendBudgetAsync(Bump(gate.GlobalDay, gate.Now), cancellationToken);
    }

    private static SmsSendBudget Bump(SmsSendBudget budget, DateTimeOffset now) =>
        budget with { SendCount = budget.SendCount + 1, LastSentAt = now };

    private async Task DeliverCodeAsync(string e164, string code, CancellationToken cancellationToken)
    {
        try
        {
            await sms.SendAsync(e164, code, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (TrustException)
        {
            throw;
        }
        catch (Exception)
        {
            throw TrustException.OtpSendFailed();
        }
    }

    private static SmsSendBudget NormalizeBudget(
        SmsSendBudget? budget,
        string key,
        DateTimeOffset now,
        TimeSpan window)
    {
        if (budget is null || now - budget.WindowStartedAt >= window)
        {
            return new SmsSendBudget(key, now, 0, budget?.LastSentAt);
        }

        return budget;
    }

    private static TimeSpan RemainingWait(SmsSendBudget budget, DateTimeOffset now)
    {
        if (budget.LastSentAt is not { } sent)
        {
            return TimeSpan.Zero;
        }

        var neededSeconds = budget.SendCount <= 0
            ? ResendCooldownSeconds
            : BackoffSeconds(budget.SendCount);
        var elapsed = now - sent;
        var needed = TimeSpan.FromSeconds(neededSeconds);
        return elapsed >= needed ? TimeSpan.Zero : needed - elapsed;
    }

    private static int NextResendSeconds(SmsGate gate) =>
        Math.Max(BackoffSeconds(gate.Account.SendCount + 1), BackoffSeconds(gate.Phone.SendCount + 1));

    /// First resend waits <see cref="ResendCooldownSeconds"/>. Later resends double, capped at 3 minutes.
    private static int BackoffSeconds(int sendsAlreadyInWindow)
    {
        if (sendsAlreadyInWindow <= 1)
        {
            return ResendCooldownSeconds;
        }

        var shift = Math.Min(sendsAlreadyInWindow - 1, 4);
        return Math.Min(ResendCooldownSeconds << shift, MaxBackoffSeconds);
    }

    private string Hash(Guid accountId, string e164, string code)
    {
        var key = Encoding.UTF8.GetBytes(SessionIssuer.RequireKey(auth.SigningKey));
        var payload = Encoding.UTF8.GetBytes($"{accountId:N}:{e164}:{code}");
        return Convert.ToHexString(HMACSHA256.HashData(key, payload));
    }

    private static bool FixedEquals(string left, string right)
    {
        var a = Encoding.UTF8.GetBytes(left);
        var b = Encoding.UTF8.GetBytes(right);
        return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
    }

    private sealed record SmsGate(
        DateTimeOffset Now,
        SmsSendBudget Account,
        SmsSendBudget Phone,
        SmsSendBudget AccountDay,
        SmsSendBudget GlobalDay,
        bool Bypass);
}
