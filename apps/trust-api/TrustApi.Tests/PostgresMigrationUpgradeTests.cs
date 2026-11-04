using System.Net;
using Npgsql;
using TrustApi.Domain;
using TrustApi.Infrastructure.Postgres;

namespace TrustApi.Tests;

[Collection("Postgres integration")]
public sealed class PostgresMigrationUpgradeTests
{
    private const string MigrationMarker = ".Migrations.";
    // Preserved verbatim from the pre-023 PostgresTrustStore.UpsertPhoneChallengeAsync at 96813cf.
    private const string LegacyPhoneChallengeUpsertSql = """
        INSERT INTO trust.phone_challenges (
            account_id, phone_e164, code_hash, expires_at, attempts, sent_at, send_count, window_started_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (account_id) DO UPDATE SET
            phone_e164 = EXCLUDED.phone_e164,
            code_hash = EXCLUDED.code_hash,
            expires_at = EXCLUDED.expires_at,
            attempts = EXCLUDED.attempts,
            sent_at = EXCLUDED.sent_at,
            send_count = EXCLUDED.send_count,
            window_started_at = EXCLUDED.window_started_at;
        """;
    private static readonly string SourceConnection =
        Environment.GetEnvironmentVariable("ConnectionStrings__Postgres")
        ?? "Host=127.0.0.1;Port=5433;Database=trust;Username=trust;Password=trust";

