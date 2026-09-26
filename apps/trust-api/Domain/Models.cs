namespace TrustApi.Domain;

public static class TrustRules
{
    /// Free person-screen history. Plus reads <see cref="ProHistoryDays"/>.
    public const int FreeHistoryHours = 24;
    public const int ProHistoryDays = 30;
    public static TimeSpan HistoryWindow(bool hasPlus) =>
        hasPlus ? TimeSpan.FromDays(ProHistoryDays) : TimeSpan.FromHours(FreeHistoryHours);
    public static int HistoryWindowHours(bool hasPlus) =>
        hasPlus ? ProHistoryDays * 24 : FreeHistoryHours;
    /// Free: <=5 (per the product model). Plus (née Circle): <=20.
    public const int FreeSeats = 5;
    public const int ProSeats = 20;
    public const int FreeLookLogDays = 30;
    public const int ProLookLogDays = 365;
    /// How long GPS is stored while any outbound share is Sealed, Always, or Paused.
    /// Off (and an empty circle) drops the trail. This is not a 3-hour prune.
    public static readonly TimeSpan LocationRetention = TimeSpan.FromDays(ProHistoryDays);
    /// If last home/away signal is older than this at a promise deadline, copy is "no signal".
    public static readonly TimeSpan PresenceSignalStale = TimeSpan.FromMinutes(30);
    /// View (Available) log entries dedupe within this window so re-opening the same person's
    /// live view repeatedly doesn't flood the view log.
    public static readonly TimeSpan ViewDedupeWindow = TimeSpan.FromMinutes(30);
    /// Invite codes are single-use-ish but also time-boxed for hygiene.
    public static readonly TimeSpan InviteValidity = TimeSpan.FromDays(7);
    public static readonly TimeSpan ConnectionRequestValidity = TimeSpan.FromDays(7);
    public static readonly TimeSpan ConnectionRequestDeclineCooldown = TimeSpan.FromDays(7);
}

public enum HomePresenceState
{
    Unknown,
    Home,
    Away,
    /// Deliberately hidden from the circle. Distinct from Unknown (no signal yet).
    Hidden
}

public enum PromiseStatus
{
    Active,
    Resolved,
    Overdue,
    NoSignal
}

public sealed record PresenceGrant(
    Guid SubjectId,
    Guid TrusteeId,
    bool Enabled,
    DateTimeOffset UpdatedAt);

public sealed record HomePlace(
    Guid AccountId,
    Guid PlaceId,
    string Label,
    DateTimeOffset UpdatedAt);

public sealed record CurrentHomePresence(
    Guid AccountId,
    Guid? PlaceId,
    HomePresenceState State,
    DateTimeOffset LastChangedAt,
    DateTimeOffset? LastSignalAt);

public sealed record HomePromise(
    Guid Id,
    Guid SubjectId,
    Guid TrusteeId,
    Guid PlaceId,
    DateTimeOffset DeadlineAt,
    PromiseStatus Status,
    DateTimeOffset? ResolvedAt,
    DateTimeOffset CreatedAt);

public sealed record LookResult(LookSession Session, bool IsNew);

/// <summary>Public metadata for the account's one current profile image.</summary>
public sealed record ProfileAvatar(string Kind, string? PresetId = null, Guid? Version = null);

public static class AccountIdentity
{
    public const int DisplayNameMinLength = 2;
    public const int DisplayNameMaxLength = 40;

    public static bool IsChosenDisplayName(string? displayName)
    {
        var trimmed = displayName?.Trim() ?? "";
        return trimmed.Length >= DisplayNameMinLength
            && trimmed.Length <= DisplayNameMaxLength
            && !string.Equals(trimmed, "You", StringComparison.OrdinalIgnoreCase);
    }
}

public static class AccountHandle
{
    public const int MinLength = 3;
    public const int MaxLength = 20;

