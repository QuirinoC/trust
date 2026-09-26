using System.Security.Cryptography;
using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

/// Exercises lock ordering, unique-pair handling, and transactional acceptance against the local integration database.
public sealed class PostgresConnectionRequestTests
{
    private static readonly string Connection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task ConcurrentReciprocalRequestsAndAcceptsAreIdempotentAndDeclineCooldownIsDirectional()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.Parse("2026-09-01T18:00:00Z") };
        var engine = new TrustEngine(store, time);
        var accounts = new List<Account>();
        try
        {
            var (sam, samHandle) = await Ready("sam");
            var (jordan, jordanHandle) = await Ready("jordan");
            var concurrent = await Task.WhenAll(
                engine.CreateConnectionRequestAsync(sam.Id, jordan.Id, CancellationToken.None),
                engine.CreateConnectionRequestAsync(jordan.Id, sam.Id, CancellationToken.None));
            Assert.Equal(concurrent[0].Id, concurrent[1].Id);
            var request = concurrent[0];
            var senderHandle = request.SenderId == sam.Id ? samHandle : jordanHandle;
            Assert.Equal(ConnectionRelationship.Incoming,
                (await engine.LookupPersonAsync(request.RecipientId, senderHandle, CancellationToken.None))!.Relationship);
            await Task.WhenAll(
                engine.AcceptConnectionRequestAsync(request.RecipientId, request.Id, CancellationToken.None),
                engine.AcceptConnectionRequestAsync(request.RecipientId, request.Id, CancellationToken.None));
            var connected = await engine.GetCircleAsync(sam.Id, CancellationToken.None);
            var member = Assert.Single(connected.Members, value => value.Person.Id == jordan.Id);
            Assert.Equal(ShareResting.Off, member.OutboundShare.Effective(time.UtcNow));
            Assert.Equal(ShareResting.Off, member.InboundShare.Effective(time.UtcNow));

            await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
            await engine.RevokeAsync(sam.Id, jordan.Id, CancellationToken.None);
            await engine.AcceptConnectionRequestAsync(request.RecipientId, request.Id, CancellationToken.None);
            Assert.DoesNotContain((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members, value => value.Person.Id == jordan.Id);

            var (ada, _) = await Ready("ada");
            var (lee, _) = await Ready("lee");
            var declined = await engine.CreateConnectionRequestAsync(ada.Id, lee.Id, CancellationToken.None);
            await engine.DeclineConnectionRequestAsync(lee.Id, declined.Id, CancellationToken.None);
            var cooldown = await Assert.ThrowsAsync<TrustException>(() => engine.CreateConnectionRequestAsync(ada.Id, lee.Id, CancellationToken.None));
            Assert.Equal("request_declined_recently", cooldown.Code);
            var reverse = await engine.CreateConnectionRequestAsync(lee.Id, ada.Id, CancellationToken.None);
            Assert.NotEqual(declined.Id, reverse.Id);
        }
        finally
        {
            foreach (var account in accounts)
                await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }

        async Task<(Account Account, string Handle)> Ready(string name)
        {
            var suffix = Guid.NewGuid().ToString("N")[..9];
            var account = await engine.SignInAsync("development", $"requests-{name}-{suffix}", name, CancellationToken.None);
            accounts.Add(account);
            var handle = $"p{name[..Math.Min(4, name.Length)]}{suffix}";
            await engine.SetHandleAsync(account.Id, handle, CancellationToken.None);
            await store.SetVerifiedPhoneAsync(account.Id, $"+1555555{RandomNumberGenerator.GetInt32(1000, 10000)}", time.UtcNow, CancellationToken.None);
            return ((await store.FindAccountAsync(account.Id, CancellationToken.None))!, handle);
        }
    }

    [Fact]
    public async Task LegacyConnectionPathsResolvePendingHandleRequest()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.Parse("2026-09-01T18:00:00Z") };
        var engine = new TrustEngine(store, time);
        var accounts = new List<Account>();
        try
        {
            var (directSender, _) = await Ready("directsender");
            var (directRecipient, directHandle) = await Ready("directrecipient");
            var directRequest = await engine.CreateConnectionRequestAsync(directSender.Id, directRecipient.Id, CancellationToken.None);
            await engine.ConnectAccountsAsync(directSender.Id, directRecipient.Id, CancellationToken.None);
            Assert.Empty((await engine.ListConnectionRequestsAsync(directSender.Id, CancellationToken.None)).Sent);
            Assert.Empty((await engine.ListConnectionRequestsAsync(directRecipient.Id, CancellationToken.None)).Incoming);
            Assert.Equal(ConnectionRelationship.Connected,
                (await engine.LookupPersonAsync(directSender.Id, directHandle, CancellationToken.None))!.Relationship);

            var (inviteSender, _) = await Ready("invitesender");
            var (inviteRecipient, inviteRecipientHandle) = await Ready("inviterecipient");
            var inviteRequest = await engine.CreateConnectionRequestAsync(inviteSender.Id, inviteRecipient.Id, CancellationToken.None);
            var invite = await engine.CreateInviteAsync(inviteSender.Id, CancellationToken.None);
            await engine.AcceptInviteAsync(inviteRecipient.Id, invite.Code, CancellationToken.None);
            Assert.Empty((await engine.ListConnectionRequestsAsync(inviteSender.Id, CancellationToken.None)).Sent);
            Assert.Empty((await engine.ListConnectionRequestsAsync(inviteRecipient.Id, CancellationToken.None)).Incoming);
            Assert.Equal(ConnectionRelationship.Connected,
                (await engine.LookupPersonAsync(inviteSender.Id, inviteRecipientHandle, CancellationToken.None))!.Relationship);
            Assert.NotEqual(directRequest.Id, inviteRequest.Id);
        }
        finally
        {
            foreach (var account in accounts)
                await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }

        async Task<(Account Account, string Handle)> Ready(string name)
        {
            var suffix = Guid.NewGuid().ToString("N")[..9];
            var account = await engine.SignInAsync("development", $"requests-{name}-{suffix}", name, CancellationToken.None);
            accounts.Add(account);
            var handle = $"p{name[..Math.Min(4, name.Length)]}{suffix}";
            await engine.SetHandleAsync(account.Id, handle, CancellationToken.None);
            await store.SetVerifiedPhoneAsync(account.Id, $"+1555555{RandomNumberGenerator.GetInt32(1000, 10000)}", time.UtcNow, CancellationToken.None);
            return ((await store.FindAccountAsync(account.Id, CancellationToken.None))!, handle);
        }
    }

    [Fact]
    public async Task PostgresRecipientPendingQuotaAndExpiryAreEnforcedAndReleased()
    {
        await PostgresMigrator.ApplyAsync(Connection);
        var store = new PostgresTrustStore(Connection);
        var time = new MutableTimeProvider { UtcNow = DateTimeOffset.Parse("2026-09-01T18:00:00Z") };
        var engine = new TrustEngine(store, time);
        var accounts = new List<Account>();
        try
        {
            var (recipient, _) = await Ready("recipient");
            for (var i = 0; i < 20; i++)
            {
                var (sender, _) = await Ready($"sender{i}");
                await engine.CreateConnectionRequestAsync(sender.Id, recipient.Id, CancellationToken.None);
            }
            var (overflow, _) = await Ready("overflow");
            var limited = await Assert.ThrowsAsync<TrustException>(() => engine.CreateConnectionRequestAsync(overflow.Id, recipient.Id, CancellationToken.None));
            Assert.Equal("request_limit", limited.Code);

            time.UtcNow = time.UtcNow.AddDays(8);
            Assert.Empty((await engine.ListConnectionRequestsAsync(recipient.Id, CancellationToken.None)).Incoming);
            await engine.CreateConnectionRequestAsync(overflow.Id, recipient.Id, CancellationToken.None);
            Assert.Single((await engine.ListConnectionRequestsAsync(recipient.Id, CancellationToken.None)).Incoming);
        }
        finally
        {
            foreach (var account in accounts)
                await store.DeleteAccountAsync(account.Id, CancellationToken.None);
        }

        async Task<(Account Account, string Handle)> Ready(string name)
        {
            var suffix = Guid.NewGuid().ToString("N")[..9];
            var account = await engine.SignInAsync("development", $"requests-{name}-{suffix}", name, CancellationToken.None);
            accounts.Add(account);
            var handle = $"p{name}{suffix}";
            await engine.SetHandleAsync(account.Id, handle, CancellationToken.None);
            await store.SetVerifiedPhoneAsync(account.Id, $"+1555555{RandomNumberGenerator.GetInt32(1000, 10000)}", time.UtcNow, CancellationToken.None);
            return ((await store.FindAccountAsync(account.Id, CancellationToken.None))!, handle);
        }
    }
}
