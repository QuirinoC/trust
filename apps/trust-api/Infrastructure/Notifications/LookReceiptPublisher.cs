using TrustApi.Domain;

namespace TrustApi.Infrastructure.Notifications;

public interface ILookReceiptPublisher
{
    Task NotifyLookAsync(LookEvent look, CancellationToken cancellationToken);
    Task NotifyQuietAsync(Guid accountId, string title, string body, string kind, CancellationToken cancellationToken);
    Task NotifyHomeArrivalAsync(Guid subjectId, CancellationToken cancellationToken);
}

public sealed class LookReceiptPublisher(
    IPushDeviceStore devices,
    ITrustStore store,
    ApnsClient apns,
    ILogger<LookReceiptPublisher> logger) : ILookReceiptPublisher
{
    public Task NotifyLookAsync(LookEvent look, CancellationToken cancellationToken) =>
        NotifyQuietAsync(
            look.SubjectId,
            look.ViewerName + " looked at your location",
            "One snapshot of your current place.",
            "look",
            cancellationToken);

    public async Task NotifyQuietAsync(
        Guid accountId,
        string title,
        string body,
        string kind,
        CancellationToken cancellationToken)
    {
        IReadOnlyList<PushDevice> registrations;
        try
        {
            registrations = await devices.ListActiveAsync(accountId, cancellationToken);
        }
        catch (Exception exception)
        {
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
            try
            {
                var outcome = await apns.SendLookReceiptAsync(device, title, body, cancellationToken);
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

    public async Task NotifyHomeArrivalAsync(Guid subjectId, CancellationToken cancellationToken)
    {
        var subject = await store.FindAccountAsync(subjectId, cancellationToken);
        if (subject is null)
        {
            return;
        }

        var connected = await store.ListConnectedAsync(subjectId, cancellationToken);
        var timeLabel = DateTimeOffset.UtcNow.ToOffset(TimeSpan.Zero).ToString("h:mm tt");
        foreach (var person in connected)
        {
            var grant = await store.GetPresenceGrantAsync(subjectId, person.Id, cancellationToken);
            if (grant?.Enabled != true)
            {
                continue;
            }

            await NotifyQuietAsync(
                person.Id,
                subject.DisplayName + " is home",
                subject.DisplayName + " is home · " + timeLabel,
                "home_arrival",
                cancellationToken);
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

    public Task NotifyHomeArrivalAsync(Guid subjectId, CancellationToken cancellationToken) => Task.CompletedTask;
}
