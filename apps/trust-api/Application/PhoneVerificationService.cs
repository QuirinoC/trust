using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using TrustApi.Configuration;
using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Phone;

namespace TrustApi.Application;

public sealed record PhoneCodeSendResult(
    DateTimeOffset ExpiresAt,
    int ResendAfterSeconds,
    string? DevelopmentCode,
    PhoneRetryMetadata Retry,
    Guid? RequestId = null,
    Guid? ChallengeId = null,
    string DeliveryState = "sent");

public sealed record AddPersonByPhoneResult(string Outcome, bool SmsSent, string? DevelopmentCode);

public sealed class PhoneVerificationService(
    ITrustStore store,
    TrustEngine engine,
    ISmsOtpSender sms,
    AuthOptions auth,
    PhoneVerificationOptions phoneOptions,
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
    public const int MaxGlobalSendsPerDay = 1000;

    public async Task<PhoneCodeSendResult> SendAsync(
        Guid accountId,
        string? rawPhone,
        CancellationToken cancellationToken,
        string? consentAction = null,
        int? consentVersion = null,
        Guid? requestId = null,
        string? intent = null)
    {
        var currentAccount = await RequireAccount(accountId, cancellationToken);
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

        if (intent is not null and not ("onboarding" or "replacement"))
            throw new TrustException("invalid_phone_intent", "Choose a supported phone verification purpose.");

        if (!PhoneE164.TryNormalize(rawPhone, out var e164))
        {
            throw TrustException.InvalidPhone();
        }

        var purpose = intent ?? "onboarding";
        if (currentAccount.HasVerifiedPhone && currentAccount.PhoneE164 != e164 && purpose != "replacement")
            throw new TrustException("reauth_required", "Sign in with Apple again before changing the verified phone number.");
        if (purpose == "replacement" && !currentAccount.HasVerifiedPhone)
            throw new TrustException("invalid_phone_intent", "Phone replacement requires an existing verified phone.");
        if (requestId is { } stableRequestId)
        {
            var existing = await store.GetPhoneVerificationOperationAsync(accountId, stableRequestId, cancellationToken);
            if (existing is not null)
            {
                if (!string.Equals(existing.PhoneE164, e164, StringComparison.Ordinal)
                    || !string.Equals(existing.Purpose, purpose, StringComparison.Ordinal))
                    throw new TrustException("idempotency_conflict", "This request id was already used for another phone action.");
                var current = await GetVerificationStateAsync(accountId, stableRequestId, cancellationToken);
                var currentRetry = current.Retry;
                var currentNow = time.GetUtcNow();
                var metadata = new PhoneRetryMetadata(currentRetry.ServerTime, currentRetry.ResendRetryAt,
                    Math.Max(0, (int)Math.Ceiling((currentRetry.ResendRetryAt - currentNow).TotalSeconds)),
                    currentRetry.ResendRetryAt, currentRetry.CorrectionRetryAt,
                    currentRetry.ImmediateNumberAttemptsRemaining, existing.PhoneE164,
                    currentRetry.AccountRetryAt, currentRetry.AccountWindowStartedAt, currentRetry.AccountSendCount,
                    Math.Max(ResendCooldownSeconds, (int)Math.Ceiling((currentRetry.ResendRetryAt - currentNow).TotalSeconds)));
                return new(existing.ExpiresAt, ResendCooldownSeconds, null, metadata, stableRequestId,
                    existing.ChallengeId, existing.DeliveryState);
            }
        }

        // Reject a number already verified by someone else before reserving a send or
        // creating a challenge. The completion path still enforces uniqueness if two
        // accounts race to verify the same previously unused number.
        var verifiedOwner = await store.FindByVerifiedPhoneAsync(e164, cancellationToken);
        if (verifiedOwner is not null && verifiedOwner.Id != accountId)
        {
            throw TrustException.PhoneUnavailable();
        }

        var stagingTestNumber = environment.IsStaging()
            && phoneOptions.StagingTestNumbers.Contains(e164, StringComparer.Ordinal);
        var bypass = (environment.IsDevelopment() && !sms.IsConfigured) || stagingTestNumber;
        if (!sms.IsConfigured && !bypass) throw TrustException.OtpNotConfigured();
        var now = time.GetUtcNow();
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        var challenge = new PhoneChallenge(accountId, e164, Hash(accountId, e164, code),
            now.AddSeconds(CodeTtlSeconds), 0, now, 1, now, Guid.NewGuid(), requestId,
            intent ?? "onboarding", bypass ? "sent" : "queued", currentAccount.PhoneE164);
        var keys = new List<string> { SmsSendBudget.AccountKey(accountId), SmsSendBudget.PhoneKey(e164), SmsSendBudget.AccountDayKey(accountId) };
        if (!bypass) keys.Add(SmsSendBudget.GlobalDayKey());
        var reservation = await store.ReservePhoneSmsAsync(keys, challenge,
            new PhoneSmsConsentEvent(accountId, e164,
                consentVersion is null ? null : PhoneConsentDisclosureKey, consentVersion, now,
                consentVersion is null ? LegacyPhoneConsentSource : PhoneConsentSource, consentAction),
            now, cancellationToken, phoneOptions.MaxGlobalSendsPerDay);
        if (!reservation.Accepted)
            throw new TrustException("otp_cooldown", "Please wait before requesting another code.") { PhoneRetry = reservation.Retry };
        if (!reservation.ShouldDispatch && requestId is { } alreadyUsed)
        {
            var existing = await store.GetPhoneVerificationOperationAsync(accountId, alreadyUsed, cancellationToken)
                ?? throw new InvalidOperationException("Reserved idempotent phone operation was not persisted.");
            return new(existing.ExpiresAt, ResendCooldownSeconds, null, reservation.Retry, alreadyUsed,
                existing.ChallengeId, existing.DeliveryState);
        }
        var retry = reservation.Retry;
        if (!bypass)
        {
            // The claim is committed before contacting Twilio. A process crash or
            // timeout after this point is recorded as uncertain and is never retried
            // automatically for the same request id.
            await store.SetPhoneDeliveryStateAsync(accountId, challenge.ChallengeId, requestId,
                "uncertain", time.GetUtcNow(), cancellationToken);
            try
            {
                await DeliverCodeAsync(e164, code, cancellationToken);
                await store.SetPhoneDeliveryStateAsync(accountId, challenge.ChallengeId, requestId,
                    "sent", time.GetUtcNow(), cancellationToken);
            }
            catch (TrustException exception)
            {
                await store.SetPhoneDeliveryStateAsync(accountId, challenge.ChallengeId, requestId,
                    "uncertain", time.GetUtcNow(), CancellationToken.None);
                var responseNow = time.GetUtcNow();
                throw new TrustException(exception.Code, exception.Message) { PhoneRetry = retry with
                { ServerTime = responseNow, RetryAt = retry.ResendRetryAt, RetryAfterSeconds = Math.Max(0, (int)Math.Ceiling((retry.ResendRetryAt - responseNow).TotalSeconds)) } };
            }
        }
        logger.LogInformation("Reserved phone verification for {Phone} account {AccountId}; SMS bypass: {Bypass}.", PhoneE164.Mask(e164), accountId, bypass);
        var completedAt = time.GetUtcNow();
        return new PhoneCodeSendResult(reservation.Retry.ServerTime.AddSeconds(CodeTtlSeconds),
            retry.ResendPacingSeconds, bypass ? code : null, retry with { ServerTime = completedAt },
            requestId, challenge.ChallengeId, bypass ? "sent" : challenge.DeliveryState);
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
        CancellationToken cancellationToken,
        Guid? requestId = null,
        Guid? challengeId = null)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        if (!PhoneE164.TryNormalize(rawPhone, out var e164))
        {
            throw TrustException.InvalidPhone();
        }

        if (requestId is { } stableRequestId)
        {
            var operation = await store.GetPhoneVerificationOperationAsync(accountId, stableRequestId, cancellationToken);
            if (operation is not null)
            {
                if (operation.PhoneE164 != e164 || (challengeId is not null && operation.ChallengeId != challengeId))
                    throw new TrustException("idempotency_conflict", "This request does not match the original phone verification.");
                if (operation.VerificationState == "verified") return;
                if (operation.VerificationState == "superseded")
                    throw new TrustException("phone_binding_changed", "This verification was superseded by a newer phone binding. Request a new code.");
            }
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
            if (requestId is { } completedId)
            {
                var completedOperation = await store.GetPhoneVerificationOperationAsync(accountId, completedId, cancellationToken);
                if (completedOperation?.VerificationState == "verified" && completedOperation.PhoneE164 == e164
                    && (challengeId is null || completedOperation.ChallengeId == challengeId)) return;
            }
            throw TrustException.OtpExpired();
        }

        if (challengeId is not null && challenge.ChallengeId != challengeId)
            throw new TrustException("idempotency_conflict", "This challenge id does not match the active phone verification.");
        if (requestId is not null && challenge.RequestId is not null && challenge.RequestId != requestId)
            throw new TrustException("idempotency_conflict", "This request id does not match the active phone verification.");

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

        var completed = false;
        for (var attempt = 0; attempt < 8 && !completed; attempt++)
        {
            try
            {
                completed = await store.TryCompletePhoneChallengeAsync(
                    accountId,
                    e164,
                    challenge.CodeHash,
                    now,
                    MaxAttempts,
                    cancellationToken,
                    NewGeneratedHandle());
            }
            catch (TrustException exception) when (exception.Code == "handle_in_use")
            {
                // A concurrently claimed generated handle is rare; keep the OTP valid
                // and choose another random candidate inside the same verified action.
            }
        }
        if (!completed)
        {
            if (requestId is { } verifiedRequestId)
            {
                var completedOperation = await store.GetPhoneVerificationOperationAsync(accountId, verifiedRequestId, cancellationToken);
                if (completedOperation?.VerificationState == "verified"
                    && completedOperation.PhoneE164 == e164
                    && (challengeId is null || completedOperation.ChallengeId == challengeId)) return;
                if (completedOperation?.VerificationState == "superseded")
                    throw new TrustException("phone_binding_changed", "This verification was superseded by a newer phone binding. Request a new code.");
            }
            throw TrustException.OtpExhausted();
        }
        logger.LogInformation(
            "Verified phone {Phone} for account {AccountId}.",
            PhoneE164.Mask(e164),
            accountId);
    }

    private static string NewGeneratedHandle()
    {
        const string alphabet = "abcdefghijklmnopqrstuvwxyz234567";
        Span<byte> bytes = stackalloc byte[12];
        RandomNumberGenerator.Fill(bytes);
        Span<char> handle = stackalloc char[19];
        "person_".AsSpan().CopyTo(handle);
        for (var index = 0; index < bytes.Length; index++) handle[7 + index] = alphabet[bytes[index] & 31];
        return new string(handle);
    }

    public async Task<Account> CompleteOnboardingAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var account = await RequireAccount(accountId, cancellationToken);
        if (!account.HasVerifiedPhone) throw TrustException.PhoneVerificationRequired();
        if (account.HasHandle) return account;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            try
            {
                return await store.SetGeneratedHandleIfMissingAsync(accountId, NewGeneratedHandle(), cancellationToken);
            }
            catch (TrustException exception) when (exception.Code == "handle_in_use") { }
        }
        throw TrustException.HandleInUse();
    }

    public Task<Account> GetAccountAsync(Guid accountId, CancellationToken cancellationToken) =>
        RequireAccount(accountId, cancellationToken);

    public async Task<PhoneVerificationStateResponse> GetVerificationStateAsync(
        Guid accountId, Guid? requestId, CancellationToken cancellationToken)
    {
        var account = await RequireAccount(accountId, cancellationToken);
        var challenge = await store.GetPhoneChallengeAsync(accountId, cancellationToken);
        if (challenge is not null && requestId is not null && challenge.RequestId != requestId) challenge = null;
        var now = time.GetUtcNow();
        var operation = requestId is { } id
            ? await store.GetPhoneVerificationOperationAsync(accountId, id, cancellationToken)
            : null;
        var phone = account.PhoneE164;
        var normalized = operation?.PhoneE164 ?? challenge?.PhoneE164 ?? phone;
        var budgets = await Task.WhenAll(new[]
        {
            SmsSendBudget.AccountKey(accountId), SmsSendBudget.AccountDayKey(accountId),
            normalized is null ? null : SmsSendBudget.PhoneKey(normalized), SmsSendBudget.GlobalDayKey()
        }.Where(key => key is not null).Select(key => store.GetSmsSendBudgetAsync(key!, cancellationToken)));
        var rows = budgets.OfType<SmsSendBudget>().ToArray();
        var retry = PhoneSmsPolicy.Metadata(rows, normalized, now, now, phoneOptions.MaxGlobalSendsPerDay);
        if (operation is not null) challenge = null;
        var region = phone is null ? null : PhoneNumbers.PhoneNumberUtil.GetInstance().GetRegionCodeForNumber(
            PhoneNumbers.PhoneNumberUtil.GetInstance().Parse(phone, null));
        return new PhoneVerificationStateResponse(
            phone is null ? null : PhoneE164.Mask(phone), region, account.HasVerifiedPhone,
            operation is not null
                ? new PhoneOperationDto(operation.RequestId, operation.ChallengeId, operation.Purpose,
                    operation.VerificationState == "pending" && operation.ExpiresAt <= now ? "expired" : operation.VerificationState,
                    operation.DeliveryState, operation.ExpiresAt, PhoneE164.Mask(operation.PhoneE164))
                : challenge is null ? null : new PhoneOperationDto(challenge.RequestId, challenge.ChallengeId,
                    challenge.Purpose, challenge.ExpiresAt <= now ? "expired" : "pending", challenge.DeliveryState,
                    challenge.ExpiresAt, PhoneE164.Mask(challenge.PhoneE164)),
            new PhoneRetryStateDto(now, retry.ResendRetryAt, retry.CorrectionRetryAt,
                retry.ImmediateNumberAttemptsRemaining, retry.AccountRetryAt, retry.AccountWindowStartedAt, retry.AccountSendCount));
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
