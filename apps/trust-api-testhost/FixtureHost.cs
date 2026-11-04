using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;
using TrustApi.Infrastructure.Identity;
using TrustApi.Infrastructure.Phone;
using TrustApi.Configuration;

namespace TrustApiLocalTestHost;

// This sibling project is never referenced by the product or its Docker image.
// It exists solely for an explicitly selected local simulator test lane.
internal static class FixtureHost
{
    public static async Task Main(string[] args)
    {
        if (Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") != "Development"
            || Environment.GetEnvironmentVariable("ASPNETCORE_URLS") != "http://127.0.0.1:5090")
            throw new InvalidOperationException("Signed identity test host requires Development and loopback port 5090.");

        Environment.SetEnvironmentVariable("ASPNETCORE_TEST_CONTENTROOT_TRUSTAPI", SignedIdentityFactory.ProductRoot);
        using var rsa = RSA.Create(2048);
        var key = new RsaSecurityKey(rsa);
        using var factory = new SignedIdentityFactory(key);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        var builder = WebApplication.CreateBuilder(args);
        builder.Logging.ClearProviders(); // Request URLs and identity proofs must never be logged.
        builder.WebHost.UseUrls("http://127.0.0.1:5090");
        var app = builder.Build();
        app.MapGet("/__test/signed-apple-fixture", () => Results.Json(new { signedAppleFixture = true, noSms = true }));
        app.MapGet("/__test/apple-identity", (HttpContext context, string? subject, string? nonce, string? displayName) =>
        {
            if (context.Connection.RemoteIpAddress is not { } remote || !IPAddress.IsLoopback(remote)
                || subject is null || !Regex.IsMatch(subject, "^[A-Za-z0-9_-]{8,100}$")
                || nonce is null || !Regex.IsMatch(nonce, "^[a-fA-F0-9]{64}$")
                || displayName is null || displayName.Length is < 1 or > 100)
                return Results.BadRequest();
            var now = DateTimeOffset.UtcNow;
            var claims = new[] { new Claim("sub", subject), new Claim("nonce", nonce),
                new Claim("name", displayName), new Claim("iat", now.ToUnixTimeSeconds().ToString(), ClaimValueTypes.Integer64),
                new Claim("auth_time", now.ToUnixTimeSeconds().ToString(), ClaimValueTypes.Integer64) };
            var jwt = new JwtSecurityToken(FixtureIdentity.Issuer, FixtureIdentity.Audience, claims,
                now.UtcDateTime.AddSeconds(-1), now.UtcDateTime.AddMinutes(5),
                new SigningCredentials(key, SecurityAlgorithms.RsaSha256));
            context.Response.Headers.CacheControl = "no-store";
            return Results.Json(new { identityToken = new JwtSecurityTokenHandler().WriteToken(jwt) });
        });
        app.MapFallback(async context =>
        {
            using var request = new HttpRequestMessage(new HttpMethod(context.Request.Method),
                context.Request.Path + context.Request.QueryString);
            if (context.Request.ContentLength is > 0 || context.Request.Headers.ContainsKey("Transfer-Encoding"))
                request.Content = new StreamContent(context.Request.Body);
            foreach (var header in context.Request.Headers)
            {
                if (header.Key.Equals("Host", StringComparison.OrdinalIgnoreCase)) continue;
                if (!request.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray()))
                    request.Content?.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray());
            }
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, context.RequestAborted);
            context.Response.StatusCode = (int)response.StatusCode;
            foreach (var header in response.Headers.Concat(response.Content.Headers))
                context.Response.Headers[header.Key] = header.Value.ToArray();
            context.Response.Headers.Remove("transfer-encoding");
            await response.Content.CopyToAsync(context.Response.Body, context.RequestAborted);
        });
        Console.WriteLine("SIGNED-APPLE-FIXTURE: local synthetic identity; not Apple evidence");
        await app.RunAsync();
    }
}

internal sealed class SignedIdentityFactory(RsaSecurityKey key) : WebApplicationFactory<global::Program>
{
    public static string ProductRoot => Path.GetFullPath("../../../../trust-api", AppContext.BaseDirectory);
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureLogging(logging => logging.ClearProviders());
        builder.UseContentRoot(ProductRoot);
        builder.UseSetting("Auth:AllowDevelopmentSignIn", "false");
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Auth:AllowDevelopmentSignIn"] = "false"
        }));
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IAppleIdentityValidator>();
            services.RemoveAll<ISmsOtpSender>();
            services.AddSingleton<ISmsOtpSender, NoSmsFixture>();
            services.AddSingleton<IAppleIdentityValidator>(new FixtureIdentity(key));
        });
    }
}

internal sealed class FixtureIdentity(RsaSecurityKey key) : IAppleIdentityValidator
{
    public const string Issuer = "https://fixture.invalid";
    public const string Audience = "trust-local-simulator-fixture";
    public Task<ExternalIdentity> ValidateAsync(string token, CancellationToken cancellationToken)
    {
        var parameters = new TokenValidationParameters
        {
            ValidIssuer = Issuer, ValidAudience = Audience, IssuerSigningKey = key,
            ValidateIssuer = true, ValidateAudience = true, ValidateLifetime = true,
            ValidateIssuerSigningKey = true, RequireSignedTokens = true,
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256], ClockSkew = TimeSpan.Zero
        };
        return Task.FromResult(ExternalIdentityTokens.Read(token, parameters, "apple"));
    }
}

internal sealed class NoSmsFixture : ISmsOtpSender
{
    public bool IsConfigured => false;
    public Task SendAsync(string e164, string code, CancellationToken cancellationToken) => throw new InvalidOperationException("Local fixture never sends SMS.");
    public Task SendTextAsync(string e164, string body, CancellationToken cancellationToken) => throw new InvalidOperationException("Local fixture never sends SMS.");
}
