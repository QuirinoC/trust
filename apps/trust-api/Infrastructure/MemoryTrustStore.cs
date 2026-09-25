using System.Collections.Concurrent;
using TrustApi.Domain;

namespace TrustApi.Infrastructure;

public sealed class MemoryTrustStore : ITrustStore
{
    private readonly ConcurrentDictionary<Guid, Account> _accounts = new();
    private readonly ConcurrentDictionary<Guid, byte[]> _avatarPhotos = new();
    private readonly ConcurrentDictionary<(string Provider, string Subject), Guid> _byProvider = new();
    private readonly ConcurrentDictionary<(Guid A, Guid B), string> _memberships = new();
    private readonly ConcurrentDictionary<(Guid Grantor, Guid Grantee), ShareState> _shares = new();
    private readonly ConcurrentDictionary<Guid, Presence> _presence = new();
    private readonly ConcurrentDictionary<Guid, List<LocationFix>> _locations = new();
    private readonly List<LookEvent> _looks = [];
    private readonly ConcurrentDictionary<string, Invite> _invites = new();
    private readonly ConcurrentDictionary<Guid, PhoneChallenge> _phoneChallenges = new();
    private readonly ConcurrentDictionary<string, SmsSendBudget> _smsBudgets = new();
    private readonly SemaphoreSlim _smsGate = new(1, 1);
    private readonly ConcurrentDictionary<(Guid Subject, Guid Trustee), PresenceGrant> _presenceGrants = new();
    private readonly ConcurrentDictionary<Guid, HomePlace> _homePlaces = new();
    private readonly ConcurrentDictionary<Guid, CurrentHomePresence> _homePresence = new();
    private readonly ConcurrentDictionary<Guid, HomePromise> _promises = new();
    private readonly object _gate = new();

    public Task<Account?> FindAccountAsync(Guid id, CancellationToken cancellationToken)
    {
        _accounts.TryGetValue(id, out var account);
        return Task.FromResult(account);
    }

    public Task<Account?> FindByProviderAsync(string provider, string subject, CancellationToken cancellationToken)
    {
        if (_byProvider.TryGetValue((provider, subject), out var id))
        {
            return FindAccountAsync(id, cancellationToken);
        }

        return Task.FromResult<Account?>(null);
    }

    public Task<Account> UpsertAccountAsync(Account account, CancellationToken cancellationToken)
    {
        _accounts[account.Id] = account;
        _byProvider[(account.Provider, account.ProviderSubject)] = account.Id;
        return Task.FromResult(account);
    }

    public Task UpdateAccountAsync(Account account, CancellationToken cancellationToken) =>
        UpsertAccountAsync(account, cancellationToken);

