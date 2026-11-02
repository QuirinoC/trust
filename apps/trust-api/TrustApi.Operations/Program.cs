using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure.StoreKit;
using Microsoft.Extensions.Options;
using System.IdentityModel.Tokens.Jwt;

if (args.Length != 3
    || string.IsNullOrWhiteSpace(args[0])
    || !Guid.TryParse(args[1], out var oldAppAccountToken)
    || !Guid.TryParse(args[2], out var targetAccountId))
{
    Console.Error.WriteLine("Usage: trust-storekit-recovery-approve <originalTransactionId> <oldAppAccountToken> <targetAccountId>");
    return 2;
}

var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres");
if (string.IsNullOrWhiteSpace(connectionString))
{
    Console.Error.WriteLine("Set ConnectionStrings__Postgres in the protected operator environment.");
    return 2;
}

var tokenPath = Environment.GetEnvironmentVariable("TRUST_STOREKIT_BEARER_TOKEN_FILE");
if (string.IsNullOrWhiteSpace(tokenPath) || !File.Exists(tokenPath))
{
    Console.Error.WriteLine("Set TRUST_STOREKIT_BEARER_TOKEN_FILE to the protected short lived App Store API bearer token file.");
    return 2;
}

string bearerToken;
try
{
    if (OperatingSystem.IsWindows()) throw new InvalidOperationException();
    var fileMode = File.GetUnixFileMode(tokenPath);
    const UnixFileMode publicBits = UnixFileMode.GroupRead | UnixFileMode.GroupWrite | UnixFileMode.GroupExecute
        | UnixFileMode.OtherRead | UnixFileMode.OtherWrite | UnixFileMode.OtherExecute;
    if ((fileMode & publicBits) != 0 || new FileInfo(tokenPath).Length is <= 0 or > 16_384)
        throw new InvalidOperationException();
    bearerToken = File.ReadAllText(tokenPath).Trim();
    var tokenHandler = new JwtSecurityTokenHandler { MapInboundClaims = false };
    if (!tokenHandler.CanReadToken(bearerToken)) throw new InvalidOperationException();
    var token = tokenHandler.ReadJwtToken(bearerToken);
    var appBundleId = Environment.GetEnvironmentVariable("StoreKit__BundleId") ?? "com.collapsetechnologies.trust";
    var now = DateTimeOffset.UtcNow;
    var issuedAtClaim = token.Claims.FirstOrDefault(claim => claim.Type == "iat")?.Value;
    if (!long.TryParse(issuedAtClaim, out var issuedAtUnix)) throw new InvalidOperationException();
    var issuedAt = DateTimeOffset.FromUnixTimeSeconds(issuedAtUnix);
    if (token.ValidTo <= now.UtcDateTime || token.ValidTo > now.AddMinutes(10).UtcDateTime
        || issuedAt < now.AddMinutes(-5) || issuedAt > now.AddSeconds(30)
        || token.ValidTo - issuedAt.UtcDateTime > TimeSpan.FromMinutes(10)
        || !string.Equals(token.Audiences.SingleOrDefault(), "appstoreconnect-v1", StringComparison.Ordinal)
        || !string.Equals(token.Claims.FirstOrDefault(claim => claim.Type == "bid")?.Value, appBundleId, StringComparison.Ordinal))
        throw new InvalidOperationException();
}
catch
{
    Console.Error.WriteLine("The protected App Store API token file is unreadable, broadly accessible, expired, or bound to another app.");
    return 2;
}

try
{
    var store = new PostgresStoreKitEntitlementStore(connectionString);
    var appBundleId = Environment.GetEnvironmentVariable("StoreKit__BundleId") ?? "com.collapsetechnologies.trust";
    var storeKitOptions = new StoreKitOptions { BundleId = appBundleId, TrustedRootCertificates = AppleRootCertificates.LoadEmbedded() };
    var verifier = new StoreKitTransactionVerifier(Options.Create(storeKitOptions), TimeProvider.System);
    using var http = new HttpClient(new SocketsHttpHandler { AllowAutoRedirect = false })
    {
        Timeout = TimeSpan.FromSeconds(8)
    };
    var authority = new StoreKitSubscriptionAuthority(http, verifier, bearerToken);
    var caseId = await store.ApproveRecoveryAsync(args[0].Trim(), oldAppAccountToken,
        targetAccountId,
        (request, token) => request.Environment is null
            ? Task.FromException<VerifiedStoreKitTransaction>(new TrustException("recovery_authority_unavailable", "The stored purchase environment is missing. Submit the verified purchase again before retrying Support recovery."))
            : authority.GetCurrentActiveSubscriptionAsync(request.OriginalTransactionId,
                request.OldAppAccountToken, request.ProductId, request.Environment, DateTimeOffset.UtcNow, token),
        DateTimeOffset.UtcNow, CancellationToken.None);
    Console.WriteLine($"Approved Support recovery case {caseId}. No entitlement was granted; the target account must resubmit the verified purchase.");
    return 0;
}
catch (TrustException exception)
{
    Console.Error.WriteLine($"Approval rejected ({exception.Code}): {exception.Message}");
    return 1;
}
catch
{
    Console.Error.WriteLine("Approval failed. Check the protected operator environment and database availability.");
    return 1;
}
