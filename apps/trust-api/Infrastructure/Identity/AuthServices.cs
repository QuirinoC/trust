using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using TrustApi.Configuration;

namespace TrustApi.Infrastructure.Identity;

public sealed record ExternalIdentity(string Provider, string Subject, string DisplayName);

public interface IAppleIdentityValidator
{
    Task<ExternalIdentity> ValidateAsync(string identityToken, CancellationToken cancellationToken);
}

public interface IGoogleIdentityValidator
{
    Task<ExternalIdentity> ValidateAsync(string idToken, CancellationToken cancellationToken);
}

public sealed class SessionIssuer(AuthOptions options)
{
    public string Issue(Guid accountId, string displayName, string provider)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(RequireKey(options.SigningKey)));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            options.Issuer,
            options.Audience,
            [
                new Claim("sub", accountId.ToString()),
                new Claim("name", displayName),
                new Claim("provider", provider)
            ],
            notBefore: DateTime.UtcNow,
            expires: DateTime.UtcNow.AddDays(30),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public static string RequireKey(string signingKey)
    {
        if (string.IsNullOrWhiteSpace(signingKey) || Encoding.UTF8.GetByteCount(signingKey) < 32)
        {
            throw new InvalidOperationException("Auth:SigningKey must be at least 32 bytes.");
        }

        return signingKey;
    }
}

public static class ExternalIdentityTokens
{
    public static ExternalIdentity Read(string token, TokenValidationParameters parameters, string provider)
    {
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        var principal = handler.ValidateToken(token, parameters, out var validated);
        return FromPrincipal(principal, validated as JwtSecurityToken, provider);
    }

    public static bool TryReadUnverified(string token, string provider, out ExternalIdentity identity)
    {
        identity = new ExternalIdentity(provider, "", "You");
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        if (string.IsNullOrWhiteSpace(token) || !handler.CanReadToken(token))
        {
            return false;
        }

        try
        {
            identity = FromPrincipal(null, handler.ReadJwtToken(token), provider);
            return !string.IsNullOrWhiteSpace(identity.Subject);
        }
        catch (Exception)
        {
            return false;
        }
    }

    public static ExternalIdentity FromPrincipal(ClaimsPrincipal? principal, JwtSecurityToken? jwt, string provider)
    {
        var subject = FirstClaim(principal, jwt, "sub")
            ?? FirstClaim(principal, jwt, ClaimTypes.NameIdentifier)
            ?? jwt?.Subject
            ?? throw new InvalidOperationException($"{provider} token is missing sub.");
        var email = FirstClaim(principal, jwt, "email");
        var name = FirstClaim(principal, jwt, "name")
            ?? (string.IsNullOrWhiteSpace(email) ? null : email.Split('@')[0])
            ?? "You";
        return new ExternalIdentity(provider, subject, name);
    }

    private static string? FirstClaim(ClaimsPrincipal? principal, JwtSecurityToken? jwt, string type)
    {
        var fromPrincipal = principal?.FindFirstValue(type);
        if (!string.IsNullOrWhiteSpace(fromPrincipal))
        {
            return fromPrincipal;
        }

        return jwt?.Claims.FirstOrDefault(claim =>
            string.Equals(claim.Type, type, StringComparison.Ordinal))?.Value;
    }
}

public sealed class AppleIdentityValidator(AppleOptions options) : IAppleIdentityValidator
{
    private static readonly HttpClient DocumentHttp = new() { Timeout = TimeSpan.FromSeconds(8) };
    private static readonly ConfigurationManager<OpenIdConnectConfiguration> Configuration = new(
        "https://appleid.apple.com/.well-known/openid-configuration",
        new OpenIdConnectConfigurationRetriever(),
        new HttpDocumentRetriever(DocumentHttp) { RequireHttps = true });

    public async Task<ExternalIdentity> ValidateAsync(string identityToken, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(12));
        var openId = await Configuration.GetConfigurationAsync(timeout.Token);
        var parameters = new TokenValidationParameters
        {
            ValidIssuer = "https://appleid.apple.com",
            ValidAudiences = [options.BundleId],
            IssuerSigningKeys = openId.SigningKeys,
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            NameClaimType = "sub",
            ClockSkew = TimeSpan.FromMinutes(5)
        };
        return ExternalIdentityTokens.Read(identityToken, parameters, "apple");
    }
}

public sealed class GoogleIdentityValidator(GoogleOptions options) : IGoogleIdentityValidator
{
    private static readonly HttpClient DocumentHttp = new() { Timeout = TimeSpan.FromSeconds(8) };
    private static readonly ConfigurationManager<OpenIdConnectConfiguration> Configuration = new(
        "https://accounts.google.com/.well-known/openid-configuration",
        new OpenIdConnectConfigurationRetriever(),
        new HttpDocumentRetriever(DocumentHttp) { RequireHttps = true });

    public async Task<ExternalIdentity> ValidateAsync(string idToken, CancellationToken cancellationToken)
    {
        if (options.ClientIds.Length == 0)
        {
            throw new InvalidOperationException("Google Sign-In is not configured on this server.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(12));
        var openId = await Configuration.GetConfigurationAsync(timeout.Token);
        var parameters = new TokenValidationParameters
        {
            ValidIssuers = ["https://accounts.google.com", "accounts.google.com"],
            ValidAudiences = options.ClientIds,
            IssuerSigningKeys = openId.SigningKeys,
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            NameClaimType = "sub",
            ClockSkew = TimeSpan.FromMinutes(5)
        };
        return ExternalIdentityTokens.Read(idToken, parameters, "google");
    }
}

public static class AccountClaims
{
    public static Guid? AccountId(ClaimsPrincipal? principal)
    {
        var sub = principal?.FindFirstValue("sub");
        return Guid.TryParse(sub, out var id) ? id : null;
    }
}

/// SIWA replay-hygiene: compares the client-supplied nonce (the same raw value it set on
/// ASAuthorizationAppleIDRequest.nonce) against the ID token's own "nonce" claim.
/// Optional for now — the iOS client doesn't send one yet, so a missing nonce is not an error.
public static class AppleNonceValidator
{
    public static bool Matches(string identityToken, string? expectedNonce)
    {
        if (string.IsNullOrWhiteSpace(expectedNonce))
        {
            return true;
        }

        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        if (string.IsNullOrWhiteSpace(identityToken) || !handler.CanReadToken(identityToken))
        {
            return false;
        }

        var claim = handler.ReadJwtToken(identityToken).Claims
            .FirstOrDefault(claim => string.Equals(claim.Type, "nonce", StringComparison.Ordinal));
        return claim is not null && string.Equals(claim.Value, expectedNonce, StringComparison.Ordinal);
    }
}
