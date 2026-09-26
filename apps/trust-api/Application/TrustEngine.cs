using TrustApi.Domain;

namespace TrustApi.Application;

public sealed class TrustEngine(ITrustStore store, TimeProvider time)
{
    public async Task<Account> SignInAsync(
        string provider,
        string subject,
        string displayName,
        CancellationToken cancellationToken)
    {
        var existing = await store.FindByProviderAsync(provider, subject, cancellationToken);
        if (existing is not null)
        {
            if (!string.Equals(existing.DisplayName, displayName, StringComparison.Ordinal)
                && !string.Equals(displayName, "You", StringComparison.Ordinal)
                && !string.IsNullOrWhiteSpace(displayName))
            {
                var renamed = existing with { DisplayName = displayName.Trim() };
                await store.UpdateAccountAsync(renamed, cancellationToken);
                return renamed;
            }

            return existing;
        }

        var now = time.GetUtcNow();
        var account = new Account(
            Guid.NewGuid(),
            provider,
            subject,
            string.IsNullOrWhiteSpace(displayName) ? "You" : displayName.Trim(),
            false,
            null,
            now);
        account = await store.UpsertAccountAsync(account, cancellationToken);
        await store.UpsertPresenceAsync(
            account.Id,
            new Presence(now, 80, false, null, null),
            cancellationToken);
        return account;
    }

    public async Task<CircleSnapshot> GetCircleAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var now = time.GetUtcNow();
        await store.RestoreExpiredPausesAsync(now, cancellationToken);
        var connected = await store.ListConnectedAsync(accountId, cancellationToken);
        var coverage = CoverageOf(you, connected);
        var members = new List<CircleMember>();
        var yourHome = await store.GetHomePlaceAsync(you.Id, cancellationToken);
        var yourPresence = await store.GetCurrentHomePresenceAsync(you.Id, cancellationToken);

        foreach (var person in connected)
        {
            var outbound = await store.GetShareAsync(you.Id, person.Id, cancellationToken);
            var inbound = await store.GetShareAsync(person.Id, you.Id, cancellationToken);
            var inboundLive = inbound.RevealsLive(now);
            // Always coordinates are a Plus pin for the viewer. A paying friend does not cover you.
            // Sealed stays coordinate-free here; Look still returns its own snapshot.
            LocationFix? live = null;
            if (inboundLive && you.HasCircle)
            {
                live = await store.LatestLocationAsync(person.Id, cancellationToken);
            }

            // Battery / last-active only while Always (live). Sealed is a Look, not a live row.
            Presence? presence = inboundLive
                ? await store.GetPresenceAsync(person.Id, now, cancellationToken)
                : null;

            var outboundGrant = await store.GetPresenceGrantAsync(you.Id, person.Id, cancellationToken);
            var inboundGrant = await store.GetPresenceGrantAsync(person.Id, you.Id, cancellationToken);
            var outboundPresenceGranted = outboundGrant?.Enabled == true;
            var inboundPresenceGranted = inboundGrant?.Enabled == true;

            VisibleHomePresence? homePresence = null;
            var current = await store.GetCurrentHomePresenceAsync(person.Id, cancellationToken);
            // Home/Away presence follows the same outbound share mode as location:
            // Sealed and Always reveal it; Off and an active Pause do not.
            // Hidden remains distinct from no signal, and the per-pair grant field is independent.
            if (inbound.AcceptsLocation(now)
                && current is not null
                && current.State is HomePresenceState.Home or HomePresenceState.Away)
            {
                var place = await store.GetHomePlaceAsync(person.Id, cancellationToken);
                homePresence = new VisibleHomePresence(
                    current.State,
                    current.LastChangedAt,
                    place?.Label);
            }

            var promiseView = await BuildPromiseViewAsync(you.Id, person.Id, cancellationToken);

            members.Add(new CircleMember(
                person,
                presence,
                outbound,
                inbound,
                inboundLive,
                live,
                outboundPresenceGranted,
                inboundPresenceGranted,
                homePresence,
                promiseView));
        }

        var since = now.AddDays(-coverage.LookLogDays);
        var log = await store.ListLooksAsync(you.Id, since, cancellationToken);
        var allLog = await store.ListLooksAsync(you.Id, DateTimeOffset.MinValue, cancellationToken);
        var invite = await store.FindPendingInviteAsync(you.Id, cancellationToken);