    public Task<ProfileAvatar> SetAvatarPresetAsync(Guid accountId, string presetId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var avatar = new ProfileAvatar("preset", presetId);
            if (_accounts.TryGetValue(accountId, out var account))
            {
                _accounts[accountId] = account with { Avatar = avatar };
            }
            _avatarPhotos.TryRemove(accountId, out _);
            return Task.FromResult(avatar);
        }
    }

    public Task<ProfileAvatar> SetAvatarPhotoAsync(Guid accountId, Guid version, byte[] jpeg, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var avatar = new ProfileAvatar("photo", Version: version);
            if (_accounts.TryGetValue(accountId, out var account))
            {
                _accounts[accountId] = account with { Avatar = avatar };
            }
            _avatarPhotos[accountId] = jpeg;
            return Task.FromResult(avatar);
        }
    }

    public Task ClearAvatarAsync(Guid accountId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (_accounts.TryGetValue(accountId, out var account))
            {
                _accounts[accountId] = account with { Avatar = null };
            }
            _avatarPhotos.TryRemove(accountId, out _);
            return Task.CompletedTask;
        }
    }

    public Task<byte[]?> GetAvatarPhotoAsync(Guid accountId, Guid version, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (_accounts.TryGetValue(accountId, out var account)
                && account.Avatar is { Kind: "photo", Version: { } current } && current == version
                && _avatarPhotos.TryGetValue(accountId, out var jpeg))
            {
                return Task.FromResult<byte[]?>(jpeg);
            }

            return Task.FromResult<byte[]?>(null);
        }
    }

    public Task<IReadOnlyList<Account>> ListConnectedAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var people = _memberships
            .Where(pair => pair.Value == "active" && (pair.Key.A == accountId || pair.Key.B == accountId))
            .Select(pair => pair.Key.A == accountId ? pair.Key.B : pair.Key.A)
            .Select(id => _accounts.GetValueOrDefault(id))
            .OfType<Account>()
            .ToList();
        return Task.FromResult<IReadOnlyList<Account>>(people);
    }

    public Task<int> ActiveMembershipCountAsync(Guid accountId, CancellationToken cancellationToken) =>
        Task.FromResult(_memberships.Count(pair =>
            pair.Value == "active" && (pair.Key.A == accountId || pair.Key.B == accountId)));

    public Task<bool> AreConnectedAsync(Guid a, Guid b, CancellationToken cancellationToken)
    {
        var key = Order(a, b);
        return Task.FromResult(_memberships.TryGetValue(key, out var status) && status == "active");
    }

    public Task InsertMembershipAsync(Guid a, Guid b, CancellationToken cancellationToken)
    {
        _memberships[Order(a, b)] = "active";
        return Task.CompletedTask;
    }

    public Task RevokeMembershipAsync(Guid a, Guid b, CancellationToken cancellationToken)
    {
        _memberships[Order(a, b)] = "revoked";
        return Task.CompletedTask;
    }

    public Task<ShareState> GetShareAsync(Guid grantor, Guid grantee, CancellationToken cancellationToken)
    {
        return Task.FromResult(_shares.GetValueOrDefault((grantor, grantee), ShareState.Default));
    }

    public Task UpsertShareAsync(Guid grantor, Guid grantee, ShareState state, CancellationToken cancellationToken)
    {
        _shares[(grantor, grantee)] = state;
        return Task.CompletedTask;
    }

    public Task RestoreExpiredPausesAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        foreach (var (key, state) in _shares.ToList())
        {
            if (state.Resting == ShareResting.Paused && state.PauseUntil is { } until && until <= now)
            {
                var restore = state.RestoresTo == ShareResting.Always
                    ? ShareResting.Always
                    : ShareResting.UntilTheyLook;
                _shares[key] = new ShareState(restore);
            }
        }

        return Task.CompletedTask;
    }

    public Task<Presence> GetPresenceAsync(Guid accountId, DateTimeOffset fallbackNow, CancellationToken cancellationToken)
    {
        if (_presence.TryGetValue(accountId, out var presence))
        {
            return Task.FromResult(presence);
        }

        return Task.FromResult(new Presence(fallbackNow.AddMinutes(-10), 80, false, null, null));
    }

    public Task UpsertPresenceAsync(Guid accountId, Presence presence, CancellationToken cancellationToken)
    {
        _presence[accountId] = presence;
        return Task.CompletedTask;
    }

    public Task IngestLocationAsync(Guid accountId, LocationFix fix, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var list = _locations.GetOrAdd(accountId, _ => []);
            list.Add(fix);
        }

        return Task.CompletedTask;
    }

    public Task PruneLocationsAsync(Guid accountId, DateTimeOffset olderThan, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (_locations.TryGetValue(accountId, out var list) && list.Count > 0)
            {
                list.RemoveAll(fix => fix.Timestamp < olderThan);
            }
        }

        return Task.CompletedTask;
    }

    public Task ClearLocationsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        _locations.TryRemove(accountId, out _);
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<LocationFix>> UnlockLocationsAsync(
        Guid accountId,
        DateTimeOffset from,
        DateTimeOffset to,
        CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (!_locations.TryGetValue(accountId, out var list))
            {
                return Task.FromResult<IReadOnlyList<LocationFix>>([]);
            }

            return Task.FromResult<IReadOnlyList<LocationFix>>(
                list.Where(fix => fix.Timestamp >= from && fix.Timestamp <= to)
                    .OrderBy(fix => fix.Timestamp)
                    .ToList());
        }
    }

    public Task<LocationFix?> LatestLocationAsync(Guid accountId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (!_locations.TryGetValue(accountId, out var list) || list.Count == 0)
            {
                return Task.FromResult<LocationFix?>(null);
            }

            return Task.FromResult<LocationFix?>(list.MaxBy(fix => fix.Timestamp));
        }
    }

    public Task InsertLookEventAsync(LookEvent look, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _looks.Add(look);
        }

        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<LookEvent>> ListLooksAsync(
        Guid accountId,
        DateTimeOffset since,
        CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            return Task.FromResult<IReadOnlyList<LookEvent>>(
                _looks.Where(look =>
                        look.At >= since && (look.ViewerId == accountId || look.SubjectId == accountId))
                    .OrderByDescending(look => look.At)
                    .ToList());
        }
    }

    public Task<int> LooksTodayAsync(Guid viewerId, DateTimeOffset startOfDay, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            return Task.FromResult(_looks.Count(look => look.ViewerId == viewerId && look.At >= startOfDay));
        }
    }

    public Task PruneAllLocationsAsync(DateTimeOffset olderThan, CancellationToken cancellationToken)
    {
        var now = olderThan + TrustRules.LocationRetention;
        lock (_gate)
        {
            foreach (var (accountId, list) in _locations)
            {
                if (!KeepsTrail(accountId, now))
                {
                    list.Clear();
                    continue;
                }

                list.RemoveAll(fix => fix.Timestamp < olderThan);
            }
        }

        return Task.CompletedTask;
    }

    private bool KeepsTrail(Guid accountId, DateTimeOffset now)
    {
        foreach (var (key, state) in _shares)
        {
            if (key.Grantor == accountId && state.KeepsTrail(now))
            {
                return true;
            }
        }

        return false;
    }

    public Task<Invite?> FindInviteByCodeAsync(string code, CancellationToken cancellationToken)
    {
        _invites.TryGetValue(code, out var invite);
        return Task.FromResult(invite);
    }

    public Task<Invite?> FindPendingInviteAsync(Guid creatorId, CancellationToken cancellationToken)
    {
        var invite = _invites.Values.FirstOrDefault(item =>
            item.CreatorId == creatorId && item.Status == "pending");
        return Task.FromResult(invite);
    }

    public Task InsertInviteAsync(Invite invite, CancellationToken cancellationToken)
    {
        _invites[invite.Code] = invite;
        return Task.CompletedTask;
    }

    public Task MarkInviteConsumedAsync(Guid inviteId, CancellationToken cancellationToken)
    {
        var match = _invites.Values.FirstOrDefault(item => item.Id == inviteId);
        if (match is not null)
        {
            _invites[match.Code] = match with { Status = "consumed" };
        }

        return Task.CompletedTask;
    }

    public Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _looks.RemoveAll(look => look.ViewerId == accountId || look.SubjectId == accountId);
            _locations.TryRemove(accountId, out _);
            _presence.TryRemove(accountId, out _);
            foreach (var key in _shares.Keys.Where(key => key.Grantor == accountId || key.Grantee == accountId).ToList())
            {
                _shares.TryRemove(key, out _);
            }

            foreach (var key in _memberships.Keys.Where(key => key.A == accountId || key.B == accountId).ToList())
            {
                _memberships.TryRemove(key, out _);
            }

            foreach (var invite in _invites.Values.Where(item => item.CreatorId == accountId).ToList())
            {
                _invites.TryRemove(invite.Code, out _);
            }

            if (_accounts.TryRemove(accountId, out var account))
            {
                _avatarPhotos.TryRemove(accountId, out _);
                _byProvider.TryRemove((account.Provider, account.ProviderSubject), out _);
            }

            _phoneChallenges.TryRemove(accountId, out _);
            _smsBudgets.TryRemove(SmsSendBudget.AccountKey(accountId), out _);
            foreach (var key in _presenceGrants.Keys
                .Where(key => key.Subject == accountId || key.Trustee == accountId).ToList())
            {
                _presenceGrants.TryRemove(key, out _);
            }

            _homePlaces.TryRemove(accountId, out _);
            _homePresence.TryRemove(accountId, out _);
            foreach (var key in _promises.Keys
                .Where(id =>
                {
                    var promise = _promises[id];
                    return promise.SubjectId == accountId || promise.TrusteeId == accountId;
                }).ToList())
            {
                _promises.TryRemove(key, out _);
            }
        }

        return Task.CompletedTask;
    }

    public Task SetPresenceGrantAsync(
        Guid subjectId,
        Guid trusteeId,
        bool enabled,
        DateTimeOffset updatedAt,
        CancellationToken cancellationToken)
    {
        _presenceGrants[(subjectId, trusteeId)] = new PresenceGrant(subjectId, trusteeId, enabled, updatedAt);
        return Task.CompletedTask;
    }

    public Task<PresenceGrant?> GetPresenceGrantAsync(
        Guid subjectId,
        Guid trusteeId,
        CancellationToken cancellationToken)
    {
        _presenceGrants.TryGetValue((subjectId, trusteeId), out var grant);
        return Task.FromResult(grant);
    }

    public Task UpsertHomePlaceAsync(HomePlace place, CancellationToken cancellationToken)
    {
        _homePlaces[place.AccountId] = place;
        return Task.CompletedTask;
    }

    public Task<HomePlace?> GetHomePlaceAsync(Guid accountId, CancellationToken cancellationToken)
    {
        _homePlaces.TryGetValue(accountId, out var place);
        return Task.FromResult(place);
    }

    public Task UpsertCurrentHomePresenceAsync(CurrentHomePresence presence, CancellationToken cancellationToken)
    {
        _homePresence[presence.AccountId] = presence;
        return Task.CompletedTask;
    }

    public Task<CurrentHomePresence?> GetCurrentHomePresenceAsync(
        Guid accountId,
        CancellationToken cancellationToken)
    {
        _homePresence.TryGetValue(accountId, out var presence);
        return Task.FromResult(presence);
    }

    public Task InsertPromiseAsync(HomePromise promise, CancellationToken cancellationToken)
    {
        _promises[promise.Id] = promise;
        return Task.CompletedTask;
    }

    public Task UpdatePromiseAsync(HomePromise promise, CancellationToken cancellationToken)
    {
        _promises[promise.Id] = promise;
        return Task.CompletedTask;
    }

    public Task<HomePromise?> GetPromiseAsync(Guid promiseId, CancellationToken cancellationToken)
    {
        _promises.TryGetValue(promiseId, out var promise);
        return Task.FromResult(promise);
    }

    public Task<HomePromise?> GetActivePromiseAsync(
        Guid subjectId,
        Guid trusteeId,
        CancellationToken cancellationToken)
    {
        var match = _promises.Values
            .Where(promise =>
                promise.SubjectId == subjectId
                && promise.TrusteeId == trusteeId
                && promise.Status == PromiseStatus.Active)
            .OrderByDescending(promise => promise.CreatedAt)
            .FirstOrDefault();
        return Task.FromResult(match);
    }

    public Task<IReadOnlyList<HomePromise>> ListPromisesForPairAsync(
        Guid a,
        Guid b,
        CancellationToken cancellationToken)
    {
        var list = _promises.Values
            .Where(promise =>
                (promise.SubjectId == a && promise.TrusteeId == b)
                || (promise.SubjectId == b && promise.TrusteeId == a))
            .OrderByDescending(promise => promise.CreatedAt)
            .ToList();
        return Task.FromResult<IReadOnlyList<HomePromise>>(list);
    }

    public Task<IReadOnlyList<HomePromise>> ListDuePromisesAsync(
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var list = _promises.Values
            .Where(promise => promise.Status == PromiseStatus.Active && promise.DeadlineAt <= now)
            .ToList();
        return Task.FromResult<IReadOnlyList<HomePromise>>(list);
    }

    public Task<Account?> FindByVerifiedPhoneAsync(string phoneE164, CancellationToken cancellationToken)
    {
        var match = _accounts.Values.FirstOrDefault(account =>
            account.HasVerifiedPhone
            && string.Equals(account.PhoneE164, phoneE164, StringComparison.Ordinal));
        return Task.FromResult(match);
    }

    public Task SetVerifiedPhoneAsync(
        Guid accountId,
        string phoneE164,
        DateTimeOffset verifiedAt,
        CancellationToken cancellationToken)
    {
        if (!_accounts.TryGetValue(accountId, out var account))
        {
            return Task.CompletedTask;
        }

        var taken = _accounts.Values.Any(other =>
            other.Id != accountId
            && other.HasVerifiedPhone
            && string.Equals(other.PhoneE164, phoneE164, StringComparison.Ordinal));
        if (taken)
        {
            throw TrustException.PhoneInUse();
        }

        _accounts[accountId] = account with { PhoneE164 = phoneE164, PhoneVerifiedAt = verifiedAt };
        return Task.CompletedTask;
    }

    public Task<Account?> FindByHandleAsync(string handle, CancellationToken cancellationToken)
    {
        var match = _accounts.Values.FirstOrDefault(account =>
            account.HasHandle
            && string.Equals(account.Handle, handle, StringComparison.OrdinalIgnoreCase));
        return Task.FromResult(match);
    }

    public Task SetHandleAsync(
        Guid accountId,
        string handle,
        string displayName,
        CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (!_accounts.TryGetValue(accountId, out var account))
            {
                return Task.CompletedTask;
            }

            var taken = _accounts.Values.Any(other =>
                other.Id != accountId
                && other.HasHandle
                && string.Equals(other.Handle, handle, StringComparison.OrdinalIgnoreCase));
            if (taken)
            {
                throw TrustException.HandleInUse();
            }

            _accounts[accountId] = account with { Handle = handle, DisplayName = displayName };
        }

        return Task.CompletedTask;
    }

    public Task<PhoneChallenge?> GetPhoneChallengeAsync(Guid accountId, CancellationToken cancellationToken)
    {
        _phoneChallenges.TryGetValue(accountId, out var challenge);
        return Task.FromResult(challenge);
    }

    public Task UpsertPhoneChallengeAsync(PhoneChallenge challenge, CancellationToken cancellationToken)
    {
        _phoneChallenges[challenge.AccountId] = challenge;
        return Task.CompletedTask;
    }

    public Task ClearPhoneChallengeAsync(Guid accountId, CancellationToken cancellationToken)
    {
        _phoneChallenges.TryRemove(accountId, out _);
        return Task.CompletedTask;
    }

    public async Task<bool> TryReserveSmsAsync(IReadOnlyList<SmsSendBudget> budgets, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await _smsGate.WaitAsync(cancellationToken);
        try
        {
            foreach (var proposed in budgets)
            {
                var current = _smsBudgets.GetValueOrDefault(proposed.ScopeKey);
                var window = proposed.ScopeKey.Contains("-day", StringComparison.Ordinal)
                    ? TimeSpan.FromHours(24)
                    : TimeSpan.FromHours(1);
                var expired = current is null || now - current.WindowStartedAt >= window;
                var count = expired ? 0 : current!.SendCount;
                var limit = proposed.ScopeKey == SmsSendBudget.GlobalDayKey() ? 40 : 8;
                if (count >= limit)
                {
                    return false;
                }

                if (!expired
                    && (proposed.ScopeKey.StartsWith("account:", StringComparison.Ordinal)
                        || proposed.ScopeKey.StartsWith("phone:", StringComparison.Ordinal))
                    && current!.LastSentAt is { } lastSent)
                {
                    var seconds = count <= 1 ? 45 : Math.Min(45 << Math.Min(count - 1, 4), 180);
                    if (now - lastSent < TimeSpan.FromSeconds(seconds))
                    {
                        return false;
                    }
                }
            }

            foreach (var proposed in budgets)
            {
                var current = _smsBudgets.GetValueOrDefault(proposed.ScopeKey);
                var window = proposed.ScopeKey.Contains("-day", StringComparison.Ordinal)
                    ? TimeSpan.FromHours(24)
                    : TimeSpan.FromHours(1);
                var expired = current is null || now - current.WindowStartedAt >= window;
                var count = expired ? 0 : current!.SendCount;
                _smsBudgets[proposed.ScopeKey] = new SmsSendBudget(
                    proposed.ScopeKey,
                    expired ? now : current!.WindowStartedAt,
                    count + 1,
                    now);
            }

            return true;
        }
        finally
        {
            _smsGate.Release();
        }
    }

    public async Task<int?> IncrementPhoneChallengeFailureAsync(Guid accountId, string phoneE164, DateTimeOffset now, int maxAttempts, CancellationToken cancellationToken)
    {
        await _smsGate.WaitAsync(cancellationToken);
        try
        {
            if (!_phoneChallenges.TryGetValue(accountId, out var challenge)
                || challenge.PhoneE164 != phoneE164
                || challenge.ExpiresAt <= now)
            {
                return null;
            }

            var attempts = challenge.Attempts + 1;
            if (attempts >= maxAttempts)
            {
                _phoneChallenges.TryRemove(accountId, out _);
            }
            else
            {
                _phoneChallenges[accountId] = challenge with { Attempts = attempts };
            }

            return attempts;
        }
        finally
        {
            _smsGate.Release();
        }
    }

    public async Task<bool> TryCompletePhoneChallengeAsync(Guid accountId, string phoneE164, string codeHash, DateTimeOffset verifiedAt, int maxAttempts, CancellationToken cancellationToken)
    {
        await _smsGate.WaitAsync(cancellationToken);
        try
        {
            if (!_phoneChallenges.TryGetValue(accountId, out var challenge)
                || challenge.PhoneE164 != phoneE164
                || challenge.CodeHash != codeHash
                || challenge.ExpiresAt <= verifiedAt
                || challenge.Attempts >= maxAttempts)
            {
                return false;
            }

            if (_accounts.Values.Any(account => account.Id != accountId
                && account.PhoneE164 == phoneE164 && account.PhoneVerifiedAt is not null))
            {
                throw TrustException.PhoneInUse();
            }

            if (_accounts.TryGetValue(accountId, out var account))
            {
                _accounts[accountId] = account with { PhoneE164 = phoneE164, PhoneVerifiedAt = verifiedAt };
                _phoneChallenges.TryRemove(accountId, out _);
                return true;
            }

            return false;
        }
        finally
        {
            _smsGate.Release();
        }
    }

    public Task<SmsSendBudget?> GetSmsSendBudgetAsync(string scopeKey, CancellationToken cancellationToken)
    {
        _smsBudgets.TryGetValue(scopeKey, out var budget);
        return Task.FromResult(budget);
    }

    public Task UpsertSmsSendBudgetAsync(SmsSendBudget budget, CancellationToken cancellationToken)
    {
        _smsBudgets[budget.ScopeKey] = budget;
        return Task.CompletedTask;
    }

    private static (Guid A, Guid B) Order(Guid a, Guid b) =>
        a.CompareTo(b) < 0 ? (a, b) : (b, a);
}
