using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using SkiaSharp;
using TrustApi.Application;
using TrustApi.Domain;

namespace TrustApi.Tests;

public sealed class DiscoveryApiTests
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    [Fact]
    public async Task LegacyHandleSaveStaysPrivateAndMissingConsentPreservesExistingChoice()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var caller = await CreateReadyAccountAsync(factory, client, "Caller");
        var legacy = await CreateReadyAccountAsync(factory, client, "Legacy");

        using (var oldClientSave = Authorized(HttpMethod.Put, "/api/v1/me/handle", legacy.Token))
        {
            oldClientSave.Content = JsonContent.Create(new { handle = legacy.Handle });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(oldClientSave)).StatusCode);
        }

        using (var state = await AuthorizedSendAsync(client, HttpMethod.Get, "/api/v1/circle", legacy.Token))
        using (var stateJson = JsonDocument.Parse(await state.Content.ReadAsStringAsync()))
            Assert.False(stateJson.RootElement.GetProperty("you").GetProperty("discoveryEnabled").GetBoolean());

        using (var legacyLookup = Authorized(HttpMethod.Get, $"/api/v1/people/lookup?handle={legacy.Handle}", caller.Token))
            Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(legacyLookup)).StatusCode);

        using (var badSave = Authorized(HttpMethod.Put, "/api/v1/me/handle", legacy.Token))
        {
            badSave.Content = JsonContent.Create(new { handle = legacy.Handle, discoveryConsentVersion = 2 });
            Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(badSave)).StatusCode);
        }

        using (var consentedSave = Authorized(HttpMethod.Put, "/api/v1/me/handle", legacy.Token))
        {
            consentedSave.Content = JsonContent.Create(new { handle = legacy.Handle, discoveryConsentVersion = 1 });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(consentedSave)).StatusCode);
        }

        using (var newLookup = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            newLookup.Content = JsonContent.Create(new { handle = legacy.Handle });
            using var response = await client.SendAsync(newLookup);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.False(json.RootElement.TryGetProperty("avatar", out _));
            Assert.False(json.RootElement.TryGetProperty("photoThumbnailBase64", out _));
            Assert.False(json.RootElement.TryGetProperty("displayName", out _));
            Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        }

        using (var enable = Authorized(HttpMethod.Put, "/api/v1/me/discovery", legacy.Token))
        {
            enable.Content = JsonContent.Create(new { enabled = true, consentVersion = 1 });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(enable)).StatusCode);
        }

        using (var badVersion = Authorized(HttpMethod.Put, "/api/v1/me/discovery", legacy.Token))
        {
            badVersion.Content = JsonContent.Create(new { enabled = true, consentVersion = 2 });
            Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(badVersion)).StatusCode);
        }

        using (var oldClientSave = Authorized(HttpMethod.Put, "/api/v1/me/handle", legacy.Token))
        {
            oldClientSave.Content = JsonContent.Create(new { handle = legacy.Handle });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(oldClientSave)).StatusCode);
        }

        using (var state = await AuthorizedSendAsync(client, HttpMethod.Get, "/api/v1/circle", legacy.Token))
        using (var stateJson = JsonDocument.Parse(await state.Content.ReadAsStringAsync()))
            Assert.True(stateJson.RootElement.GetProperty("you").GetProperty("discoveryEnabled").GetBoolean());

        using (var disable = Authorized(HttpMethod.Put, "/api/v1/me/discovery", legacy.Token))
        {
            disable.Content = JsonContent.Create(new { enabled = false, consentVersion = 1 });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(disable)).StatusCode);
        }

        using (var search = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            search.Content = JsonContent.Create(new { handle = legacy.Handle });
            using var response = await client.SendAsync(search);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.False(json.RootElement.TryGetProperty("avatar", out _));
        }
    }

    [Fact]
    public async Task PhoneLookupRequiresCompleteRegionAwareExactOptedInMatch()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var caller = await CreateReadyAccountAsync(factory, client, "Phone Caller");
        var target = await CreateReadyAccountAsync(factory, client, "Phone Target");
        var store = factory.Services.GetRequiredService<ITrustStore>();
        const string phone = "+15555550123";
        await store.SetVerifiedPhoneAsync(target.Id, phone, DateTimeOffset.UtcNow, CancellationToken.None);

        using (var unauthenticated = new HttpRequestMessage(HttpMethod.Post, "/api/v1/people/lookup"))
        {
            unauthenticated.Content = JsonContent.Create(new { phone, region = "US" });
            Assert.Equal(HttpStatusCode.Unauthorized, (await client.SendAsync(unauthenticated)).StatusCode);
        }

        using (var invalid = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            invalid.Content = JsonContent.Create(new { phone = "555-0123", region = "US" });
            using var response = await client.SendAsync(invalid);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("invalid_search_query", json.RootElement.GetProperty("code").GetString());
        }

        using (var missingRegion = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            missingRegion.Content = JsonContent.Create(new { phone = "5555550123" });
            Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(missingRegion)).StatusCode);
        }
        using (var invalidRegion = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            invalidRegion.Content = JsonContent.Create(new { phone, region = "ZZ" });
            Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(invalidRegion)).StatusCode);
        }

        using (var notOptedIn = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            notOptedIn.Content = JsonContent.Create(new { phone, region = "US" });
            using var response = await client.SendAsync(notOptedIn);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("person_not_found", json.RootElement.GetProperty("code").GetString());
        }

        using (var enable = Authorized(HttpMethod.Put, "/api/v1/me/discovery", target.Token))
        {
            enable.Content = JsonContent.Create(new { enabled = true, consentVersion = 1 });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(enable)).StatusCode);
        }

        using (var found = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            found.Content = JsonContent.Create(new { phone, region = "US" });
            using var response = await client.SendAsync(found);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal(target.Id, json.RootElement.GetProperty("accountId").GetGuid());
            Assert.False(json.RootElement.TryGetProperty("phone", out _));
            Assert.False(json.RootElement.TryGetProperty("displayName", out _));
        }
    }

    [Fact]
    public async Task BothSearchModesRequireAuthenticatedCompletedOnboarding()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var deviceId = Guid.NewGuid().ToString("N");
        using var session = await client.PostAsJsonAsync("/api/v1/session/development", new { displayName = "Unverified", deviceId });
        session.EnsureSuccessStatusCode();
        using var sessionJson = JsonDocument.Parse(await session.Content.ReadAsStringAsync());
        var token = sessionJson.RootElement.GetProperty("token").GetString()!;

        using (var handle = Authorized(HttpMethod.Post, "/api/v1/people/lookup", token))
        {
            handle.Content = JsonContent.Create(new { handle = "somebody" });
            using var response = await client.SendAsync(handle);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("verification_required", json.RootElement.GetProperty("code").GetString());
        }

        using (var phone = Authorized(HttpMethod.Post, "/api/v1/people/lookup", token))
        {
            phone.Content = JsonContent.Create(new { phone = "+15555550123", region = "US" });
            using var response = await client.SendAsync(phone);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("verification_required", json.RootElement.GetProperty("code").GetString());
        }
    }

    [Fact]
    public async Task SearchPhotoThumbnailIsBoundedAndImmediatelyHiddenAfterOptOut()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var caller = await CreateReadyAccountAsync(factory, client, "Photo Caller");
        var target = await CreateReadyAccountAsync(factory, client, "Photo Target");
        var store = factory.Services.GetRequiredService<ITrustStore>();
        await store.SetVerifiedPhoneAsync(target.Id, "+15555550456", DateTimeOffset.UtcNow, CancellationToken.None);

        using (var upload = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", target.Token))
        {
            upload.Content = new ByteArrayContent(CreateJpeg(256, 192));
            upload.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
            Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(upload)).StatusCode);
        }
        using (var enable = Authorized(HttpMethod.Put, "/api/v1/me/discovery", target.Token))
        {
            enable.Content = JsonContent.Create(new { enabled = true, consentVersion = 1 });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(enable)).StatusCode);
        }

        using (var lookup = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            lookup.Content = JsonContent.Create(new { handle = target.Handle });
            using var response = await client.SendAsync(lookup);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("photo", json.RootElement.GetProperty("avatar").GetProperty("kind").GetString());
            var thumbnail = Convert.FromBase64String(json.RootElement.GetProperty("photoThumbnailBase64").GetString()!);
            Assert.InRange(thumbnail.Length, 1, 20 * 1024);
            using var bitmap = SKBitmap.Decode(thumbnail);
            Assert.NotNull(bitmap);
            Assert.InRange(bitmap!.Width, 1, 128);
            Assert.InRange(bitmap.Height, 1, 128);
        }

        using (var disable = Authorized(HttpMethod.Put, "/api/v1/me/discovery", target.Token))
        {
            disable.Content = JsonContent.Create(new { enabled = false, consentVersion = 1 });
            Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(disable)).StatusCode);
        }
        using (var lookup = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            lookup.Content = JsonContent.Create(new { handle = target.Handle });
            using var response = await client.SendAsync(lookup);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.False(json.RootElement.TryGetProperty("avatar", out _));
            Assert.False(json.RootElement.TryGetProperty("photoThumbnailBase64", out _));
        }
    }

    [Fact]
    public async Task SearchHasAccountLimitAndRejectsAmbiguousFields()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var caller = await CreateReadyAccountAsync(factory, client, "Rate Caller");

        using (var ambiguous = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token))
        {
            ambiguous.Content = JsonContent.Create(new { handle = caller.Handle, phone = "+15555550789", region = "US" });
            Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(ambiguous)).StatusCode);
        }

        for (var i = 0; i < 60; i++)
        {
            using var request = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token);
            request.Content = JsonContent.Create(new { handle = $"nobody{i}" });
            using var response = await client.SendAsync(request);
        }
        using var limited = Authorized(HttpMethod.Post, "/api/v1/people/lookup", caller.Token);
        limited.Content = JsonContent.Create(new { handle = "nobody" });
        using var limitedResponse = await client.SendAsync(limited);
        Assert.Equal(HttpStatusCode.TooManyRequests, limitedResponse.StatusCode);
    }

    private static async Task<(string Token, Guid Id, string Handle)> CreateReadyAccountAsync(
        TrustApiFactory factory,
        HttpClient client,
        string name)
    {
        var deviceId = Guid.NewGuid().ToString("N");
        using var response = await client.PostAsJsonAsync("/api/v1/session/development", new { displayName = name, deviceId });
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var you = json.RootElement.GetProperty("you");
        var id = you.GetProperty("id").GetGuid();
        var token = json.RootElement.GetProperty("token").GetString()!;
        var handle = "u" + deviceId[..8];
        var engine = factory.Services.GetRequiredService<TrustEngine>();
        await engine.SetHandleAsync(id, handle, CancellationToken.None);
        await factory.Services.GetRequiredService<ITrustStore>().SetVerifiedPhoneAsync(
            id,
            $"+1555555{deviceId[..4]}",
            DateTimeOffset.UtcNow,
            CancellationToken.None);
        return (token, id, handle);
    }

    private static HttpRequestMessage Authorized(HttpMethod method, string path, string token)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private static Task<HttpResponseMessage> AuthorizedSendAsync(HttpClient client, HttpMethod method, string path, string token) =>
        client.SendAsync(Authorized(method, path, token));

    private static byte[] CreateJpeg(int width, int height)
    {
        using var bitmap = new SKBitmap(width, height);
        using (var canvas = new SKCanvas(bitmap))
        {
            canvas.Clear(new SKColor(53, 103, 142));
            using var paint = new SKPaint { Color = new SKColor(229, 182, 97), IsAntialias = true };
            canvas.DrawCircle(width / 2f, height / 2f, Math.Min(width, height) / 4f, paint);
        }
        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Jpeg, 90);
        return data!.ToArray();
    }
}
