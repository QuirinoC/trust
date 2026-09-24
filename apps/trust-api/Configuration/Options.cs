using Npgsql;

namespace TrustApi.Configuration;

public static class PostgresConnectionString
{
    public static string Normalize(string value)
    {
        if (!value.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase)
            && !value.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            return value;
        }

        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || string.IsNullOrWhiteSpace(uri.Host)
            || string.IsNullOrWhiteSpace(uri.AbsolutePath.Trim('/')))
        {
            throw new InvalidOperationException("The PostgreSQL URI is not valid.");
        }

        var userInfoSeparator = uri.UserInfo.IndexOf(':');
        if (userInfoSeparator <= 0)
        {
            throw new InvalidOperationException("The PostgreSQL URI must include a username and password.");
        }

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.IsDefaultPort ? 5432 : uri.Port,
            Database = Uri.UnescapeDataString(uri.AbsolutePath.TrimStart('/')),
            Username = Uri.UnescapeDataString(uri.UserInfo[..userInfoSeparator]),
            Password = Uri.UnescapeDataString(uri.UserInfo[(userInfoSeparator + 1)..])
        };
        return builder.ConnectionString;
    }
}

public sealed class AuthOptions
{
    public const string SectionName = "Auth";
    public string Issuer { get; set; } = "trust";
    public string Audience { get; set; } = "com.collapsetechnologies.trust";
    public string SigningKey { get; set; } = "";
    public bool AllowDevelopmentSignIn { get; set; }
}

public sealed class AppleOptions
{
    public const string SectionName = "Apple";
    public string BundleId { get; set; } = "com.collapsetechnologies.trust";
}

public sealed class GoogleOptions
{
    public const string SectionName = "Google";
    public string[] ClientIds { get; set; } = [];
}

public sealed class TrustProductOptions
{
    public const string SectionName = "Trust";
    public string Store { get; set; } = "postgres";
    public bool SeedReviewCircle { get; set; }
}

public sealed class StripeOptions
{
    public const string SectionName = "Stripe";
    public bool Enabled { get; set; }
    public string SecretKey { get; set; } = "";
    public string WebhookSecret { get; set; } = "";
    public string ProductId { get; set; } = "prod_trust_circle";
    public string PriceMonthly { get; set; } = "";
    public string PriceAnnual { get; set; } = "";
    public string SuccessUrl { get; set; } = "";
    public string CancelUrl { get; set; } = "";
}

public sealed class StoreKitOptions
{
    public const string SectionName = "StoreKit";
    public bool Enabled { get; set; }
    public bool AllowReviewUnlock { get; set; }
    public string BundleId { get; set; } = "com.collapsetechnologies.trust";
    public string MonthlyProductId { get; set; } = "com.collapsetechnologies.trust.circle.monthly";
    public string AnnualProductId { get; set; } = "com.collapsetechnologies.trust.circle.annual";
    public string[] TrustedRootCertificates { get; set; } = [];
    public string[] AllowedEnvironments { get; set; } = ["Production", "Sandbox"];
}

public sealed class ApnsOptions
{
    public const string SectionName = "Apns";
    public bool Enabled { get; set; }
    public string TeamId { get; set; } = "3S529795M9";
    public string KeyId { get; set; } = "";
    public string PrivateKey { get; set; } = "";
    public string BundleId { get; set; } = "com.collapsetechnologies.trust";
}

public sealed class TwilioOptions
{
    public const string SectionName = "Twilio";
    public string AccountSid { get; set; } = "";
    public string AuthToken { get; set; } = "";
    public string FromNumber { get; set; } = "";
    public string MessagingServiceSid { get; set; } = "";

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(AccountSid)
        && !string.IsNullOrWhiteSpace(AuthToken)
        && (!string.IsNullOrWhiteSpace(FromNumber) || !string.IsNullOrWhiteSpace(MessagingServiceSid));
}
