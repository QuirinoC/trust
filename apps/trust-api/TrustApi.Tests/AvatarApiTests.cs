using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using SkiaSharp;

namespace TrustApi.Tests;

public sealed class AvatarApiTests
{
    [Fact]
    public async Task AvatarUploadIsVersionedPrivateAndRevokedWithMembership()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var sam = await CreateAccountAsync(client, "Avatar Sam");
        var jordan = await CreateAccountAsync(client, "Avatar Jordan");
        var stranger = await CreateAccountAsync(client, "Avatar Stranger");

        var invite = Authorized(HttpMethod.Post, "/api/v1/invites", jordan.Token);
        using var inviteResponse = await client.SendAsync(invite);
        inviteResponse.EnsureSuccessStatusCode();
        using var inviteJson = JsonDocument.Parse(await inviteResponse.Content.ReadAsStringAsync());
        var code = inviteJson.RootElement.GetProperty("code").GetString();
        using var accept = Authorized(HttpMethod.Post, "/api/v1/invites/accept", sam.Token);
        accept.Content = JsonContent.Create(new { code });
        (await client.SendAsync(accept)).EnsureSuccessStatusCode();

        var original = AddPrivateJpegMetadata(CreateJpeg(128, 128));
        using var upload = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", sam.Token);
        upload.Content = new ByteArrayContent(original);
        upload.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        using var uploadResponse = await client.SendAsync(upload);
        uploadResponse.EnsureSuccessStatusCode();
        using var uploadJson = JsonDocument.Parse(await uploadResponse.Content.ReadAsStringAsync());
        Assert.Equal("photo", uploadJson.RootElement.GetProperty("kind").GetString());
        var version = uploadJson.RootElement.GetProperty("version").GetGuid();

        using var circleRequest = Authorized(HttpMethod.Get, "/api/v1/circle", jordan.Token);
        using var circleResponse = await client.SendAsync(circleRequest);
        circleResponse.EnsureSuccessStatusCode();
        using var circleJson = JsonDocument.Parse(await circleResponse.Content.ReadAsStringAsync());
        var samDto = circleJson.RootElement.GetProperty("members").EnumerateArray()
            .Single(member => member.GetProperty("person").GetProperty("id").GetGuid() == sam.Id)
            .GetProperty("person");
        Assert.Equal("photo", samDto.GetProperty("avatar").GetProperty("kind").GetString());
        Assert.False(samDto.GetProperty("avatar").TryGetProperty("url", out _));
        Assert.Equal(version, samDto.GetProperty("avatar").GetProperty("version").GetGuid());

