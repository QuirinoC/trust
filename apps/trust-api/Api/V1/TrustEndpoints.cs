using System.Security.Claims;
using System.Buffers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Hosting;
using Microsoft.IdentityModel.Tokens;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Notifications;
using TrustApi.Infrastructure.StoreKit;
using SkiaSharp;

namespace TrustApi.Api.V1;

public static class TrustEndpoints
{
    private const int AvatarUploadMaxBytes = 1024 * 1024;
    private const int AvatarDimensionMin = 64;
    private const int AvatarDimensionMax = 1024;
    private static readonly HashSet<string> AvatarPresetIds = new(StringComparer.Ordinal)
    {
        "fern", "ember", "sky", "ocean", "sunrise", "lavender",
        "moon", "star", "cloud", "raindrop", "rainbow", "mountain",
        "river", "meadow", "clover", "bloom", "cherry", "lotus",
        "mushroom", "seashell", "coral", "butterfly", "hummingbird", "fox",
        "whale", "koi", "rabbit", "bear", "cat", "dog",
        "otter", "owl", "turtle", "siamese", "ragdoll", "british-shorthair"
    };

    public static IEndpointRouteBuilder MapTrustApiV1(this IEndpointRouteBuilder endpoints)
    {
        var api = endpoints.MapGroup("/api/v1");
        api.MapPost("/session/apple", AppleSessionAsync).RequireRateLimiting(RateLimitPolicies.Auth);
        api.MapPost("/session/google", GoogleSessionAsync).RequireRateLimiting(RateLimitPolicies.Auth);
        api.MapPost("/session/development", DevelopmentSessionAsync).RequireRateLimiting(RateLimitPolicies.Auth);

        var auth = api.MapGroup(string.Empty).RequireAuthorization();
        auth.MapGet("/circle", GetCircleAsync);
        auth.MapPut("/me/avatar/preset", SetAvatarPresetAsync);
        auth.MapPut("/me/avatar/photo", SetAvatarPhotoAsync).RequireRateLimiting(RateLimitPolicies.Avatar);
        auth.MapDelete("/me/avatar", ClearAvatarAsync);
        auth.MapPatch("/me", RenameAsync);
        auth.MapGet("/handles/available", CheckHandleAvailableAsync);
        auth.MapPut("/me/handle", SetHandleAsync);
        auth.MapPost("/me/phone/send", SendPhoneCodeAsync).RequireRateLimiting(RateLimitPolicies.PhoneSend);
        auth.MapPost("/me/phone/verify", VerifyPhoneCodeAsync).RequireRateLimiting(RateLimitPolicies.PhoneVerify);
        auth.MapPost("/people/phone", AddPersonByPhoneAsync).RequireRateLimiting(RateLimitPolicies.Invite);
        auth.MapGet("/people/lookup", LookupPersonAsync);
        auth.MapGet("/connection-requests", ListConnectionRequestsAsync);
        auth.MapPost("/connection-requests", CreateConnectionRequestAsync);
        auth.MapPost("/connection-requests/{requestId:guid}/accept", AcceptConnectionRequestAsync);
        auth.MapPost("/connection-requests/{requestId:guid}/decline", DeclineConnectionRequestAsync);
        auth.MapDelete("/connection-requests/{requestId:guid}", CancelConnectionRequestAsync);
        auth.MapPost("/invites", CreateInviteAsync).RequireRateLimiting(RateLimitPolicies.Invite);
        auth.MapPost("/invites/accept", AcceptInviteAsync).RequireRateLimiting(RateLimitPolicies.Invite);
        auth.MapPatch("/people/{personId:guid}/share", SetShareAsync);
        auth.MapGet("/people/{personId:guid}/history", HistoryAsync);
        auth.MapGet("/people/{personId:guid}/avatar/{version:guid}", GetAvatarPhotoAsync);
        auth.MapPost("/people/{personId:guid}/revoke", RevokeAsync);
        auth.MapPost("/location", IngestAsync).RequireRateLimiting(RateLimitPolicies.Location);
        auth.MapPost("/looks", LookAsync).RequireRateLimiting(RateLimitPolicies.Look);
        auth.MapPost("/views", ViewAsync).RequireRateLimiting(RateLimitPolicies.Look);
        auth.MapPost("/presence/check-in", CheckInAsync);
        auth.MapPost("/presence/place-ping", PlacePingAsync);
        auth.MapPut("/people/{personId:guid}/presence-grant", SetPresenceGrantAsync);
        auth.MapPut("/me/home", SetHomePlaceAsync);
        auth.MapPost("/me/home/presence", PostHomePresenceAsync);
        auth.MapPost("/promises", CreatePromiseAsync);
        auth.MapPost("/circle/entitlement", EntitlementAsync);
        auth.MapGet("/storekit/account-token", StoreKitAccountTokenAsync);
        auth.MapPost("/storekit/transactions", VerifyStoreKitTransactionAsync);
        api.MapPost("/storekit/notifications", StoreKitNotificationAsync);
        auth.MapPost("/push/devices", RegisterPushDeviceAsync);
        auth.MapDelete("/push/devices/{installationId:guid}", RemovePushDeviceAsync);
        auth.MapDelete("/account", DeleteAccountAsync);
        auth.MapPost("/stripe/checkout", CheckoutAsync);
        return endpoints;
    }

