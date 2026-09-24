using Npgsql;
using TrustApi.Configuration;

namespace TrustApi.Infrastructure.Notifications;

public sealed class PostgresPushDeviceStore(string connectionString) : IPushDeviceStore
{
    private readonly string _connectionString = PostgresConnectionString.Normalize(connectionString);

    public async Task RegisterAsync(
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
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        // A new installation id with the same token used to violate
        // ux_push_devices_account_token and the registration was dropped.
        await using (var clear = new NpgsqlCommand(
            """
            DELETE FROM trust.push_devices
            WHERE account_id = $1 AND apns_token = $2 AND installation_id <> $3;
            """,
            connection,
            transaction))
        {
            clear.Parameters.AddWithValue(accountId);
            clear.Parameters.AddWithValue(token);
            clear.Parameters.AddWithValue(installationId);
            await clear.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO trust.push_devices (
                installation_id, account_id, apns_token, environment, bundle_id,
                enabled, last_seen_at, invalidated_at, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, true, now(), NULL, now(), now())
            ON CONFLICT (installation_id) DO UPDATE SET
                account_id = EXCLUDED.account_id,
                apns_token = EXCLUDED.apns_token,
                environment = EXCLUDED.environment,
                bundle_id = EXCLUDED.bundle_id,
                enabled = true,
                last_seen_at = now(),
                invalidated_at = NULL,
                updated_at = now();
            """,
            connection,
            transaction))
        {
            command.Parameters.AddWithValue(installationId);
            command.Parameters.AddWithValue(accountId);
            command.Parameters.AddWithValue(token);
            command.Parameters.AddWithValue(env);
            command.Parameters.AddWithValue(bundleId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    public async Task RemoveAsync(Guid accountId, Guid installationId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.push_devices
            SET enabled = false, invalidated_at = now(), updated_at = now()
            WHERE account_id = $1 AND installation_id = $2;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(installationId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task RemoveAllAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "DELETE FROM trust.push_devices WHERE account_id = $1;",
            connection);
        command.Parameters.AddWithValue(accountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task InvalidateTokenAsync(string token, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.push_devices
            SET enabled = false, invalidated_at = now(), updated_at = now()
            WHERE apns_token = $1;
            """,
            connection);
        command.Parameters.AddWithValue(token);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<PushDevice>> ListActiveAsync(
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT installation_id, account_id, apns_token, environment, bundle_id, enabled
            FROM trust.push_devices
            WHERE account_id = $1 AND enabled = true AND invalidated_at IS NULL;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var devices = new List<PushDevice>();
        while (await reader.ReadAsync(cancellationToken))
        {
            devices.Add(new PushDevice(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetBoolean(5)));
        }

        return devices;
    }
}
