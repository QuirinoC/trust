using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using TrustApi.Application;
using TrustApi.Domain;
using TrustApi.Infrastructure;
using TrustApi.Infrastructure.AgeAssurance;

namespace TrustApi.Tests;

public sealed class AgeAssurancePrivacyHoldHttpTests
{
    [Fact]
    public async Task ForgedHoldBodyCannotTargetAnotherAccountAndHoldOnlyClearsOnExplicitDeletion()
    {
        using var factory = new TrustApiFactory();
        using var client = factory.CreateClient();
        var accountA = await CreateAccountAsync(client, "Privacy Hold A");
        var accountB = await CreateAccountAsync(client, "Privacy Hold B");
        var ageAssurance = factory.Services.GetRequiredService<IAgeAssuranceAccountStore>();
        var accounts = factory.Services.GetRequiredService<ITrustStore>();

        using var holdRequest = Authorized(HttpMethod.Post, "/api/v1/age-assurance/privacy-hold", accountA.Token);
        holdRequest.Content = JsonContent.Create(new
        {
            accountId = accountB.Id,
            ageRangeUpperBound = 7,
            underMinimum = false,
            consentGranted = true,
            reason = "attacker_supplied_reason"
        });
        using var holdResponse = await client.SendAsync(holdRequest);
        Assert.Equal(HttpStatusCode.NoContent, holdResponse.StatusCode);

        var holdA = await ageAssurance.FindAccountPrivacyHoldAsync(accountA.Id, CancellationToken.None);
        Assert.NotNull(holdA);
        Assert.Equal(accountA.Id, holdA.AccountId);
        Assert.Equal(AccountPrivacyHoldPolicy.Version, holdA.PolicyVersion);
        Assert.Equal("client_reported_age_restriction", holdA.Reason);
        Assert.Null(await ageAssurance.FindAccountPrivacyHoldAsync(accountB.Id, CancellationToken.None));

        using var ordinaryRequest = Authorized(HttpMethod.Get, "/api/v1/circle", accountA.Token);
        using var ordinaryResponse = await client.SendAsync(ordinaryRequest);
        Assert.Equal((HttpStatusCode)423, ordinaryResponse.StatusCode);

        using var linkRequest = Authorized(HttpMethod.Put, "/api/v1/age-assurance/app-transaction", accountA.Token);
        linkRequest.Content = JsonContent.Create(new { signedAppTransactionInfo = "not-a-real-transaction" });
        using var linkResponse = await client.SendAsync(linkRequest);
        Assert.Equal((HttpStatusCode)423, linkResponse.StatusCode);
        Assert.NotNull(await ageAssurance.FindAccountPrivacyHoldAsync(accountA.Id, CancellationToken.None));

        using var accountBRequest = Authorized(HttpMethod.Get, "/api/v1/circle", accountB.Token);
        using var accountBResponse = await client.SendAsync(accountBRequest);
        Assert.Equal(HttpStatusCode.OK, accountBResponse.StatusCode);

        using var deleteRequest = Authorized(HttpMethod.Delete, "/api/v1/account", accountA.Token);
        using var deleteResponse = await client.SendAsync(deleteRequest);
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);
        Assert.Null(await accounts.FindAccountAsync(accountA.Id, CancellationToken.None));
        Assert.Null(await ageAssurance.FindAccountPrivacyHoldAsync(accountA.Id, CancellationToken.None));
    }

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
        return (
            json.RootElement.GetProperty("token").GetString()!,
            json.RootElement.GetProperty("you").GetProperty("id").GetGuid());
    }
}