    private static readonly System.Text.RegularExpressions.Regex Pattern = new(
        "^[a-z][a-z0-9_]{2,19}$",
        System.Text.RegularExpressions.RegexOptions.Compiled | System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    private static readonly HashSet<string> Reserved = new(StringComparer.Ordinal)
    {
        "about", "account", "admin", "administrator", "api", "apple",
        "bot", "circle", "collapse", "collapsetechnologies",
        "everyone", "google", "help", "here", "invite", "look",
        "login", "me", "mod", "moderator", "null", "official", "owner",
        "privacy", "root", "settings", "signin", "signout", "signup",
        "staff", "status", "support", "system", "terms", "trust",
        "trustcircle", "www", "you"
    };

    public static string Normalize(string? raw)
    {
        var value = (raw ?? "").Trim();
        if (value.StartsWith('@'))
        {
            value = value[1..].Trim();
        }

        return value.ToLowerInvariant();
    }

    public static bool TryValidate(string? raw, out string normalized, out string? errorCode)
    {
        normalized = Normalize(raw);
        if (!Pattern.IsMatch(normalized))
        {
            errorCode = "invalid_handle";
            return false;
        }

        if (Reserved.Contains(normalized))
        {
            errorCode = "reserved_handle";
            return false;
        }

        errorCode = null;
        return true;
    }

    public static bool IsChosen(string? handle) =>
        TryValidate(handle, out _, out _);
}

public sealed record Account(
    Guid Id,
    string Provider,
    string ProviderSubject,
    string DisplayName,
    bool HasCircle,
    string? CircleSource,
    DateTimeOffset CreatedAt,
    string? PhoneE164 = null,
    DateTimeOffset? PhoneVerifiedAt = null,
    string? Handle = null,
    ProfileAvatar? Avatar = null)
{
    public bool HasChosenDisplayName => AccountIdentity.IsChosenDisplayName(DisplayName);

    public bool HasVerifiedPhone =>
        !string.IsNullOrWhiteSpace(PhoneE164) && PhoneVerifiedAt is not null;

    public bool HasHandle => AccountHandle.IsChosen(Handle);

    public bool OnboardingComplete => HasHandle && HasVerifiedPhone;

    public string PublicName => HasHandle ? $"@{Handle}" : DisplayName;
}

public sealed record HandleAvailability(string Handle, bool Available, string? Code);

public enum ConnectionRequestStatus { Pending, Accepted, Declined, Cancelled, Expired }

public sealed record ConnectionRequest(
    Guid Id, Guid SenderId, Guid RecipientId, ConnectionRequestStatus Status,
    DateTimeOffset CreatedAt, DateTimeOffset ExpiresAt, DateTimeOffset UpdatedAt);

/// Internal request row joined to the other party. API contracts deliberately map only ID/handle.
public sealed record ConnectionRequestEntry(ConnectionRequest Request, Account OtherParty);

public sealed record ConnectionRequestLists(
    IReadOnlyList<ConnectionRequestEntry> Incoming,
    IReadOnlyList<ConnectionRequestEntry> Sent);

public enum ConnectionRelationship { None, Connected, Sent, Incoming }
public sealed record ConnectionRelationshipMatch(ConnectionRelationship Relationship, Guid? RequestId = null);
public sealed record PersonLookup(Guid AccountId, string Handle, ConnectionRelationship Relationship, Guid? RequestId);

public sealed record PhoneChallenge(
    Guid AccountId,
    string PhoneE164,
    string CodeHash,
    DateTimeOffset ExpiresAt,
    int Attempts,
    DateTimeOffset SentAt,
    int SendCount,
    DateTimeOffset WindowStartedAt);

/// SMS budget for verification texts. Account and phone keys roll every hour.
/// Account-day and global-day keys roll every 24 hours.
public sealed record SmsSendBudget(
    string ScopeKey,
    DateTimeOffset WindowStartedAt,
    int SendCount,
    DateTimeOffset? LastSentAt)
{
    public static string AccountKey(Guid accountId) => $"account:{accountId:N}";

    public static string AccountDayKey(Guid accountId) => $"account-day:{accountId:N}";

    public static string PhoneKey(string e164) => $"phone:{e164}";

    public static string GlobalDayKey() => "global-day";
}

public sealed record Presence(
    DateTimeOffset LastActiveAt,
    int BatteryPercent,
    bool IsCharging,
    DateTimeOffset? GotHomeAt,
    DateTimeOffset? CheckedInAt);

public sealed record LocationFix(
    DateTimeOffset Timestamp,
    double Latitude,
    double Longitude);

public enum ShareResting
{
    /// Not sharing at all. The default for both sides of a fresh join.
    Off,
    UntilTheyLook,
    Always,
    /// Temporarily not revealing. <see cref="ShareState.RestoresTo"/> returns when the timer ends.
    Paused
}

public sealed record ShareState(
    ShareResting Resting,
    DateTimeOffset? PauseUntil = null,
    ShareResting? RestoresTo = null)
{
    /// Join default is Off/Off — invite is not permission.
    public static ShareState Default { get; } = new(ShareResting.Off);

    /// Mode a reader should use. An expired pause behaves as the restored mode
    /// even if the sweep has not rewritten the row yet.
    public ShareResting Effective(DateTimeOffset now)
    {
        if (Resting != ShareResting.Paused)
        {
            return Resting;
        }

        if (PauseUntil is { } until && until > now)
        {
            return ShareResting.Paused;
        }

        return RestoresTo == ShareResting.Always ? ShareResting.Always : ShareResting.UntilTheyLook;
    }

    public SharePresentation Presentation(DateTimeOffset now) => Effective(now) switch
    {
        ShareResting.Always => SharePresentation.Always.Instance,
        ShareResting.Off => SharePresentation.Off.Instance,
        ShareResting.Paused => new SharePresentation.Paused(
            PauseUntil ?? now,
            RestoresTo == ShareResting.Always ? ShareResting.Always : ShareResting.UntilTheyLook),
        _ => SharePresentation.UntilTheyLook.Instance
    };

    public bool RevealsLive(DateTimeOffset now) => Effective(now) == ShareResting.Always;

    /// Sealed and Always upload. Pause keeps the existing trail but does not add points. Off does not.
    public bool AcceptsLocation(DateTimeOffset now)
    {
        var mode = Effective(now);
        return mode is ShareResting.Always or ShareResting.UntilTheyLook;
    }

    /// Ongoing trail reads are available only in Always. Sealed grants a confirmed snapshot via Look.
    public bool SharesHistory(DateTimeOffset now) => Effective(now) == ShareResting.Always;

    /// Paused still holds the trail so restore is not empty. Off does not.
    public bool KeepsTrail(DateTimeOffset now)
    {
        var mode = Effective(now);
        return mode is ShareResting.Always or ShareResting.UntilTheyLook or ShareResting.Paused;
    }
}

public abstract record SharePresentation
{
    public sealed record Off : SharePresentation
    {
        public static Off Instance { get; } = new();
    }

