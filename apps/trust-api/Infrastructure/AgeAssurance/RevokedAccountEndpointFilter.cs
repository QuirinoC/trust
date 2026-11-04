using TrustApi.Contracts.V1;
using TrustApi.Infrastructure.Identity;

namespace TrustApi.Infrastructure.AgeAssurance;

/// <summary>Fails closed for accounts whose Apple consent revocation is pending cleanup.</summary>
public sealed class RevokedAccountEndpointFilter(
    IAgeAssuranceAccountStore ageAssurance) : IEndpointFilter
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

        if (IsAllowedWhileConsentRevoked(http.Request.Method, http.Request.Path))
        {
            return await next(context);
        }

        if (await ShouldBlockAsync(accountId, http.Request.Method, http.Request.Path, http.RequestAborted))
        {
            return Results.Conflict(new ApiError(
                "consent_revoked",
                "Consent for this Apple app transaction has been revoked."));
        }

        return await next(context);
    }

    public Task<bool> ShouldBlockAsync(Guid? accountId, string method, PathString path, CancellationToken cancellationToken) =>
        accountId is not null && !IsAllowedWhileConsentRevoked(method, path)
            ? ageAssurance.IsAccountBlockedAsync(accountId.Value, cancellationToken)
            : Task.FromResult(false);

    public Task<bool> ShouldBlockForPrivacyHoldAsync(Guid? accountId, string method, PathString path, CancellationToken cancellationToken) =>
        accountId is not null && !IsAllowedWhilePrivacyHeld(method, path)
            ? ageAssurance.IsAccountPrivacyHeldAsync(accountId.Value, cancellationToken)
            : Task.FromResult(false);

    private static bool IsAllowedWhileConsentRevoked(string method, PathString path) =>
        (HttpMethods.IsPut(method) && path.Equals("/api/v1/age-assurance/app-transaction", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsPost(method) && path.Equals("/api/v1/age-assurance/privacy-hold", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.Equals("/api/v1/account", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.StartsWithSegments("/api/v1/push/devices", StringComparison.OrdinalIgnoreCase));

    private static bool IsAllowedWhilePrivacyHeld(string method, PathString path) =>
        (HttpMethods.IsPost(method) && path.Equals("/api/v1/age-assurance/privacy-hold", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.Equals("/api/v1/account", StringComparison.OrdinalIgnoreCase))
        || (HttpMethods.IsDelete(method) && path.StartsWithSegments("/api/v1/push/devices", StringComparison.OrdinalIgnoreCase));
}
