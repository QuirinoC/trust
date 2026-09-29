using System.Security.Cryptography;
using System.Text;
using Npgsql;
using TrustApi.Configuration;
using TrustApi.Infrastructure.StoreKit;

namespace TrustApi.Infrastructure.AgeAssurance;

public enum AppTransactionLinkResult
{
    Linked,
    ConsentRevoked
}

public sealed record PendingAccountDeletion(Guid AccountId, Guid LeaseToken, int AttemptCount);
public sealed record AccountPrivacyHold(Guid AccountId, DateTimeOffset HeldAt, string PolicyVersion, string Reason);

public static class AccountPrivacyHoldPolicy
{
    public const string Version = "2026-09-v1";
    public const string Reason = "client_reported_age_restriction";
}

public interface IAgeAssuranceAccountStore
{
    Task<AppTransactionLinkResult> TryRegisterAppTransactionLinkAsync(
        Guid accountId,
        VerifiedStoreKitAppTransaction appTransaction,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<Guid>> RecordConsentRevocationAsync(
        Guid notificationId,
        VerifiedStoreKitAppTransaction appTransaction,
        DateTimeOffset signedAt,
        CancellationToken cancellationToken);

    Task RemoveAppTransactionLinkAsync(
        Guid accountId,
        VerifiedStoreKitAppTransaction appTransaction,
        CancellationToken cancellationToken);

    Task<bool> HasAppTransactionLinkAsync(Guid accountId, CancellationToken cancellationToken);
    Task<bool> IsAccountBlockedAsync(Guid accountId, CancellationToken cancellationToken);
    Task<bool> IsAccountPrivacyHeldAsync(Guid accountId, CancellationToken cancellationToken);
    Task<AccountPrivacyHold> PlaceAccountPrivacyHoldAsync(Guid accountId, DateTimeOffset heldAt, CancellationToken cancellationToken);
    Task<AccountPrivacyHold?> FindAccountPrivacyHoldAsync(Guid accountId, CancellationToken cancellationToken);
    Task<IReadOnlyList<Guid>> ListAccountsPendingDeletionAsync(int limit, CancellationToken cancellationToken);
    Task<IReadOnlyList<PendingAccountDeletion>> ClaimPendingAccountDeletionsAsync(
        int limit, DateTimeOffset now, TimeSpan leaseDuration, CancellationToken cancellationToken);
    Task RecordAccountDeletionRetryAsync(
        PendingAccountDeletion claim, DateTimeOffset retryAt, CancellationToken cancellationToken);
    Task CompleteAccountDeletionAsync(Guid accountId, CancellationToken cancellationToken);
}

public static class AppTransactionIdentifier
{
    public static string Hash(string appTransactionId) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(appTransactionId))).ToLowerInvariant();
}

public sealed class MemoryAgeAssuranceAccountStore : IAgeAssuranceAccountStore
{
    private readonly object _gate = new();
    private readonly Dictionary<(string Hash, string Environment), HashSet<Guid>> _links = [];
    private readonly Dictionary<(string Hash, string Environment), DateTimeOffset> _revoked = [];
    private readonly Dictionary<Guid, (string Hash, string Environment)> _notifications = [];
    private readonly Dictionary<Guid, HashSet<(string Hash, string Environment)>> _blockedAccounts = [];
    private readonly Dictionary<Guid, CleanupJob> _cleanupJobs = [];
    private readonly Dictionary<Guid, AccountPrivacyHold> _privacyHolds = [];

    private sealed record CleanupJob(int AttemptCount, DateTimeOffset NextAttemptAt, Guid? LeaseToken, DateTimeOffset? LeaseUntil);