    public sealed record UntilTheyLook : SharePresentation
    {
        public static UntilTheyLook Instance { get; } = new();
    }

    public sealed record Always : SharePresentation
    {
        public static Always Instance { get; } = new();
    }

    public sealed record Paused(DateTimeOffset Ends, ShareResting RevertsTo) : SharePresentation;
}

public sealed record Invite(
    Guid Id,
    string Code,
    Guid CreatorId,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ExpiresAt = null);

public enum LookKind
{
    Look,
    View,
    /// The pair was revoked. Not a location read.
    Removed
}

public sealed record LookEvent(
    Guid Id,
    Guid ViewerId,
    string ViewerName,
    Guid SubjectId,
    string SubjectName,
    DateTimeOffset At,
    int HistoryWindowHours,
    bool IncludedLive,
    LookKind Kind = LookKind.Look);

public sealed record LookSession(
    LookEvent Event,
    LocationFix Live,
    IReadOnlyList<LocationFix> Trail);

public sealed record VisibleHomePresence(
    HomePresenceState State,
    DateTimeOffset ChangedAt,
    string? PlaceLabel);

public sealed record PromiseView(
    Guid Id,
    Guid SubjectId,
    Guid TrusteeId,
    string PlaceLabel,
    DateTimeOffset DeadlineAt,
    PromiseStatus Status,
    DateTimeOffset? ResolvedAt,
    bool YouAreSubject);

public sealed record CircleMember(
    Account Person,
    Presence? Presence,
    ShareState OutboundShare,
    ShareState InboundShare,
    bool InboundLive,
    LocationFix? Live,
    bool OutboundPresenceGranted,
    bool InboundPresenceGranted,
    VisibleHomePresence? HomePresence,
    PromiseView? Promise);

public sealed record CircleSnapshot(
    Account You,
    IReadOnlyList<CircleMember> Members,
    CircleCoverage Coverage,
    Invite? PendingInvite,
    /// Always null. A Look is the snapshot returned by POST /looks, not an open session.
    LookSession? ActiveSession,
    /// Always null. The receipt is the push, not a lingering watched state.
    LookEvent? BeingWatched,
    IReadOnlyList<LookEvent> LookLog,
    int RetainedLookLogCount,
    HomePlace? YourHomePlace,
    CurrentHomePresence? YourHomePresence);

public sealed record CircleCoverage(
    bool IsCovered,
    string? SponsorName,
    bool ActingIsSponsor)
{
    public int SeatLimit => IsCovered ? TrustRules.ProSeats : TrustRules.FreeSeats;
    public int LookLogDays => IsCovered ? TrustRules.ProLookLogDays : TrustRules.FreeLookLogDays;
    public bool HasPlacePings => IsCovered;
    public bool CanExtendHistory => IsCovered;
    public bool CanExportLookLog => IsCovered;

    /// Plus is this account only. A friend's Plus never produces a banner here.
    public string? Banner => IsCovered && ActingIsSponsor ? "Plus is on this account" : null;
}

public enum PauseDuration
{
    OneHour,
    EightHours,
    OneDay,
    TwoDays,
    ThreeDays
}

public static class PauseShare
{
    public static DateTimeOffset EndAt(PauseDuration duration, DateTimeOffset now) => duration switch
    {
        PauseDuration.OneHour => now.AddHours(1),
        PauseDuration.EightHours => now.AddHours(8),
        PauseDuration.OneDay => now.AddDays(1),
        PauseDuration.TwoDays => now.AddDays(2),
        PauseDuration.ThreeDays => now.AddDays(3),
        _ => now.AddHours(1)
    };
}

public sealed class TrustException : Exception
{
    public string Code { get; }

