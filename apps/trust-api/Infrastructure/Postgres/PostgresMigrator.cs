using System.Reflection;
using Npgsql;
using TrustApi.Configuration;

namespace TrustApi.Infrastructure.Postgres;

public static class PostgresMigrator
{
    private const long AdvisoryLockKey = 812_441_902_331_008_441;
    private const string Marker = ".Migrations.";

    public static async Task ApplyAsync(
        string connectionString,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new NpgsqlConnection(
            PostgresConnectionString.Normalize(connectionString));
        await connection.OpenAsync(cancellationToken);
        await using (var lockCommand = new NpgsqlCommand("SELECT pg_advisory_lock($1);", connection))
        {
            lockCommand.Parameters.AddWithValue(AdvisoryLockKey);
            await lockCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        try
        {
            await using (var create = new NpgsqlCommand(
                """
                CREATE SCHEMA IF NOT EXISTS trust;
                CREATE TABLE IF NOT EXISTS trust.schema_migrations (
                    name text PRIMARY KEY,
                    applied_at timestamptz NOT NULL
                );
                """,
                connection))
            {
                await create.ExecuteNonQueryAsync(cancellationToken);
            }

            foreach (var migration in LoadMigrations())
            {
                await using var exists = new NpgsqlCommand(
                    "SELECT 1 FROM trust.schema_migrations WHERE name = $1;",
                    connection);
                exists.Parameters.AddWithValue(migration.Name);
                var applied = await exists.ExecuteScalarAsync(cancellationToken);
                if (applied is not null)
                {
                    continue;
                }

                await using var apply = new NpgsqlCommand(migration.Sql, connection);
                await apply.ExecuteNonQueryAsync(cancellationToken);
                await using var record = new NpgsqlCommand(
                    "INSERT INTO trust.schema_migrations (name, applied_at) VALUES ($1, $2);",
                    connection);
                record.Parameters.AddWithValue(migration.Name);
                record.Parameters.AddWithValue(DateTimeOffset.UtcNow);
                await record.ExecuteNonQueryAsync(cancellationToken);
            }
        }
        finally
        {
            await using var unlock = new NpgsqlCommand("SELECT pg_advisory_unlock($1);", connection);
            unlock.Parameters.AddWithValue(AdvisoryLockKey);
            await unlock.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    private static IReadOnlyList<(string Name, string Sql)> LoadMigrations()
    {
        var assembly = typeof(PostgresMigrator).Assembly;
        return assembly.GetManifestResourceNames()
            .Where(name => name.Contains(Marker, StringComparison.Ordinal)
                && name.EndsWith(".sql", StringComparison.Ordinal))
            .Select(name =>
            {
                var file = name[(name.LastIndexOf(Marker, StringComparison.Ordinal) + Marker.Length)..];
                using var stream = assembly.GetManifestResourceStream(name)
                    ?? throw new InvalidOperationException($"Missing migration {name}.");
                using var reader = new StreamReader(stream);
                return (file, reader.ReadToEnd());
            })
            .OrderBy(item => item.file, StringComparer.Ordinal)
            .ToList();
    }
}
