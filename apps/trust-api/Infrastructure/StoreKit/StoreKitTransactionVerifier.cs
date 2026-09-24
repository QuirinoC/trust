using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TrustApi.Configuration;

namespace TrustApi.Infrastructure.StoreKit;

public sealed class StoreKitTransactionVerifier(
    IOptions<StoreKitOptions> options,
    TimeProvider timeProvider) : IStoreKitTransactionVerifier
{
    private const string AppStoreReceiptSigningOid = "1.2.840.113635.100.6.11.1";
    private static readonly JsonDocumentOptions JsonOptions = new()
    {
        MaxDepth = 16
    };
    private readonly StoreKitOptions _options = options.Value;
    private readonly X509Certificate2Collection _trustedRoots =
        LoadCertificates(options.Value.TrustedRootCertificates);

    public StoreKitVerificationResult Verify(string signedTransaction)
    {
        if (!TryVerifyPayload(signedTransaction, out var payloadBytes, out var error))
        {
            return Invalid(error);
        }

        try
        {
            using var payload = JsonDocument.Parse(payloadBytes, JsonOptions);
            return ParsePayload(payload.RootElement);
        }
        catch (JsonException)
        {
            return Invalid("The signed transaction contains invalid JSON.");
        }
    }

    public StoreKitNotificationVerificationResult VerifyNotification(string signedPayload)
    {
        if (!TryVerifyPayload(signedPayload, out var payloadBytes, out var error))
        {
            return InvalidNotification(error);
        }

        try
        {
            using var payload = JsonDocument.Parse(payloadBytes, JsonOptions);
            var root = payload.RootElement;
            if (!TryGetString(root, "notificationType", out var notificationType)
                || !TryGetString(root, "notificationUUID", out var rawNotificationId)
                || !Guid.TryParse(rawNotificationId, out var notificationId)
                || !root.TryGetProperty("data", out var data)
                || data.ValueKind != JsonValueKind.Object)
            {
                return InvalidNotification("The StoreKit notification claims are invalid.");
            }

            if (!data.TryGetProperty("signedTransactionInfo", out var transactionProperty))
            {
                return new StoreKitNotificationVerificationResult(
                    true,
                    notificationId,
                    notificationType,
                    null,
                    null);
            }

            if (transactionProperty.ValueKind != JsonValueKind.String)
            {
                return InvalidNotification(
                    "The StoreKit notification contains an invalid transaction.");
            }

            var transaction = Verify(transactionProperty.GetString() ?? string.Empty);
            return transaction.IsValid
                ? new StoreKitNotificationVerificationResult(
                    true,
                    notificationId,
                    notificationType,
                    transaction.Transaction,
                    null)
                : InvalidNotification(transaction.Error ?? "The nested transaction is invalid.");
        }
        catch (JsonException)
        {
            return InvalidNotification("The StoreKit notification contains invalid JSON.");
        }
    }

    private bool TryVerifyPayload(
        string signedJws,
        out byte[] payloadBytes,
        out string error)
    {
        payloadBytes = [];
        error = string.Empty;
        if (string.IsNullOrWhiteSpace(signedJws)
            || signedJws.Length > 32_768)
        {
            error = "The signed StoreKit payload is missing or too large.";
            return false;
        }

        var segments = signedJws.Split('.');
        if (segments.Length != 3
            || !TryDecode(segments[0], out var headerBytes)
            || !TryDecode(segments[1], out payloadBytes)
            || !TryDecode(segments[2], out var signature))
        {
            error = "The signed StoreKit payload is not a valid JWS.";
            return false;
        }

        try
        {
            using var header = JsonDocument.Parse(headerBytes, JsonOptions);
            if (!header.RootElement.TryGetProperty("alg", out var algorithm)
                || algorithm.GetString() != "ES256"
                || !TryReadCertificateChain(header.RootElement, out var certificates))
            {
                error = "The signed StoreKit payload has an invalid JWS header.";
                return false;
            }

            try
            {
                if (!ValidateCertificateChain(certificates))
                {
                    error = "The StoreKit certificate chain is not trusted.";
                    return false;
                }

                using var publicKey = certificates[0].GetECDsaPublicKey();
                var signedBytes = Encoding.ASCII.GetBytes($"{segments[0]}.{segments[1]}");
                if (publicKey is null
                    || signature.Length != 64
                    || !publicKey.VerifyData(
                        signedBytes,
                        signature,
                        HashAlgorithmName.SHA256,
                        DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
                {
                    error = "The StoreKit signature is invalid.";
                    return false;
                }
            }
            finally
            {
                DisposeCertificates(certificates);
            }

            return true;
        }
        catch (JsonException)
        {
            error = "The signed StoreKit payload contains invalid JSON.";
            return false;
        }
        catch (CryptographicException)
        {
            error = "The signed StoreKit payload contains invalid certificate data.";
            return false;
        }
        catch (FormatException)
        {
            error = "The signed StoreKit payload contains invalid certificate data.";
            return false;
        }
    }

    private StoreKitVerificationResult ParsePayload(JsonElement payload)
    {
        if (!TryGetString(payload, "bundleId", out var bundleId)
            || !string.Equals(bundleId, _options.BundleId, StringComparison.Ordinal)
            || !TryGetString(payload, "productId", out var productId)
            || !IsKnownProduct(productId)
            || !TryGetString(payload, "environment", out var environment)
            || !_options.AllowedEnvironments.Contains(environment, StringComparer.Ordinal)
            || !TryGetString(payload, "transactionId", out var transactionId)
            || !TryGetString(payload, "originalTransactionId", out var originalTransactionId)
            || !TryGetString(payload, "appAccountToken", out var rawToken)
            || !Guid.TryParse(rawToken, out var appAccountToken)
            || !TryGetUnixMilliseconds(payload, "signedDate", out var signedAt)
            || !TryGetUnixMilliseconds(payload, "expiresDate", out var expiresAt))
        {
            return Invalid("The StoreKit transaction claims are invalid.");
        }

        if (signedAt > timeProvider.GetUtcNow().AddMinutes(5))
        {
            return Invalid("The StoreKit transaction is dated in the future.");
        }

        DateTimeOffset? revokedAt = null;
        if (payload.TryGetProperty("revocationDate", out _))
        {
            if (!TryGetUnixMilliseconds(payload, "revocationDate", out var parsedRevocation))
            {
                return Invalid("The StoreKit revocation date is invalid.");
            }

            revokedAt = parsedRevocation;
        }

        return new StoreKitVerificationResult(
            new VerifiedStoreKitTransaction(
                transactionId,
                originalTransactionId,
                productId,
                appAccountToken,
                environment,
                signedAt,
                expiresAt,
                revokedAt),
            null);
    }

    private bool ValidateCertificateChain(X509Certificate2Collection certificates)
    {
        if (certificates.Count < 2
            || _trustedRoots.Count == 0
            || !certificates[0].Extensions.Cast<X509Extension>()
                .Any(extension => extension.Oid?.Value == AppStoreReceiptSigningOid))
        {
            return false;
        }

        using var chain = new X509Chain();
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.VerificationTime = timeProvider.GetUtcNow().UtcDateTime;
        chain.ChainPolicy.CustomTrustStore.AddRange(_trustedRoots);
        for (var index = 1; index < certificates.Count; index++)
        {
            chain.ChainPolicy.ExtraStore.Add(certificates[index]);
        }

        return chain.Build(certificates[0]);
    }

    private static bool TryReadCertificateChain(
        JsonElement header,
        out X509Certificate2Collection certificates)
    {
        certificates = [];
        if (!header.TryGetProperty("x5c", out var x5c)
            || x5c.ValueKind != JsonValueKind.Array
            || x5c.GetArrayLength() is < 2 or > 4)
        {
            return false;
        }

        foreach (var encodedCertificate in x5c.EnumerateArray())
        {
            if (encodedCertificate.ValueKind != JsonValueKind.String)
            {
                DisposeCertificates(certificates);
                certificates = [];
                return false;
            }

            try
            {
                var encoded = encodedCertificate.GetString();
                if (string.IsNullOrWhiteSpace(encoded))
                {
                    DisposeCertificates(certificates);
                    certificates = [];
                    return false;
                }

                certificates.Add(X509CertificateLoader.LoadCertificate(
                    Convert.FromBase64String(encoded)));
            }
            catch (ArgumentException)
            {
                DisposeCertificates(certificates);
                certificates = [];
                return false;
            }
            catch (FormatException)
            {
                DisposeCertificates(certificates);
                certificates = [];
                return false;
            }
            catch (CryptographicException)
            {
                DisposeCertificates(certificates);
                certificates = [];
                return false;
            }
            catch (InvalidOperationException)
            {
                DisposeCertificates(certificates);
                certificates = [];
                return false;
            }
        }

        return true;
    }

    private static X509Certificate2Collection LoadCertificates(IEnumerable<string> encodedRoots)
    {
        var certificates = new X509Certificate2Collection();
        foreach (var encodedRoot in encodedRoots)
        {
            if (!string.IsNullOrWhiteSpace(encodedRoot))
            {
                certificates.Add(X509CertificateLoader.LoadCertificate(
                    Convert.FromBase64String(encodedRoot)));
            }
        }

        return certificates;
    }

    private static void DisposeCertificates(X509Certificate2Collection certificates)
    {
        foreach (var certificate in certificates)
        {
            certificate.Dispose();
        }
    }

    private bool IsKnownProduct(string productId) =>
        string.Equals(productId, _options.MonthlyProductId, StringComparison.Ordinal)
        || string.Equals(productId, _options.AnnualProductId, StringComparison.Ordinal);

    private static bool TryGetString(
        JsonElement payload,
        string propertyName,
        out string value)
    {
        value = string.Empty;
        return payload.TryGetProperty(propertyName, out var property)
            && property.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(value = property.GetString()!);
    }

    private static bool TryGetUnixMilliseconds(
        JsonElement payload,
        string propertyName,
        out DateTimeOffset value)
    {
        value = default;
        if (!payload.TryGetProperty(propertyName, out var property)
            || !property.TryGetInt64(out var milliseconds))
        {
            return false;
        }

        try
        {
            value = DateTimeOffset.FromUnixTimeMilliseconds(milliseconds);
            return true;
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }
    }

    private static bool TryDecode(string segment, out byte[] bytes)
    {
        try
        {
            bytes = Convert.FromBase64String(
                segment.Replace('-', '+').Replace('_', '/')
                + new string('=', (4 - segment.Length % 4) % 4));
            return true;
        }
        catch (FormatException)
        {
            bytes = [];
            return false;
        }
    }

    private static StoreKitVerificationResult Invalid(string error) => new(null, error);

    private static StoreKitNotificationVerificationResult InvalidNotification(string error) =>
        new(false, null, null, null, error);
}