    public TrustException(string code, string message) : base(message)
    {
        Code = code;
    }

    public static TrustException ConfirmationRequired() =>
        new("confirmation_required", "Looking requires an explicit confirm.");

    public static TrustException NotConnected() =>
        new("not_connected", "This person is not connected to you.");

    public static TrustException PairInactive() =>
        new("pair_inactive", "This pair is no longer active.");

    public static TrustException InvalidCode() =>
        new("invalid_code", "That invite code does not match.");

    public static TrustException SeatLimit() =>
        new("seat_limit", "Free includes up to five trusted people. Plus adds seats.");

    public static TrustException ProRequired() =>
        new("pro_required", "Plus is required for this.");

    public static TrustException NoLocation() =>
        new("no_location", "Getting location.");

    public static TrustException ShareOff() =>
        new("share_off", "This person has sharing off.");

    public static TrustException LookRequiresSealed() =>
        new("look_requires_sealed", "This person is Available. Open View instead of Look.");

    public static TrustException ViewRequiresAvailable() =>
        new("view_requires_available", "This person isn't sharing live location right now.");

    public static TrustException Unauthorized() =>
        new("unauthorized", "Sign in is required.");

    public static TrustException InvalidPhone() =>
        new("invalid_phone", "Enter a valid phone number, including country code.");

    public static TrustException OtpNotConfigured() =>
        new("otp_not_configured", "Phone verification is not configured on this server.");

    public static TrustException OtpCooldown() =>
        new("otp_cooldown", "Wait a moment before requesting another code.");

    public static TrustException OtpExpired() =>
        new("otp_expired", "That code expired. Request a new one.");

    public static TrustException OtpInvalid() =>
        new("otp_invalid", "That code does not match.");

    public static TrustException OtpExhausted() =>
        new("otp_exhausted", "Too many attempts. Request a new code.");

    public static TrustException OtpSendFailed() =>
        new("otp_send_failed", "Trust could not send a text. Try again.");

    public static TrustException PhoneInUse() =>
        new("phone_in_use", "That phone is already on another Trust account.");

    public static TrustException PhoneUnavailable() =>
        new("phone_unavailable", "This number can't be used for this account.");

    public static TrustException OwnPhone() =>
        new("own_phone", "That number is already on this account.");

    public static TrustException InvalidHandle() =>
        new("invalid_handle", "That handle isn’t valid.");

    public static TrustException ReservedHandle() =>
        new("reserved_handle", "That handle is reserved.");

    public static TrustException HandleInUse() =>
        new("handle_in_use", "That handle is taken.");

    public static TrustException RequestNotFound() =>
        new("request_not_found", "That request is no longer available.");