        return new CircleSnapshot(
            you,
            members,
            coverage,
            invite,
            null,
            null,
            log,
            Math.Max(0, allLog.Count - log.Count),
            yourHome,
            yourPresence);
    }

    public async Task<Invite> CreateInviteAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var now = time.GetUtcNow();
        var existing = await store.FindPendingInviteAsync(you.Id, cancellationToken);
        if (existing is not null && existing.ExpiresAt is { } notExpiredUntil && notExpiredUntil > now)
        {
            return existing;
        }

        var invite = new Invite(
            Guid.NewGuid(),
            MakeInviteCode(),
            you.Id,
            "pending",
            now,
            now.Add(TrustRules.InviteValidity));
        await store.InsertInviteAsync(invite, cancellationToken);
        return invite;
    }

    public async Task AcceptInviteAsync(Guid accountId, string code, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var normalized = code.Trim().ToUpperInvariant();
        var invite = await store.FindInviteByCodeAsync(normalized, cancellationToken)
            ?? throw TrustException.InvalidCode();
        if (!string.Equals(invite.Status, "pending", StringComparison.Ordinal))
        {
            throw TrustException.InvalidCode();
        }

        if (invite.ExpiresAt is null || invite.ExpiresAt <= time.GetUtcNow())
        {
            throw TrustException.InvalidCode();
        }

        if (invite.CreatorId == you.Id)
        {
            throw new TrustException("own_invite", "You cannot join your own invite.");
        }

        _ = await RequireAccount(invite.CreatorId, cancellationToken);
        await store.AcceptInviteConnectionAsync(invite.Id, you.Id, time.GetUtcNow(), cancellationToken);
    }

    /// Same membership as an accepted invite. Does not send SMS.
    public async Task<bool> ConnectAccountsAsync(
        Guid accountId,
        Guid otherAccountId,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var other = await RequireAccount(otherAccountId, cancellationToken);
        if (you.Id == other.Id)
        {
            throw TrustException.OwnPhone();
        }

        return await store.ConnectAccountsWithOffSharesAsync(you.Id, other.Id, time.GetUtcNow(), cancellationToken);
    }

    public async Task SetShareAsync(
        Guid accountId,
        Guid granteeId,
        ShareResting? resting,
        PauseDuration? pause,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        if (!await store.AreConnectedAsync(you.Id, granteeId, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        var now = time.GetUtcNow();
        await store.RestoreExpiredPausesAsync(now, cancellationToken);
        var current = await store.GetShareAsync(you.Id, granteeId, cancellationToken);

        if (pause is { } duration)
        {
            var effective = current.Effective(now);
            var restores = effective switch
            {
                ShareResting.Always => ShareResting.Always,
                ShareResting.UntilTheyLook => ShareResting.UntilTheyLook,
                ShareResting.Paused => current.RestoresTo == ShareResting.Always
                    ? ShareResting.Always
                    : ShareResting.UntilTheyLook,
                _ => throw new TrustException(
                    "pause_requires_share",
                    "Pause only applies while you are sharing.")
            };
            await store.UpsertShareAsync(
                you.Id,
                granteeId,
                new ShareState(ShareResting.Paused, PauseShare.EndAt(duration, now), restores),
                cancellationToken);
            return;
        }

        // Always is Plus on this account. A friend's Plus does not unlock it.
        // Sealed, Off, and Pause are never paywalled.
        if (resting == ShareResting.Always && !you.HasCircle)
        {
            throw TrustException.ProRequired();
        }

        if (resting is null)
        {
            return;
        }

        if (resting == ShareResting.Paused)
        {
            throw new TrustException("pause_required", "Choose how long to pause.");
        }

        await store.UpsertShareAsync(
            you.Id,
            granteeId,
            new ShareState(resting.Value),
            cancellationToken);

        if (resting == ShareResting.Off)
        {
            await ClearLocationsIfNothingHeldAsync(you.Id, now, cancellationToken);
        }
    }

    public async Task<IReadOnlyList<LocationFix>> HistoryAsync(
        Guid viewerId,
        Guid subjectId,
        CancellationToken cancellationToken)
    {
        var viewer = await RequireAccount(viewerId, cancellationToken);
        if (!await store.AreConnectedAsync(viewer.Id, subjectId, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        var now = time.GetUtcNow();
        await store.RestoreExpiredPausesAsync(now, cancellationToken);
        var shareToViewer = await store.GetShareAsync(subjectId, viewer.Id, cancellationToken);
        // History is an ongoing trail and is available only in Always. Sealed grants
        // exactly one confirmed snapshot through LookAsync.
        if (!shareToViewer.SharesHistory(now))
        {
            throw TrustException.ShareOff();
        }

        var window = TrustRules.HistoryWindow(viewer.HasCircle);
        var points = await store.UnlockLocationsAsync(subjectId, now - window, now, cancellationToken);
        return points.OrderByDescending(point => point.Timestamp).ToList();
    }

    public Task IngestAsync(
        Guid accountId,
        LocationFix fix,
        int? batteryPercent,
        bool? isCharging,
        CancellationToken cancellationToken) =>
        IngestManyAsync(accountId, [fix], batteryPercent, isCharging, cancellationToken);

    public async Task IngestManyAsync(
        Guid accountId,
        IReadOnlyList<LocationFix> fixes,
        int? batteryPercent,
        bool? isCharging,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var connected = await store.ListConnectedAsync(you.Id, cancellationToken);
        if (connected.Count == 0)
        {
            await store.ClearLocationsAsync(you.Id, cancellationToken);
            return;
        }

        var now = time.GetUtcNow();

        // Upload only while Sealed or Always. Pause keeps the trail but does not add points.
        // If every outbound share is Off, wipe what's stored.
        var acceptsLocation = false;
        var keepsTrail = false;
        foreach (var person in connected)
        {
            var outbound = await store.GetShareAsync(you.Id, person.Id, cancellationToken);
            if (outbound.AcceptsLocation(now))
            {
                acceptsLocation = true;
            }

            if (outbound.KeepsTrail(now))
            {
                keepsTrail = true;
            }
        }

        if (!acceptsLocation)
        {
            if (!keepsTrail)
            {
                await store.ClearLocationsAsync(you.Id, cancellationToken);
            }

            return;
        }

        var cutoff = now - TrustRules.LocationRetention;
        LocationFix? latest = null;
        foreach (var raw in fixes.OrderBy(fix => fix.Timestamp))
        {
            var recorded = raw.Timestamp;
            if (recorded > now.AddMinutes(2))
            {
                recorded = now;
            }

            if (recorded < cutoff)
            {
                continue;
            }

            var fix = raw with { Timestamp = recorded };
            await store.IngestLocationAsync(you.Id, fix, cancellationToken);
            latest = fix;
        }

        await store.PruneLocationsAsync(you.Id, cutoff, cancellationToken);
        if (latest is null)
        {
            return;
        }

        var presence = await store.GetPresenceAsync(you.Id, latest.Timestamp, cancellationToken);
        var gotHome = LocationTrail.IsNearHome(latest) ? latest.Timestamp : presence.GotHomeAt;
        await store.UpsertPresenceAsync(
            you.Id,
            presence with
            {
                LastActiveAt = latest.Timestamp,
                BatteryPercent = batteryPercent ?? presence.BatteryPercent,
                IsCharging = isCharging ?? presence.IsCharging,
                GotHomeAt = gotHome
            },
            cancellationToken);
    }

    public async Task<LookResult> LookAsync(
        Guid viewerId,
        Guid subjectId,
        bool confirmed,
        CancellationToken cancellationToken)
    {
        if (!confirmed)
        {
            throw TrustException.ConfirmationRequired();
        }

        var viewer = await RequireAccount(viewerId, cancellationToken);
        var subject = await RequireAccount(subjectId, cancellationToken);
        if (!await store.AreConnectedAsync(viewer.Id, subject.Id, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        var now = time.GetUtcNow();
        var shareToViewer = await store.GetShareAsync(subject.Id, viewer.Id, cancellationToken);
        var presentation = shareToViewer.Presentation(now);
        if (presentation is SharePresentation.Off)
        {
            throw TrustException.ShareOff();
        }

        if (presentation is not SharePresentation.UntilTheyLook)
        {
            // Always is already live — the client should use View, not Look.
            // Paused and Off are not a Look.
            throw presentation is SharePresentation.Paused
                ? TrustException.ShareOff()
                : TrustException.LookRequiresSealed();
        }

        // One confirmed Look is one snapshot and one receipt. History is GET /history, not this call.
        var live = await store.LatestLocationAsync(subject.Id, cancellationToken)
            ?? throw TrustException.NoLocation();

        var look = new LookEvent(
            Guid.NewGuid(),
            viewer.Id,
            viewer.DisplayName,
            subject.Id,
            subject.DisplayName,
            now,
            0,
            true,
            LookKind.Look);
        await store.InsertLookEventAsync(look, cancellationToken);
        return new LookResult(new LookSession(look, live, [live]), IsNew: true);
    }

    /// View is the Always read: no confirm sheet, no push. It only works while they share Always.
    /// Repeated views within <see cref="TrustRules.ViewDedupeWindow"/> don't add new log rows;
    /// this returns null in that case so the caller knows nothing new was logged.
    public async Task<LookEvent?> ViewAsync(
        Guid viewerId,
        Guid subjectId,
        CancellationToken cancellationToken)
    {
        var viewer = await RequireAccount(viewerId, cancellationToken);
        var subject = await RequireAccount(subjectId, cancellationToken);
        if (!await store.AreConnectedAsync(viewer.Id, subject.Id, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        var now = time.GetUtcNow();
        var shareToViewer = await store.GetShareAsync(subject.Id, viewer.Id, cancellationToken);
        if (!shareToViewer.RevealsLive(now))
        {
            throw TrustException.ViewRequiresAvailable();
        }

        var since = now - TrustRules.ViewDedupeWindow;
        var recent = await store.ListLooksAsync(viewer.Id, since, cancellationToken);
        var deduped = recent.Any(look =>
            look.Kind == LookKind.View && look.ViewerId == viewer.Id && look.SubjectId == subject.Id);
        if (deduped)
        {
            return null;
        }

        var view = new LookEvent(
            Guid.NewGuid(),
            viewer.Id,
            viewer.DisplayName,
            subject.Id,
            subject.DisplayName,
            now,
            0,
            true,
            LookKind.View);
        await store.InsertLookEventAsync(view, cancellationToken);
        return view;
    }

    public async Task CheckInAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var presence = await store.GetPresenceAsync(accountId, now, cancellationToken);
        await store.UpsertPresenceAsync(
            accountId,
            presence with { CheckedInAt = now, LastActiveAt = now },
            cancellationToken);
    }

    public async Task PlacePingAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var snapshot = await GetCircleAsync(accountId, cancellationToken);
        if (!snapshot.Coverage.HasPlacePings)
        {
            throw TrustException.ProRequired();
        }

        var now = time.GetUtcNow();
        var presence = await store.GetPresenceAsync(accountId, now, cancellationToken);
        await store.UpsertPresenceAsync(
            accountId,
            presence with { GotHomeAt = now, LastActiveAt = now },
            cancellationToken);
    }

    public async Task GrantCircleAsync(Guid accountId, string source, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        await store.UpdateAccountAsync(
            you with { HasCircle = true, CircleSource = source },
            cancellationToken);
    }

    public async Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await RequireAccount(accountId, cancellationToken);
        await store.DeleteAccountAsync(accountId, cancellationToken);
    }

    public async Task RevokeAsync(Guid accountId, Guid otherId, CancellationToken cancellationToken)
    {
        if (!await store.AreConnectedAsync(accountId, otherId, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        var you = await RequireAccount(accountId, cancellationToken);
        var other = await RequireAccount(otherId, cancellationToken);
        var now = time.GetUtcNow();
        await store.InsertLookEventAsync(
            new LookEvent(
                Guid.NewGuid(),
                you.Id,
                you.DisplayName,
                other.Id,
                other.DisplayName,
                now,
                0,
                false,
                LookKind.Removed),
            cancellationToken);
        await store.RevokeMembershipAsync(accountId, otherId, cancellationToken);
        if (await store.ActiveMembershipCountAsync(accountId, cancellationToken) == 0)
        {
            await store.ClearLocationsAsync(accountId, cancellationToken);
        }

        if (await store.ActiveMembershipCountAsync(otherId, cancellationToken) == 0)
        {
            await store.ClearLocationsAsync(otherId, cancellationToken);
        }
    }

    public async Task RenameAsync(Guid accountId, string displayName, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var trimmed = displayName.Trim();
        if (!AccountIdentity.IsChosenDisplayName(trimmed))
        {
            throw new TrustException(
                "invalid_name",
                "Enter a display name of at least two characters.");
        }

        await store.UpdateAccountAsync(you with { DisplayName = trimmed }, cancellationToken);
    }

    public HandleAvailability CheckHandle(Guid accountId, string? raw, Account? existing)
    {
        if (!AccountHandle.TryValidate(raw, out var normalized, out var errorCode))
        {
            return new HandleAvailability(normalized, false, errorCode);
        }

        if (existing is not null && existing.Id != accountId)
        {
            return new HandleAvailability(normalized, false, "handle_in_use");
        }

        return new HandleAvailability(normalized, true, null);
    }

    public async Task<HandleAvailability> CheckHandleAsync(
        Guid accountId,
        string? raw,
        CancellationToken cancellationToken)
    {
        if (!AccountHandle.TryValidate(raw, out var normalized, out var errorCode))
        {
            return new HandleAvailability(normalized, false, errorCode);
        }

        var existing = await store.FindByHandleAsync(normalized, cancellationToken);
        return CheckHandle(accountId, normalized, existing);
    }

    public async Task SetHandleAsync(Guid accountId, string? raw, CancellationToken cancellationToken)
    {
        if (!AccountHandle.TryValidate(raw, out var normalized, out var errorCode))
        {
            throw errorCode == "reserved_handle"
                ? TrustException.ReservedHandle()
                : TrustException.InvalidHandle();
        }

        var you = await RequireAccount(accountId, cancellationToken);
        var existing = await store.FindByHandleAsync(normalized, cancellationToken);
        if (existing is not null && existing.Id != accountId)
        {
            throw TrustException.HandleInUse();
        }

        var displayName = you.HasChosenDisplayName ? you.DisplayName : normalized;
        await store.SetHandleAsync(accountId, normalized, displayName, cancellationToken);
    }

    public async Task<PersonLookup?> LookupPersonAsync(Guid accountId, string? rawHandle, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        RequireConnectionRequestEligibility(you);
        if (!AccountHandle.TryValidate(rawHandle, out var handle, out var code))
            throw code == "reserved_handle" ? TrustException.ReservedHandle() : TrustException.InvalidHandle();
        var other = await store.FindByHandleAsync(handle, cancellationToken);
        // Keep missing, self, and not-yet-discoverable accounts indistinguishable.
        if (other is null || other.Id == accountId || !other.OnboardingComplete) return null;
        var match = await store.GetConnectionRelationshipAsync(accountId, other.Id, time.GetUtcNow(), cancellationToken);
        return new PersonLookup(other.Id, other.Handle!, match.Relationship, match.RequestId);
    }

    public async Task<ConnectionRequestLists> ListConnectionRequestsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        return await store.ListConnectionRequestsAsync(accountId, time.GetUtcNow(), cancellationToken);
    }

    public async Task<ConnectionRequest> CreateConnectionRequestAsync(Guid accountId, Guid recipientId, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        RequireConnectionRequestEligibility(you);
        var recipient = await store.FindAccountAsync(recipientId, cancellationToken);
        if (recipient is null || !recipient.OnboardingComplete || recipientId == accountId) throw TrustException.RequestNotFound();
        return await store.CreateConnectionRequestAsync(accountId, recipientId, time.GetUtcNow(), cancellationToken);
    }

    public async Task AcceptConnectionRequestAsync(Guid accountId, Guid requestId, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        RequireConnectionRequestEligibility(you);
        await store.AcceptConnectionRequestAsync(requestId, accountId, time.GetUtcNow(), cancellationToken);
    }

    public async Task DeclineConnectionRequestAsync(Guid accountId, Guid requestId, CancellationToken cancellationToken)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        await store.DeclineConnectionRequestAsync(requestId, accountId, time.GetUtcNow(), cancellationToken);
    }

    public async Task CancelConnectionRequestAsync(Guid accountId, Guid requestId, CancellationToken cancellationToken)
    {
        _ = await RequireAccount(accountId, cancellationToken);
        await store.CancelConnectionRequestAsync(requestId, accountId, time.GetUtcNow(), cancellationToken);
    }

    private static void RequireConnectionRequestEligibility(Account account)
    {
        if (!account.OnboardingComplete) throw TrustException.PhoneVerificationRequired();
    }

    public async Task<int> LooksTodayAsync(Guid viewerId, CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var start = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
        return await store.LooksTodayAsync(viewerId, start, cancellationToken);
    }

    public async Task SetPresenceGrantAsync(
        Guid subjectId,
        Guid trusteeId,
        bool enabled,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(subjectId, cancellationToken);
        await RequireAccount(trusteeId, cancellationToken);
        if (!await store.AreConnectedAsync(you.Id, trusteeId, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        await store.SetPresenceGrantAsync(you.Id, trusteeId, enabled, time.GetUtcNow(), cancellationToken);
    }

    public async Task SetHomePlaceAsync(
        Guid accountId,
        Guid placeId,
        string label,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var trimmed = string.IsNullOrWhiteSpace(label) ? "Home" : label.Trim();
        if (trimmed.Length > 40)
        {
            trimmed = trimmed[..40];
        }

        var now = time.GetUtcNow();
        await store.UpsertHomePlaceAsync(new HomePlace(you.Id, placeId, trimmed, now), cancellationToken);
        var current = await store.GetCurrentHomePresenceAsync(you.Id, cancellationToken);
        if (current is null)
        {
            await store.UpsertCurrentHomePresenceAsync(
                new CurrentHomePresence(you.Id, placeId, HomePresenceState.Unknown, now, null),
                cancellationToken);
        }
    }

    public async Task<bool> PostHomePresenceAsync(
        Guid accountId,
        HomePresenceState state,
        DateTimeOffset? signaledAt,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        // Home|Away|Hidden is a manual, global triad — it does not require Home to be set.
        // A Home place only adds the label shown alongside Home/Away for those who have one.
        var place = await store.GetHomePlaceAsync(you.Id, cancellationToken);
        var now = time.GetUtcNow();
        var at = signaledAt ?? now;
        if (at > now.AddMinutes(2))
        {
            at = now;
        }

        var previous = await store.GetCurrentHomePresenceAsync(you.Id, cancellationToken);
        var arrivedHome = state == HomePresenceState.Home && previous?.State != HomePresenceState.Home;
        var changedAt = previous is not null && previous.State == state
            ? previous.LastChangedAt
            : at;
        await store.UpsertCurrentHomePresenceAsync(
            new CurrentHomePresence(you.Id, place?.PlaceId, state, changedAt, at),
            cancellationToken);

        if (state == HomePresenceState.Home)
        {
            await ResolvePromisesOnArrivalAsync(you.Id, at, cancellationToken);
        }

        return arrivedHome;
    }

    public async Task<HomePromise> CreatePromiseAsync(
        Guid subjectId,
        Guid trusteeId,
        DateTimeOffset deadlineAt,
        CancellationToken cancellationToken)
    {
        var you = await RequireAccount(subjectId, cancellationToken);
        await RequireAccount(trusteeId, cancellationToken);
        if (!await store.AreConnectedAsync(you.Id, trusteeId, cancellationToken))
        {
            throw TrustException.NotConnected();
        }

        var place = await store.GetHomePlaceAsync(you.Id, cancellationToken)
            ?? throw new TrustException("home_unset", "Set Home before making a promise.");
        var now = time.GetUtcNow();
        if (deadlineAt <= now)
        {
            throw new TrustException("invalid_deadline", "Choose a time in the future.");
        }

        var existing = await store.GetActivePromiseAsync(you.Id, trusteeId, cancellationToken);
        if (existing is not null)
        {
            var updated = existing with { DeadlineAt = deadlineAt, PlaceId = place.PlaceId };
            await store.UpdatePromiseAsync(updated, cancellationToken);
            return updated;
        }

        var promise = new HomePromise(
            Guid.NewGuid(),
            you.Id,
            trusteeId,
            place.PlaceId,
            deadlineAt,
            PromiseStatus.Active,
            null,
            now);
        await store.InsertPromiseAsync(promise, cancellationToken);
        return promise;
    }

    public async Task EvaluateDuePromisesAsync(CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var due = await store.ListDuePromisesAsync(now, cancellationToken);
        foreach (var promise in due)
        {
            var presence = await store.GetCurrentHomePresenceAsync(promise.SubjectId, cancellationToken);
            PromiseStatus status;
            if (presence?.State == HomePresenceState.Home
                && presence.LastChangedAt <= promise.DeadlineAt)
            {
                status = PromiseStatus.Resolved;
            }
            else if (presence?.LastSignalAt is { } signal
                     && now - signal > TrustRules.PresenceSignalStale)
            {
                status = PromiseStatus.NoSignal;
            }
            else if (presence is null
                     || presence.LastSignalAt is null
                     || now - presence.LastSignalAt > TrustRules.PresenceSignalStale)
            {
                status = PromiseStatus.NoSignal;
            }
            else
            {
                status = PromiseStatus.Overdue;
            }

            await store.UpdatePromiseAsync(
                promise with
                {
                    Status = status,
                    ResolvedAt = status == PromiseStatus.Resolved ? presence!.LastChangedAt : now
                },
                cancellationToken);
        }
    }

    /// Review seed covers every M1 share/presence bucket in one pass: Sealed (Alex), Always
    /// (Jordan), Timed (Riley) — plus Riley demonstrating Hidden presence (granted, but
    /// withheld from the circle) and one already-completed prior Look so the view log isn't
    /// empty on first run.
    public async Task EnsureReviewCircleAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var you = await RequireAccount(accountId, cancellationToken);
        var connected = await store.ListConnectedAsync(accountId, cancellationToken);
        if (connected.Count > 0)
        {
            return;
        }

        var now = time.GetUtcNow();
        var alex = await SeedPersonAsync(you.Id, "alex", "Alex", now, 0.000, 0.000, 74, false, cancellationToken);
        var jordan = await SeedPersonAsync(you.Id, "jordan", "Jordan", now, 0.004, 0.003, 81, false, cancellationToken);
        var riley = await SeedPersonAsync(you.Id, "riley", "Riley", now, -0.003, 0.005, 58, true, cancellationToken);

        await store.InsertMembershipAsync(you.Id, alex.Id, cancellationToken);
        await store.InsertMembershipAsync(you.Id, jordan.Id, cancellationToken);
        await store.InsertMembershipAsync(you.Id, riley.Id, cancellationToken);

        // Alex: Sealed both ways — reachable only via an explicit Look.
        await store.UpsertShareAsync(
            you.Id, alex.Id, new ShareState(ShareResting.UntilTheyLook, null), cancellationToken);
        await store.UpsertShareAsync(
            alex.Id, you.Id, new ShareState(ShareResting.UntilTheyLook, null), cancellationToken);

        // Jordan: Always — Available, live without a Look.
        await store.UpsertShareAsync(
            you.Id, jordan.Id, new ShareState(ShareResting.Always, null), cancellationToken);
        await store.UpsertShareAsync(
            jordan.Id, you.Id, new ShareState(ShareResting.Always, null), cancellationToken);

        // Riley: Paused — not sharing until the timer, then Sealed returns. Not a live pin.
        await store.UpsertShareAsync(
            you.Id, riley.Id, new ShareState(ShareResting.Paused, now.AddMinutes(47), ShareResting.UntilTheyLook), cancellationToken);
        await store.UpsertShareAsync(
            riley.Id, you.Id, new ShareState(ShareResting.Paused, now.AddMinutes(47), ShareResting.UntilTheyLook), cancellationToken);

        // Riley: Hidden presence — grant is on, but the state itself must never surface to you.
        await store.SetPresenceGrantAsync(riley.Id, you.Id, true, now, cancellationToken);
        await store.UpsertHomePlaceAsync(new HomePlace(riley.Id, Guid.NewGuid(), "Home", now), cancellationToken);
        await store.UpsertCurrentHomePresenceAsync(
            new CurrentHomePresence(riley.Id, null, HomePresenceState.Hidden, now, now),
            cancellationToken);

        // One prior look already in the log, so review doesn't start from a blank view log.
        await store.InsertLookEventAsync(
            new LookEvent(
                Guid.NewGuid(),
                you.Id,
                you.DisplayName,
                alex.Id,
                alex.DisplayName,
                now.AddHours(-20),
                0,
                true,
                LookKind.Look),
            cancellationToken);
    }

    private async Task ResolvePromisesOnArrivalAsync(
        Guid subjectId,
        DateTimeOffset arrivedAt,
        CancellationToken cancellationToken)
    {
        var connected = await store.ListConnectedAsync(subjectId, cancellationToken);
        foreach (var person in connected)
        {
            var active = await store.GetActivePromiseAsync(subjectId, person.Id, cancellationToken);
            if (active is null)
            {
                continue;
            }

            await store.UpdatePromiseAsync(
                active with { Status = PromiseStatus.Resolved, ResolvedAt = arrivedAt },
                cancellationToken);
        }
    }

    private async Task<PromiseView?> BuildPromiseViewAsync(
        Guid youId,
        Guid otherId,
        CancellationToken cancellationToken)
    {
        var promises = await store.ListPromisesForPairAsync(youId, otherId, cancellationToken);
        var relevant = promises.FirstOrDefault(promise =>
            promise.Status is PromiseStatus.Active or PromiseStatus.Overdue or PromiseStatus.NoSignal
            || (promise.Status == PromiseStatus.Resolved
                && promise.ResolvedAt is { } resolved
                && time.GetUtcNow() - resolved < TimeSpan.FromHours(12)));
        if (relevant is null)
        {
            return null;
        }

        var subjectPlace = await store.GetHomePlaceAsync(relevant.SubjectId, cancellationToken);
        return new PromiseView(
            relevant.Id,
            relevant.SubjectId,
            relevant.TrusteeId,
            subjectPlace?.Label ?? "Home",
            relevant.DeadlineAt,
            relevant.Status,
            relevant.ResolvedAt,
            relevant.SubjectId == youId);
    }

    private async Task<Account> SeedPersonAsync(
        Guid ownerId,
        string slug,
        string name,
        DateTimeOffset now,
        double latOff,
        double lonOff,
        int battery,
        bool charging,
        CancellationToken cancellationToken)
    {
        var subject = $"{ownerId:N}:{slug}";
        var existing = await store.FindByProviderAsync("seed", subject, cancellationToken);
        var origin = new LocationFix(
            now,
            LocationTrail.Home.Latitude + latOff,
            LocationTrail.Home.Longitude + lonOff);
        if (existing is null)
        {
            existing = await store.UpsertAccountAsync(
                new Account(Guid.NewGuid(), "seed", subject, name, false, null, now),
                cancellationToken);
        }

        await store.UpsertPresenceAsync(
            existing.Id,
            new Presence(now.AddMinutes(-12), battery, charging, now.AddMinutes(-40), null),
            cancellationToken);
        foreach (var point in LocationTrail.Seed(origin, now, 24, 15, 0.0004))
        {
            await store.IngestLocationAsync(existing.Id, point, cancellationToken);
        }

        return existing;
    }

    /// Plus is this account. A paying friend does not cover you.
    private static CircleCoverage CoverageOf(Account you, IReadOnlyList<Account> connected)
    {
        _ = connected;
        return new CircleCoverage(
            you.HasCircle,
            you.HasCircle ? you.DisplayName : null,
            you.HasCircle);
    }

    private async Task EnsureSeatAsync(Account a, Account b, CancellationToken cancellationToken)
    {
        var limitA = a.HasCircle ? TrustRules.ProSeats : TrustRules.FreeSeats;
        var limitB = b.HasCircle ? TrustRules.ProSeats : TrustRules.FreeSeats;
        var countA = await store.ActiveMembershipCountAsync(a.Id, cancellationToken);
        var countB = await store.ActiveMembershipCountAsync(b.Id, cancellationToken);
        if (countA >= limitA || countB >= limitB)
        {
            throw TrustException.SeatLimit();
        }
    }

    private async Task ClearLocationsIfNothingHeldAsync(
        Guid accountId,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var connected = await store.ListConnectedAsync(accountId, cancellationToken);
        foreach (var person in connected)
        {
            var outbound = await store.GetShareAsync(accountId, person.Id, cancellationToken);
            if (outbound.KeepsTrail(now))
            {
                return;
            }
        }

        await store.ClearLocationsAsync(accountId, cancellationToken);
    }

    private async Task<Account> RequireAccount(Guid id, CancellationToken cancellationToken) =>
        await store.FindAccountAsync(id, cancellationToken)
        ?? throw TrustException.Unauthorized();

    private static string MakeInviteCode()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        Span<char> chars = stackalloc char[6];
        for (var i = 0; i < chars.Length; i++)
        {
            chars[i] = alphabet[System.Security.Cryptography.RandomNumberGenerator.GetInt32(alphabet.Length)];
        }

        return new string(chars);
    }
}

public static class LocationTrail
{
    public static LocationFix Home { get; } = new(
        DateTimeOffset.UnixEpoch,
        37.7599,
        -122.4148);

    public static IReadOnlyList<LocationFix> Seed(
        LocationFix origin,
        DateTimeOffset now,
        double hours,
        double intervalMinutes,
        double drift)
    {
        var totalMinutes = hours * 60;
        var steps = (int)(totalMinutes / intervalMinutes);
        var points = new List<LocationFix>(steps + 1);
        for (var index = 0; index <= steps; index++)
        {
            var minutesAgo = totalMinutes - index * intervalMinutes;
            var progress = steps == 0 ? 1 : (double)index / steps;
            var lat = origin.Latitude
                + 0.004 * Math.Sin(progress * Math.PI * 2)
                + 0.0015 * progress
                + drift;
            var lon = origin.Longitude
                + 0.005 * (Math.Cos(progress * Math.PI * 2) - 1)
                - 0.0008 * progress
                + drift * 0.6;
            points.Add(new LocationFix(now.AddMinutes(-minutesAgo), lat, lon));
        }

        return points;
    }

    public static bool IsNearHome(LocationFix point, LocationFix? home = null)
    {
        home ??= Home;
        var dlat = point.Latitude - home.Latitude;
        var dlon = point.Longitude - home.Longitude;
        var meters = Math.Sqrt(dlat * dlat + dlon * dlon) * 111_000;
        return meters < 120;
    }
}
