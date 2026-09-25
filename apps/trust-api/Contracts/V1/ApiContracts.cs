using System.Text.Json.Serialization;
using TrustApi.Domain;

namespace TrustApi.Contracts.V1;

public sealed record SessionRequest(
    string? IdentityToken,
    string? IdToken,
    string? DisplayName,
    string? Provider,
    string? DeviceId,
    /// Optional SIWA replay-hygiene nonce: the same raw value the client set on
    /// ASAuthorizationAppleIDRequest.nonce, echoed back in the ID token's "nonce" claim.
    /// If omitted, the server skips the check (back-compat until the iOS client sends it).
    string? Nonce = null);

public sealed record SessionResponse(string Token, PersonDto You);

public sealed record PersonDto(
    Guid Id,
    string DisplayName,
    bool HasCircle,
    bool OnboardingComplete,
    bool PhoneVerified,
    string? Handle,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    AvatarDto? Avatar = null);

public sealed record AvatarDto(
    string Kind,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    string? PresetId = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    Guid? Version = null);

public sealed record SetAvatarPresetRequest(string PresetId);

public sealed record PresenceDto(
    DateTimeOffset LastActiveAt,
    int BatteryPercent,
    bool IsCharging,
    DateTimeOffset? GotHomeAt,
    DateTimeOffset? CheckedInAt);

public sealed record HomePresenceDto(
    string State,
    DateTimeOffset ChangedAt,
    string? PlaceLabel);

public sealed record PromiseDto(
    Guid Id,
    Guid SubjectId,
    Guid TrusteeId,
    string PlaceLabel,
    DateTimeOffset DeadlineAt,
    string Status,
    DateTimeOffset? ResolvedAt,
    bool YouAreSubject);

public sealed record HomePlaceDto(Guid PlaceId, string Label);

public sealed record YourHomeDto(
    HomePlaceDto? Place,
    string? State,
    DateTimeOffset? ChangedAt);

public sealed record LocationDto(
    DateTimeOffset Timestamp,
    double Latitude,
    double Longitude);

public sealed record ShareDto(
    string Resting,
    DateTimeOffset? PauseUntil,
    string Presentation,
    string? RevertsTo);

public sealed record MemberDto(
    PersonDto Person,
    PresenceDto? Presence,
    ShareDto Share,
    ShareDto InboundShare,
    bool InboundLive,
    LocationDto? Live,
    bool OutboundPresenceGranted,
    bool InboundPresenceGranted,
    HomePresenceDto? HomePresence,
    PromiseDto? Promise);

public sealed record CoverageDto(
    bool IsCovered,
    string? SponsorName,
    bool ActingIsSponsor,
    int SeatLimit,
    int LookLogDays,
    bool HasPlacePings,
    bool CanExtendHistory,
    bool CanExportLookLog,
    string? Banner);

public sealed record LookEventDto(
    Guid Id,
    Guid ViewerId,
    string ViewerName,
    Guid SubjectId,
    string SubjectName,
    DateTimeOffset At,
    int HistoryWindowHours,
    bool IncludedLive,
    string Kind);

public sealed record LookSessionDto(
    LookEventDto Event,
    LocationDto Live,
    IReadOnlyList<LocationDto> Trail);

public sealed record CircleResponse(
    PersonDto You,
    IReadOnlyList<MemberDto> Members,
    CoverageDto Coverage,
    string? PendingInviteCode,
    LookSessionDto? ActiveSession,
    LookEventDto? BeingWatched,
    IReadOnlyList<LookEventDto> LookLog,
    int RetainedLookLogCount,
    bool AllowsDevelopmentSignIn,
    bool AllowsReviewUnlock,
    YourHomeDto? YourHome);

public sealed record LocationIngestRequest(
    DateTimeOffset Timestamp,
    double Latitude,
    double Longitude,
    int? BatteryPercent,
    bool? IsCharging,
    IReadOnlyList<LocationDto>? Points);

public sealed record HistoryResponse(IReadOnlyList<LocationDto> Points);

public sealed record LookRequest(Guid SubjectId, bool Confirmed);

public sealed record ViewRequest(Guid SubjectId);

public sealed record ViewResponse(bool Logged, LookEventDto? Event);

