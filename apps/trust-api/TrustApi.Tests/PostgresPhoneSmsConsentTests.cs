using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

[Collection("Postgres integration")]
public sealed class PostgresPhoneSmsConsentTests
{
    private static readonly string Connection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task PhoneSmsConsentPersistsAcrossStoreInstancesAndCascadesOnAccountDeletion()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var account = await new TrustEngine(store, TimeProvider.System).SignInAsync(
            "development", $"phone-consent-{Guid.NewGuid():N}", "Synthetic", CancellationToken.None);
        try
        {
            var now = DateTimeOffset.UtcNow;
            var consent = new PhoneSmsConsentEvent(
                account.Id,
                "+15555550188",
                PhoneVerificationService.PhoneConsentDisclosureKey,
                PhoneVerificationService.PhoneConsentDisclosureVersion,
                now.AddTicks(-(now.Ticks % TimeSpan.TicksPerSecond)),
                PhoneVerificationService.PhoneConsentSource,
                "resend_code");
            var legacyEvent = new PhoneSmsConsentEvent(
                account.Id,
                "+15555550188",
                null,
                null,
                consent.ConsentedAt.AddSeconds(1),
                PhoneVerificationService.LegacyPhoneConsentSource,
                null);
            await store.RecordPhoneSmsConsentAsync(consent, CancellationToken.None);
            await store.RecordPhoneSmsConsentAsync(legacyEvent, CancellationToken.None);

            var persisted = await new PostgresTrustStore(Connection)
                .ListPhoneSmsConsentEventsAsync(account.Id, CancellationToken.None);
            Assert.Equal(new[] { consent, legacyEvent }, persisted);

            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
            Assert.Empty(await new PostgresTrustStore(Connection)
                .ListPhoneSmsConsentEventsAsync(account.Id, CancellationToken.None));
        }
        finally
        {
            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }
    }

    [Fact]
    public async Task PhoneRequestIdReservationIsAtomicAndPayloadBound()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var account = await new TrustEngine(store, TimeProvider.System).SignInAsync(
            "development", $"phone-idempotency-{Guid.NewGuid():N}", "Synthetic", CancellationToken.None);
        var requestId = Guid.NewGuid();
        var challengeId = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        var phone = $"+1555555{Random.Shared.Next(1000, 10000)}";
        var challenge = new PhoneChallenge(account.Id, phone, "hashed-otp-fixture", now.AddMinutes(10), 0,
            now, 1, now, challengeId, requestId, "onboarding", "queued");
        var keys = new[] { SmsSendBudget.AccountKey(account.Id), SmsSendBudget.PhoneKey(phone), SmsSendBudget.AccountDayKey(account.Id) };
        var consent = new PhoneSmsConsentEvent(account.Id, phone, null, null, now,
            PhoneVerificationService.LegacyPhoneConsentSource, null);
        try
        {
            var first = await store.ReservePhoneSmsAsync(keys, challenge, consent, now, CancellationToken.None, 1000);
            var duplicate = await store.ReservePhoneSmsAsync(keys,
                challenge with { ChallengeId = Guid.NewGuid(), CodeHash = "different-hash" },
                consent with { ConsentedAt = now.AddSeconds(1) }, now.AddSeconds(1), CancellationToken.None, 1000);
            Assert.True(first.Accepted);
            Assert.True(first.ShouldDispatch);
            Assert.True(duplicate.Accepted);
            Assert.False(duplicate.ShouldDispatch);
            Assert.Equal(challengeId, (await store.GetPhoneChallengeAsync(account.Id, CancellationToken.None))!.ChallengeId);
            Assert.Single(await store.ListPhoneSmsConsentEventsAsync(account.Id, CancellationToken.None));
            Assert.Equal(1, (await store.GetSmsSendBudgetAsync(SmsSendBudget.AccountKey(account.Id), CancellationToken.None))!.SendCount);
            Assert.Equal("queued", (await store.GetPhoneVerificationOperationAsync(account.Id, requestId, CancellationToken.None))!.DeliveryState);

            var conflict = await Assert.ThrowsAsync<TrustException>(() => store.ReservePhoneSmsAsync(keys,
                challenge with { PhoneE164 = "+15555550190" }, consent, now.AddSeconds(2), CancellationToken.None, 1000));
            Assert.Equal("idempotency_conflict", conflict.Code);
        }
        finally
        {
            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }
    }

    [Fact]
    public async Task PhoneChallengeCompletionRejectsAStaleBindingAfterAccountLockRevalidation()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var account = await new TrustEngine(store, TimeProvider.System).SignInAsync(
            "development", $"phone-binding-race-{Guid.NewGuid():N}", "Synthetic", CancellationToken.None);
        try
        {
            var now = DateTimeOffset.UtcNow;
            var oldPhone = $"+1555555{Random.Shared.Next(1000, 10000)}";
            var newPhone = $"+1555555{Random.Shared.Next(1000, 10000)}";
            await store.SetVerifiedPhoneAsync(account.Id, oldPhone, now, CancellationToken.None);
            var requestId = Guid.NewGuid();
            var challenge = new PhoneChallenge(account.Id, oldPhone, "hashed-otp-fixture", now.AddMinutes(10), 0,
                now, 1, now, Guid.NewGuid(), requestId, "onboarding", "queued", oldPhone);
            var keys = new[] { SmsSendBudget.AccountKey(account.Id), SmsSendBudget.PhoneKey(oldPhone), SmsSendBudget.AccountDayKey(account.Id) };
            var consent = new PhoneSmsConsentEvent(account.Id, oldPhone, null, null, now,
                PhoneVerificationService.LegacyPhoneConsentSource, null);
            Assert.True((await store.ReservePhoneSmsAsync(keys, challenge, consent, now, CancellationToken.None, 1000)).Accepted);

            await store.SetVerifiedPhoneAsync(account.Id, newPhone, now.AddSeconds(1), CancellationToken.None);
            Assert.False(await store.TryCompletePhoneChallengeAsync(account.Id, oldPhone, challenge.CodeHash,
                now.AddSeconds(2), PhoneVerificationService.MaxAttempts, CancellationToken.None, "person_aaaaaaaaaaaa"));

            Assert.Equal(newPhone, (await store.FindAccountAsync(account.Id, CancellationToken.None))!.PhoneE164);
            Assert.Equal("superseded", (await store.GetPhoneVerificationOperationAsync(account.Id, requestId, CancellationToken.None))!.VerificationState);
        }
        finally
        {
            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }
    }

    [Fact]
    public async Task PhoneOwnershipSupportRequestIsIdempotentAndAccountScoped()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var account = await new TrustEngine(store, TimeProvider.System).SignInAsync(
            "development", $"phone-support-{Guid.NewGuid():N}", "Synthetic", CancellationToken.None);
        var recovery = new PostgresStoreKitEntitlementStore(Connection);
        try
        {
            var first = await recovery.CreatePhoneOwnershipRecoveryRequestAsync(account.Id, "number already linked", DateTimeOffset.UtcNow, CancellationToken.None);
            var duplicate = await recovery.CreatePhoneOwnershipRecoveryRequestAsync(account.Id, "retry", DateTimeOffset.UtcNow.AddSeconds(1), CancellationToken.None);
            Assert.Equal(first, duplicate);

            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
            await using var connection = new Npgsql.NpgsqlConnection(Connection);
            await connection.OpenAsync();
            await using var read = new Npgsql.NpgsqlCommand("SELECT count(*) FROM trust.phone_support_recovery_requests WHERE recovery_request_id=$1;", connection);
            read.Parameters.AddWithValue(first);
            Assert.Equal(0L, (long)(await read.ExecuteScalarAsync())!);
        }
        finally
        {
            await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }
    }
}
