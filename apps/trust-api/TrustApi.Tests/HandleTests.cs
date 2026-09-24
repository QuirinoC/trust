using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure;

namespace TrustApi.Tests;

public sealed class HandleTests
{
    [Theory]
    [InlineData("jordan")]
    [InlineData("@Jordan")]
    [InlineData("jordan_1")]
    [InlineData("a_b")]
    [InlineData("abc")]
    public void AcceptsValidHandles(string raw)
    {
        Assert.True(AccountHandle.TryValidate(raw, out var normalized, out var error));
        Assert.Null(error);
        Assert.Equal(AccountHandle.Normalize(raw), normalized);
        Assert.InRange(normalized.Length, AccountHandle.MinLength, AccountHandle.MaxLength);
    }

    [Theory]
    [InlineData("")]
    [InlineData("ab")]
    [InlineData("1jordan")]
    [InlineData("_jordan")]
    [InlineData("jordan!")]
    [InlineData("jordan-1")]
    [InlineData("this_handle_is_way_too_long")]
    public void RejectsInvalidHandles(string raw)
    {
        Assert.False(AccountHandle.TryValidate(raw, out _, out var error));
        Assert.Equal("invalid_handle", error);
    }

    [Theory]
    [InlineData("you")]
    [InlineData("Trust")]
    [InlineData("@admin")]
    [InlineData("support")]
    [InlineData("apple")]
    public void RejectsReservedHandles(string raw)
    {
        Assert.False(AccountHandle.TryValidate(raw, out _, out var error));
        Assert.Equal("reserved_handle", error);
    }

    [Fact]
    public async Task SettingHandleCompletesOnboarding()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var account = await engine.SignInAsync("development", "handle-sam", "You", CancellationToken.None);
        Assert.False(account.OnboardingComplete);

        await engine.SetHandleAsync(account.Id, "@Jordan", CancellationToken.None);
        var named = await engine.GetCircleAsync(account.Id, CancellationToken.None);
        Assert.False(named.You.OnboardingComplete);
        Assert.Equal("jordan", named.You.Handle);
        Assert.Equal("jordan", named.You.DisplayName);

        await store.SetVerifiedPhoneAsync(account.Id, "+15555550199", DateTimeOffset.UtcNow, CancellationToken.None);
        var circle = await engine.GetCircleAsync(account.Id, CancellationToken.None);
        Assert.True(circle.You.OnboardingComplete);
        Assert.True(circle.You.HasVerifiedPhone);
    }

    [Fact]
    public async Task KeepsChosenDisplayNameWhenClaimingHandle()
    {
        var engine = new TrustEngine(new MemoryTrustStore(), TimeProvider.System);
        var account = await engine.SignInAsync("development", "handle-name", "Sam", CancellationToken.None);
        await engine.SetHandleAsync(account.Id, "sam", CancellationToken.None);
        var circle = await engine.GetCircleAsync(account.Id, CancellationToken.None);
        Assert.Equal("sam", circle.You.Handle);
        Assert.Equal("Sam", circle.You.DisplayName);
    }

    [Fact]
    public async Task DuplicateHandleIsRejected()
    {
        var store = new MemoryTrustStore();
        var engine = new TrustEngine(store, TimeProvider.System);
        var first = await engine.SignInAsync("development", "handle-a", "Sam", CancellationToken.None);
        var second = await engine.SignInAsync("development", "handle-b", "Jordan", CancellationToken.None);
        await engine.SetHandleAsync(first.Id, "jordan", CancellationToken.None);

        var exception = await Assert.ThrowsAsync<TrustException>(() =>
            engine.SetHandleAsync(second.Id, "jordan", CancellationToken.None));
        Assert.Equal("handle_in_use", exception.Code);

        var availability = await engine.CheckHandleAsync(second.Id, "jordan", CancellationToken.None);
        Assert.False(availability.Available);
        Assert.Equal("handle_in_use", availability.Code);

        var own = await engine.CheckHandleAsync(first.Id, "jordan", CancellationToken.None);
        Assert.True(own.Available);
    }
}