public sealed record ShareRequest(string? Resting, string? Pause);

public sealed record PresenceGrantRequest(bool Enabled);

public sealed record SetHomePlaceRequest(Guid PlaceId, string? Label);

public sealed record HomePresenceRequest(string State, DateTimeOffset? SignaledAt);

public sealed record CreatePromiseRequest(Guid TrusteeId, DateTimeOffset DeadlineAt);

public sealed record InviteAcceptRequest(string Code);

public sealed record RenameRequest(string DisplayName);

public sealed record SetHandleRequest(string Handle);

public sealed record HandleAvailabilityResponse(
    string Handle,
    bool Available,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    string? Code);

public sealed record SendPhoneCodeRequest(string Phone);

public sealed record VerifyPhoneCodeRequest(string Phone, string Code);

public sealed record AddPersonByPhoneRequest(string Phone);

public sealed record AddPersonByPhoneResponse(
    string Outcome,
    bool SmsSent,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    string? DevelopmentCode);

public sealed record SendPhoneCodeResponse(
    DateTimeOffset ExpiresAt,
    int ResendAfterSeconds,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    string? DevelopmentCode);

public sealed record EntitlementRequest(string? ProductId, bool ReviewUnlock, string? SignedTransactionInfo);

public sealed record StoreKitAccountTokenResponse(Guid AppAccountToken);

public sealed record VerifyStoreKitTransactionRequest(string SignedTransactionInfo);

public sealed record StoreKitNotificationRequest(string SignedPayload);

public sealed record PushDeviceRequest(
    Guid InstallationId,
    string Token,
    string Environment,
    string BundleId);

public sealed record CheckoutRequest(string Interval);

public sealed record CheckoutResponse(string Url);

public sealed record ApiError(string Code, string Message);

public static class ContractMap
{
    public static PersonDto Person(Account account) =>
        new(account.Id, account.DisplayName, account.HasCircle, account.OnboardingComplete, account.HasVerifiedPhone, account.Handle,
            account.Avatar is null ? null : new AvatarDto(account.Avatar.Kind, account.Avatar.PresetId, account.Avatar.Version));

    public static PresenceDto? Presence(Presence? presence) =>
        presence is null
            ? null
            : new(
                presence.LastActiveAt,
                presence.BatteryPercent,
                presence.IsCharging,
                presence.GotHomeAt,
                presence.CheckedInAt);

    public static HomePresenceDto? HomePresence(VisibleHomePresence? presence) =>
        presence is null
            ? null
            : new(HomeStateName(presence.State), presence.ChangedAt, presence.PlaceLabel);

    public static PromiseDto? Promise(PromiseView? promise) =>
        promise is null
            ? null
            : new(
                promise.Id,
                promise.SubjectId,
                promise.TrusteeId,
                promise.PlaceLabel,
                promise.DeadlineAt,
                PromiseStatusName(promise.Status),
                promise.ResolvedAt,
                promise.YouAreSubject);

    public static YourHomeDto YourHome(HomePlace? place, CurrentHomePresence? presence) =>
        new(
            place is null ? null : new HomePlaceDto(place.PlaceId, place.Label),
            presence is null ? null : HomeStateName(presence.State),
            presence?.LastChangedAt);

    public static LocationDto? Location(LocationFix? fix) =>
        fix is null ? null : new LocationDto(fix.Timestamp, fix.Latitude, fix.Longitude);

    public static LocationDto LocationRequired(LocationFix fix) =>
        new(fix.Timestamp, fix.Latitude, fix.Longitude);

    public static IReadOnlyList<LocationFix> IngestFixes(LocationIngestRequest request)
    {
        if (request.Points is { Count: > 0 })
        {
            return request.Points
                .Select(point => new LocationFix(point.Timestamp, point.Latitude, point.Longitude))
                .ToList();
        }

        return [new LocationFix(request.Timestamp, request.Latitude, request.Longitude)];
    }

    public static ShareDto Share(ShareState state, DateTimeOffset now)
    {
        var presentation = state.Presentation(now);
        return presentation switch
        {
            SharePresentation.Always => new ShareDto("always", null, "always", null),
            SharePresentation.Off => new ShareDto("off", null, "off", null),
            SharePresentation.Paused paused => new ShareDto(
                "paused",
                paused.Ends,
                "paused",
                RestingName(paused.RevertsTo)),
            _ => new ShareDto("untilTheyLook", null, "untilTheyLook", null)
        };
    }

