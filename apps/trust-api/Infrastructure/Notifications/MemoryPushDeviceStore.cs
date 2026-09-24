using System.Collections.Concurrent;

namespace TrustApi.Infrastructure.Notifications;

public sealed class MemoryPushDeviceStore : IPushDeviceStore
{
    private readonly ConcurrentDictionary<Guid, PushDevice> _devices = new();

    public Task RegisterAsync(
        Guid accountId,
        Guid installationId,
        string token,
        string environment,
        string bundleId,
        CancellationToken cancellationToken)
    {
        var env = string.Equals(environment, "sandbox", StringComparison.OrdinalIgnoreCase)
            ? "sandbox"
            : "production";
        _devices[installationId] = new PushDevice(installationId, accountId, token, env, bundleId, true);
        return Task.CompletedTask;
    }

    public Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken)
    {
        if (_devices.TryGetValue(installationId, out var device) && device.AccountId == accountId)
        {
            _devices[installationId] = device with { Enabled = false };
        }

        return Task.CompletedTask;
    }

    public Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken)
    {
        foreach (var pair in _devices.Where(pair => pair.Value.AccountId == accountId).ToList())
        {
            _devices.TryRemove(pair.Key, out _);
        }

        return Task.CompletedTask;
    }

    public Task InvalidateTokenAsync(string token, CancellationToken cancellationToken)
    {
        foreach (var pair in _devices.Where(pair => pair.Value.Token == token).ToList())
        {
            _devices[pair.Key] = pair.Value with { Enabled = false };
        }

        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<PushDevice>> ListActiveAsync(Guid accountId, CancellationToken cancellationToken)
    {
        IReadOnlyList<PushDevice> devices = _devices.Values
            .Where(device => device.AccountId == accountId && device.Enabled)
            .ToList();
        return Task.FromResult(devices);
    }
}