    public static TrustException RequestExpired() =>
        new("request_expired", "That request has expired.");

    public static TrustException RequestDeclinedRecently() =>
        new("request_declined_recently", "Wait before sending another request to this person.");

    public static TrustException RequestLimit() =>
        new("request_limit", "You have reached the current request limit. Try again later.");

    public static TrustException PhoneVerificationRequired() =>
        new("verification_required", "Verify your phone before finding people and sending connection requests.");
}

public interface ITrustStore
{
    Task<Account?> FindAccountAsync(Guid id, CancellationToken cancellationToken);
    Task<Account?> FindByProviderAsync(string provider, string subject, CancellationToken cancellationToken);
    Task<Account> UpsertAccountAsync(Account account, CancellationToken cancellationToken);
    Task UpdateAccountAsync(Account account, CancellationToken cancellationToken);
    Task<ProfileAvatar> SetAvatarPresetAsync(Guid accountId, string presetId, CancellationToken cancellationToken);
    Task<ProfileAvatar> SetAvatarPhotoAsync(Guid accountId, Guid version, byte[] jpeg, CancellationToken cancellationToken);
    Task ClearAvatarAsync(Guid accountId, CancellationToken cancellationToken);
    Task<byte[]?> GetAvatarPhotoAsync(Guid accountId, Guid version, CancellationToken cancellationToken);
    Task<IReadOnlyList<Account>> ListConnectedAsync(Guid accountId, CancellationToken cancellationToken);
    Task<int> ActiveMembershipCountAsync(Guid accountId, CancellationToken cancellationToken);
    Task<bool> AreConnectedAsync(Guid a, Guid b, CancellationToken cancellationToken);
    Task InsertMembershipAsync(Guid a, Guid b, CancellationToken cancellationToken);
    Task<bool> ConnectAccountsWithOffSharesAsync(Guid a, Guid b, DateTimeOffset now, CancellationToken cancellationToken);
    Task RevokeMembershipAsync(Guid a, Guid b, CancellationToken cancellationToken);
    Task<ShareState> GetShareAsync(Guid grantor, Guid grantee, CancellationToken cancellationToken);
    Task UpsertShareAsync(Guid grantor, Guid grantee, ShareState state, CancellationToken cancellationToken);
    /// Rewrites expired pauses back to <see cref="ShareState.RestoresTo"/>.
    Task RestoreExpiredPausesAsync(DateTimeOffset now, CancellationToken cancellationToken);
    Task<Presence> GetPresenceAsync(Guid accountId, DateTimeOffset fallbackNow, CancellationToken cancellationToken);
    Task UpsertPresenceAsync(Guid accountId, Presence presence, CancellationToken cancellationToken);
    Task IngestLocationAsync(Guid accountId, LocationFix fix, CancellationToken cancellationToken);
    Task PruneLocationsAsync(Guid accountId, DateTimeOffset olderThan, CancellationToken cancellationToken);
    Task ClearLocationsAsync(Guid accountId, CancellationToken cancellationToken);
    Task<IReadOnlyList<LocationFix>> UnlockLocationsAsync(
        Guid accountId,
        DateTimeOffset from,
        DateTimeOffset to,
        CancellationToken cancellationToken);
    Task<LocationFix?> LatestLocationAsync(Guid accountId, CancellationToken cancellationToken);
    Task InsertLookEventAsync(LookEvent look, CancellationToken cancellationToken);
    Task<IReadOnlyList<LookEvent>> ListLooksAsync(
        Guid accountId,
        DateTimeOffset since,
        CancellationToken cancellationToken);
    Task<int> LooksTodayAsync(Guid viewerId, DateTimeOffset startOfDay, CancellationToken cancellationToken);
    Task PruneAllLocationsAsync(DateTimeOffset olderThan, CancellationToken cancellationToken);
    Task<Invite?> FindInviteByCodeAsync(string code, CancellationToken cancellationToken);
    Task<Invite?> FindPendingInviteAsync(Guid creatorId, CancellationToken cancellationToken);
    Task InsertInviteAsync(Invite invite, CancellationToken cancellationToken);
    Task MarkInviteConsumedAsync(Guid inviteId, CancellationToken cancellationToken);
    Task AcceptInviteConnectionAsync(Guid inviteId, Guid joiningAccountId, DateTimeOffset now, CancellationToken cancellationToken);
    Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken);
    Task<Account?> FindByVerifiedPhoneAsync(string phoneE164, CancellationToken cancellationToken);
    Task SetVerifiedPhoneAsync(Guid accountId, string phoneE164, DateTimeOffset verifiedAt, CancellationToken cancellationToken);
    Task<Account?> FindByHandleAsync(string handle, CancellationToken cancellationToken);
    Task<ConnectionRelationshipMatch> GetConnectionRelationshipAsync(Guid accountId, Guid otherId, DateTimeOffset now, CancellationToken cancellationToken);
    Task<ConnectionRequestLists> ListConnectionRequestsAsync(Guid accountId, DateTimeOffset now, CancellationToken cancellationToken);
    Task ExpireConnectionRequestsAsync(DateTimeOffset now, CancellationToken cancellationToken);
    Task PruneConnectionRequestsAsync(DateTimeOffset terminalBefore, CancellationToken cancellationToken);
    Task<ConnectionRequest> CreateConnectionRequestAsync(Guid senderId, Guid recipientId, DateTimeOffset now, CancellationToken cancellationToken);
    Task AcceptConnectionRequestAsync(Guid requestId, Guid recipientId, DateTimeOffset now, CancellationToken cancellationToken);
    Task DeclineConnectionRequestAsync(Guid requestId, Guid recipientId, DateTimeOffset now, CancellationToken cancellationToken);
    Task CancelConnectionRequestAsync(Guid requestId, Guid senderId, DateTimeOffset now, CancellationToken cancellationToken);
    Task SetHandleAsync(Guid accountId, string handle, string displayName, CancellationToken cancellationToken);
    Task<PhoneChallenge?> GetPhoneChallengeAsync(Guid accountId, CancellationToken cancellationToken);
    Task UpsertPhoneChallengeAsync(PhoneChallenge challenge, CancellationToken cancellationToken);
    Task ClearPhoneChallengeAsync(Guid accountId, CancellationToken cancellationToken);
    Task<bool> TryReserveSmsAsync(IReadOnlyList<SmsSendBudget> budgets, DateTimeOffset now, CancellationToken cancellationToken);
    Task<int?> IncrementPhoneChallengeFailureAsync(Guid accountId, string phoneE164, DateTimeOffset now, int maxAttempts, CancellationToken cancellationToken);
    Task<bool> TryCompletePhoneChallengeAsync(Guid accountId, string phoneE164, string codeHash, DateTimeOffset verifiedAt, int maxAttempts, CancellationToken cancellationToken);
    Task<SmsSendBudget?> GetSmsSendBudgetAsync(string scopeKey, CancellationToken cancellationToken);
    Task UpsertSmsSendBudgetAsync(SmsSendBudget budget, CancellationToken cancellationToken);

