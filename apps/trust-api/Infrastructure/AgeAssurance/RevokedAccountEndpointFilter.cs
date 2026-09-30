using TrustApi.Contracts.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure.Identity;
using Microsoft.Extensions.Hosting;

namespace TrustApi.Infrastructure.AgeAssurance;

/// <summary>Fails closed for accounts whose Apple consent revocation is pending cleanup.</summary>
public sealed class RevokedAccountEndpointFilter(
    IAgeAssuranceAccountStore ageAssurance,
    ITrustStore accounts,
    IHostEnvironment environment) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var http = context.HttpContext;
        var accountId = AccountClaims.AccountId(http.User);
        if (await ShouldBlockForPrivacyHoldAsync(accountId, http.Request.Method, http.Request.Path, http.RequestAborted))
        {
            return Results.Json(
                new ApiError("account_privacy_hold", "This Trust account is on privacy hold. Contact Support for help."),
                statusCode: StatusCodes.Status423Locked);
        }

        if (IsAllowedWithoutAgeAssuranceLink(http.Request.Method, http.Request.Path))
        {
            return await next(context);
        }

        if (await ShouldBlockAsync(accountId, http.Request.Method, http.Request.Path, http.RequestAborted))
        {
            return Results.Conflict(new ApiError(
                "consent_revoked",
                "Consent for this Apple app transaction has been revoked."));
        }

        if (await ShouldBlockForMissingLinkAsync(
                accountId,
                http.Request.Method,
                http.Request.Path,
                IsAllowedPrivacyControlWithoutLink(context),
                http.RequestAborted))
        {
            return Results.Conflict(new ApiError(
                "age_assurance_link_required",
                "Update Trust to continue. This app version must register its App Store transaction before using the service."));
        }

        return await next(context);
    }

    public Task<bool> ShouldBlockAsync(Guid? accountId, string method, PathString path, CancellationToken cancellationToken) =>
        accountId is not null && !IsAllowedWithoutAgeAssuranceLink(method, path)
            ? ageAssurance.IsAccountBlockedAsync(accountId.Value, cancellationToken)
            : Task.FromResult(false);

    public Task<bool> ShouldBlockForPrivacyHoldAsync(Guid? accountId, string method, PathString path, CancellationToken cancellationToken) =>
        accountId is not null && !IsAllowedWhilePrivacyHeld(method, path)
            ? ageAssurance.IsAccountPrivacyHeldAsync(accountId.Value, cancellationToken)
            : Task.FromResult(false);

    public async Task<bool> ShouldBlockForMissingLinkAsync(
        Guid? accountId,
        string method,
        PathString path,
        CancellationToken cancellationToken) =>
        await ShouldBlockForMissingLinkAsync(accountId, method, path, false, cancellationToken);

    private async Task<bool> ShouldBlockForMissingLinkAsync(
        Guid? accountId,
        string method,
        PathString path,
        bool privacyControlAllowed,
        CancellationToken cancellationToken) =>
        !environment.IsDevelopment()
        && accountId is not null
        && !IsAllowedWithoutAgeAssuranceLink(method, path)
        && !privacyControlAllowed
        && await accounts.FindAccountAsync(accountId.Value, cancellationToken) is not null
        && !await ageAssurance.HasAppTransactionLinkAsync(accountId.Value, cancellationToken);

    private static bool IsAllowedPrivacyControlWithoutLink(EndpointFilterInvocationContext context)
    {
        var request = context.HttpContext.Request;
        if (HttpMethods.IsPatch(request.Method) && IsRelationshipPath(request.Path, "share"))
        {
            var share = context.Arguments.OfType<ShareRequest>().SingleOrDefault();
            return share is not null
                && ContractMap.ParseResting(share.Resting) == ShareResting.Off
                && string.IsNullOrWhiteSpace(share.Pause);
        }

        if (HttpMethods.IsPost(request.Method) && IsRelationshipPath(request.Path, "revoke"))
        {
            return context.Arguments.OfType<RevokeRequest>().Any();
        }

        if (HttpMethods.IsPost(request.Method)
            && request.Path.Equals("/api/v1/me/sharing/stop-all", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }

    private static bool IsRelationshipPath(PathString path, string action)
    {
        var segments = path.Value?.Split('/', StringSplitOptions.RemoveEmptyEntries);
        return segments is { Length: 5 }
            && segments[0].Equals("api", StringComparison.OrdinalIgnoreCase)
            && segments[1].Equals("v1", StringComparison.OrdinalIgnoreCase)
            && segments[2].Equals("people", StringComparison.OrdinalIgnoreCase)
            && Guid.TryParse(segments[3], out _)
            && segments[4].Equals(action, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsAllowedWithoutAgeAssuranceLink(string method, PathString path) =>
        (HttpMethods.IsPut(method) && path.Equals("/api/v1/age-assurance/app-transaction", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsPost(method) && path.Equals("/api/v1/age-assurance/privacy-hold", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.Equals("/api/v1/account", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.StartsWithSegments("/api/v1/push/devices", StringComparison.OrdinalIgnoreCase));

    private static bool IsAllowedWhilePrivacyHeld(string method, PathString path) =>
        (HttpMethods.IsPost(method) && path.Equals("/api/v1/age-assurance/privacy-hold", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.Equals("/api/v1/account", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.StartsWithSegments("/api/v1/push/devices", StringComparison.OrdinalIgnoreCase));
}