        using var connectedFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, version), jordan.Token);
        using var connectedResponse = await client.SendAsync(connectedFetch);
        Assert.Equal(HttpStatusCode.OK, connectedResponse.StatusCode);
        Assert.Equal("image/jpeg", connectedResponse.Content.Headers.ContentType?.MediaType);
        var sanitized = await connectedResponse.Content.ReadAsByteArrayAsync();
        Assert.NotEqual(original, sanitized);
        Assert.False(HasApplicationOrCommentSegments(sanitized));
        Assert.DoesNotContain("GPSSECRET", System.Text.Encoding.ASCII.GetString(sanitized));
        using (var decoded = SKBitmap.Decode(sanitized))
        {
            Assert.NotNull(decoded);
            Assert.Equal(128, decoded!.Width);
            Assert.Equal(128, decoded.Height);
        }

        using var strangerFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, version), stranger.Token);
        using var strangerResponse = await client.SendAsync(strangerFetch);
        Assert.Equal(HttpStatusCode.NotFound, strangerResponse.StatusCode);

        using var revoke = Authorized(HttpMethod.Post, $"/api/v1/people/{sam.Id}/revoke", jordan.Token);
        (await client.SendAsync(revoke)).EnsureSuccessStatusCode();
        using var revokedFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, version), jordan.Token);
        using var revokedResponse = await client.SendAsync(revokedFetch);
        Assert.Equal(HttpStatusCode.NotFound, revokedResponse.StatusCode);

        using var ownerFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, version), sam.Token);
        using var ownerResponse = await client.SendAsync(ownerFetch);
        Assert.Equal(HttpStatusCode.OK, ownerResponse.StatusCode);

        using var staleFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, version), sam.Token);
        using var replacement = Authorized(HttpMethod.Put, "/api/v1/me/avatar/preset", sam.Token);
        replacement.Content = JsonContent.Create(new { presetId = "fern" });
        using var replacementResponse = await client.SendAsync(replacement);
        replacementResponse.EnsureSuccessStatusCode();
        using var replacementJson = JsonDocument.Parse(await replacementResponse.Content.ReadAsStringAsync());
        Assert.Equal("preset", replacementJson.RootElement.GetProperty("kind").GetString());
        Assert.Equal("fern", replacementJson.RootElement.GetProperty("presetId").GetString());
        using var staleResponse = await client.SendAsync(staleFetch);
        Assert.Equal(HttpStatusCode.NotFound, staleResponse.StatusCode);

        using var removed = Authorized(HttpMethod.Delete, "/api/v1/me/avatar", sam.Token);
        (await client.SendAsync(removed)).EnsureSuccessStatusCode();
        using var removedFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, version), sam.Token);
        using var removedResponse = await client.SendAsync(removedFetch);
        Assert.Equal(HttpStatusCode.NotFound, removedResponse.StatusCode);

        using var secondUpload = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", sam.Token);
        secondUpload.Content = new ByteArrayContent(original);
        secondUpload.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        using var secondUploadResponse = await client.SendAsync(secondUpload);
        secondUploadResponse.EnsureSuccessStatusCode();
        using var secondUploadJson = JsonDocument.Parse(await secondUploadResponse.Content.ReadAsStringAsync());
        var currentVersion = secondUploadJson.RootElement.GetProperty("version").GetGuid();

        using var deleteAccount = Authorized(HttpMethod.Delete, "/api/v1/account", sam.Token);
        (await client.SendAsync(deleteAccount)).EnsureSuccessStatusCode();
        using var deletedFetch = Authorized(HttpMethod.Get, PhotoPath(sam.Id, currentVersion), sam.Token);
        using var deletedResponse = await client.SendAsync(deletedFetch);
        Assert.Equal(HttpStatusCode.NotFound, deletedResponse.StatusCode);
    }

    [Fact]
    public async Task AvatarRoutesRejectUnsupportedContentAndUnknownPresets()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var sam = await CreateAccountAsync(client, "Avatar Invalid");

        using var anonymousUpload = new HttpRequestMessage(HttpMethod.Put, "/api/v1/me/avatar/photo")
        {
            Content = new ByteArrayContent([1, 2, 3])
        };
        anonymousUpload.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        using var anonymousResponse = await client.SendAsync(anonymousUpload);
        Assert.Equal(HttpStatusCode.Unauthorized, anonymousResponse.StatusCode);

        using var invalidPreset = Authorized(HttpMethod.Put, "/api/v1/me/avatar/preset", sam.Token);
        invalidPreset.Content = JsonContent.Create(new { presetId = "arbitrary-url" });
        using var invalidPresetResponse = await client.SendAsync(invalidPreset);
        Assert.Equal(HttpStatusCode.BadRequest, invalidPresetResponse.StatusCode);

        using var wrongMediaType = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", sam.Token);
        wrongMediaType.Content = new ByteArrayContent([1, 2, 3]);
        wrongMediaType.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        using var wrongMediaResponse = await client.SendAsync(wrongMediaType);
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, wrongMediaResponse.StatusCode);

        using var invalidJpeg = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", sam.Token);
        invalidJpeg.Content = new ByteArrayContent([1, 2, 3]);
        invalidJpeg.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        using var invalidImageResponse = await client.SendAsync(invalidJpeg);
        Assert.Equal(HttpStatusCode.BadRequest, invalidImageResponse.StatusCode);

        using var tooLarge = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", sam.Token);
        tooLarge.Content = new ByteArrayContent(new byte[1024 * 1024 + 1]);
        tooLarge.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        using var tooLargeResponse = await client.SendAsync(tooLarge);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, tooLargeResponse.StatusCode);

        foreach (var size in new[] { (32, 128), (128, 1025) })
        {
            using var wrongDimensions = Authorized(HttpMethod.Put, "/api/v1/me/avatar/photo", sam.Token);
            wrongDimensions.Content = new ByteArrayContent(CreateJpeg(size.Item1, size.Item2));
            wrongDimensions.Content.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
            using var wrongDimensionsResponse = await client.SendAsync(wrongDimensions);
            Assert.Equal(HttpStatusCode.BadRequest, wrongDimensionsResponse.StatusCode);
        }
    }

    [Fact]
    public async Task AvatarPresetRouteAcceptsAllAdditionalCatalogPresets()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var sam = await CreateAccountAsync(client, "Avatar Catalog");
        var presetIds = new[]
        {
            "fern", "ember", "sky", "ocean", "sunrise", "lavender",
            "moon", "star", "cloud", "raindrop", "rainbow", "mountain",
            "river", "meadow", "clover", "bloom", "cherry", "lotus",
            "mushroom", "seashell", "coral", "butterfly", "hummingbird", "fox",
            "whale", "koi", "rabbit", "bear", "cat", "dog",
            "otter", "owl", "turtle", "siamese", "ragdoll", "british-shorthair"
        };

        foreach (var presetId in presetIds)
        {
            using var request = Authorized(HttpMethod.Put, "/api/v1/me/avatar/preset", sam.Token);
            request.Content = JsonContent.Create(new { presetId });
            using var response = await client.SendAsync(request);
            response.EnsureSuccessStatusCode();
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal("preset", json.RootElement.GetProperty("kind").GetString());
            Assert.Equal(presetId, json.RootElement.GetProperty("presetId").GetString());
        }
    }

    private static string PhotoPath(Guid id, Guid version) => $"/api/v1/people/{id}/avatar/{version}";

    private static HttpRequestMessage Authorized(HttpMethod method, string path, string token)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private static async Task<(string Token, Guid Id)> CreateAccountAsync(HttpClient client, string name)
    {
        using var response = await client.PostAsJsonAsync("/api/v1/session/development", new
        {
            displayName = name,
            deviceId = Guid.NewGuid().ToString("N")
        });
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return (json.RootElement.GetProperty("token").GetString()!, json.RootElement.GetProperty("you").GetProperty("id").GetGuid());
    }

    private static byte[] CreateJpeg(int width, int height)
    {
        using var bitmap = new SKBitmap(width, height);
        bitmap.Erase(SKColors.CornflowerBlue);
        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(SKEncodedImageFormat.Jpeg, 95);
        return encoded.ToArray();
    }

    private static byte[] AddPrivateJpegMetadata(byte[] jpeg)
    {
        var exif = new byte[] { 0xff, 0xe1, 0x00, 0x0b, (byte)'G', (byte)'P', (byte)'S', (byte)'S', (byte)'E', (byte)'C', (byte)'R', (byte)'E', (byte)'T' };
        var comment = new byte[] { 0xff, 0xfe, 0x00, 0x08, (byte)'p', (byte)'r', (byte)'i', (byte)'v', (byte)'a', (byte)'t' };
        return [.. jpeg[..2], .. exif, .. comment, .. jpeg[2..]];
    }

    private static bool HasApplicationOrCommentSegments(byte[] jpeg)
    {
        var position = 2;
        while (position + 4 <= jpeg.Length && jpeg[position] == 0xff)
        {
            while (position < jpeg.Length && jpeg[position] == 0xff) position++;
            if (position >= jpeg.Length) break;
            var marker = jpeg[position++];
            if (marker == 0xda || marker == 0xd9) return false;
            if (marker is >= 0xe0 and <= 0xef or 0xfe) return true;
            if (marker is 0xd8 or >= 0xd0 and <= 0xd7 or 0x01) continue;
            if (position + 2 > jpeg.Length) break;
            var length = jpeg[position] * 256 + jpeg[position + 1];
            if (length < 2 || position + length > jpeg.Length) break;
            position += length;
        }
        return false;
    }
}