    Task SetPresenceGrantAsync(Guid subjectId, Guid trusteeId, bool enabled, DateTimeOffset updatedAt, CancellationToken cancellationToken);
    Task<PresenceGrant?> GetPresenceGrantAsync(Guid subjectId, Guid trusteeId, CancellationToken cancellationToken);
    Task UpsertHomePlaceAsync(HomePlace place, CancellationToken cancellationToken);
    Task<HomePlace?> GetHomePlaceAsync(Guid accountId, CancellationToken cancellationToken);
    Task UpsertCurrentHomePresenceAsync(CurrentHomePresence presence, CancellationToken cancellationToken);
    Task<CurrentHomePresence?> GetCurrentHomePresenceAsync(Guid accountId, CancellationToken cancellationToken);
    Task InsertPromiseAsync(HomePromise promise, CancellationToken cancellationToken);
    Task UpdatePromiseAsync(HomePromise promise, CancellationToken cancellationToken);
    Task<HomePromise?> GetPromiseAsync(Guid promiseId, CancellationToken cancellationToken);
    Task<HomePromise?> GetActivePromiseAsync(Guid subjectId, Guid trusteeId, CancellationToken cancellationToken);
    Task<IReadOnlyList<HomePromise>> ListPromisesForPairAsync(Guid a, Guid b, CancellationToken cancellationToken);
    Task<IReadOnlyList<HomePromise>> ListDuePromisesAsync(DateTimeOffset now, CancellationToken cancellationToken);
}
