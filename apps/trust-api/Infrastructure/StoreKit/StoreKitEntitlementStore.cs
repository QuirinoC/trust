using Npgsql;
using TrustApi.Configuration;
using TrustApi.Domain;

namespace TrustApi.Infrastructure.StoreKit;

public sealed class PostgresStoreKitEntitlementStore(string connectionString) : IStoreKitEntitlementStore
{
    private readonly string _connectionString = PostgresConnectionString.Normalize(connectionString);

    public async Task<Guid> GetOrCreateAccountTokenAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.storekit_account_tokens (account_id, app_account_token, created_at)
            VALUES ($1, $2, now())
            ON CONFLICT (account_id) DO UPDATE SET account_id = EXCLUDED.account_id
            RETURNING app_account_token;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(Guid.NewGuid());
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is Guid token ? token : throw new InvalidOperationException("Could not issue an App Account Token.");
    }

    public async Task<StoreKitApplyOutcome> ApplyAsync(
        Guid accountId,
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);

        var expected = await ReadTokenAsync(connection, db, accountId, cancellationToken);
        if (expected is null || expected != transaction.AppAccountToken)
        {
            await db.RollbackAsync(cancellationToken);
            return StoreKitApplyOutcome.NotApplied;
        }

        var owner = await ReadOwnerAsync(connection, db, transaction.OriginalTransactionId, cancellationToken);
        if (owner.HasValue
            && (owner.Value.AccountId != accountId || owner.Value.Token != transaction.AppAccountToken))
        {
            await db.RollbackAsync(cancellationToken);
            return StoreKitApplyOutcome.LinkedToAnotherAccount;
        }

        if (owner is null)
        {
            await using var insertOwner = new NpgsqlCommand(
                """
                INSERT INTO trust.storekit_subscription_owners (
                    original_transaction_id, account_id, app_account_token, created_at)
                VALUES ($1, $2, $3, now());
                """,
                connection,
                db);
            insertOwner.Parameters.AddWithValue(transaction.OriginalTransactionId);
            insertOwner.Parameters.AddWithValue(accountId);
            insertOwner.Parameters.AddWithValue(transaction.AppAccountToken);
            await insertOwner.ExecuteNonQueryAsync(cancellationToken);
        }

        await UpsertTransactionAsync(connection, db, accountId, transaction, cancellationToken);
        await RefreshCircleAsync(connection, db, accountId, cancellationToken);
        await db.CommitAsync(cancellationToken);
        return StoreKitApplyOutcome.Applied;
    }

    public async Task<bool> ApplyNotificationAsync(
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        var owner = await ReadOwnerAsync(connection, db, transaction.OriginalTransactionId, cancellationToken);
        if (owner is null || owner.Value.Token != transaction.AppAccountToken)
        {
            await db.RollbackAsync(cancellationToken);
            return false;
        }

        await UpsertTransactionAsync(connection, db, owner.Value.AccountId, transaction, cancellationToken);
        await RefreshCircleAsync(connection, db, owner.Value.AccountId, cancellationToken);
        await db.CommitAsync(cancellationToken);
        return true;
    }

    public async Task RefreshExpiredCoveragesAsync(CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var list = new NpgsqlCommand(
            "SELECT DISTINCT account_id FROM trust.storekit_transactions;",
            connection);
        await using var reader = await list.ExecuteReaderAsync(cancellationToken);
        var accountIds = new List<Guid>();
        while (await reader.ReadAsync(cancellationToken))
        {
            accountIds.Add(reader.GetGuid(0));
        }

        await reader.CloseAsync();
        foreach (var accountId in accountIds)
        {
            await using var db = await connection.BeginTransactionAsync(cancellationToken);
            await RefreshCircleAsync(connection, db, accountId, cancellationToken);
            await db.CommitAsync(cancellationToken);
        }
    }

    public async Task RefreshAccountCoverageAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        await RefreshCircleAsync(connection, db, accountId, cancellationToken);
        await db.CommitAsync(cancellationToken);
    }

    private static async Task<Guid?> ReadTokenAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction db,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT app_account_token FROM trust.storekit_account_tokens WHERE account_id = $1;",
            connection,
            db);
        command.Parameters.AddWithValue(accountId);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is Guid token ? token : null;
    }

    private static async Task<(Guid AccountId, Guid Token)?> ReadOwnerAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction db,
        string originalTransactionId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT account_id, app_account_token
            FROM trust.storekit_subscription_owners
            WHERE original_transaction_id = $1;
            """,
            connection,
            db);
        command.Parameters.AddWithValue(originalTransactionId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return (reader.GetGuid(0), reader.GetGuid(1));
    }

    private static async Task UpsertTransactionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction db,
        Guid accountId,
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.storekit_transactions (
                transaction_id, original_transaction_id, account_id, product_id, environment,
                signed_at, expires_at, revoked_at, received_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
            ON CONFLICT (transaction_id) DO UPDATE SET
                product_id = EXCLUDED.product_id,
                environment = EXCLUDED.environment,
                signed_at = EXCLUDED.signed_at,
                expires_at = EXCLUDED.expires_at,
                revoked_at = EXCLUDED.revoked_at,
                received_at = EXCLUDED.received_at
            WHERE EXCLUDED.signed_at >= trust.storekit_transactions.signed_at;
            """,
            connection,
            db);
        command.Parameters.AddWithValue(transaction.TransactionId);
        command.Parameters.AddWithValue(transaction.OriginalTransactionId);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(transaction.ProductId);
        command.Parameters.AddWithValue(transaction.Environment);
        command.Parameters.AddWithValue(transaction.SignedAt);
        command.Parameters.AddWithValue(transaction.ExpiresAt);
        command.Parameters.AddWithValue((object?)transaction.RevokedAt ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task RefreshCircleAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction db,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            WITH latest AS (
                SELECT product_id, expires_at, revoked_at
                FROM trust.storekit_transactions
                WHERE account_id = $1
                ORDER BY signed_at DESC
                LIMIT 1
            )
            UPDATE trust.accounts
            SET has_circle = EXISTS (
                    SELECT 1 FROM latest
                    WHERE revoked_at IS NULL AND expires_at > now()
                ),
                circle_source = (SELECT product_id FROM latest)
            WHERE account_id = $1
              AND EXISTS (SELECT 1 FROM latest);
            """,
            connection,
            db);
        command.Parameters.AddWithValue(accountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task RefreshExpiredCoveragesAsync(CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var list = new NpgsqlCommand(
            "SELECT DISTINCT account_id FROM trust.storekit_transactions;",
            connection);
        await using var reader = await list.ExecuteReaderAsync(cancellationToken);
        var accountIds = new List<Guid>();
        while (await reader.ReadAsync(cancellationToken))
        {
            accountIds.Add(reader.GetGuid(0));
        }

        await reader.CloseAsync();
        foreach (var accountId in accountIds)
        {
            await using var db = await connection.BeginTransactionAsync(cancellationToken);
            await RefreshCircleAsync(connection, db, accountId, cancellationToken);
            await db.CommitAsync(cancellationToken);
        }
    }

    public async Task RefreshAccountCoverageAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        await RefreshCircleAsync(connection, db, accountId, cancellationToken);
        await db.CommitAsync(cancellationToken);
    }
}

public sealed class MemoryStoreKitEntitlementStore(ITrustStore accounts) : IStoreKitEntitlementStore
{
    private readonly Dictionary<Guid, Guid> _tokens = [];
    private readonly Dictionary<string, Guid> _owners = [];
    private readonly Dictionary<string, Guid> _ownerTokens = [];
    private readonly Dictionary<string, VerifiedStoreKitTransaction> _transactions = [];
    private readonly object _gate = new();

    public Task<Guid> GetOrCreateAccountTokenAsync(Guid accountId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            if (!_tokens.TryGetValue(accountId, out var token))
            {
                token = Guid.NewGuid();
                _tokens[accountId] = token;
            }

            return Task.FromResult(token);
        }
    }

    public async Task<StoreKitApplyOutcome> ApplyAsync(
        Guid accountId,
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken)
    {
        Guid token;
        lock (_gate)
        {
            if (!_tokens.TryGetValue(accountId, out token) || token != transaction.AppAccountToken)
            {
                return StoreKitApplyOutcome.NotApplied;
            }

            if (_owners.TryGetValue(transaction.OriginalTransactionId, out var owner)
                && (owner != accountId || _ownerTokens[transaction.OriginalTransactionId] != transaction.AppAccountToken))
            {
                return StoreKitApplyOutcome.LinkedToAnotherAccount;
            }

            _owners[transaction.OriginalTransactionId] = accountId;
            _ownerTokens[transaction.OriginalTransactionId] = transaction.AppAccountToken;
            if (!_transactions.TryGetValue(transaction.TransactionId, out var existing)
                || transaction.SignedAt >= existing.SignedAt)
            {
                _transactions[transaction.TransactionId] = transaction;
            }
        }

        await RefreshAsync(accountId, cancellationToken);
        return StoreKitApplyOutcome.Applied;
    }

    public async Task<bool> ApplyNotificationAsync(
        VerifiedStoreKitTransaction transaction,
        CancellationToken cancellationToken)
    {
        Guid accountId;
        lock (_gate)
        {
            if (!_owners.TryGetValue(transaction.OriginalTransactionId, out accountId)
                || _ownerTokens[transaction.OriginalTransactionId] != transaction.AppAccountToken)
            {
                return false;
            }

            if (!_transactions.TryGetValue(transaction.TransactionId, out var existing)
                || transaction.SignedAt >= existing.SignedAt)
            {
                _transactions[transaction.TransactionId] = transaction;
            }
        }

        await RefreshAsync(accountId, cancellationToken);
        return true;
    }

    public async Task RefreshExpiredCoveragesAsync(CancellationToken cancellationToken)
    {
        HashSet<Guid> accountIds;
        lock (_gate)
        {
            accountIds = _owners.Values.ToHashSet();
        }

        foreach (var accountId in accountIds)
        {
            await RefreshAsync(accountId, cancellationToken);
        }
    }

    public Task RefreshAccountCoverageAsync(Guid accountId, CancellationToken cancellationToken) =>
        RefreshAsync(accountId, cancellationToken);

    private async Task RefreshAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var account = await accounts.FindAccountAsync(accountId, cancellationToken);
        if (account is null)
        {
            return;
        }

        VerifiedStoreKitTransaction? latest;
        lock (_gate)
        {
            latest = _transactions.Values
                .Where(item => _owners.TryGetValue(item.OriginalTransactionId, out var owner) && owner == accountId)
                .OrderByDescending(item => item.SignedAt)
                .FirstOrDefault();
        }

        // Review unlock / test grants with no StoreKit row stay untouched.
        if (latest is null)
        {
            return;
        }

        var active = latest.RevokedAt is null && latest.ExpiresAt > DateTimeOffset.UtcNow;
        await accounts.UpdateAccountAsync(
            account with
            {
                HasCircle = active,
                CircleSource = latest.ProductId
            },
            cancellationToken);
    }

    public async Task RefreshExpiredCoveragesAsync(CancellationToken cancellationToken)
    {
        HashSet<Guid> accountIds;
        lock (_gate)
        {
            accountIds = _owners.Values.ToHashSet();
        }

        foreach (var accountId in accountIds)
        {
            await RefreshAsync(accountId, cancellationToken);
        }
    }

    public Task RefreshAccountCoverageAsync(Guid accountId, CancellationToken cancellationToken) =>
        RefreshAsync(accountId, cancellationToken);
}