    [Fact]
    public async Task PopulatedSchemaAt013UpgradesTo025AndRemainsRepeatable()
    {
        var source = new NpgsqlConnectionStringBuilder(SourceConnection);
        if (!IPAddress.TryParse(source.Host, out var address) || !IPAddress.IsLoopback(address) || source.Port is not (5433 or 5434 or 5435))
        {
            throw new InvalidOperationException(
                $"Migration upgrade rehearsal only runs against PostgreSQL on loopback port 5433, 5434, or 5435; configured host/port was {source.Host}:{source.Port}.");
        }

        var database = $"trust_upgrade_{Guid.NewGuid():N}";
        var admin = new NpgsqlConnectionStringBuilder(source.ConnectionString)
        {
            Database = "postgres",
            Pooling = false
        }.ConnectionString;
        var databaseCreated = false;
        try
        {
            await using (var adminConnection = new NpgsqlConnection(admin))
            {
                await adminConnection.OpenAsync();
                await using var create = new NpgsqlCommand($"CREATE DATABASE \"{database}\";", adminConnection);
                try
                {
                    await create.ExecuteNonQueryAsync();
                    databaseCreated = true;
                }
                catch (PostgresException exception)
                {
                    throw new InvalidOperationException(
                        $"Could not create an isolated temporary database on local PostgreSQL at {source.Host}:{source.Port}. Grant the configured test role CREATEDB permission and rerun.",
                        exception);
                }
            }

            var target = new NpgsqlConnectionStringBuilder(source.ConnectionString)
            {
                Database = database,
                Pooling = false
            }.ConnectionString;
            var ids = new[] { Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid() };
            var membershipAB = Guid.NewGuid();
            var membershipAC = Guid.NewGuid();
            var requestBC = Guid.NewGuid();
            var placeId = Guid.NewGuid();
            var now = DateTimeOffset.UtcNow;
            now = now.AddTicks(-(now.Ticks % TimeSpan.TicksPerSecond));
            var pauseUntil = now.AddHours(2);
            var originalTransaction = $"upgrade-{Guid.NewGuid():N}";
            var transactionId = $"transaction-{Guid.NewGuid():N}";

            await ApplyEmbeddedMigrationsThrough013Async(target);
            await SeedPre014DataAsync(target, ids, membershipAB, membershipAC, requestBC, placeId, now, pauseUntil, originalTransaction, transactionId);

            await PostgresMigrator.ApplyAsync(target);
            var transitionAfterFirstApply = await ReadTransitionIdAsync(target, ids[0]);
            Assert.NotEqual(Guid.Empty, transitionAfterFirstApply);
            await PostgresMigrator.ApplyAsync(target);

            await AssertUpgradedDataAsync(target, ids, membershipAB, membershipAC, requestBC, placeId, originalTransaction, transactionId, pauseUntil);
            await AssertMigrationLedger030Async(target);
            Assert.Equal(transitionAfterFirstApply, await ReadTransitionIdAsync(target, ids[0]));

            var store = new PostgresTrustStore(target);
            var stoppedShare = new ShareState(ShareResting.Off, Revision: 0);
            await store.SetShareForConnectionAsync(ids[0], ids[1], membershipAB, 0, stoppedShare, true, CancellationToken.None);
            Assert.Equal(ShareResting.Off, (await store.GetShareAsync(ids[0], ids[1], CancellationToken.None)).Resting);
            await store.RevokeMembershipAsync(ids[0], ids[1], CancellationToken.None);
            Assert.False(await store.AreConnectedAsync(ids[0], ids[1], CancellationToken.None));
            Assert.Null(await store.GetPresenceGrantAsync(ids[0], ids[1], CancellationToken.None));
            Assert.Equal(transitionAfterFirstApply, await ReadTransitionIdAsync(target, ids[0]));
        }
        finally
        {
            if (databaseCreated)
            {
                await using var adminConnection = new NpgsqlConnection(admin);
                await adminConnection.OpenAsync();
                await using var terminate = new NpgsqlCommand(
                    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid();",
                    adminConnection);
                terminate.Parameters.AddWithValue(database);
                await terminate.ExecuteNonQueryAsync();
                await using var drop = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{database}\";", adminConnection);
                await drop.ExecuteNonQueryAsync();
            }
        }
    }

    [Fact]
    public async Task PhoneChallengeLegacyWriterWorksAt023AndAfterHistorical029Upgrade()
    {
        var source = new NpgsqlConnectionStringBuilder(SourceConnection);
        if (!IPAddress.TryParse(source.Host, out var address) || !IPAddress.IsLoopback(address) || source.Port is not (5433 or 5434 or 5435))
        {
            throw new InvalidOperationException(
                $"Migration compatibility rehearsal only runs against PostgreSQL on loopback port 5433, 5434, or 5435; configured host/port was {source.Host}:{source.Port}.");
        }

        var database = $"trust_phone_compat_{Guid.NewGuid():N}";
        var admin = new NpgsqlConnectionStringBuilder(source.ConnectionString)
        {
            Database = "postgres",
            Pooling = false
        }.ConnectionString;
        var databaseCreated = false;
        try
        {
            await using (var adminConnection = new NpgsqlConnection(admin))
            {
                await adminConnection.OpenAsync();
                await using var create = new NpgsqlCommand($"CREATE DATABASE \"{database}\";", adminConnection);
                await create.ExecuteNonQueryAsync();
                databaseCreated = true;
            }

            var target = new NpgsqlConnectionStringBuilder(source.ConnectionString)
            {
                Database = database,
                Pooling = false
            }.ConnectionString;
            var boundaryAccount = Guid.NewGuid();
            await ApplyEmbeddedMigrationsThroughAsync(target, "022_phone_correction_attempts.sql");
            await InsertSyntheticAccountAsync(target, boundaryAccount);
            await ApplyEmbeddedMigrationAsync(target, "023_phone_operations.sql");

            var now = DateTimeOffset.UtcNow;
            await ExecuteLegacyPhoneChallengeUpsertAsync(target, boundaryAccount, "+15555550101", "boundary-hash", now);
            var boundaryChallengeId = await ReadChallengeIdAsync(target, boundaryAccount);
            Assert.NotEqual(Guid.Empty, boundaryChallengeId);
            await ExecuteLegacyPhoneChallengeUpsertAsync(target, boundaryAccount, "+15555550102", "boundary-updated-hash", now.AddSeconds(1));
            Assert.Equal(boundaryChallengeId, await ReadChallengeIdAsync(target, boundaryAccount));

            await PostgresMigrator.ApplyAsync(target);
            await AssertMigrationLedgerCountAsync(target, 30);

            var historicalAccount = Guid.NewGuid();
            var explicitWriterAccount = Guid.NewGuid();
            await InsertSyntheticAccountAsync(target, historicalAccount);
            await InsertSyntheticAccountAsync(target, explicitWriterAccount);
            await ExecuteLegacyPhoneChallengeUpsertAsync(target, historicalAccount, "+15555550103", "full-schema-hash", now);
            var fullSchemaChallengeId = await ReadChallengeIdAsync(target, historicalAccount);
            Assert.NotEqual(Guid.Empty, fullSchemaChallengeId);
            await ExecuteLegacyPhoneChallengeUpsertAsync(target, historicalAccount, "+15555550104", "full-schema-updated-hash", now.AddSeconds(1));
            Assert.Equal(fullSchemaChallengeId, await ReadChallengeIdAsync(target, historicalAccount));

            var explicitChallengeId = Guid.NewGuid();
            await new PostgresTrustStore(target).UpsertPhoneChallengeAsync(
                new PhoneChallenge(explicitWriterAccount, "+15555550105", "explicit-writer-hash",
                    now.AddMinutes(10), 0, now, 1, now, ChallengeId: explicitChallengeId),
                CancellationToken.None);
            Assert.Equal(explicitChallengeId, await ReadChallengeIdAsync(target, explicitWriterAccount));

            // Simulate a database already marked through 029 whose 023 column lacks the
            // default. The append-only 030 migration must repair it without changing rows.
            await ExecuteAsync(target,
                "ALTER TABLE trust.phone_challenges ALTER COLUMN challenge_id DROP DEFAULT; " +
                "DELETE FROM trust.schema_migrations WHERE name = '030_phone_challenge_legacy_insert_default.sql';");
            await AssertMigrationLedgerCountAsync(target, 29);
            Assert.Null(await ReadChallengeIdDefaultAsync(target));
            await PostgresMigrator.ApplyAsync(target);
            await AssertMigrationLedgerCountAsync(target, 30);
            Assert.Contains("gen_random_uuid", (await ReadChallengeIdDefaultAsync(target)) ?? "", StringComparison.OrdinalIgnoreCase);
            Assert.Equal(boundaryChallengeId, await ReadChallengeIdAsync(target, boundaryAccount));
            Assert.Equal(fullSchemaChallengeId, await ReadChallengeIdAsync(target, historicalAccount));
            Assert.Equal(explicitChallengeId, await ReadChallengeIdAsync(target, explicitWriterAccount));

            var repairedLegacyAccount = Guid.NewGuid();
            await InsertSyntheticAccountAsync(target, repairedLegacyAccount);
            await ExecuteLegacyPhoneChallengeUpsertAsync(target, repairedLegacyAccount, "+15555550106", "repaired-hash", now);
            var repairedChallengeId = await ReadChallengeIdAsync(target, repairedLegacyAccount);
            Assert.NotEqual(Guid.Empty, repairedChallengeId);
            await ExecuteLegacyPhoneChallengeUpsertAsync(target, repairedLegacyAccount, "+15555550107", "repaired-updated-hash", now.AddSeconds(1));
            Assert.Equal(repairedChallengeId, await ReadChallengeIdAsync(target, repairedLegacyAccount));
        }
        finally
        {
            if (databaseCreated)
            {
                await using var adminConnection = new NpgsqlConnection(admin);
                await adminConnection.OpenAsync();
                await using var terminate = new NpgsqlCommand(
                    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid();",
                    adminConnection);
                terminate.Parameters.AddWithValue(database);
                await terminate.ExecuteNonQueryAsync();
                await using var drop = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{database}\";", adminConnection);
                await drop.ExecuteNonQueryAsync();
            }
        }
    }

    private static async Task ApplyEmbeddedMigrationsThrough013Async(string connectionString) =>
        await ApplyEmbeddedMigrationsThroughAsync(connectionString, "013_discovery_consent.sql");

    private static async Task ApplyEmbeddedMigrationsThroughAsync(string connectionString, string throughMigration)
    {
        var migrations = typeof(PostgresMigrator).Assembly.GetManifestResourceNames()
            .Where(name => name.Contains(MigrationMarker, StringComparison.Ordinal) && name.EndsWith(".sql", StringComparison.Ordinal))
            .Select(name =>
            {
                var file = name[(name.LastIndexOf(MigrationMarker, StringComparison.Ordinal) + MigrationMarker.Length)..];
                using var stream = typeof(PostgresMigrator).Assembly.GetManifestResourceStream(name)
                    ?? throw new InvalidOperationException($"Missing embedded migration {name}.");
                using var reader = new StreamReader(stream);
                return (Name: file, Sql: reader.ReadToEnd());
            })
            .Where(item => string.CompareOrdinal(item.Name, throughMigration) <= 0)
            .OrderBy(item => item.Name, StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(int.Parse(throughMigration.AsSpan(0, 3)), migrations.Length);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using (var initialize = new NpgsqlCommand(
            "CREATE SCHEMA trust; CREATE TABLE trust.schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL);",
            connection))
        {
            await initialize.ExecuteNonQueryAsync();
        }

        foreach (var migration in migrations)
        {
            await using var transaction = await connection.BeginTransactionAsync();
            await using (var apply = new NpgsqlCommand(migration.Sql, connection, transaction))
            {
                await apply.ExecuteNonQueryAsync();
            }
            await using (var record = new NpgsqlCommand(
                "INSERT INTO trust.schema_migrations(name, applied_at) VALUES ($1, now());",
                connection,
                transaction))
            {
                record.Parameters.AddWithValue(migration.Name);
                await record.ExecuteNonQueryAsync();
            }
            await transaction.CommitAsync();
        }
    }

    private static async Task ApplyEmbeddedMigrationAsync(string connectionString, string migrationName)
    {
        var resourceName = typeof(PostgresMigrator).Assembly.GetManifestResourceNames()
            .Single(name => name.Contains(MigrationMarker, StringComparison.Ordinal)
                && name.EndsWith(migrationName, StringComparison.Ordinal));
        using var stream = typeof(PostgresMigrator).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing embedded migration {resourceName}.");
        using var reader = new StreamReader(stream);
        var sql = await reader.ReadToEndAsync();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        await using (var apply = new NpgsqlCommand(sql, connection, transaction))
            await apply.ExecuteNonQueryAsync();
        await using (var record = new NpgsqlCommand(
            "INSERT INTO trust.schema_migrations(name, applied_at) VALUES ($1, now());",
            connection, transaction))
        {
            record.Parameters.AddWithValue(migrationName);
            await record.ExecuteNonQueryAsync();
        }
        await transaction.CommitAsync();
    }

    private static async Task InsertSyntheticAccountAsync(string connectionString, Guid accountId)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "INSERT INTO trust.accounts(account_id, provider, provider_subject, display_name, has_circle, circle_source, created_at) VALUES ($1, 'synthetic-phone-migration', $2, 'Synthetic Test', true, 'test', now());",
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue($"phone-migration-{Guid.NewGuid():N}");
        await command.ExecuteNonQueryAsync();
    }

    private static async Task ExecuteLegacyPhoneChallengeUpsertAsync(
        string connectionString, Guid accountId, string phone, string codeHash, DateTimeOffset timestamp)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(LegacyPhoneChallengeUpsertSql, connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(phone);
        command.Parameters.AddWithValue(codeHash);
        command.Parameters.AddWithValue(timestamp.AddMinutes(10));
        command.Parameters.AddWithValue(0);
        command.Parameters.AddWithValue(timestamp);
        command.Parameters.AddWithValue(1);
        command.Parameters.AddWithValue(timestamp);
        await command.ExecuteNonQueryAsync();
    }

    private static async Task<Guid> ReadChallengeIdAsync(string connectionString, Guid accountId)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT challenge_id FROM trust.phone_challenges WHERE account_id = $1;", connection);
        command.Parameters.AddWithValue(accountId);
        return (Guid)(await command.ExecuteScalarAsync())!;
    }

    private static async Task<string?> ReadChallengeIdDefaultAsync(string connectionString)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT column_default FROM information_schema.columns WHERE table_schema = 'trust' AND table_name = 'phone_challenges' AND column_name = 'challenge_id';",
            connection);
        var value = await command.ExecuteScalarAsync();
        return value is null or DBNull ? null : (string)value;
    }

    private static async Task AssertMigrationLedgerCountAsync(string connectionString, int expected)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM trust.schema_migrations;", connection);
        Assert.Equal(expected, Convert.ToInt32(await command.ExecuteScalarAsync()));
    }

    private static async Task ExecuteAsync(string connectionString, string sql)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync();
    }

    private static async Task SeedPre014DataAsync(
        string connectionString,
        Guid[] ids,
        Guid membershipAB,
        Guid membershipAC,
        Guid requestBC,
        Guid placeId,
        DateTimeOffset now,
        DateTimeOffset pauseUntil,
        string originalTransaction,
        string transactionId)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        foreach (var (id, suffix) in ids.Select((id, index) => (id, index)))
        {
            await using var account = new NpgsqlCommand(
                "INSERT INTO trust.accounts(account_id, provider, provider_subject, display_name, has_circle, circle_source, created_at) VALUES ($1, 'synthetic-migration-upgrade', $2, $3, true, 'test', $4);",
                connection,
                transaction);
            account.Parameters.AddWithValue(id);
            account.Parameters.AddWithValue($"account-{Guid.NewGuid():N}-{suffix}");
            account.Parameters.AddWithValue($"Upgrade Test {suffix}");
            account.Parameters.AddWithValue(now);
            await account.ExecuteNonQueryAsync();
        }

        await using (var membership = new NpgsqlCommand(
            "INSERT INTO trust.memberships(membership_id, person_a, person_b, status, created_at) VALUES ($1, LEAST($2, $3), GREATEST($2, $3), 'active', $4), ($5, LEAST($2, $6), GREATEST($2, $6), 'active', $4);",
            connection,
            transaction))
        {
            membership.Parameters.AddWithValue(membershipAB);
            membership.Parameters.AddWithValue(ids[0]);
            membership.Parameters.AddWithValue(ids[1]);
            membership.Parameters.AddWithValue(now);
            membership.Parameters.AddWithValue(membershipAC);
            membership.Parameters.AddWithValue(ids[2]);
            // Membership rows require canonical GUID ordering.
            await membership.ExecuteNonQueryAsync();
        }

        await using (var shares = new NpgsqlCommand(
            "INSERT INTO trust.shares(grantor_id, grantee_id, resting, timed_until, pause_until, restores_to) VALUES ($1, $2, 'until_they_look', NULL, NULL, NULL), ($1, $3, 'always', NULL, NULL, NULL), ($3, $1, 'paused', NULL, $4, 'always');",
            connection,
            transaction))
        {
            shares.Parameters.AddWithValue(ids[0]);
            shares.Parameters.AddWithValue(ids[1]);
            shares.Parameters.AddWithValue(ids[2]);
            shares.Parameters.AddWithValue(pauseUntil);
            await shares.ExecuteNonQueryAsync();
        }

        await using (var presence = new NpgsqlCommand(
            "INSERT INTO trust.presence_grants(subject_id, trustee_id, enabled, updated_at) VALUES ($1, $2, true, $3);",
            connection,
            transaction))
        {
            presence.Parameters.AddWithValue(ids[0]);
            presence.Parameters.AddWithValue(ids[1]);
            presence.Parameters.AddWithValue(now);
            await presence.ExecuteNonQueryAsync();
        }

        await using (var home = new NpgsqlCommand(
            "INSERT INTO trust.home_places(account_id, place_id, label, updated_at) VALUES ($1, $2, 'Synthetic home', $3);",
            connection,
            transaction))
        {
            home.Parameters.AddWithValue(ids[0]);
            home.Parameters.AddWithValue(placeId);
            home.Parameters.AddWithValue(now);
            await home.ExecuteNonQueryAsync();
        }

        await using (var currentPresence = new NpgsqlCommand(
            "INSERT INTO trust.current_home_presence(account_id, place_id, state, last_changed_at, last_signal_at) VALUES ($1, $2, 'home', $3, $3);",
            connection,
            transaction))
        {
            currentPresence.Parameters.AddWithValue(ids[0]);
            currentPresence.Parameters.AddWithValue(placeId);
            currentPresence.Parameters.AddWithValue(now);
            await currentPresence.ExecuteNonQueryAsync();
        }

        await using (var request = new NpgsqlCommand(
            "INSERT INTO trust.connection_requests(request_id, sender_id, recipient_id, status, created_at, expires_at, updated_at) VALUES ($1, $2, $3, 'pending', $4, $5, $4);",
            connection,
            transaction))
        {
            request.Parameters.AddWithValue(requestBC);
            request.Parameters.AddWithValue(ids[1]);
            request.Parameters.AddWithValue(ids[2]);
            request.Parameters.AddWithValue(now);
            request.Parameters.AddWithValue(now.AddDays(7));
            await request.ExecuteNonQueryAsync();
        }

        await using (var location = new NpgsqlCommand(
            "INSERT INTO trust.location_points(account_id, recorded_at, latitude, longitude) VALUES ($1, $2, 37.7749, -122.4194);",
            connection,
            transaction))
        {
            location.Parameters.AddWithValue(ids[0]);
            location.Parameters.AddWithValue(now);
            await location.ExecuteNonQueryAsync();
        }

        await using (var subscription = new NpgsqlCommand(
            "INSERT INTO trust.storekit_subscription_owners(original_transaction_id, account_id, app_account_token, created_at) VALUES ($1, $2, $3, $4);",
            connection,
            transaction))
        {
            subscription.Parameters.AddWithValue(originalTransaction);
            subscription.Parameters.AddWithValue(ids[0]);
            subscription.Parameters.AddWithValue(Guid.NewGuid());
            subscription.Parameters.AddWithValue(now);
            await subscription.ExecuteNonQueryAsync();
        }

        await using (var transactionRow = new NpgsqlCommand(
            "INSERT INTO trust.storekit_transactions(transaction_id, original_transaction_id, account_id, product_id, environment, signed_at, expires_at, received_at) VALUES ($1, $2, $3, 'trust.plus.monthly', 'Sandbox', $4, $5, $4);",
            connection,
            transaction))
        {
            transactionRow.Parameters.AddWithValue(transactionId);
            transactionRow.Parameters.AddWithValue(originalTransaction);
            transactionRow.Parameters.AddWithValue(ids[0]);
            transactionRow.Parameters.AddWithValue(now);
            transactionRow.Parameters.AddWithValue(now.AddDays(30));
            await transactionRow.ExecuteNonQueryAsync();
        }

        await transaction.CommitAsync();
    }

    private static async Task AssertUpgradedDataAsync(
        string connectionString,
        Guid[] ids,
        Guid membershipAB,
        Guid membershipAC,
        Guid requestBC,
        Guid placeId,
        string originalTransaction,
        string transactionId,
        DateTimeOffset pauseUntil)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using (var command = new NpgsqlCommand(
            "SELECT account_id, provider, provider_subject, display_name FROM trust.accounts ORDER BY account_id;",
            connection))
        await using (var reader = await command.ExecuteReaderAsync())
        {
            var found = new Dictionary<Guid, (string Provider, string Subject, string DisplayName)>();
            while (await reader.ReadAsync())
                found.Add(reader.GetGuid(0), (reader.GetString(1), reader.GetString(2), reader.GetString(3)));
            Assert.True(ids.ToHashSet().SetEquals(found.Keys), "The migrated account identities did not match the seeded identities.");
            Assert.All(found.Values, account =>
            {
                Assert.Equal("synthetic-migration-upgrade", account.Provider);
                Assert.StartsWith("account-", account.Subject);
                Assert.StartsWith("Upgrade Test ", account.DisplayName);
            });
        }

        await using (var command = new NpgsqlCommand(
            "SELECT membership_id FROM trust.memberships WHERE status = 'active';",
            connection))
        await using (var reader = await command.ExecuteReaderAsync())
        {
            var found = new HashSet<Guid>();
            while (await reader.ReadAsync()) found.Add(reader.GetGuid(0));
            Assert.True(new[] { membershipAB, membershipAC }.ToHashSet().SetEquals(found), "The accepted memberships did not survive migration.");
        }

        await using (var command = new NpgsqlCommand(
            "SELECT resting, pause_until, restores_to, revision FROM trust.shares WHERE grantor_id = $1 ORDER BY grantee_id;",
            connection))
        {
            command.Parameters.AddWithValue(ids[0]);
            await using var reader = await command.ExecuteReaderAsync();
            var values = new Dictionary<string, (DateTimeOffset? PauseUntil, string? RestoresTo, long Revision)>();
            while (await reader.ReadAsync())
            {
                values.Add(reader.GetString(0), (reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1), reader.IsDBNull(2) ? null : reader.GetString(2), reader.GetInt64(3)));
            }
            Assert.Equal(2, values.Count);
            Assert.Contains(values, item => item.Key == "until_they_look" && item.Value.Revision == 0);
            Assert.Contains(values, item => item.Key == "always" && item.Value.Revision == 0);
        }

        await using (var command = new NpgsqlCommand(
            "SELECT resting, pause_until, restores_to, revision FROM trust.shares WHERE grantor_id = $1 AND grantee_id = $2;",
            connection))
        {
            command.Parameters.AddWithValue(ids[2]);
            command.Parameters.AddWithValue(ids[0]);
            await using var reader = await command.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal("paused", reader.GetString(0));
            Assert.Equal(pauseUntil, reader.GetFieldValue<DateTimeOffset>(1));
            Assert.Equal("always", reader.GetString(2));
            Assert.Equal(0L, reader.GetInt64(3));
        }

        Assert.Equal((ids[0], ids[1], true, 0L), await ReadPresenceGrantAsync(connection, ids[0]));
        Assert.Equal((ids[0], placeId, "Synthetic home"), await ReadHomeAsync(connection, ids[0]));
        Assert.Equal((ids[0], placeId, "home"), await ReadCurrentHomeAsync(connection, ids[0]));
        Assert.Equal((requestBC, ids[1], ids[2], "pending"), await ReadRequestAsync(connection));
        Assert.Equal((37.7749, -122.4194), await ReadLocationAsync(connection, ids[0]));
        Assert.Equal((originalTransaction, transactionId, ids[0]), await ReadSubscriptionAsync(connection));
    }

    private static async Task<(Guid Subject, Guid Trustee, bool Enabled, long Revision)> ReadPresenceGrantAsync(NpgsqlConnection connection, Guid subject)
    {
        await using var command = new NpgsqlCommand("SELECT subject_id, trustee_id, enabled, revision FROM trust.presence_grants WHERE subject_id = $1;", connection);
        command.Parameters.AddWithValue(subject);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetGuid(0), reader.GetGuid(1), reader.GetBoolean(2), reader.GetInt64(3));
    }

    private static async Task<(Guid Account, Guid PlaceId, string Label)> ReadHomeAsync(NpgsqlConnection connection, Guid account)
    {
        await using var command = new NpgsqlCommand("SELECT account_id, place_id, label FROM trust.home_places WHERE account_id = $1;", connection);
        command.Parameters.AddWithValue(account);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2));
    }

    private static async Task<(Guid Account, Guid PlaceId, string State)> ReadCurrentHomeAsync(NpgsqlConnection connection, Guid account)
    {
        await using var command = new NpgsqlCommand("SELECT account_id, place_id, state FROM trust.current_home_presence WHERE account_id = $1;", connection);
        command.Parameters.AddWithValue(account);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2));
    }

    private static async Task<(Guid Request, Guid Sender, Guid Recipient, string Status)> ReadRequestAsync(NpgsqlConnection connection)
    {
        await using var command = new NpgsqlCommand("SELECT request_id, sender_id, recipient_id, status FROM trust.connection_requests;", connection);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2), reader.GetString(3));
    }

    private static async Task<(double Latitude, double Longitude)> ReadLocationAsync(NpgsqlConnection connection, Guid account)
    {
        await using var command = new NpgsqlCommand("SELECT latitude, longitude FROM trust.location_points WHERE account_id = $1;", connection);
        command.Parameters.AddWithValue(account);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetDouble(0), reader.GetDouble(1));
    }

    private static async Task<(string OriginalTransaction, string Transaction, Guid Account)> ReadSubscriptionAsync(NpgsqlConnection connection)
    {
        await using var command = new NpgsqlCommand(
            "SELECT owner.original_transaction_id, transaction.transaction_id, transaction.account_id FROM trust.storekit_subscription_owners owner JOIN trust.storekit_transactions transaction USING (original_transaction_id);",
            connection);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetString(0), reader.GetString(1), reader.GetGuid(2));
    }

    private static async Task<Guid> ReadTransitionIdAsync(string connectionString, Guid account)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT transition_id FROM trust.current_home_presence WHERE account_id = $1;", connection);
        command.Parameters.AddWithValue(account);
        return (Guid)(await command.ExecuteScalarAsync())!;
    }

    private static async Task AssertMigrationLedger030Async(string connectionString)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT name FROM trust.schema_migrations ORDER BY name;", connection);
        await using var reader = await command.ExecuteReaderAsync();
        var names = new List<string>();
        while (await reader.ReadAsync()) names.Add(reader.GetString(0));
        Assert.Equal(30, names.Count);
        Assert.Equal("001_initial.sql", names[0]);
        Assert.Equal("030_phone_challenge_legacy_insert_default.sql", names[^1]);
    }
}
