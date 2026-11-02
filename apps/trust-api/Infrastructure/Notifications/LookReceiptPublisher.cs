using TrustApi.Domain;
using TrustApi.Infrastructure.AgeAssurance;

namespace TrustApi.Infrastructure.Notifications;

public interface ILookReceiptPublisher
{
    Task NotifyLookAsync(LookEvent look, CancellationToken cancellationToken);
    Task NotifyQuietAsync(Guid accountId, string title, string body, string kind, CancellationToken cancellationToken);
    Task NotifyHomeArrivalAsync(Guid subjectId, Guid transitionId, CancellationToken cancellationToken);
}

public sealed class LookReceiptPublisher(
    IPushDeviceStore devices,
    ITrustStore store,
    ApnsClient apns,
    ILogger<LookReceiptPublisher> logger,
    IAgeAssuranceAccountStore? ageAssurance = null) : ILookReceiptPublisher
{
    public Task NotifyLookAsync(LookEvent look, CancellationToken cancellationToken) =>
        NotifyQuietCoreAsync(
            look.SubjectId,
            look.ViewerName + " looked at your location",
            "One snapshot of the latest location available to Trust.",
            "look",
            null,
            look.ViewerId,
            cancellationToken,
            actorName: look.ViewerName,
            eventAt: look.At);

    public async Task NotifyQuietAsync(
        Guid accountId,
        string title,
        string body,
        string kind,
        CancellationToken cancellationToken) =>
        await NotifyQuietCoreAsync(accountId, title, body, kind, null, null, cancellationToken);

    private async Task NotifyQuietCoreAsync(
        Guid accountId,
        string title,
        string body,
        string kind,
        Guid? subjectId,
        Guid? relatedAccountId,
        CancellationToken cancellationToken,
        Func<CancellationToken, Task<bool>>? canDeliver = null,
        string? actorName = null,
        DateTimeOffset? eventAt = null)
    {
        if (subjectId is { } subject && await IsBlockedForNotificationAsync(subject, cancellationToken)) return;
        if (relatedAccountId is { } related && await IsBlockedForNotificationAsync(related, cancellationToken)) return;
        if (await IsBlockedForNotificationAsync(accountId, cancellationToken)) return;

        IReadOnlyList<PushDevice> registrations;
        try
        {
            registrations = await devices.ListActiveAsync(accountId, cancellationToken);
        }
        catch (Exception exception)
        {
            if (exception is OperationCanceledException && cancellationToken.IsCancellationRequested) throw;
            logger.LogWarning(exception, "Could not load push devices for {AccountId}.", accountId);
            return;
        }

        if (registrations.Count == 0)
        {
            logger.LogInformation("No push devices registered for {AccountId} ({Kind}).", accountId, kind);
            return;
        }

        foreach (var device in registrations)
        {
            // Home alerts carry the subject's presence. Recheck both accounts after
            // the device-store await and before each APNs send so a consent revocation
            // stops the remaining fan-out immediately.
            if (subjectId is { } source && await IsBlockedForNotificationAsync(source, cancellationToken)) return;
            if (relatedAccountId is { } relatedSource && await IsBlockedForNotificationAsync(relatedSource, cancellationToken)) return;
            if (await IsBlockedForNotificationAsync(accountId, cancellationToken)) return;
            if (canDeliver is not null && !await canDeliver(cancellationToken)) return;
            try
            {
                var message = actorName is not null && kind is "look" or "home_arrival"
                    ? NotificationLanguage.Localize(device.Language, kind, actorName)
                    : (title, body);
                var outcome = await apns.SendNotificationAsync(device, message.Item1, message.Item2, kind, cancellationToken, eventAt);
                if (outcome.Result == ApnsDeliveryResult.InvalidToken)
                {
                    await devices.InvalidateTokenAsync(device.Token, cancellationToken);
                }
                else if (outcome.Result == ApnsDeliveryResult.Retry)
                {
                    logger.LogWarning(
                        "APNs did not deliver {Kind} to {InstallationId}: {Error}",
                        kind,
                        device.InstallationId,
                        outcome.Error);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "APNs failed for {Kind} installation {InstallationId}.",
                    kind,
                    device.InstallationId);
            }
        }
    }

    // Convenience overload for explicit local/test publishing. Request handlers must
    // pass the exact transition ID produced by the atomic status write.
    public async Task NotifyHomeArrivalAsync(Guid subjectId, CancellationToken cancellationToken)
    {
        var current = await store.GetCurrentHomePresenceAsync(subjectId, cancellationToken);
        if (current is null || current.TransitionId == Guid.Empty) return;
        await NotifyHomeArrivalAsync(subjectId, current.TransitionId, cancellationToken);
    }

    public async Task NotifyHomeArrivalAsync(Guid subjectId, Guid transitionId, CancellationToken cancellationToken)
    {
        if (transitionId == Guid.Empty || await IsBlockedForNotificationAsync(subjectId, cancellationToken)) return;

        var subject = await store.FindAccountAsync(subjectId, cancellationToken);
        if (subject is null)
        {
            return;
        }

        var current = await store.GetCurrentHomePresenceAsync(subjectId, cancellationToken);
        if (current is null || current.TransitionId != transitionId || current.State != HomePresenceState.Home) return;
        var connected = await store.ListConnectedAsync(subjectId, cancellationToken);
        foreach (var person in connected)
        {
            if (await IsBlockedForNotificationAsync(subjectId, cancellationToken)) return;
            var expectedConnectionId = await store.GetActiveMembershipIdAsync(subjectId, person.Id, cancellationToken);
            if (expectedConnectionId is null)
            {
                continue;
            }

            if (await IsBlockedForNotificationAsync(subjectId, cancellationToken)) return;
            if (!await store.IsHomeTransitionEligibleAsync(subjectId, person.Id, expectedConnectionId.Value,
                    transitionId, DateTimeOffset.UtcNow, cancellationToken)) continue;

            async Task<bool> ConsentStillAllowsDelivery(CancellationToken token)
            {
                // The device-store lookup and each earlier APNs send are awaits. Revalidate
                // all user-controlled gates immediately before delivering this recipient's
                // Home signal. Bind it to the relationship incarnation captured above so a
                // remove/re-add cannot inherit an already queued notification.
                return await store.IsHomeTransitionEligibleAsync(subjectId, person.Id, expectedConnectionId.Value,
                    transitionId, DateTimeOffset.UtcNow, token);
            }

            await NotifyQuietCoreAsync(
                person.Id,
                subject.DisplayName + " is home",
                subject.DisplayName + " is home.",
                "home_arrival",
                subjectId,
                null,
                cancellationToken,
                ConsentStillAllowsDelivery,
                subject.DisplayName,
                current.LastChangedAt);
        }
    }

    private async Task<bool> IsBlockedForNotificationAsync(Guid accountId, CancellationToken cancellationToken)
    {
        if (ageAssurance is null) return false;
        try
        {
            return await ageAssurance.IsAccountBlockedAsync(accountId, cancellationToken)
                || await ageAssurance.IsAccountPrivacyHeldAsync(accountId, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Could not confirm account privacy status for notification account {AccountId}; suppressing notification.", accountId);
            return true;
        }
    }
}

public sealed class NoOpLookReceiptPublisher : ILookReceiptPublisher
{
    public Task NotifyLookAsync(LookEvent look, CancellationToken cancellationToken) => Task.CompletedTask;

    public Task NotifyQuietAsync(
        Guid accountId,
        string title,
        string body,
        string kind,
        CancellationToken cancellationToken) => Task.CompletedTask;

    public Task NotifyHomeArrivalAsync(Guid subjectId, Guid transitionId, CancellationToken cancellationToken) => Task.CompletedTask;
}
