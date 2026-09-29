using TrustApi.Api.V1;
using TrustApi.Domain;
using TrustApi.Infrastructure.Notifications;

namespace TrustApi.Infrastructure.AgeAssurance;

/// <summary>
/// Retries deletion for accounts that remain durably blocked after an Apple consent
/// revocation. The batch and cadence are intentionally bounded so a bad store or a
/// large backlog cannot monopolize a worker process.
/// </summary>
public sealed class AgeAssuranceRevocationCleanupWorker(
    IAgeAssuranceAccountStore ageAssurance,
    ITrustStore accounts,
    IPushDeviceStore devices,
    ILogger<AgeAssuranceRevocationCleanupWorker> logger,
    TimeProvider timeProvider) : BackgroundService
{
    private static readonly TimeSpan RetryInterval = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan LeaseDuration = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan InitialBackoff = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan MaximumBackoff = TimeSpan.FromHours(6);
    private const int BatchSize = 50;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RetryPendingAccountsAsync(
                    (accountId, token) => accounts.DeleteAccountAsync(accountId, token),
                    stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Could not process accounts pending Apple consent-revocation cleanup.");
            }

            try
            {
                await Task.Delay(RetryInterval, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
        }
    }

    /// <summary>Runs one bounded retry pass; exposed so cleanup behavior can be exercised without waiting for the timer.</summary>
    public async Task<int> RetryPendingAccountsAsync(
        Func<Guid, CancellationToken, Task> deleteAccount,
        CancellationToken cancellationToken)
    {
        var cleaned = 0;
        for (var processed = 0; processed < BatchSize; processed++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            // Claim one item at a time so a slow first deletion cannot let later leases
            // expire while waiting in a serial in-memory batch.
            var claims = await ageAssurance.ClaimPendingAccountDeletionsAsync(
                1, timeProvider.GetUtcNow(), LeaseDuration, cancellationToken);
            if (claims.Count == 0) break;
            var claim = claims[0];
            if (await TrustEndpoints.TryDeleteRevokedAccountAsync(
                    claim.AccountId,
                    token => deleteAccount(claim.AccountId, token),
                    devices,
                    ageAssurance,
                    logger,
                    cancellationToken))
            {
                cleaned++;
            }
            else
            {
                await ageAssurance.RecordAccountDeletionRetryAsync(
                    claim,
                    timeProvider.GetUtcNow() + RetryDelay(claim.AttemptCount),
                    cancellationToken);
            }
        }
        return cleaned;
    }

    private static TimeSpan RetryDelay(int priorAttempts)
    {
        var factor = Math.Pow(2, Math.Clamp(priorAttempts, 0, 10));
        var ticks = (long)Math.Min(InitialBackoff.Ticks * factor, MaximumBackoff.Ticks);
        return TimeSpan.FromTicks(ticks);
    }
}
