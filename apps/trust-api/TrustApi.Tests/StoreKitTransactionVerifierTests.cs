using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TrustApi.Configuration;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Tests;

public sealed class StoreKitTransactionVerifierTests
{
    private const string BundleId = "com.collapsetechnologies.trust";
    private const string MonthlyProductId = "com.collapsetechnologies.trust.circle.monthly";
    private const string AnnualProductId = "com.collapsetechnologies.trust.circle.annual";
    private const string SigningOid = "1.2.840.113635.100.6.11.1";

    [Fact]
    public void VerifyAcceptsTrustedStoreKitTransaction()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);
        var token = Guid.NewGuid();
        var signedAt = DateTimeOffset.UtcNow.AddMinutes(-1);
        var expiresAt = signedAt.AddMonths(1);

        var result = verifier.Verify(CreateJws(
            certificates,
            ProductId: MonthlyProductId,
            Token: token,
            SignedAt: signedAt,
            ExpiresAt: expiresAt));

        Assert.True(result.IsValid, result.Error);
        Assert.NotNull(result.Transaction);
        Assert.Equal(token, result.Transaction.AppAccountToken);
        Assert.Equal(MonthlyProductId, result.Transaction.ProductId);
        Assert.Equal(expiresAt.ToUnixTimeMilliseconds(), result.Transaction.ExpiresAt.ToUnixTimeMilliseconds());
    }

    [Fact]
    public void VerifyRejectsTamperedPayload()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);
        var jws = CreateJws(
            certificates,
            ProductId: MonthlyProductId,
            Token: Guid.NewGuid(),
            SignedAt: DateTimeOffset.UtcNow,
            ExpiresAt: DateTimeOffset.UtcNow.AddMonths(1));
        var segments = jws.Split('.');
        var payload = Decode(segments[1]);
        var tamperedPayload = payload.Replace(MonthlyProductId, AnnualProductId);
        segments[1] = Encode(Encoding.UTF8.GetBytes(tamperedPayload));

        var result = verifier.Verify(string.Join('.', segments));

        Assert.False(result.IsValid);
        Assert.Equal("The StoreKit signature is invalid.", result.Error);
    }

    [Fact]
    public void VerifyRejectsUnknownProduct()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);

        var result = verifier.Verify(CreateJws(
            certificates,
            ProductId: "trust.fake",
            Token: Guid.NewGuid(),
            SignedAt: DateTimeOffset.UtcNow,
            ExpiresAt: DateTimeOffset.UtcNow.AddMonths(1)));

        Assert.False(result.IsValid);
        Assert.Equal("The StoreKit transaction claims are invalid.", result.Error);
    }

    [Fact]
    public void VerifyRejectsMalformedCertificateChainWithoutThrowing()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);

        var result = verifier.Verify(CreateMalformedCertificateChainJws());

        Assert.False(result.IsValid);
        Assert.Equal("The signed StoreKit payload has an invalid JWS header.", result.Error);
    }

    [Fact]
    public void VerifyNotificationAcceptsSignedNestedTransaction()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);
        var transaction = CreateJws(
            certificates,
            ProductId: AnnualProductId,
            Token: Guid.NewGuid(),
            SignedAt: DateTimeOffset.UtcNow,
            ExpiresAt: DateTimeOffset.UtcNow.AddYears(1));
        var notificationId = Guid.NewGuid();
        var notification = CreateSignedPayload(certificates, new
        {
            notificationType = "DID_RENEW",
            notificationUUID = notificationId,
            data = new
            {
                signedTransactionInfo = transaction
            }
        });

        var result = verifier.VerifyNotification(notification);

        Assert.True(result.IsValid, result.Error);
        Assert.Equal(notificationId, result.NotificationId);
        Assert.Equal("DID_RENEW", result.NotificationType);
        Assert.Equal(AnnualProductId, result.Transaction?.ProductId);
    }

    [Fact]
    public void VerifyNotificationAcceptsVerifiedNotificationWithoutTransaction()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);
        var notification = CreateSignedPayload(certificates, new
        {
            notificationType = "DID_CHANGE_RENEWAL_STATUS",
            notificationUUID = Guid.NewGuid(),
            data = new
            {
                signedRenewalInfo = "not-used-for-entitlement-state"
            }
        });

        var result = verifier.VerifyNotification(notification);

        Assert.True(result.IsValid, result.Error);
        Assert.Null(result.Transaction);
    }

    private static StoreKitTransactionVerifier CreateVerifier(TestCertificates certificates) =>
        new(
            Options.Create(new StoreKitOptions
            {
                Enabled = true,
                BundleId = BundleId,
                MonthlyProductId = MonthlyProductId,
                AnnualProductId = AnnualProductId,
                TrustedRootCertificates =
                [
                    Convert.ToBase64String(certificates.Root.Export(X509ContentType.Cert))
                ],
                AllowedEnvironments = ["Sandbox"]
            }),
            TimeProvider.System);

    private static string CreateJws(
        TestCertificates certificates,
        string ProductId,
        Guid Token,
        DateTimeOffset SignedAt,
        DateTimeOffset ExpiresAt)
    {
        return CreateSignedPayload(certificates, new
        {
            bundleId = BundleId,
            productId = ProductId,
            environment = "Sandbox",
            transactionId = $"transaction-{Guid.NewGuid():N}",
            originalTransactionId = $"original-{Guid.NewGuid():N}",
            appAccountToken = Token,
            signedDate = SignedAt.ToUnixTimeMilliseconds(),
            expiresDate = ExpiresAt.ToUnixTimeMilliseconds()
        });
    }

    private static string CreateSignedPayload(TestCertificates certificates, object value)
    {
        var header = Encode(JsonSerializer.SerializeToUtf8Bytes(new
        {
            alg = "ES256",
            x5c = new[]
            {
                Convert.ToBase64String(certificates.Leaf.Export(X509ContentType.Cert)),
                Convert.ToBase64String(certificates.Root.Export(X509ContentType.Cert))
            }
        }));
        var payload = Encode(JsonSerializer.SerializeToUtf8Bytes(value));
        var signedData = Encoding.ASCII.GetBytes($"{header}.{payload}");
        using var key = certificates.Leaf.GetECDsaPrivateKey();
        var signature = key!.SignData(
            signedData,
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        return $"{header}.{payload}.{Encode(signature)}";
    }

    private static string CreateMalformedCertificateChainJws()
    {
        var header = Encode(JsonSerializer.SerializeToUtf8Bytes(new
        {
            alg = "ES256",
            x5c = new object[] { 12, "not-a-certificate" }
        }));
        var payload = Encode(JsonSerializer.SerializeToUtf8Bytes(new { }));
        return $"{header}.{payload}.{Encode(new byte[64])}";
    }

    private static string Encode(byte[] value) =>
        Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static string Decode(string value) =>
        Encoding.UTF8.GetString(Convert.FromBase64String(
            value.Replace('-', '+').Replace('_', '/')
            + new string('=', (4 - value.Length % 4) % 4)));

    private sealed class TestCertificates : IDisposable
    {
        private TestCertificates(X509Certificate2 root, X509Certificate2 leaf)
        {
            Root = root;
            Leaf = leaf;
        }

        public X509Certificate2 Root { get; }

        public X509Certificate2 Leaf { get; }

        public static TestCertificates Create()
        {
            using var rootKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var rootRequest = new CertificateRequest(
                "CN=Test StoreKit Root",
                rootKey,
                HashAlgorithmName.SHA256);
            rootRequest.CertificateExtensions.Add(
                new X509BasicConstraintsExtension(true, false, 0, true));
            rootRequest.CertificateExtensions.Add(
                new X509KeyUsageExtension(
                    X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign,
                    true));
            var root = rootRequest.CreateSelfSigned(
                DateTimeOffset.UtcNow.AddDays(-1),
                DateTimeOffset.UtcNow.AddDays(2));

            using var leafKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var leafRequest = new CertificateRequest(
                "CN=Test StoreKit Signing",
                leafKey,
                HashAlgorithmName.SHA256);
            leafRequest.CertificateExtensions.Add(
                new X509BasicConstraintsExtension(false, false, 0, true));
            leafRequest.CertificateExtensions.Add(
                new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
            leafRequest.CertificateExtensions.Add(
                new X509Extension(SigningOid, [0x05, 0x00], false));
            var serial = RandomNumberGenerator.GetBytes(16);
            using var publicLeaf = leafRequest.Create(
                root,
                DateTimeOffset.UtcNow.AddHours(-1),
                DateTimeOffset.UtcNow.AddDays(1),
                serial);
            var leaf = publicLeaf.CopyWithPrivateKey(leafKey);
            return new TestCertificates(root, leaf);
        }

        public void Dispose()
        {
            Leaf.Dispose();
            Root.Dispose();
        }
    }
}