public sealed class HandleApiTests : IClassFixture<TrustApiFactory>
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _client;

    public HandleApiTests(TrustApiFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task HttpSetHandleCompletesOnboarding()
    {
        var deviceId = Guid.NewGuid().ToString("N");
        var session = await _client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "You", provider = "development", deviceId });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionHandleWire>(Json);
        Assert.False(payload!.You.OnboardingComplete);
        Assert.Null(payload.You.Handle);

        var handle = $"j{deviceId[..8]}";
        using var available = new HttpRequestMessage(
            HttpMethod.Get,
            $"/api/v1/handles/available?handle={handle}");
        available.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        var availableResponse = await _client.SendAsync(available);
        availableResponse.EnsureSuccessStatusCode();
        var check = await availableResponse.Content.ReadFromJsonAsync<AvailabilityWire>(Json);
        Assert.True(check!.Available);

        using var claim = new HttpRequestMessage(HttpMethod.Put, "/api/v1/me/handle");
        claim.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        claim.Content = JsonContent.Create(new { handle });
        var claimResponse = await _client.SendAsync(claim);
        claimResponse.EnsureSuccessStatusCode();

        using var circleRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/circle");
        circleRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        var circleResponse = await _client.SendAsync(circleRequest);
        circleResponse.EnsureSuccessStatusCode();
        var named = await circleResponse.Content.ReadFromJsonAsync<CircleHandleWire>(Json);
        Assert.False(named!.You.OnboardingComplete);
        Assert.Equal(handle, named.You.Handle);

        var phone = $"+1555555{RandomNumberGenerator.GetInt32(1000, 10000)}";
        using var send = new HttpRequestMessage(HttpMethod.Post, "/api/v1/me/phone/send");
        send.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        send.Content = JsonContent.Create(new { phone });
        var sendResponse = await _client.SendAsync(send);
        sendResponse.EnsureSuccessStatusCode();
        var otp = await sendResponse.Content.ReadFromJsonAsync<PhoneSendWire>(Json);

        using var verify = new HttpRequestMessage(HttpMethod.Post, "/api/v1/me/phone/verify");
        verify.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        verify.Content = JsonContent.Create(new { phone, code = otp!.DevelopmentCode });
        var verifyResponse = await _client.SendAsync(verify);
        verifyResponse.EnsureSuccessStatusCode();

        using var doneRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/circle");
        doneRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        var doneResponse = await _client.SendAsync(doneRequest);
        doneResponse.EnsureSuccessStatusCode();
        var circle = await doneResponse.Content.ReadFromJsonAsync<CircleHandleWire>(Json);
        Assert.True(circle!.You.OnboardingComplete);
        Assert.Equal(handle, circle.You.Handle);
    }

    [Fact]
    public async Task HttpReservedHandleIsUnavailable()
    {
        var deviceId = Guid.NewGuid().ToString("N");
        var session = await _client.PostAsJsonAsync(
            "/api/v1/session/development",
            new { displayName = "You", provider = "development", deviceId });
        session.EnsureSuccessStatusCode();
        var payload = await session.Content.ReadFromJsonAsync<SessionHandleWire>(Json);

        using var available = new HttpRequestMessage(HttpMethod.Get, "/api/v1/handles/available?handle=admin");
        available.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload!.Token);
        var availableResponse = await _client.SendAsync(available);
        availableResponse.EnsureSuccessStatusCode();
        var check = await availableResponse.Content.ReadFromJsonAsync<AvailabilityWire>(Json);
        Assert.False(check!.Available);
        Assert.Equal("reserved_handle", check.Code);

        using var claim = new HttpRequestMessage(HttpMethod.Put, "/api/v1/me/handle");
        claim.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", payload.Token);
        claim.Content = JsonContent.Create(new { handle = "admin" });
        var claimResponse = await _client.SendAsync(claim);
        Assert.Equal(System.Net.HttpStatusCode.BadRequest, claimResponse.StatusCode);
    }

    private sealed record SessionHandleWire(string Token, HandlePersonWire You);
    private sealed record HandlePersonWire(Guid Id, string DisplayName, bool OnboardingComplete, string? Handle);
    private sealed record PhoneSendWire(string? DevelopmentCode);
    private sealed record AvailabilityWire(string Handle, bool Available, string? Code);
    private sealed record CircleHandleWire(HandlePersonWire You);
}
