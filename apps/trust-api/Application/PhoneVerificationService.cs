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
    string? DevelopmentCode,
    PhoneRetryMetadata Retry);

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
    public const int PhoneConsentDisclosureVersion = 1;
    public const string PhoneConsentDisclosureKey = "phone_consent_details";
    public const string PhoneConsentSource = "ios_phone_verification";
    public const string LegacyPhoneConsentSource = "phone_verification_endpoint_legacy";
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
        CancellationToken cancellationToken,
        string? consentAction = null,
        int? consentVersion = null)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        if (consentVersion is not null and not PhoneConsentDisclosureVersion)
        {
            throw TrustException.InvalidPhoneConsentVersion();
        }

        if (consentAction is not null and not ("send_code" or "resend_code"))
        {
            throw TrustException.InvalidPhoneConsentAction();
        }

        if ((consentVersion is null) != (consentAction is null))
        {
            throw TrustException.InvalidPhoneConsentMetadata();
        }

        if (!PhoneE164.TryNormalize(rawPhone, out var e164))
        {
            throw TrustException.InvalidPhone();
        }

        // Reject a number already verified by someone else before reserving a send or
        // creating a challenge. The completion path still enforces uniqueness if two
        // accounts race to verify the same previously unused number.
        var verifiedOwner = await store.FindByVerifiedPhoneAsync(e164, cancellationToken);
        if (verifiedOwner is not null && verifiedOwner.Id != accountId)
        {
            throw TrustException.PhoneUnavailable();
        }

        var bypass = environment.IsDevelopment() && !sms.IsConfigured;
        if (!sms.IsConfigured && !bypass) throw TrustException.OtpNotConfigured();
        var now = time.GetUtcNow();
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var challenge = new PhoneChallenge(accountId, e164, Hash(accountId, e164, code),
            now.AddSeconds(CodeTtlSeconds), 0, now, 1, now);
        var keys = new List<string> { SmsSendBudget.AccountKey(accountId), SmsSendBudget.PhoneKey(e164), SmsSendBudget.AccountDayKey(accountId) };
        if (!bypass) keys.Add(SmsSendBudget.GlobalDayKey());
        var reservation = await store.ReservePhoneSmsAsync(keys, challenge,
            new PhoneSmsConsentEvent(accountId, e164,
                consentVersion is null ? null : PhoneConsentDisclosureKey, consentVersion, now,
                consentVersion is null ? LegacyPhoneConsentSource : PhoneConsentSource, consentAction),
            now, cancellationToken);
        if (!reservation.Accepted)
            throw new TrustException("otp_cooldown", "Please wait before requesting another code.") { PhoneRetry = reservation.Retry };
        var retry = reservation.Retry;
        if (!bypass)
        {
            try { await DeliverCodeAsync(e164, code, cancellationToken); }
            catch (TrustException exception)
            {
                var responseNow = time.GetUtcNow();
                throw new TrustException(exception.Code, exception.Message) { PhoneRetry = retry with
                { ServerTime = responseNow, RetryAt = retry.ResendRetryAt, RetryAfterSeconds = Math.Max(0, (int)Math.Ceiling((retry.ResendRetryAt - responseNow).TotalSeconds)) } };
            }
        }
        logger.LogInformation("Reserved phone verification for {Phone} account {AccountId}; SMS bypass: {Bypass}.", PhoneE164.Mask(e164), accountId, bypass);
        var completedAt = time.GetUtcNow();
        return new PhoneCodeSendResult(reservation.Retry.ServerTime.AddSeconds(CodeTtlSeconds),
            retry.ResendPacingSeconds, bypass ? code : null, retry with { ServerTime = completedAt });
    }

    /// Phone entry always creates the ordinary invite. Looking up a number never reveals
    /// whether it belongs to a Trust account and never connects accounts automatically.
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
            throw TrustException.OtpExhausted();
        }

        var expected = Hash(accountId, e164, code);
        if (!FixedEquals(challenge.CodeHash, expected))
        {
            var attempts = await store.IncrementPhoneChallengeFailureAsync(
                accountId,
                e164,
                challenge.CodeHash,
                now,
                MaxAttempts,
                cancellationToken);
            if (attempts is null)
            {
                throw TrustException.OtpExpired();
            }

            if (attempts >= MaxAttempts)
            {
                throw TrustException.OtpExhausted();
            }

            throw TrustException.OtpInvalid();
        }

        var completed = await store.TryCompletePhoneChallengeAsync(
            accountId,
            e164,
            challenge.CodeHash,
            now,
            MaxAttempts,
            cancellationToken);
        if (!completed)
        {
            throw TrustException.OtpExhausted();
        }
        logger.LogInformation(
            "Verified phone {Phone} for account {AccountId}.",
            PhoneE164.Mask(e164),
            accountId);
    }

    private async Task<Account> RequireAccount(Guid accountId, CancellationToken cancellationToken) =>
        await store.FindAccountAsync(accountId, cancellationToken)
        ?? throw TrustException.Unauthorized();

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

}