    public static LookEventDto Look(LookEvent look) =>
        new(
            look.Id,
            look.ViewerId,
            look.ViewerName,
            look.SubjectId,
            look.SubjectName,
            look.At,
            look.HistoryWindowHours,
            look.IncludedLive,
            LookKindName(look.Kind));

    public static LookSessionDto Session(LookSession session) =>
        new(
            Look(session.Event),
            LocationRequired(session.Live),
            session.Trail.Select(LocationRequired).ToList());

    public static CoverageDto Coverage(CircleCoverage coverage) =>
        new(
            coverage.IsCovered,
            coverage.SponsorName,
            coverage.ActingIsSponsor,
            coverage.SeatLimit,
            coverage.LookLogDays,
            coverage.HasPlacePings,
            coverage.CanExtendHistory,
            coverage.CanExportLookLog,
            coverage.Banner);

    public static CircleResponse Circle(
        CircleSnapshot snapshot,
        bool allowsDevelopmentSignIn,
        bool allowsReviewUnlock,
        DateTimeOffset now) =>
        new(
            Person(snapshot.You),
            snapshot.Members.Select(member => new MemberDto(
                Person(member.Person),
                Presence(member.Presence),
                Share(member.OutboundShare, now),
                Share(member.InboundShare, now),
                member.InboundLive,
                Location(member.Live),
                member.OutboundPresenceGranted,
                member.InboundPresenceGranted,
                HomePresence(member.HomePresence),
                Promise(member.Promise))).ToList(),
            Coverage(snapshot.Coverage),
            snapshot.PendingInvite?.Code,
            snapshot.ActiveSession is null ? null : Session(snapshot.ActiveSession),
            snapshot.BeingWatched is null ? null : Look(snapshot.BeingWatched),
            snapshot.LookLog.Select(Look).ToList(),
            snapshot.RetainedLookLogCount,
            allowsDevelopmentSignIn,
            allowsReviewUnlock,
            YourHome(snapshot.YourHomePlace, snapshot.YourHomePresence));

    public static ShareResting? ParseResting(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "always" => ShareResting.Always,
        "untiltheylook" or "until_they_look" or "sealed" => ShareResting.UntilTheyLook,
        "off" => ShareResting.Off,
        "paused" => ShareResting.Paused,
        null or "" => null,
        _ => null
    };

    public static PauseDuration? ParsePause(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "1h" or "hour" or "1hour" or "onehour" => PauseDuration.OneHour,
        "8h" or "8hours" or "eighthours" => PauseDuration.EightHours,
        "1d" or "1day" or "day" or "oneday" => PauseDuration.OneDay,
        "2d" or "2days" or "twodays" => PauseDuration.TwoDays,
        "3d" or "3days" or "threedays" => PauseDuration.ThreeDays,
        null or "" => null,
        _ => null
    };

    public static HomePresenceState? ParseHomeState(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "home" => HomePresenceState.Home,
        "away" => HomePresenceState.Away,
        "hidden" => HomePresenceState.Hidden,
        "unknown" => HomePresenceState.Unknown,
        null or "" => null,
        _ => null
    };

    private static string RestingName(ShareResting resting) => resting switch
    {
        ShareResting.Always => "always",
        ShareResting.Off => "off",
        ShareResting.Paused => "paused",
        _ => "untilTheyLook"
    };

    private static string HomeStateName(HomePresenceState state) => state switch
    {
        HomePresenceState.Home => "home",
        HomePresenceState.Away => "away",
        HomePresenceState.Hidden => "hidden",
        _ => "unknown"
    };

    private static string LookKindName(LookKind kind) => kind switch
    {
        LookKind.View => "view",
        LookKind.Removed => "removed",
        _ => "look"
    };

    private static string PromiseStatusName(PromiseStatus status) => status switch
    {
        PromiseStatus.Resolved => "resolved",
        PromiseStatus.Overdue => "overdue",
        PromiseStatus.NoSignal => "no_signal",
        _ => "active"
    };
}
