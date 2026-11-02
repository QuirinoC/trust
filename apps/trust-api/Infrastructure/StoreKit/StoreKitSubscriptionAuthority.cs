using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace TrustApi.Infrastructure.StoreKit;

/// <summary>Calls Apple's current subscription-status API. Construct only in the operator CLI;</summary>
/// <summary>the API service never loads the App Store Server API bearer token.</summary>
public sealed class StoreKitSubscriptionAuthority(
    HttpClient client,
    IStoreKitTransactionVerifier verifier,
    string bearerToken)
{
    private static readonly JsonDocumentOptions JsonOptions = new() { MaxDepth = 32 };

    public async Task<VerifiedStoreKitTransaction> GetCurrentActiveSubscriptionAsync(
        string originalTransactionId,
        Guid oldAppAccountToken,
        string expectedProductId,
        string environment,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(bearerToken))
            throw AuthorityUnavailable();
        if (environment is not ("Production" or "Sandbox"))
            throw new TrustApi.Domain.TrustException("recovery_purchase_mismatch", "The stored purchase environment is invalid.");

        var host = environment == "Sandbox"
            ? "https://api.storekit-sandbox.apple.com"
            : "https://api.storekit.apple.com";
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"{host}/inApps/v1/subscriptions/{Uri.EscapeDataString(originalTransactionId)}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken.Trim());
        using var lookupTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        lookupTimeout.CancelAfter(TimeSpan.FromSeconds(8));
        var lookupToken = lookupTimeout.Token;

        HttpResponseMessage response;
        try
        {
            response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, lookupToken);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw AuthorityUnavailable();
        }
        catch (HttpRequestException)
        {
            throw AuthorityUnavailable();
        }

        using (response)
        {
            if (response.StatusCode == HttpStatusCode.NotFound)
                throw new TrustApi.Domain.TrustException("recovery_purchase_inactive", "Apple has no current subscription status for this purchase.");
            if (!response.IsSuccessStatusCode)
                throw AuthorityUnavailable();

            try
            {
                if (response.Content.Headers.ContentLength is > 1_048_576)
                    throw AuthorityUnavailable();
                await using var stream = await response.Content.ReadAsStreamAsync(lookupToken);
                using var document = await JsonDocument.ParseAsync(stream, JsonOptions, lookupToken);
                if (!document.RootElement.TryGetProperty("data", out var groups)
                    || groups.ValueKind != JsonValueKind.Array)
                    throw AuthorityUnavailable();

                VerifiedStoreKitTransaction? current = null;
                var currentStatus = -1;
                foreach (var group in groups.EnumerateArray())
                {
                    if (!group.TryGetProperty("lastTransactions", out var transactions)
                        || transactions.ValueKind != JsonValueKind.Array) continue;
                    foreach (var item in transactions.EnumerateArray())
                    {
                        if (!item.TryGetProperty("status", out var statusElement)
                            || !statusElement.TryGetInt32(out var status)
                            || !item.TryGetProperty("signedTransactionInfo", out var signedElement)
                            || signedElement.ValueKind != JsonValueKind.String) continue;
                        var verified = verifier.Verify(signedElement.GetString() ?? string.Empty);
                        var transaction = verified.Transaction;
                        if (!verified.IsValid || transaction is null
                            || transaction.OriginalTransactionId != originalTransactionId
                            || transaction.AppAccountToken != oldAppAccountToken
                            || transaction.ProductId != expectedProductId
                            || transaction.Environment != environment
                            || transaction.SignedAt > now.AddMinutes(5)) continue;
                        if (current is null || transaction.SignedAt > current.SignedAt)
                        {
                            current = transaction;
                            currentStatus = status;
                        }
                    }
                }

                if (current is null || currentStatus != 1 || current.RevokedAt is not null || current.ExpiresAt <= now)
                    throw new TrustApi.Domain.TrustException("recovery_purchase_inactive", "Apple did not confirm an active subscription for this exact purchase.");
                return current;
            }
            catch (JsonException)
            {
                throw AuthorityUnavailable();
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw AuthorityUnavailable();
            }
            catch (HttpRequestException)
            {
                throw AuthorityUnavailable();
            }
        }
    }

    private static TrustApi.Domain.TrustException AuthorityUnavailable() =>
        new("recovery_authority_unavailable", "Apple current subscription status could not be verified. The Support request remains blocked for retry.");
}
