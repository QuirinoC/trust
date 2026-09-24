using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TrustApi.Configuration;

namespace TrustApi.Infrastructure.Notifications;

public enum ApnsDeliveryResult
{
    Delivered,
    InvalidToken,
    Retry,
    Disabled
}

public sealed record ApnsDeliveryOutcome(ApnsDeliveryResult Result, string? Error = null);

public sealed record PushDevice(
    Guid InstallationId,
    Guid AccountId,
    string Token,
    string Environment,
    string BundleId,
    bool Enabled);

public interface IPushDeviceStore
{
    Task RegisterAsync(
        Guid accountId,
        Guid installationId,
        string token,
        string environment,
        string bundleId,
        CancellationToken cancellationToken);

    Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken);

    Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken);

    Task InvalidateTokenAsync(string token, CancellationToken cancellationToken);

    Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid accountId, CancellationToken cancellationToken);
}

public sealed class ApnsClient(HttpClient httpClient, IOptions<ApnsOptions> options)
{
    private readonly ApnsOptions options = options.Value;
    private readonly object tokenLock = new();
    private string? providerToken;
    private DateTimeOffset providerTokenExpiresAt;

    public bool IsConfigured =>
        options.Enabled
        && !string.IsNullOrWhiteSpace(options.KeyId)
        && !string.IsNullOrWhiteSpace(options.TeamId)
        && !string.IsNullOrWhiteSpace(options.PrivateKey);

    public async ValueTask<ApnsDeliveryOutcome> SendLookReceiptAsync(
        PushDevice device,
        string title,
        string body,
        CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return new ApnsDeliveryOutcome(ApnsDeliveryResult.Disabled, "APNs is not configured.");
        }

        var host = device.Environment == "sandbox"
            ? "https://api.sandbox.push.apple.com"
            : "https://api.push.apple.com";
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{host}/3/device/{device.Token}")
        {
            Version = HttpVersion.Version20,
            VersionPolicy = HttpVersionPolicy.RequestVersionOrHigher,
            Content = new StringContent(
                JsonSerializer.Serialize(new
                {
                    aps = new Dictionary<string, object?>
                    {
                        ["alert"] = new { title, body },
                        ["sound"] = "default",
                        ["interruption-level"] = "active",
                        ["thread-id"] = "trust.look"
                    },
                    trust = new { kind = "look" }
                }),
                Encoding.UTF8,
                "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("bearer", GetProviderToken());
        request.Headers.TryAddWithoutValidation("apns-topic", string.IsNullOrWhiteSpace(device.BundleId) ? options.BundleId : device.BundleId);
        request.Headers.TryAddWithoutValidation("apns-push-type", "alert");
        request.Headers.TryAddWithoutValidation("apns-priority", "10");

        try
        {
            using var response = await httpClient.SendAsync(request, cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                return new ApnsDeliveryOutcome(ApnsDeliveryResult.Delivered);
            }

            var error = await response.Content.ReadAsStringAsync(cancellationToken);
            var reason = TryReadReason(error);
            if (response.StatusCode == HttpStatusCode.Gone
                || reason is "BadDeviceToken" or "Unregistered" or "DeviceTokenNotForTopic")
            {
                return new ApnsDeliveryOutcome(ApnsDeliveryResult.InvalidToken, reason);
            }

            return new ApnsDeliveryOutcome(
                ApnsDeliveryResult.Retry,
                $"{(int)response.StatusCode}: {reason ?? "APNs request failed"}");
        }
        catch (HttpRequestException exception)
        {
            return new ApnsDeliveryOutcome(ApnsDeliveryResult.Retry, exception.Message);
        }
    }

    private string GetProviderToken()
    {
        lock (tokenLock)
        {
            var now = DateTimeOffset.UtcNow;
            if (providerToken is not null && providerTokenExpiresAt > now.AddMinutes(5))
            {
                return providerToken;
            }

            var header = Base64Url(JsonSerializer.Serialize(new
            {
                alg = "ES256",
                kid = options.KeyId
            }));
            var payload = Base64Url(
                JsonSerializer.Serialize(new
                {
                    iss = options.TeamId,
                    iat = now.ToUnixTimeSeconds()
                }));
            var unsigned = $"{header}.{payload}";
            using var key = ECDsa.Create();
            var pem = options.PrivateKey.Replace("\\n", "\n", StringComparison.Ordinal).Trim();
            if (pem.Contains("BEGIN", StringComparison.Ordinal))
            {
                key.ImportFromPem(pem);
            }
            else
            {
                key.ImportPkcs8PrivateKey(Convert.FromBase64String(pem), out _);
            }

            var signature = key.SignData(
                Encoding.UTF8.GetBytes(unsigned),
                HashAlgorithmName.SHA256,
                DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
            providerToken = $"{unsigned}.{Base64Url(signature)}";
            providerTokenExpiresAt = now.AddMinutes(50);
            return providerToken;
        }
    }

    private static string Base64Url(string value) =>
        Base64Url(Encoding.UTF8.GetBytes(value));

    private static string Base64Url(byte[] value) =>
        Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    private static string? TryReadReason(string payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);
            return document.RootElement.TryGetProperty("reason", out var reason)
                ? reason.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
