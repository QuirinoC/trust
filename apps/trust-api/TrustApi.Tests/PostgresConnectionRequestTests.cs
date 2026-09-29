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
            await engine.GrantCircleAsync(sam.Id, "test-matrix", CancellationToken.None);
            await engine.GrantCircleAsync(jordan.Id, "test-matrix", CancellationToken.None);

            // Exercise the reciprocal 3×3 mode matrix as stored by each side.
            foreach (var samMode in new[] { ShareResting.Off, ShareResting.UntilTheyLook, ShareResting.Always })
            foreach (var jordanMode in new[] { ShareResting.Off, ShareResting.UntilTheyLook, ShareResting.Always })
            {
                await engine.SetShareAsync(sam.Id, jordan.Id, samMode, null, CancellationToken.None);
                await engine.SetShareAsync(jordan.Id, sam.Id, jordanMode, null, CancellationToken.None);
                var samView = Assert.Single((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members,
                    value => value.Person.Id == jordan.Id);
                var jordanView = Assert.Single((await engine.GetCircleAsync(jordan.Id, CancellationToken.None)).Members,
                    value => value.Person.Id == sam.Id);
                Assert.Equal(samMode, samView.OutboundShare.Effective(time.UtcNow));
                Assert.Equal(jordanMode, samView.InboundShare.Effective(time.UtcNow));
                Assert.Equal(jordanMode, jordanView.OutboundShare.Effective(time.UtcNow));
                Assert.Equal(samMode, jordanView.InboundShare.Effective(time.UtcNow));
            }

            await engine.SetShareAsync(sam.Id, jordan.Id, ShareResting.UntilTheyLook, null, CancellationToken.None);
            await SetGrantAsync(engine, store, sam.Id, jordan.Id, true);
            await SetGrantAsync(engine, store, jordan.Id, sam.Id, true);
            var connectionA = Assert.IsType<Guid>(await store.GetActiveMembershipIdAsync(sam.Id, jordan.Id, CancellationToken.None));
            Assert.Equal(connectionA, Assert.Single((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members,
                value => value.Person.Id == jordan.Id).ConnectionId);
            await engine.RevokeAsync(sam.Id, jordan.Id, CancellationToken.None);
            Assert.Null(await store.GetPresenceGrantAsync(sam.Id, jordan.Id, CancellationToken.None));
            Assert.Null(await store.GetPresenceGrantAsync(jordan.Id, sam.Id, CancellationToken.None));
            var staleGrant = await Assert.ThrowsAsync<TrustException>(
                () => engine.SetPresenceGrantAsync(sam.Id, jordan.Id, connectionA, true, null, CancellationToken.None));
            Assert.Equal("not_connected", staleGrant.Code);
            Assert.Null(await store.GetPresenceGrantAsync(sam.Id, jordan.Id, CancellationToken.None));
            await engine.AcceptConnectionRequestAsync(request.RecipientId, request.Id, CancellationToken.None);
            Assert.DoesNotContain((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members, value => value.Person.Id == jordan.Id);
            await engine.ConnectAccountsAsync(sam.Id, jordan.Id, CancellationToken.None);
            var connectionB = Assert.IsType<Guid>(await store.GetActiveMembershipIdAsync(sam.Id, jordan.Id, CancellationToken.None));
            Assert.NotEqual(connectionA, connectionB);
            var staleRemoval = await Assert.ThrowsAsync<TrustException>(
                () => engine.RevokeAsync(sam.Id, jordan.Id, connectionA, CancellationToken.None));
            Assert.Equal("connection_changed", staleRemoval.Code);
            Assert.Equal(connectionB, await store.GetActiveMembershipIdAsync(sam.Id, jordan.Id, CancellationToken.None));
            var freshSamView = Assert.Single((await engine.GetCircleAsync(sam.Id, CancellationToken.None)).Members,
                value => value.Person.Id == jordan.Id);
            Assert.Equal(connectionB, freshSamView.ConnectionId);
            var freshJordanView = Assert.Single((await engine.GetCircleAsync(jordan.Id, CancellationToken.None)).Members,
                value => value.Person.Id == sam.Id);
            Assert.Equal(ShareResting.Off, freshSamView.OutboundShare.Effective(time.UtcNow));
            Assert.Equal(ShareResting.Off, freshJordanView.OutboundShare.Effective(time.UtcNow));
            Assert.False(freshSamView.OutboundPresenceGranted);
            Assert.False(freshSamView.InboundPresenceGranted);
            Assert.False(freshJordanView.OutboundPresenceGranted);
            Assert.False(freshJordanView.InboundPresenceGranted);
            var initialShareRevision = (await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None)).Revision;
            var delayedGrant = await Assert.ThrowsAsync<TrustException>(
                () => engine.SetPresenceGrantAsync(sam.Id, jordan.Id, connectionA, true, null, CancellationToken.None));
            Assert.Equal("connection_changed", delayedGrant.Code);
            Assert.Null(await store.GetPresenceGrantAsync(sam.Id, jordan.Id, CancellationToken.None));
            var delayedShare = await Assert.ThrowsAsync<TrustException>(
                () => engine.SetShareAsync(sam.Id, jordan.Id, connectionA, initialShareRevision, ShareResting.UntilTheyLook, null, CancellationToken.None));
            Assert.Equal("connection_changed", delayedShare.Code);
            Assert.Equal(ShareResting.Off,
                (await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None)).Effective(time.UtcNow));
            await engine.SetShareAsync(sam.Id, jordan.Id, connectionB, initialShareRevision, ShareResting.UntilTheyLook, null, CancellationToken.None);
            await engine.SetShareAsync(sam.Id, jordan.Id, connectionB, initialShareRevision, ShareResting.Off, null, CancellationToken.None);
            var staleEnable = await Assert.ThrowsAsync<TrustException>(
                () => engine.SetShareAsync(sam.Id, jordan.Id, connectionB, initialShareRevision, ShareResting.UntilTheyLook, null, CancellationToken.None));
            Assert.Equal("share_state_changed", staleEnable.Code);
            Assert.Equal(initialShareRevision + 2, (await store.GetShareAsync(sam.Id, jordan.Id, CancellationToken.None)).Revision);
            var enabledRevision = await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, connectionB, true, 0, CancellationToken.None);
            Assert.Equal(1, enabledRevision);
            var disabledRevision = await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, connectionB, false, 0, CancellationToken.None);
            Assert.Equal(2, disabledRevision);
            var stalePresenceEnable = await Assert.ThrowsAsync<TrustException>(() =>
                engine.SetPresenceGrantAsync(sam.Id, jordan.Id, connectionB, true, enabledRevision, CancellationToken.None));
            Assert.Equal("presence_state_changed", stalePresenceEnable.Code);
            await engine.SetPresenceGrantAsync(sam.Id, jordan.Id, connectionB, true, disabledRevision, CancellationToken.None);
            Assert.True((await store.GetPresenceGrantAsync(sam.Id, jordan.Id, CancellationToken.None))?.Enabled);

            var (ada, _) = await Ready("ada");
            var (lee, _) = await Ready("lee");
            var declined = await engine.CreateConnectionRequestAsync(ada.Id, lee.Id, CancellationToken.None);
            await engine.DeclineConnectionRequestAsync(lee.Id, declined.Id, CancellationToken.None);
            var cooldown = await Assert.ThrowsAsync<TrustException>(() => engine.CreateConnectionRequestAsync(ada.Id, lee.Id, CancellationToken.None));
            Assert.Equal("request_declined_recently", cooldown.Code);
            var reverse = await engine.CreateConnectionRequestAsync(lee.Id, ada.Id, CancellationToken.None);
            Assert.NotEqual(declined.Id, reverse.Id);

            var (cancelSender, _) = await Ready("cancelsender");
            var (cancelRecipient, _) = await Ready("cancelrecipient");
            var canceled = await engine.CreateConnectionRequestAsync(cancelSender.Id, cancelRecipient.Id, CancellationToken.None);
            await engine.CancelConnectionRequestAsync(cancelSender.Id, canceled.Id, CancellationToken.None);
            Assert.Empty((await engine.ListConnectionRequestsAsync(cancelRecipient.Id, CancellationToken.None)).Incoming);
            var readded = await engine.CreateConnectionRequestAsync(cancelSender.Id, cancelRecipient.Id, CancellationToken.None);
            Assert.NotEqual(canceled.Id, readded.Id);
            await engine.AcceptConnectionRequestAsync(cancelRecipient.Id, readded.Id, CancellationToken.None);
            Assert.Contains((await engine.GetCircleAsync(cancelSender.Id, CancellationToken.None)).Members,
                value => value.Person.Id == cancelRecipient.Id);
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
            await store.SetVerifiedPhoneAsync(account.Id, $"+1555555{RandomNumberGenerator.GetInt32(1_000_000, 10_000_000)}", time.UtcNow, CancellationToken.None);
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
            await store.SetVerifiedPhoneAsync(account.Id, $"+1555555{RandomNumberGenerator.GetInt32(1_000_000, 10_000_000)}", time.UtcNow, CancellationToken.None);
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
            await store.SetVerifiedPhoneAsync(account.Id, $"+1555555{RandomNumberGenerator.GetInt32(1_000_000, 10_000_000)}", time.UtcNow, CancellationToken.None);
            return ((await store.FindAccountAsync(account.Id, CancellationToken.None))!, handle);
        }
    }

    private static async Task SetGrantAsync(TrustEngine engine, ITrustStore store, Guid subjectId, Guid trusteeId, bool enabled)
    {
        var connectionId = await store.GetActiveMembershipIdAsync(subjectId, trusteeId, CancellationToken.None)
            ?? throw new InvalidOperationException("Test relationship is not active.");
        var revision = (await store.GetPresenceGrantAsync(subjectId, trusteeId, CancellationToken.None))?.Revision ?? 0;
        await engine.SetPresenceGrantAsync(subjectId, trusteeId, connectionId, enabled, enabled ? revision : null, CancellationToken.None);
    }
}