    public Task<AppTransactionLinkResult> TryRegisterAppTransactionLinkAsync(
        Guid accountId,
        VerifiedStoreKitAppTransaction appTransaction,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var key = (AppTransactionIdentifier.Hash(appTransaction.AppTransactionId), appTransaction.Environment);
        lock (_gate)
        {
            // An AppTransaction proves app ownership only. It cannot restore withdrawn
            // parental consent, regardless of when this account registers it.
            if (_revoked.ContainsKey(key))
            {
                if (!_blockedAccounts.TryGetValue(accountId, out var blockedTransactions))
                {
                    blockedTransactions = [];
                    _blockedAccounts[accountId] = blockedTransactions;
                }
                blockedTransactions.Add(key);
                EnqueueCleanupJob(accountId);
                return Task.FromResult(AppTransactionLinkResult.ConsentRevoked);
            }

            if (!_links.TryGetValue(key, out var accounts))
            {
                accounts = [];
                _links[key] = accounts;
            }

            accounts.Add(accountId);
        }

        return Task.FromResult(AppTransactionLinkResult.Linked);
    }

    public Task<IReadOnlyList<Guid>> RecordConsentRevocationAsync(
        Guid notificationId,
        VerifiedStoreKitAppTransaction appTransaction,
        DateTimeOffset signedAt,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var key = (AppTransactionIdentifier.Hash(appTransaction.AppTransactionId), appTransaction.Environment);
        lock (_gate)
        {
            if (_notifications.TryGetValue(notificationId, out var recordedKey))
            {
                if (recordedKey != key || !_revoked.ContainsKey(key))
                {
                    return Task.FromResult<IReadOnlyList<Guid>>([]);
                }

                var retryAccounts = AccountsFor(key);
                foreach (var accountId in retryAccounts) EnqueueCleanupJob(accountId);
                return Task.FromResult<IReadOnlyList<Guid>>(retryAccounts);
            }

            _notifications[notificationId] = key;
            _revoked[key] = signedAt;
            var accountIds = AccountsFor(key);
            foreach (var accountId in accountIds) EnqueueCleanupJob(accountId);
            return Task.FromResult<IReadOnlyList<Guid>>(accountIds);
        }
    }