    public static async Task<IResult> AppleSessionAsync(
        SessionRequest request,
        IAppleIdentityValidator apple,
        TrustEngine engine,
        SessionIssuer sessions,
        IOptions<TrustProductOptions> product,
        IOptions<AuthOptions> auth,
        ILogger<AppleIdentityValidator> logger,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.IdentityToken))
        {
            return Results.BadRequest(new ApiError("invalid_token", "Apple identityToken is required."));
        }

        try
        {
            var identity = await apple.ValidateAsync(request.IdentityToken, cancellationToken);
            if (!AppleNonceValidator.Matches(request.IdentityToken, request.Nonce))
            {
                return Results.Json(
                    new ApiError("invalid_apple_token", "Apple sign-in nonce did not match."),
                    statusCode: StatusCodes.Status401Unauthorized);
            }

            var name = string.IsNullOrWhiteSpace(request.DisplayName) ? identity.DisplayName : request.DisplayName;
            return await IssueAsync(engine, sessions, product.Value, identity.Provider, identity.Subject, name!, cancellationToken);
        }
        catch (Exception exception) when (IsAppleTokenFailure(exception) || IsAppleDirectoryFailure(exception))
        {
            if (auth.Value.AllowDevelopmentSignIn
                && ExternalIdentityTokens.TryReadUnverified(request.IdentityToken, "apple", out var unverified))
            {
                logger.LogWarning(
                    exception,
                    "Apple identity token failed verification; issuing a development session for subject {Subject}.",
                    unverified.Subject);
                var name = string.IsNullOrWhiteSpace(request.DisplayName) ? unverified.DisplayName : request.DisplayName;
                return await IssueAsync(engine, sessions, product.Value, unverified.Provider, unverified.Subject, name!, cancellationToken);
            }

            if (IsAppleDirectoryFailure(exception))
            {
                logger.LogWarning(exception, "Apple JWKS or OpenID discovery timed out.");
                return Results.Json(
                    new ApiError("apple_unavailable", "Apple sign-in timed out. Try again."),
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }

            logger.LogWarning(exception, "Apple identity token was rejected.");
            return Results.Json(
                new ApiError("invalid_apple_token", "Apple could not verify this sign-in. Try again."),
                statusCode: StatusCodes.Status401Unauthorized);
        }
    }

    public static async Task<IResult> GoogleSessionAsync(
        SessionRequest request,
        IGoogleIdentityValidator google,
        TrustEngine engine,
        SessionIssuer sessions,
        IOptions<TrustProductOptions> product,
        IOptions<AuthOptions> auth,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.IdToken))
        {
            try
            {
                var identity = await google.ValidateAsync(request.IdToken, cancellationToken);
                var name = string.IsNullOrWhiteSpace(request.DisplayName) ? identity.DisplayName : request.DisplayName;
                return await IssueAsync(engine, sessions, product.Value, identity.Provider, identity.Subject, name!, cancellationToken);
            }
            catch (Exception exception) when (exception is SecurityTokenException or InvalidOperationException)
            {
                return Results.Json(
                    new ApiError("google_unavailable", exception.Message),
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }
        }

        if (auth.Value.AllowDevelopmentSignIn)
        {
            return await DevelopmentSessionAsync(request, engine, sessions, product, auth, cancellationToken);
        }

        return Results.BadRequest(new ApiError("invalid_token", "Google idToken is required."));
    }

    public static async Task<IResult> DevelopmentSessionAsync(
        SessionRequest request,
        TrustEngine engine,
        SessionIssuer sessions,
        IOptions<TrustProductOptions> product,
        IOptions<AuthOptions> auth,
        CancellationToken cancellationToken)
    {
        if (!auth.Value.AllowDevelopmentSignIn)
        {
            return Results.NotFound();
        }

        var name = string.IsNullOrWhiteSpace(request.DisplayName) ? "You" : request.DisplayName.Trim();
        var provider = string.IsNullOrWhiteSpace(request.Provider) ? "development" : request.Provider.Trim().ToLowerInvariant();
        if (provider is not ("development" or "google" or "apple"))
        {
            provider = "development";
        }

        var subject = string.IsNullOrWhiteSpace(request.DeviceId)
            ? $"dev:{name.ToLowerInvariant()}"
            : $"dev:{request.DeviceId.Trim()}";
        return await IssueAsync(engine, sessions, product.Value, provider, subject, name, cancellationToken);
    }

    public static async Task<IResult> GetCircleAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        IOptions<AuthOptions> auth,
        IOptions<StoreKitOptions> storeKit,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            var snapshot = await engine.GetCircleAsync(accountId.Value, cancellationToken);
            return Results.Ok(ContractMap.Circle(
                snapshot,
                auth.Value.AllowDevelopmentSignIn,
                storeKit.Value.AllowReviewUnlock,
                DateTimeOffset.UtcNow));
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> RenameAsync(
        RenameRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        await engine.RenameAsync(accountId.Value, request.DisplayName, cancellationToken);
        return Results.NoContent();
    }

    public static async Task<IResult> SetAvatarPresetAsync(
        SetAvatarPresetRequest request,
        ClaimsPrincipal principal,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        if (request.PresetId is not { } presetId || !AvatarPresetIds.Contains(presetId))
        {
            return Results.BadRequest(new ApiError("invalid_avatar_preset", "Choose an available profile icon."));
        }

        var avatar = await store.SetAvatarPresetAsync(accountId.Value, presetId, cancellationToken);
        return Results.Ok(new AvatarDto(avatar.Kind, avatar.PresetId, avatar.Version));
    }

    public static async Task<IResult> SetAvatarPhotoAsync(
        HttpRequest request,
        ClaimsPrincipal principal,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        if (!string.Equals(request.ContentType?.Split(';', 2)[0].Trim(), "image/jpeg", StringComparison.OrdinalIgnoreCase))
        {
            return Results.StatusCode(StatusCodes.Status415UnsupportedMediaType);
        }
        if (request.ContentLength is > AvatarUploadMaxBytes)
        {
            return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);
        }

        var input = await ReadLimitedBodyAsync(request.Body, AvatarUploadMaxBytes, cancellationToken);
        if (input is null) return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);
        if (!TrySanitizeJpeg(input, out var sanitized))
        {
            return Results.BadRequest(new ApiError("invalid_avatar_image", "Upload a valid JPEG image between 64 and 1024 pixels on each side."));
        }

        var avatar = await store.SetAvatarPhotoAsync(accountId.Value, Guid.NewGuid(), sanitized, cancellationToken);
        return Results.Ok(new AvatarDto(avatar.Kind, avatar.PresetId, avatar.Version));
    }

    public static async Task<IResult> ClearAvatarAsync(
        ClaimsPrincipal principal,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        await store.ClearAvatarAsync(accountId.Value, cancellationToken);
        return Results.NoContent();
    }

    public static async Task<IResult> GetAvatarPhotoAsync(
        Guid personId,
        Guid version,
        HttpContext context,
        ClaimsPrincipal principal,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var viewerId = AccountClaims.AccountId(principal);
        if (viewerId is null) return Results.Unauthorized();
        if (viewerId != personId && !await store.AreConnectedAsync(viewerId.Value, personId, cancellationToken))
        {
            return Results.NotFound();
        }

        var jpeg = await store.GetAvatarPhotoAsync(personId, version, cancellationToken);
        if (jpeg is null) return Results.NotFound();
        context.Response.Headers.CacheControl = "private, no-store";
        context.Response.Headers.XContentTypeOptions = "nosniff";
        return Results.Bytes(jpeg, "image/jpeg");
    }

    private static async Task<byte[]?> ReadLimitedBodyAsync(Stream body, int maxBytes, CancellationToken cancellationToken)
    {
        await using var output = new MemoryStream();
        var buffer = ArrayPool<byte>.Shared.Rent(16 * 1024);
        try
        {
            while (true)
            {
                var read = await body.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
                if (read == 0) return output.ToArray();
                if (output.Length + read > maxBytes) return null;
                await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    private static bool TrySanitizeJpeg(byte[] input, out byte[] sanitized)
    {
        sanitized = [];
        if (input.Length < 4) return false;
        try
        {
            using var data = SKData.CreateCopy(input);
            using var codec = SKCodec.Create(data);
            if (codec is null || codec.EncodedFormat != SKEncodedImageFormat.Jpeg) return false;
            var info = codec.Info;
            if (info.Width is < AvatarDimensionMin or > AvatarDimensionMax
                || info.Height is < AvatarDimensionMin or > AvatarDimensionMax)
            {
                return false;
            }

            using var bitmap = SKBitmap.Decode(data);
            if (bitmap is null || bitmap.Width != info.Width || bitmap.Height != info.Height) return false;
            using var image = SKImage.FromBitmap(bitmap);
            using var encoded = image.Encode(SKEncodedImageFormat.Jpeg, 85);
            if (encoded is null || encoded.Size == 0 || encoded.Size > AvatarUploadMaxBytes) return false;
            return TryStripJpegMetadata(encoded.ToArray(), out sanitized);
        }
        catch (Exception)
        {
            return false;
        }
    }

    // The encoder drops source metadata, but JPEG encoders may add their own APP0/JFIF header.
    // Strip every APPn and COM segment from the normalized output as a final privacy guarantee.
    private static bool TryStripJpegMetadata(byte[] jpeg, out byte[] sanitized)
    {
        sanitized = [];
        if (jpeg.Length < 4 || jpeg[0] != 0xff || jpeg[1] != 0xd8) return false;
        using var output = new MemoryStream(jpeg.Length);
        output.Write(jpeg, 0, 2);
        var position = 2;
        var foundFrame = false;
        var foundScan = false;
        var foundEnd = false;

        while (position < jpeg.Length)
        {
            var markerStart = position;
            if (jpeg[position] != 0xff) return false;
            while (position < jpeg.Length && jpeg[position] == 0xff) position++;
            if (position >= jpeg.Length) return false;
            var marker = jpeg[position++];

            if (marker == 0xd9)
            {
                output.Write(jpeg, markerStart, position - markerStart);
                foundEnd = position == jpeg.Length;
                break;
            }

            if (marker is 0xd8 or 0x00) return false;
            if (marker is 0x01 or >= 0xd0 and <= 0xd7)
            {
                output.Write(jpeg, markerStart, position - markerStart);
                continue;
            }

            if (position + 2 > jpeg.Length) return false;
            var segmentLength = jpeg[position] * 256 + jpeg[position + 1];
            if (segmentLength < 2 || position + segmentLength > jpeg.Length) return false;
            var segmentEnd = position + segmentLength;
            if (IsJpegFrameMarker(marker)) foundFrame = true;
            var isMetadata = marker is >= 0xe0 and <= 0xef or 0xfe;
            if (!isMetadata)
            {
                output.Write(jpeg, markerStart, segmentEnd - markerStart);
            }

            position = segmentEnd;
            if (marker == 0xda)
            {
                foundScan = true;
                var nextMarker = FindJpegMarkerInScan(jpeg, position);
                if (nextMarker < 0) return false;
                output.Write(jpeg, position, nextMarker - position);
                position = nextMarker;
            }
        }

        if (!foundFrame || !foundScan || !foundEnd) return false;
        sanitized = output.ToArray();
        return true;
    }

    private static int FindJpegMarkerInScan(byte[] jpeg, int start)
    {
        for (var position = start; position < jpeg.Length;)
        {
            if (jpeg[position] != 0xff)
            {
                position++;
                continue;
            }

            var markerStart = position;
            var markerPosition = position + 1;
            while (markerPosition < jpeg.Length && jpeg[markerPosition] == 0xff) markerPosition++;
            if (markerPosition >= jpeg.Length) return -1;
            var marker = jpeg[markerPosition];
            if (marker == 0x00 || marker is >= 0xd0 and <= 0xd7)
            {
                position = markerPosition + 1;
                continue;
            }

            return markerStart;
        }

        return -1;
    }

    private static bool IsJpegFrameMarker(byte marker) =>
        marker is 0xc0 or 0xc1 or 0xc2 or 0xc3
            or 0xc5 or 0xc6 or 0xc7 or 0xc9 or 0xca or 0xcb
            or 0xcd or 0xce or 0xcf;

    public static async Task<IResult> CheckHandleAvailableAsync(
        [FromQuery] string? handle,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        var result = await engine.CheckHandleAsync(accountId.Value, handle, cancellationToken);
        return Results.Ok(new HandleAvailabilityResponse(result.Handle, result.Available, result.Code));
    }

    public static async Task<IResult> SetHandleAsync(
        SetHandleRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            await engine.SetHandleAsync(accountId.Value, request.Handle, cancellationToken);
            return Results.NoContent();
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> SendPhoneCodeAsync(
        SendPhoneCodeRequest request,
        ClaimsPrincipal principal,
        PhoneVerificationService phones,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            var result = await phones.SendAsync(accountId.Value, request.Phone, cancellationToken);
            return Results.Ok(new SendPhoneCodeResponse(
                result.ExpiresAt,
                result.ResendAfterSeconds,
                result.DevelopmentCode));
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> VerifyPhoneCodeAsync(
        VerifyPhoneCodeRequest request,
        ClaimsPrincipal principal,
        PhoneVerificationService phones,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            await phones.VerifyAsync(accountId.Value, request.Phone, request.Code, cancellationToken);
            return Results.NoContent();
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> AddPersonByPhoneAsync(
        AddPersonByPhoneRequest request,
        ClaimsPrincipal principal,
        PhoneVerificationService phones,
        IHostEnvironment environment,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        var onboardingError = await ProductionOnboardingErrorAsync(accountId.Value, environment, store, cancellationToken);
        if (onboardingError is not null) return onboardingError;

        try
        {
            var result = await phones.AddPersonAsync(accountId.Value, request.Phone, cancellationToken);
            return Results.Ok(new AddPersonByPhoneResponse(result.Outcome, result.SmsSent, result.DevelopmentCode));
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> CreateInviteAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        IHostEnvironment environment,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        var onboardingError = await ProductionOnboardingErrorAsync(accountId.Value, environment, store, cancellationToken);
        if (onboardingError is not null) return onboardingError;

        var invite = await engine.CreateInviteAsync(accountId.Value, cancellationToken);
        return Results.Ok(new { code = invite.Code });
    }

    public static async Task<IResult> AcceptInviteAsync(
        InviteAcceptRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        IHostEnvironment environment,
        ITrustStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        var onboardingError = await ProductionOnboardingErrorAsync(accountId.Value, environment, store, cancellationToken);
        if (onboardingError is not null) return onboardingError;
        return await RunAsync(principal, engine, (id, ct) => engine.AcceptInviteAsync(id, request.Code, ct), cancellationToken);
    }

    private static async Task<IResult?> ProductionOnboardingErrorAsync(
        Guid accountId, IHostEnvironment environment, ITrustStore store, CancellationToken cancellationToken)
    {
        if (!environment.IsProduction()) return null;
        var account = await store.FindAccountAsync(accountId, cancellationToken);
        return account?.OnboardingComplete == true ? null : Map(TrustException.PhoneVerificationRequired());
    }

    public static async Task<IResult> LookupPersonAsync(
        [FromQuery] string? handle,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        try
        {
            var match = await engine.LookupPersonAsync(accountId.Value, handle, cancellationToken);
            if (match is null) return Results.NotFound(new ApiError("person_not_found", "No eligible person uses that handle."));
            return Results.Ok(new PersonLookupResponse(
                match.AccountId,
                match.Handle,
                RelationshipName(match.Relationship),
                match.RequestId));
        }
        catch (TrustException exception) { return Map(exception); }
    }

    public static async Task<IResult> ListConnectionRequestsAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        try
        {
            var lists = await engine.ListConnectionRequestsAsync(accountId.Value, cancellationToken);
            static ConnectionRequestDto MapEntry(ConnectionRequestEntry entry) => new(
                entry.Request.Id,
                new ConnectionRequestPartyDto(entry.OtherParty.Id, entry.OtherParty.Handle ?? ""),
                entry.Request.CreatedAt,
                entry.Request.ExpiresAt);
            return Results.Ok(new ConnectionRequestListResponse(
                lists.Incoming.Select(MapEntry).ToList(),
                lists.Sent.Select(MapEntry).ToList()));
        }
        catch (TrustException exception) { return Map(exception); }
    }

    public static async Task<IResult> CreateConnectionRequestAsync(
        ConnectionRequestCreateRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null) return Results.Unauthorized();
        try
        {
            var created = await engine.CreateConnectionRequestAsync(accountId.Value, request.RecipientId, cancellationToken);
            return Results.Ok(new ConnectionRequestCreateResponse(created.Id, "pending", created.CreatedAt, created.ExpiresAt));
        }
        catch (TrustException exception) { return Map(exception); }
    }

    public static async Task<IResult> AcceptConnectionRequestAsync(
        Guid requestId, ClaimsPrincipal principal, TrustEngine engine, CancellationToken cancellationToken) =>
        await RunAsync(principal, engine, (id, ct) => engine.AcceptConnectionRequestAsync(id, requestId, ct), cancellationToken);

    public static async Task<IResult> DeclineConnectionRequestAsync(
        Guid requestId, ClaimsPrincipal principal, TrustEngine engine, CancellationToken cancellationToken) =>
        await RunAsync(principal, engine, (id, ct) => engine.DeclineConnectionRequestAsync(id, requestId, ct), cancellationToken);

    public static async Task<IResult> CancelConnectionRequestAsync(
        Guid requestId, ClaimsPrincipal principal, TrustEngine engine, CancellationToken cancellationToken) =>
        await RunAsync(principal, engine, (id, ct) => engine.CancelConnectionRequestAsync(id, requestId, ct), cancellationToken);

    private static string RelationshipName(ConnectionRelationship relationship) => relationship switch
    {
        ConnectionRelationship.Connected => "connected",
        ConnectionRelationship.Sent => "sent",
        ConnectionRelationship.Incoming => "incoming",
        _ => "none"
    };

    public static async Task<IResult> SetShareAsync(
        Guid personId,
        ShareRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        return await RunAsync(
            principal,
            engine,
            (id, ct) => engine.SetShareAsync(
                id,
                personId,
                ContractMap.ParseResting(request.Resting),
                ContractMap.ParsePause(request.Pause),
                ct),
            cancellationToken);
    }

    public static async Task<IResult> HistoryAsync(
        Guid personId,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            var points = await engine.HistoryAsync(accountId.Value, personId, cancellationToken);
            return Results.Ok(new HistoryResponse(points.Select(ContractMap.LocationRequired).ToList()));
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> RevokeAsync(
        Guid personId,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        return await RunAsync(principal, engine, (id, ct) => engine.RevokeAsync(id, personId, ct), cancellationToken);
    }

    public static async Task<IResult> IngestAsync(
        LocationIngestRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        const int maxBatchSize = 100;
        var fixes = ContractMap.IngestFixes(request);
        if (fixes.Count is 0 or > maxBatchSize
            || fixes.Any(fix => !double.IsFinite(fix.Latitude)
                || !double.IsFinite(fix.Longitude)
                || fix.Latitude is < -90 or > 90
                || fix.Longitude is < -180 or > 180))
        {
            return Results.BadRequest(new ApiError("invalid_location", "Location coordinates must be valid and a batch may contain at most 100 points."));
        }

        return await RunAsync(
            principal,
            engine,
            (id, ct) => engine.IngestManyAsync(
                id,
                fixes,
                request.BatteryPercent,
                request.IsCharging,
                ct),
            cancellationToken);
    }

    public static async Task<IResult> LookAsync(
        LookRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        ILookReceiptPublisher receipts,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            var result = await engine.LookAsync(accountId.Value, request.SubjectId, request.Confirmed, cancellationToken);
            if (result.IsNew)
            {
                await receipts.NotifyLookAsync(result.Session.Event, cancellationToken);
            }

            return Results.Ok(ContractMap.Session(result.Session));
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> ViewAsync(
        ViewRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            // View never sends a push — it's Available's no-sheet counterpart to Look.
            var view = await engine.ViewAsync(accountId.Value, request.SubjectId, cancellationToken);
            return Results.Ok(new ViewResponse(view is not null, view is null ? null : ContractMap.Look(view)));
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> CheckInAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        return await RunAsync(principal, engine, engine.CheckInAsync, cancellationToken);
    }

    public static async Task<IResult> PlacePingAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        return await RunAsync(principal, engine, engine.PlacePingAsync, cancellationToken);
    }

    public static async Task<IResult> SetPresenceGrantAsync(
        Guid personId,
        PresenceGrantRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        return await RunAsync(
            principal,
            engine,
            (id, ct) => engine.SetPresenceGrantAsync(id, personId, request.Enabled, ct),
            cancellationToken);
    }

    public static async Task<IResult> SetHomePlaceAsync(
        SetHomePlaceRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        return await RunAsync(
            principal,
            engine,
            (id, ct) => engine.SetHomePlaceAsync(id, request.PlaceId, request.Label ?? "Home", ct),
            cancellationToken);
    }

    public static async Task<IResult> PostHomePresenceAsync(
        HomePresenceRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        ILookReceiptPublisher receipts,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        var state = ContractMap.ParseHomeState(request.State);
        if (state is null)
        {
            return Results.BadRequest(new ApiError("invalid_state", "State must be home, away, or hidden."));
        }

        try
        {
            var arrivedHome = await engine.PostHomePresenceAsync(accountId.Value, state.Value, request.SignaledAt, cancellationToken);
            if (arrivedHome)
            {
                await receipts.NotifyHomeArrivalAsync(accountId.Value, cancellationToken);
            }

            return Results.NoContent();
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> CreatePromiseAsync(
        CreatePromiseRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            _ = await engine.CreatePromiseAsync(
                accountId.Value,
                request.TrusteeId,
                request.DeadlineAt,
                cancellationToken);
            return Results.NoContent();
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    public static async Task<IResult> EntitlementAsync(
        EntitlementRequest request,
        ClaimsPrincipal principal,
        TrustEngine engine,
        IStoreKitTransactionVerifier verifier,
        IStoreKitEntitlementStore store,
        IOptions<StoreKitOptions> storeKit,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        if (request.ReviewUnlock)
        {
            if (!storeKit.Value.AllowReviewUnlock)
            {
                return Results.Json(
                    new ApiError("storekit_unavailable", "Review unlock is disabled on this server."),
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }

            await engine.GrantCircleAsync(accountId.Value, "storekit-review", cancellationToken);
            return Results.NoContent();
        }

        if (!string.IsNullOrWhiteSpace(request.SignedTransactionInfo))
        {
            return await ApplySignedTransactionAsync(
                accountId.Value,
                request.SignedTransactionInfo,
                verifier,
                store,
                storeKit.Value,
                cancellationToken);
        }

        if (storeKit.Value.AllowReviewUnlock
            && !string.IsNullOrWhiteSpace(request.ProductId)
            && (request.ProductId.Contains("circle.monthly", StringComparison.Ordinal)
                || request.ProductId.Contains("circle.annual", StringComparison.Ordinal)))
        {
            await engine.GrantCircleAsync(accountId.Value, request.ProductId, cancellationToken);
            return Results.NoContent();
        }

        return Results.Json(
            new ApiError(
                "storekit_unverified",
                "This server verifies signed App Store transactions. Purchase or restore Plus, then the app submits the signed transaction."),
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }

    public static async Task<IResult> StoreKitAccountTokenAsync(
        ClaimsPrincipal principal,
        IStoreKitEntitlementStore store,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        var token = await store.GetOrCreateAccountTokenAsync(accountId.Value, cancellationToken);
        return Results.Ok(new StoreKitAccountTokenResponse(token));
    }

    public static async Task<IResult> VerifyStoreKitTransactionAsync(
        VerifyStoreKitTransactionRequest request,
        ClaimsPrincipal principal,
        IStoreKitTransactionVerifier verifier,
        IStoreKitEntitlementStore store,
        IOptions<StoreKitOptions> storeKit,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        return await ApplySignedTransactionAsync(
            accountId.Value,
            request.SignedTransactionInfo,
            verifier,
            store,
            storeKit.Value,
            cancellationToken);
    }

    public static async Task<IResult> StoreKitNotificationAsync(
        StoreKitNotificationRequest request,
        IStoreKitTransactionVerifier verifier,
        IStoreKitEntitlementStore store,
        IOptions<StoreKitOptions> storeKit,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        if (!storeKit.Value.Enabled)
        {
            return Results.Json(
                new ApiError("storekit_unavailable", "StoreKit is not enabled on this server."),
                statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        var notification = verifier.VerifyNotification(request.SignedPayload);
        if (!notification.IsValid)
        {
            return Results.BadRequest(new ApiError(
                "invalid_storekit",
                notification.Error ?? "The StoreKit notification is invalid."));
        }

        var logger = loggerFactory.CreateLogger(typeof(TrustEndpoints));
        if (notification.Transaction is not null
            && !await store.ApplyNotificationAsync(notification.Transaction, cancellationToken))
        {
            logger.LogWarning(
                "Ignored StoreKit notification {NotificationId} because its app account token is unknown.",
                notification.NotificationId);
        }

        return Results.NoContent();
    }

    public static async Task<IResult> RegisterPushDeviceAsync(
        PushDeviceRequest request,
        ClaimsPrincipal principal,
        IPushDeviceStore devices,
        IOptions<AppleOptions> apple,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.Token) || request.InstallationId == Guid.Empty)
        {
            return Results.BadRequest(new ApiError("invalid_device", "A push token and installation id are required."));
        }

        var bundleId = string.IsNullOrWhiteSpace(request.BundleId) ? apple.Value.BundleId : request.BundleId.Trim();
        if (!string.Equals(bundleId, apple.Value.BundleId, StringComparison.Ordinal))
        {
            return Results.BadRequest(new ApiError("invalid_bundle", "That push topic is not this app."));
        }

        await devices.RegisterAsync(
            accountId.Value,
            request.InstallationId,
            request.Token.Trim(),
            request.Environment,
            bundleId,
            cancellationToken);
        return Results.NoContent();
    }

    public static async Task<IResult> RemovePushDeviceAsync(
        Guid installationId,
        ClaimsPrincipal principal,
        IPushDeviceStore devices,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        await devices.RemoveAsync(accountId.Value, installationId, cancellationToken);
        return Results.NoContent();
    }

    public static async Task<IResult> DeleteAccountAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        IPushDeviceStore devices,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        await devices.RemoveAllAsync(accountId.Value, cancellationToken);
        await engine.DeleteAccountAsync(accountId.Value, cancellationToken);
        return Results.NoContent();
    }

    private static async Task<IResult> ApplySignedTransactionAsync(
        Guid accountId,
        string signedTransactionInfo,
        IStoreKitTransactionVerifier verifier,
        IStoreKitEntitlementStore store,
        StoreKitOptions storeKit,
        CancellationToken cancellationToken)
    {
        if (!storeKit.Enabled)
        {
            return Results.Json(
                new ApiError("storekit_unavailable", "StoreKit verification is not enabled on this server."),
                statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        var verification = verifier.Verify(signedTransactionInfo);
        if (!verification.IsValid)
        {
            return Results.BadRequest(new ApiError(
                "invalid_storekit",
                verification.Error ?? "The StoreKit transaction is invalid."));
        }

        var outcome = await store.ApplyAsync(accountId, verification.Transaction!, cancellationToken);
        return outcome switch
        {
            StoreKitApplyOutcome.Applied => Results.NoContent(),
            StoreKitApplyOutcome.LinkedToAnotherAccount => Results.Json(
                new ApiError(
                    "storekit_account_mismatch",
                    "This Apple subscription is linked to another Trust account. Contact hello@collapsetechnologies.com."),
                statusCode: StatusCodes.Status403Forbidden),
            _ => Results.Json(
                new ApiError(
                    "storekit_not_linked",
                    "This Apple transaction could not be linked to the signed-in Trust account."),
                statusCode: StatusCodes.Status403Forbidden)
        };
    }

    public static Task<IResult> CheckoutAsync(
        CheckoutRequest request,
        ClaimsPrincipal principal,
        IOptions<StripeOptions> stripe)
    {
        if (AccountClaims.AccountId(principal) is null)
        {
            return Task.FromResult(Results.Unauthorized());
        }

        if (!stripe.Value.Enabled || string.IsNullOrWhiteSpace(stripe.Value.SecretKey))
        {
            return Task.FromResult(Results.Json(
                new ApiError(
                    "stripe_unconfigured",
                    "Stripe is not configured. Circle on iPhone uses StoreKit. Set Stripe__SecretKey and price IDs to enable web checkout for prod_trust_circle."),
                statusCode: StatusCodes.Status503ServiceUnavailable));
        }

        try
        {
            Stripe.StripeConfiguration.ApiKey = stripe.Value.SecretKey;
            var price = string.Equals(request.Interval, "year", StringComparison.OrdinalIgnoreCase)
                ? stripe.Value.PriceAnnual
                : stripe.Value.PriceMonthly;
            if (string.IsNullOrWhiteSpace(price))
            {
                return Task.FromResult(Results.Json(
                    new ApiError("stripe_price_missing", "Stripe price IDs are not set."),
                    statusCode: StatusCodes.Status503ServiceUnavailable));
            }

            var service = new Stripe.Checkout.SessionService();
            var session = service.Create(new Stripe.Checkout.SessionCreateOptions
            {
                Mode = "subscription",
                SuccessUrl = stripe.Value.SuccessUrl,
                CancelUrl = stripe.Value.CancelUrl,
                LineItems =
                [
                    new Stripe.Checkout.SessionLineItemOptions
                    {
                        Price = price,
                        Quantity = 1
                    }
                ],
                Metadata = new Dictionary<string, string>
                {
                    ["product"] = stripe.Value.ProductId
                }
            });
            return Task.FromResult(Results.Ok(new CheckoutResponse(session.Url)));
        }
        catch (Exception exception)
        {
            return Task.FromResult(Results.Json(
                new ApiError("stripe_error", exception.Message),
                statusCode: StatusCodes.Status503ServiceUnavailable));
        }
    }

    private static async Task<IResult> IssueAsync(
        TrustEngine engine,
        SessionIssuer sessions,
        TrustProductOptions product,
        string provider,
        string subject,
        string displayName,
        CancellationToken cancellationToken)
    {
        var account = await engine.SignInAsync(provider, subject, displayName, cancellationToken);
        if (product.SeedReviewCircle)
        {
            await engine.EnsureReviewCircleAsync(account.Id, cancellationToken);
            account = await engine.SignInAsync(provider, subject, displayName, cancellationToken);
        }

        var token = sessions.Issue(account.Id, account.DisplayName, provider);
        return Results.Ok(new SessionResponse(token, ContractMap.Person(account)));
    }

    private static async Task<IResult> RunAsync(
        ClaimsPrincipal principal,
        TrustEngine engine,
        Func<Guid, CancellationToken, Task> action,
        CancellationToken cancellationToken)
    {
        var accountId = AccountClaims.AccountId(principal);
        if (accountId is null)
        {
            return Results.Unauthorized();
        }

        try
        {
            await action(accountId.Value, cancellationToken);
            return Results.NoContent();
        }
        catch (TrustException exception)
        {
            return Map(exception);
        }
    }

    private static bool IsAppleTokenFailure(Exception exception) =>
        exception is SecurityTokenException or InvalidOperationException or ArgumentException;

    private static bool IsAppleDirectoryFailure(Exception exception) =>
        exception is OperationCanceledException
            or HttpRequestException
            or TimeoutException
            or IOException
        || exception.InnerException is HttpRequestException or TimeoutException or IOException;

    private static IResult Map(TrustException exception) => exception.Code switch
    {
        "unauthorized" => Results.Unauthorized(),
        "confirmation_required" or "invalid_code" or "own_invite" or "invalid_product"
            or "invalid_phone" or "invalid_name" or "invalid_handle" or "reserved_handle"
            or "otp_invalid" or "otp_expired"
            or "otp_exhausted" or "otp_cooldown" =>
            Results.BadRequest(new ApiError(exception.Code, exception.Message)),
        "verification_required" => Results.Json(new ApiError(exception.Code, exception.Message), statusCode: StatusCodes.Status403Forbidden),
        "request_not_found" => Results.NotFound(new ApiError(exception.Code, exception.Message)),
        "request_expired" or "request_declined_recently" or "request_limit" =>
            Results.Json(new ApiError(exception.Code, exception.Message), statusCode: StatusCodes.Status409Conflict),
        "otp_not_configured" or "otp_send_failed" =>
            Results.Json(new ApiError(exception.Code, exception.Message), statusCode: StatusCodes.Status503ServiceUnavailable),
        "not_connected" or "pair_inactive" or "no_location" or "phone_in_use" or "phone_unavailable" or "handle_in_use"
            or "share_off" or "look_requires_sealed" or "view_requires_available" =>
            Results.Json(new ApiError(exception.Code, exception.Message), statusCode: StatusCodes.Status409Conflict),
        "seat_limit" or "pro_required" =>
            Results.Json(new ApiError(exception.Code, exception.Message), statusCode: StatusCodes.Status402PaymentRequired),
        _ => Results.Json(new ApiError(exception.Code, exception.Message), statusCode: StatusCodes.Status400BadRequest)
    };
}

/// Names of the rate limiter policies registered in Program.cs. Kept as named constants so the
/// endpoint map and the policy registration can't silently drift apart.
public static class RateLimitPolicies
{
    public const string Auth = "auth";
    public const string Invite = "invite";
    public const string PhoneSend = "phone-send";
    public const string PhoneVerify = "phone-verify";
    public const string Location = "location";
    public const string Look = "look";
    public const string Avatar = "avatar";
}
