using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using TrustApi.Configuration;
using TrustApi.Infrastructure.AgeAssurance;
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

    [Theory]
    [InlineData("Sandbox")]
    [InlineData("Production")]
    public void VerifyAppTransactionAcceptsOfficialReceiptClaims(string receiptType)
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates, ["Sandbox", "Production"]);
        const string appTransactionId = "apple-app-transaction-123";
        var receiptCreationDate = DateTimeOffset.UtcNow.AddMinutes(-1);
        var appTransaction = CreateSignedPayload(certificates, new
        {
            appTransactionId,
            bundleId = BundleId,
            receiptType,
            receiptCreationDate = receiptCreationDate.ToUnixTimeMilliseconds()
        });

        var result = verifier.VerifyAppTransaction(appTransaction);

        Assert.True(result.IsValid, result.Error);
        Assert.Equal(appTransactionId, result.AppTransaction?.AppTransactionId);
        Assert.Equal(receiptType, result.AppTransaction?.Environment);
    }

    [Fact]
    public void VerifyAppTransactionRejectsEnvironmentAliasWithoutReceiptType()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates, ["Sandbox", "Production"]);
        var appTransaction = CreateSignedPayload(certificates, new
        {
            appTransactionId = "apple-app-transaction-123",
            bundleId = BundleId,
            environment = "Sandbox",
            signedDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        });

        var result = verifier.VerifyAppTransaction(appTransaction);

        Assert.False(result.IsValid);
        Assert.Null(result.AppTransaction);
    }

    [Fact]
    public void VerifyAppTransactionRejectsInvalidOfficialClaimsAndSignature()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates, ["Sandbox", "Production"]);
        var validCreationDate = DateTimeOffset.UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds();
        var invalidPayloads = new object[]
        {
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptCreationDate"] = validCreationDate
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptType"] = 7,
                ["receiptCreationDate"] = validCreationDate
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptType"] = "Xcode",
                ["receiptCreationDate"] = validCreationDate
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = "com.example.other",
                ["receiptType"] = "Sandbox",
                ["receiptCreationDate"] = validCreationDate
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptType"] = "Sandbox"
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptType"] = "Sandbox",
                ["receiptCreationDate"] = "not-a-timestamp"
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptType"] = "Sandbox",
                ["receiptCreationDate"] = long.MaxValue
            },
            new Dictionary<string, object?>
            {
                ["appTransactionId"] = "apple-app-transaction-123",
                ["bundleId"] = BundleId,
                ["receiptType"] = "Sandbox",
                ["receiptCreationDate"] = DateTimeOffset.UtcNow.AddMinutes(6).ToUnixTimeMilliseconds()
            }
        };

        foreach (var payload in invalidPayloads)
        {
            var result = verifier.VerifyAppTransaction(CreateSignedPayload(certificates, payload));
            Assert.False(result.IsValid);
            Assert.Null(result.AppTransaction);
        }

        var signedAppTransaction = CreateSignedPayload(certificates, new
        {
            appTransactionId = "apple-app-transaction-123",
            bundleId = BundleId,
            receiptType = "Sandbox",
            receiptCreationDate = validCreationDate
        });
        var segments = signedAppTransaction.Split('.');
        segments[2] = (segments[2][0] == 'A' ? 'B' : 'A') + segments[2][1..];

        var badSignatureResult = verifier.VerifyAppTransaction(string.Join('.', segments));

        Assert.False(badSignatureResult.IsValid);
        Assert.Null(badSignatureResult.AppTransaction);
    }

    [Fact]
    public async Task AppTransactionEndpointAcceptsOfficialSignedPayload()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates, ["Sandbox", "Production"]);
        using var factory = new TrustApiFactory();
        using var configuredFactory = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IStoreKitTransactionVerifier>();
                services.AddSingleton<IStoreKitTransactionVerifier>(verifier);
            });
        });
        using var client = configuredFactory.CreateClient();

        using var sessionResponse = await client.PostAsJsonAsync("/api/v1/session/development", new
        {
            displayName = "Migration Fixture",
            deviceId = Guid.NewGuid().ToString("N")
        });
        sessionResponse.EnsureSuccessStatusCode();
        using var session = JsonDocument.Parse(await sessionResponse.Content.ReadAsStringAsync());
        var token = session.RootElement.GetProperty("token").GetString();
        var accountId = session.RootElement.GetProperty("you").GetProperty("id").GetGuid();
        Assert.False(string.IsNullOrWhiteSpace(token));

        using var request = new HttpRequestMessage(HttpMethod.Put, "/api/v1/age-assurance/app-transaction");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new
        {
            signedAppTransactionInfo = CreateSignedPayload(certificates, new
            {
                appTransactionId = "synthetic-app-transaction-registration",
                bundleId = BundleId,
                receiptType = "Sandbox",
                receiptCreationDate = DateTimeOffset.UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds()
            })
        });

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.True(await configuredFactory.Services.GetRequiredService<IAgeAssuranceAccountStore>()
            .HasAppTransactionLinkAsync(accountId, CancellationToken.None));
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
            version = "2.0",
            signedDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
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
            version = "2.0",
            signedDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
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

    [Fact]
    public void VerifyNotificationAcceptsConsentRevocationWithMatchingAppTransaction()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);
        const string appTransactionId = "apple-app-transaction-123";
        var appTransaction = CreateSignedPayload(certificates, new
        {
            appTransactionId,
            bundleId = BundleId,
            receiptType = "Sandbox",
            receiptCreationDate = DateTimeOffset.UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds()
        });
        var notificationId = Guid.NewGuid();
        var signedAt = DateTimeOffset.UtcNow.AddSeconds(-10);
        var notification = CreateSignedPayload(certificates, new
        {
            version = "2.0",
            signedDate = signedAt.ToUnixTimeMilliseconds(),
            notificationType = "RESCIND_CONSENT",
            notificationUUID = notificationId,
            appData = new
            {
                bundleId = BundleId,
                environment = "sandbox",
                signedAppTransactionInfo = appTransaction
            }
        });

        var result = verifier.VerifyNotification(notification);

        Assert.True(result.IsValid, result.Error);
        Assert.Equal(notificationId, result.NotificationId);
        Assert.Equal("RESCIND_CONSENT", result.NotificationType);
        Assert.Null(result.Transaction);
        Assert.Equal(appTransactionId, result.RevokedAppTransaction?.AppTransactionId);
        Assert.Equal("Sandbox", result.RevokedAppTransaction?.Environment);
        Assert.Equal(signedAt.ToUnixTimeMilliseconds(), result.SignedAt?.ToUnixTimeMilliseconds());
    }

    [Fact]
    public void VerifyNotificationRejectsConsentRevocationForAnotherBundle()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates);
        var appTransaction = CreateSignedPayload(certificates, new
        {
            appTransactionId = "apple-app-transaction-123",
            bundleId = "com.example.other",
            receiptType = "Sandbox",
            receiptCreationDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        });
        var notification = CreateSignedPayload(certificates, new
        {
            version = "2.0",
            signedDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            notificationType = "RESCIND_CONSENT",
            notificationUUID = Guid.NewGuid(),
            appData = new
            {
                bundleId = BundleId,
                environment = "Sandbox",
                signedAppTransactionInfo = appTransaction
            }
        });

        var result = verifier.VerifyNotification(notification);

        Assert.False(result.IsValid);
        Assert.Null(result.RevokedAppTransaction);
    }

    [Fact]
    public void VerifyNotificationRejectsConsentRevocationWithMismatchedReceiptType()
    {
        using var certificates = TestCertificates.Create();
        var verifier = CreateVerifier(certificates, ["Sandbox", "Production"]);
        var appTransaction = CreateSignedPayload(certificates, new
        {
            appTransactionId = "apple-app-transaction-123",
            bundleId = BundleId,
            receiptType = "Production",
            receiptCreationDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        });
        var notification = CreateSignedPayload(certificates, new
        {
            version = "2.0",
            signedDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            notificationType = "RESCIND_CONSENT",
            notificationUUID = Guid.NewGuid(),
            appData = new
            {
                bundleId = BundleId,
                environment = "Sandbox",
                signedAppTransactionInfo = appTransaction
            }
        });

        var result = verifier.VerifyNotification(notification);

        Assert.False(result.IsValid);
        Assert.Null(result.RevokedAppTransaction);
    }

    private static StoreKitTransactionVerifier CreateVerifier(
        TestCertificates certificates,
        string[]? allowedEnvironments = null) =>
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
                AllowedEnvironments = allowedEnvironments ?? ["Sandbox"]
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