    public Task<bool> IsAccountBlockedAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            return Task.FromResult(
                _blockedAccounts.ContainsKey(accountId)
                || _links.Any(pair => pair.Value.Contains(accountId) && _revoked.ContainsKey(pair.Key)));
        }
    }

    public Task<bool> HasAppTransactionLinkAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            return Task.FromResult(_links.Values.Any(accounts => accounts.Contains(accountId)));
        }
    }

    public Task<bool> IsAccountPrivacyHeldAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate) return Task.FromResult(_privacyHolds.ContainsKey(accountId));
    }

    public Task<AccountPrivacyHold> PlaceAccountPrivacyHoldAsync(
        Guid accountId, DateTimeOffset heldAt, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            if (!_privacyHolds.TryGetValue(accountId, out var hold))
            {
                hold = new AccountPrivacyHold(accountId, heldAt, AccountPrivacyHoldPolicy.Version, AccountPrivacyHoldPolicy.Reason);
                _privacyHolds.Add(accountId, hold);
            }
            return Task.FromResult(hold);
        }
    }

    public Task<AccountPrivacyHold?> FindAccountPrivacyHoldAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            _privacyHolds.TryGetValue(accountId, out var hold);
            return Task.FromResult(hold);
        }
    }

    public Task<IReadOnlyList<Guid>> ListAccountsPendingDeletionAsync(int limit, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var boundedLimit = Math.Clamp(limit, 1, 500);
        lock (_gate)
        {
            var pending = _blockedAccounts.Keys
                .Concat(_links.Where(pair => _revoked.ContainsKey(pair.Key)).SelectMany(pair => pair.Value))
                .Distinct()
                .Take(boundedLimit)
                .ToArray();
            return Task.FromResult<IReadOnlyList<Guid>>(pending);
        }
    }

    public Task CompleteAccountDeletionAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            _blockedAccounts.Remove(accountId);
            _cleanupJobs.Remove(accountId);
            _privacyHolds.Remove(accountId);
            foreach (var key in _links.Keys.ToList())
            {
                _links[key].Remove(accountId);
                if (_links[key].Count == 0) _links.Remove(key);
            }
        }
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<PendingAccountDeletion>> ClaimPendingAccountDeletionsAsync(
        int limit, DateTimeOffset now, TimeSpan leaseDuration, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var boundedLimit = Math.Clamp(limit, 1, 500);
        lock (_gate)
        {
            var due = _cleanupJobs
                .Where(pair => pair.Value.NextAttemptAt <= now
                    && (pair.Value.LeaseUntil is null || pair.Value.LeaseUntil <= now))
                .OrderBy(pair => pair.Value.NextAttemptAt)
                .ThenBy(pair => pair.Key)
                .Take(boundedLimit)
                .ToArray();
            var claims = new List<PendingAccountDeletion>(due.Length);
            foreach (var pair in due)
            {
                var leaseToken = Guid.NewGuid();
                _cleanupJobs[pair.Key] = pair.Value with { LeaseToken = leaseToken, LeaseUntil = now + leaseDuration };
                claims.Add(new PendingAccountDeletion(pair.Key, leaseToken, pair.Value.AttemptCount));
            }
            return Task.FromResult<IReadOnlyList<PendingAccountDeletion>>(claims);
        }
    }

    public Task RecordAccountDeletionRetryAsync(
        PendingAccountDeletion claim, DateTimeOffset retryAt, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            if (_cleanupJobs.TryGetValue(claim.AccountId, out var job) && job.LeaseToken == claim.LeaseToken)
            {
                _cleanupJobs[claim.AccountId] = job with
                {
                    AttemptCount = job.AttemptCount + 1,
                    NextAttemptAt = retryAt,
                    LeaseToken = null,
                    LeaseUntil = null
                };
            }
        }
        return Task.CompletedTask;
    }

    private void EnqueueCleanupJob(Guid accountId) =>
        _cleanupJobs.TryAdd(accountId, new CleanupJob(0, DateTimeOffset.MinValue, null, null));

    private IReadOnlyList<Guid> AccountsFor((string Hash, string Environment) key) =>
        _links.Where(pair => pair.Key == key).SelectMany(pair => pair.Value)
            .Concat(_blockedAccounts.Where(pair => pair.Value.Contains(key)).Select(pair => pair.Key))
            .Distinct().ToArray();

    public Task RemoveAppTransactionLinkAsync(
        Guid accountId,
        VerifiedStoreKitAppTransaction appTransaction,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var key = (AppTransactionIdentifier.Hash(appTransaction.AppTransactionId), appTransaction.Environment);
        lock (_gate)
        {
            if (_links.TryGetValue(key, out var accounts))
            {
                accounts.Remove(accountId);
                if (accounts.Count == 0)
                {
                    _links.Remove(key);
                }
            }
        }

        return Task.CompletedTask;
    }

    public Task RemoveAllAppTransactionLinksAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            foreach (var key in _links.Keys.ToList())
            {
                if (_links[key].Remove(accountId) && _links[key].Count == 0)
                {
                    _links.Remove(key);
                }
            }
        }

        return Task.CompletedTask;
    }
}

public sealed class PostgresAgeAssuranceAccountStore(string connectionString) : IAgeAssuranceAccountStore
{
    private readonly string _connectionString = PostgresConnectionString.Normalize(connectionString);

