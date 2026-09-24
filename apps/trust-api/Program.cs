using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using TrustApi.Api.V1;
using TrustApi.Application;
using TrustApi.Configuration;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Notifications;
using TrustApi.Infrastructure.Phone;
using TrustApi.Infrastructure.Postgres;
using TrustApi.Infrastructure.StoreKit;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<AuthOptions>(builder.Configuration.GetSection(AuthOptions.SectionName));
builder.Services.Configure<AppleOptions>(builder.Configuration.GetSection(AppleOptions.SectionName));
builder.Services.Configure<GoogleOptions>(builder.Configuration.GetSection(GoogleOptions.SectionName));
builder.Services.Configure<TrustProductOptions>(builder.Configuration.GetSection(TrustProductOptions.SectionName));
builder.Services.Configure<StripeOptions>(builder.Configuration.GetSection(StripeOptions.SectionName));
builder.Services.Configure<StoreKitOptions>(builder.Configuration.GetSection(StoreKitOptions.SectionName));
builder.Services.PostConfigure<StoreKitOptions>(options =>
{
    if (options.TrustedRootCertificates.Length == 0)
    {
        options.TrustedRootCertificates = AppleRootCertificates.LoadEmbedded();
    }
});
builder.Services.Configure<ApnsOptions>(builder.Configuration.GetSection(ApnsOptions.SectionName));
builder.Services.Configure<TwilioOptions>(builder.Configuration.GetSection(TwilioOptions.SectionName));
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    if (builder.Configuration.GetValue<bool>("ForwardedHeaders:TrustPlatformProxy"))
    {
        options.KnownNetworks.Clear();
        options.KnownProxies.Clear();
    }
});

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddRazorPages();

// Auth hygiene: coarse per-IP rate limits on session issuance, invites, location ingest, and
// Look/View. Windows are generous enough to never trip normal app usage or the test suite —
// this is a floor against scripted abuse, not a strict per-user quota.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    static string PartitionKey(HttpContext context) =>
        context.Connection.RemoteIpAddress?.ToString() ?? "local";

    options.AddPolicy(RateLimitPolicies.Auth, context => RateLimitPartition.GetFixedWindowLimiter(
        PartitionKey(context),
        _ => new FixedWindowRateLimiterOptions { Window = TimeSpan.FromMinutes(1), PermitLimit = 30, QueueLimit = 0 }));

    options.AddPolicy(RateLimitPolicies.Invite, context => RateLimitPartition.GetFixedWindowLimiter(
        PartitionKey(context),
        _ => new FixedWindowRateLimiterOptions { Window = TimeSpan.FromMinutes(1), PermitLimit = 30, QueueLimit = 0 }));

    options.AddPolicy(RateLimitPolicies.PhoneSend, context => RateLimitPartition.GetFixedWindowLimiter(
        PartitionKey(context),
        _ => new FixedWindowRateLimiterOptions { Window = TimeSpan.FromMinutes(1), PermitLimit = 5, QueueLimit = 0 }));

    options.AddPolicy(RateLimitPolicies.PhoneVerify, context => RateLimitPartition.GetFixedWindowLimiter(
        PartitionKey(context),
        _ => new FixedWindowRateLimiterOptions { Window = TimeSpan.FromMinutes(1), PermitLimit = 15, QueueLimit = 0 }));

    options.AddPolicy(RateLimitPolicies.Location, context => RateLimitPartition.GetFixedWindowLimiter(
        PartitionKey(context),
        _ => new FixedWindowRateLimiterOptions { Window = TimeSpan.FromMinutes(1), PermitLimit = 120, QueueLimit = 0 }));

    options.AddPolicy(RateLimitPolicies.Look, context => RateLimitPartition.GetFixedWindowLimiter(
        PartitionKey(context),
        _ => new FixedWindowRateLimiterOptions { Window = TimeSpan.FromMinutes(1), PermitLimit = 60, QueueLimit = 0 }));
});
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
    options.SerializerOptions.Converters.Add(new UtcDateTimeOffsetConverter());
});

var authOptions = builder.Configuration.GetSection(AuthOptions.SectionName).Get<AuthOptions>() ?? new AuthOptions();
AuthOptionsGuard.EnsureDevelopmentSignInIsSafe(authOptions, builder.Environment.IsDevelopment());

if (builder.Environment.IsDevelopment() && string.IsNullOrWhiteSpace(authOptions.SigningKey))
{
    authOptions.SigningKey = "development-signing-key-32bytes-min!!";
}

builder.Services.AddSingleton(authOptions);
builder.Services.AddSingleton(builder.Configuration.GetSection(AppleOptions.SectionName).Get<AppleOptions>() ?? new AppleOptions());
builder.Services.AddSingleton(builder.Configuration.GetSection(GoogleOptions.SectionName).Get<GoogleOptions>() ?? new GoogleOptions());
builder.Services.AddSingleton<SessionIssuer>();
builder.Services.AddSingleton<IAppleIdentityValidator, AppleIdentityValidator>();
builder.Services.AddSingleton<IGoogleIdentityValidator, GoogleIdentityValidator>();

