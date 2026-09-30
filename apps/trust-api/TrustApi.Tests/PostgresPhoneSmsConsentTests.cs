using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

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
}