    public async Task<AppTransactionLinkResult> TryRegisterAppTransactionLinkAsync(
        Guid accountId,
        VerifiedStoreKitAppTransaction appTransaction,
        CancellationToken cancellationToken)
    {
        var hash = AppTransactionIdentifier.Hash(appTransaction.AppTransactionId);
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await AcquireTransactionLockAsync(
            connection,
            transaction,
            hash,
            appTransaction.Environment,
            cancellationToken);
        if (await IsRevokedAsync(
                connection,
                transaction,
                hash,
                appTransaction.Environment,
                cancellationToken))
        {
            await using var block = new NpgsqlCommand(
                "INSERT INTO trust.age_assurance_blocked_accounts (account_id, app_transaction_hash, environment) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING;",
                connection,
                transaction);
            block.Parameters.AddWithValue(accountId);
            block.Parameters.AddWithValue(hash);
            block.Parameters.AddWithValue(appTransaction.Environment);
            await block.ExecuteNonQueryAsync(cancellationToken);
            await EnqueueCleanupJobsAsync(connection, transaction, [accountId], cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return AppTransactionLinkResult.ConsentRevoked;
        }

        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO trust.age_assurance_app_transactions (
                app_transaction_hash, environment, account_id)
            VALUES ($1, $2, $3)
            ON CONFLICT (app_transaction_hash, environment, account_id) DO NOTHING;
            """,
            connection,
            transaction))
        {
            command.Parameters.AddWithValue(hash);
            command.Parameters.AddWithValue(appTransaction.Environment);
            command.Parameters.AddWithValue(accountId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return AppTransactionLinkResult.Linked;
    }

    public async Task<IReadOnlyList<Guid>> RecordConsentRevocationAsync(
        Guid notificationId,
        VerifiedStoreKitAppTransaction appTransaction,
        DateTimeOffset signedAt,
        CancellationToken cancellationToken)
    {
        var hash = AppTransactionIdentifier.Hash(appTransaction.AppTransactionId);
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await AcquireTransactionLockAsync(
            connection,
            transaction,
            hash,
            appTransaction.Environment,
            cancellationToken);

        bool inserted;
        await using (var record = new NpgsqlCommand(
            """
            INSERT INTO trust.age_assurance_notifications (
                notification_id, app_transaction_hash, environment, signed_at, received_at)
            VALUES ($1, $2, $3, $4, now())
            ON CONFLICT (notification_id) DO NOTHING
            RETURNING notification_id;
            """,
            connection,
            transaction))
        {
            record.Parameters.AddWithValue(notificationId);
            record.Parameters.AddWithValue(hash);
            record.Parameters.AddWithValue(appTransaction.Environment);
            record.Parameters.AddWithValue(signedAt);
            inserted = await record.ExecuteScalarAsync(cancellationToken) is Guid;
        }

        if (!inserted)
        {
            var original = await ReadNotificationKeyAsync(connection, transaction, notificationId, cancellationToken);
            if (original is null
                || original.Value.Hash != hash
                || original.Value.Environment != appTransaction.Environment
                || !await IsRevokedAsync(connection, transaction, hash, appTransaction.Environment, cancellationToken))
            {
                await transaction.CommitAsync(cancellationToken);
                return [];
            }

            var retryAccountIds = await ReadLinkedAccountIdsAsync(
                connection,
                transaction,
                hash,
                appTransaction.Environment,
                cancellationToken);
            await EnqueueCleanupJobsAsync(connection, transaction, retryAccountIds, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return retryAccountIds;
        }

        await using (var revoke = new NpgsqlCommand(
            """
            INSERT INTO trust.age_assurance_revoked_app_transactions (
                app_transaction_hash, environment, notification_id, revoked_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (app_transaction_hash, environment) DO UPDATE SET
                notification_id = EXCLUDED.notification_id,
                revoked_at = GREATEST(trust.age_assurance_revoked_app_transactions.revoked_at, EXCLUDED.revoked_at);
            """,
            connection,
            transaction))
        {
            revoke.Parameters.AddWithValue(hash);
            revoke.Parameters.AddWithValue(appTransaction.Environment);
            revoke.Parameters.AddWithValue(notificationId);
            revoke.Parameters.AddWithValue(signedAt);
            await revoke.ExecuteNonQueryAsync(cancellationToken);
        }

        var accountIds = await ReadLinkedAccountIdsAsync(
            connection,
            transaction,
            hash,
            appTransaction.Environment,
            cancellationToken);
        await EnqueueCleanupJobsAsync(connection, transaction, accountIds, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return accountIds;
    }

    public async Task RemoveAppTransactionLinkAsync(
        Guid accountId,
        VerifiedStoreKitAppTransaction appTransaction,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "DELETE FROM trust.age_assurance_app_transactions WHERE app_transaction_hash = $1 AND environment = $2 AND account_id = $3;",
            connection);
        command.Parameters.AddWithValue(AppTransactionIdentifier.Hash(appTransaction.AppTransactionId));
        command.Parameters.AddWithValue(appTransaction.Environment);
        command.Parameters.AddWithValue(accountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<bool> IsAccountBlockedAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT EXISTS (
                SELECT 1 FROM trust.age_assurance_blocked_accounts WHERE account_id = $1
                UNION ALL
                SELECT 1 FROM trust.age_assurance_app_transactions link
                INNER JOIN trust.age_assurance_revoked_app_transactions revoked
                    USING (app_transaction_hash, environment)
                WHERE link.account_id = $1);
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    public async Task<bool> IsAccountPrivacyHeldAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM trust.age_assurance_privacy_holds WHERE account_id = $1);",
            connection);
        command.Parameters.AddWithValue(accountId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    public async Task<AccountPrivacyHold> PlaceAccountPrivacyHoldAsync(
        Guid accountId, DateTimeOffset heldAt, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var insert = new NpgsqlCommand(
            "INSERT INTO trust.age_assurance_privacy_holds (account_id, held_at, policy_version, reason) VALUES ($1, $2, $3, $4) ON CONFLICT (account_id) DO NOTHING;",
            connection,
            transaction))
        {
            insert.Parameters.AddWithValue(accountId);
            insert.Parameters.AddWithValue(heldAt);
            insert.Parameters.AddWithValue(AccountPrivacyHoldPolicy.Version);
            insert.Parameters.AddWithValue(AccountPrivacyHoldPolicy.Reason);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        await using var read = new NpgsqlCommand(
            "SELECT account_id, held_at, policy_version, reason FROM trust.age_assurance_privacy_holds WHERE account_id = $1;",
            connection,
            transaction);
        read.Parameters.AddWithValue(accountId);
        await using var reader = await read.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
            throw new InvalidOperationException("Account privacy hold was not persisted.");
        var hold = new AccountPrivacyHold(reader.GetGuid(0), reader.GetFieldValue<DateTimeOffset>(1), reader.GetString(2), reader.GetString(3));
        await reader.CloseAsync();
        await transaction.CommitAsync(cancellationToken);
        return hold;
    }

    public async Task<AccountPrivacyHold?> FindAccountPrivacyHoldAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT account_id, held_at, policy_version, reason FROM trust.age_assurance_privacy_holds WHERE account_id = $1;",
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? new AccountPrivacyHold(reader.GetGuid(0), reader.GetFieldValue<DateTimeOffset>(1), reader.GetString(2), reader.GetString(3))
            : null;
    }

    public async Task<bool> HasAppTransactionLinkAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM trust.age_assurance_app_transactions WHERE account_id = $1);",
            connection);
        command.Parameters.AddWithValue(accountId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    public async Task<IReadOnlyList<Guid>> ListAccountsPendingDeletionAsync(int limit, CancellationToken cancellationToken)
    {
        var boundedLimit = Math.Clamp(limit, 1, 500);
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT account_id FROM trust.age_assurance_blocked_accounts
            UNION
            SELECT link.account_id
            FROM trust.age_assurance_app_transactions link
            INNER JOIN trust.age_assurance_revoked_app_transactions revoked
                USING (app_transaction_hash, environment)
            ORDER BY account_id
            LIMIT $1;
            """,
            connection);
        command.Parameters.AddWithValue(boundedLimit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var pending = new List<Guid>();
        while (await reader.ReadAsync(cancellationToken))
        {
            pending.Add(reader.GetGuid(0));
        }
        return pending;
    }

    public async Task<IReadOnlyList<PendingAccountDeletion>> ClaimPendingAccountDeletionsAsync(
        int limit, DateTimeOffset now, TimeSpan leaseDuration, CancellationToken cancellationToken)
    {
        var boundedLimit = Math.Clamp(limit, 1, 500);
        var leaseUntil = now + leaseDuration;
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var due = new List<(Guid AccountId, int AttemptCount)>();
        await using (var select = new NpgsqlCommand(
            """
            SELECT account_id, attempt_count
            FROM trust.age_assurance_cleanup_jobs
            WHERE next_attempt_at <= $1 AND (lease_until IS NULL OR lease_until <= $1)
            ORDER BY next_attempt_at, account_id
            LIMIT $2
            FOR UPDATE SKIP LOCKED;
            """,
            connection,
            transaction))
        {
            select.Parameters.AddWithValue(now);
            select.Parameters.AddWithValue(boundedLimit);
            await using var reader = await select.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                due.Add((reader.GetGuid(0), reader.GetInt32(1)));
            }
        }

        var claims = new List<PendingAccountDeletion>(due.Count);
        foreach (var item in due)
        {
            var leaseToken = Guid.NewGuid();
            await using var update = new NpgsqlCommand(
                "UPDATE trust.age_assurance_cleanup_jobs SET lease_token = $1, lease_until = $2 WHERE account_id = $3;",
                connection,
                transaction);
            update.Parameters.AddWithValue(leaseToken);
            update.Parameters.AddWithValue(leaseUntil);
            update.Parameters.AddWithValue(item.AccountId);
            await update.ExecuteNonQueryAsync(cancellationToken);
            claims.Add(new PendingAccountDeletion(item.AccountId, leaseToken, item.AttemptCount));
        }
        await transaction.CommitAsync(cancellationToken);
        return claims;
    }

    public async Task RecordAccountDeletionRetryAsync(
        PendingAccountDeletion claim, DateTimeOffset retryAt, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.age_assurance_cleanup_jobs
            SET attempt_count = attempt_count + 1,
                next_attempt_at = $1,
                lease_token = NULL,
                lease_until = NULL
            WHERE account_id = $2 AND lease_token = $3;
            """,
            connection);
        command.Parameters.AddWithValue(retryAt);
        command.Parameters.AddWithValue(claim.AccountId);
        command.Parameters.AddWithValue(claim.LeaseToken);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task CompleteAccountDeletionAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        foreach (var table in new[] { "age_assurance_app_transactions", "age_assurance_blocked_accounts", "age_assurance_cleanup_jobs", "age_assurance_privacy_holds" })
        {
            await using var command = new NpgsqlCommand($"DELETE FROM trust.{table} WHERE account_id = $1;", connection, transaction);
            command.Parameters.AddWithValue(accountId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
    }

    private static async Task EnqueueCleanupJobsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        IReadOnlyList<Guid> accountIds,
        CancellationToken cancellationToken)
    {
        if (accountIds.Count == 0) return;
        await using var command = new NpgsqlCommand(
            "INSERT INTO trust.age_assurance_cleanup_jobs (account_id) SELECT unnest($1::uuid[]) ON CONFLICT (account_id) DO NOTHING;",
            connection,
            transaction);
        command.Parameters.AddWithValue(accountIds.ToArray());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<(string Hash, string Environment)?> ReadNotificationKeyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid notificationId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT app_transaction_hash, environment FROM trust.age_assurance_notifications WHERE notification_id = $1;",
            connection,
            transaction);
        command.Parameters.AddWithValue(notificationId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? (reader.GetString(0), reader.GetString(1))
            : null;
    }

    private static async Task AcquireTransactionLockAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string hash,
        string environment,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT pg_advisory_xact_lock(hashtextextended($1, 0));",
            connection,
            transaction);
        command.Parameters.AddWithValue($"age-assurance:{hash}:{environment}");
        await command.ExecuteScalarAsync(cancellationToken);
    }

    private static async Task<bool> IsRevokedAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string hash,
        string environment,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM trust.age_assurance_revoked_app_transactions WHERE app_transaction_hash = $1 AND environment = $2);",
            connection,
            transaction);
        command.Parameters.AddWithValue(hash);
        command.Parameters.AddWithValue(environment);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private static async Task<IReadOnlyList<Guid>> ReadLinkedAccountIdsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string hash,
        string environment,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT account_id FROM trust.age_assurance_app_transactions WHERE app_transaction_hash = $1 AND environment = $2
            UNION
            SELECT account_id FROM trust.age_assurance_blocked_accounts WHERE app_transaction_hash = $1 AND environment = $2;
            """,
            connection,
            transaction);
        command.Parameters.AddWithValue(hash);
        command.Parameters.AddWithValue(environment);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var accountIds = new List<Guid>();
        while (await reader.ReadAsync(cancellationToken))
        {
            accountIds.Add(reader.GetGuid(0));
        }

        return accountIds;
    }
}