var storeMode = builder.Configuration["Trust:Store"] ?? "postgres";
if (string.Equals(storeMode, "memory", StringComparison.OrdinalIgnoreCase)
    && !builder.Environment.IsDevelopment())
{
    throw new InvalidOperationException(
        "Trust:Store=memory is a Development/test fallback. Location history must persist in Postgres.");
}

if (string.Equals(storeMode, "memory", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddSingleton<ITrustStore, MemoryTrustStore>();
    builder.Services.AddSingleton<IPushDeviceStore, MemoryPushDeviceStore>();
    builder.Services.AddSingleton<IStoreKitEntitlementStore>(services =>
        new MemoryStoreKitEntitlementStore(services.GetRequiredService<ITrustStore>()));
    builder.Services.AddHealthChecks().AddCheck("memory", () =>
        Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy(), ["ready"]);
}
else
{
    var connectionString = builder.Configuration.GetConnectionString("Postgres")
        ?? throw new InvalidOperationException("ConnectionStrings:Postgres is required when Trust:Store=postgres.");
    builder.Services.AddSingleton<ITrustStore>(_ => new PostgresTrustStore(connectionString));
    builder.Services.AddSingleton<IPushDeviceStore>(_ => new PostgresPushDeviceStore(connectionString));
    builder.Services.AddSingleton<IStoreKitEntitlementStore>(_ => new PostgresStoreKitEntitlementStore(connectionString));
    builder.Services.AddHealthChecks().AddCheck("postgres", () =>
    {
        try
        {
            using var connection = new NpgsqlConnection(PostgresConnectionString.Normalize(connectionString));
            connection.Open();
            using var command = new NpgsqlCommand("SELECT 1;", connection);
            command.ExecuteScalar();
            return Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy();
        }
        catch (Exception exception)
        {
            return Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Unhealthy(exception.Message);
        }
    }, ["ready"]);
}

builder.Services.AddSingleton<IStoreKitTransactionVerifier, StoreKitTransactionVerifier>();
builder.Services.AddHttpClient<ApnsClient>();
builder.Services.AddSingleton<ILookReceiptPublisher, LookReceiptPublisher>();
builder.Services.AddHttpClient("twilio");
builder.Services.AddSingleton<ISmsOtpSender, TwilioSmsSender>();
builder.Services.AddSingleton<PhoneVerificationService>();
builder.Services.AddSingleton<TrustEngine>();
builder.Services.AddHostedService<TrustSweepService>();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = authOptions.Issuer,
            ValidateAudience = true,
            ValidAudience = authOptions.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SessionIssuer.RequireKey(authOptions.SigningKey))),
            ValidateLifetime = true,
            NameClaimType = "sub",
            ClockSkew = TimeSpan.FromMinutes(2)
        };
    });
builder.Services.AddAuthorization();

var app = builder.Build();

app.UseForwardedHeaders();
app.UseRateLimiter();

if (!string.Equals(storeMode, "memory", StringComparison.OrdinalIgnoreCase))
{
    var connectionString = builder.Configuration.GetConnectionString("Postgres")
        ?? throw new InvalidOperationException("ConnectionStrings:Postgres is required.");
    await PostgresMigrator.ApplyAsync(connectionString);
}

app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();
app.MapTrustApiV1();
app.MapGet("/i/{code}", (string code) =>
{
    var sanitized = new string(code.Where(char.IsLetterOrDigit).Take(12).ToArray());
    var deepLink = $"trust://invite/{sanitized}";
    var html = $"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Trust invite</title>
          <meta http-equiv="refresh" content="0;url={deepLink}" />
        </head>
        <body style="font-family:Helvetica,Arial,sans-serif;background:#fff;color:#000;padding:2rem;">
          <p>I trust you with my location.</p>
          <p><a href="{deepLink}">Open in Trust</a></p>
        </body>
        </html>
        """;
    return Results.Content(html, "text/html; charset=utf-8");
});
app.MapGet("/.well-known/apple-app-site-association", () => Results.Json(new
{
    applinks = new
    {
        apps = Array.Empty<string>(),
        details = new[]
        {
            new
            {
                appID = "3S529795M9.com.collapsetechnologies.trust",
                paths = new[] { "/i/*" }
            }
        }
    }
}));
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = registration => registration.Tags.Contains("ready")
});

app.Run();

public partial class Program;

internal sealed class UtcDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString() ?? throw new JsonException("Date was null.");
        return DateTimeOffset.Parse(text, null, System.Globalization.DateTimeStyles.RoundtripKind);
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"));
    }
}
