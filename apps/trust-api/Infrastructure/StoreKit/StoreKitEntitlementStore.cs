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

        await using (var ownerLock = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtextextended($1, 0));", connection, db))
        {
            ownerLock.Parameters.AddWithValue(transaction.OriginalTransactionId);
            await ownerLock.ExecuteNonQueryAsync(cancellationToken);
        }

        var expected = await ReadTokenAsync(connection, db, accountId, cancellationToken);
        var approvedAlias = await ReadApprovedAliasAsync(connection, db, transaction.OriginalTransactionId,
            transaction.AppAccountToken, accountId, cancellationToken);
        if (expected is null || (expected != transaction.AppAccountToken && !approvedAlias))
        {
            await db.RollbackAsync(cancellationToken);
            return StoreKitApplyOutcome.NotApplied;
        }

        var owner = await ReadOwnerAsync(connection, db, transaction.OriginalTransactionId, cancellationToken);
        if (owner.HasValue
            && (owner.Value.AccountId != accountId || (owner.Value.Token != transaction.AppAccountToken && !approvedAlias)))
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
        await RefreshCircleAsync(connection, db, accountId, DateTimeOffset.UtcNow, cancellationToken);
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
        await using (var timeout = new NpgsqlCommand("SET LOCAL statement_timeout = '12s';", connection, db))
            await timeout.ExecuteNonQueryAsync(cancellationToken);
        await using (var ownerLock = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtextextended($1, 0));", connection, db))
        {
            ownerLock.Parameters.AddWithValue(transaction.OriginalTransactionId);
            await ownerLock.ExecuteNonQueryAsync(cancellationToken);
        }
        var owner = await ReadOwnerAsync(connection, db, transaction.OriginalTransactionId, cancellationToken);
        var approvedAlias = owner is { } currentOwner
            && await ReadApprovedAliasAsync(connection, db, transaction.OriginalTransactionId,
                transaction.AppAccountToken, currentOwner.AccountId, cancellationToken);
        if (owner is null || (owner.Value.Token != transaction.AppAccountToken && !approvedAlias))
        {
            await db.RollbackAsync(cancellationToken);
            return false;
        }

        await UpsertTransactionAsync(connection, db, owner.Value.AccountId, transaction, cancellationToken);
        await RefreshCircleAsync(connection, db, owner.Value.AccountId, DateTimeOffset.UtcNow, cancellationToken);
        await db.CommitAsync(cancellationToken);
        return true;
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
            WHERE EXCLUDED.signed_at > trust.storekit_transactions.signed_at
               OR (EXCLUDED.signed_at = trust.storekit_transactions.signed_at
                   AND (trust.storekit_transactions.revoked_at IS NULL OR EXCLUDED.revoked_at IS NOT NULL));
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
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            WITH latest AS (
                SELECT product_id, expires_at, revoked_at
                FROM trust.storekit_transactions
                WHERE account_id = $1
                ORDER BY signed_at DESC, (revoked_at IS NOT NULL) DESC, transaction_id DESC
                LIMIT 1
            )
            UPDATE trust.accounts
            SET has_circle = EXISTS (
                    SELECT 1 FROM latest
                    WHERE revoked_at IS NULL AND expires_at > $2
                ),
                circle_source = (SELECT product_id FROM latest)
            WHERE account_id = $1
              AND EXISTS (SELECT 1 FROM latest);
            """,
            connection,
            db);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(now);
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
            await RefreshCircleAsync(connection, db, accountId, DateTimeOffset.UtcNow, cancellationToken);
            await db.CommitAsync(cancellationToken);
        }
    }

    public async Task RefreshAccountCoverageAsync(Guid accountId, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        await RefreshCircleAsync(connection, db, accountId, now, cancellationToken);
        await db.CommitAsync(cancellationToken);
    }

    public async Task<DateTimeOffset?> GetActiveEntitlementExpiryAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("SELECT expires_at,revoked_at FROM trust.storekit_transactions WHERE account_id=$1 ORDER BY signed_at DESC, (revoked_at IS NOT NULL) DESC, transaction_id DESC LIMIT 1;", connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        if (!reader.IsDBNull(1)) return null;
        return reader.GetFieldValue<DateTimeOffset>(0);
    }

    public async Task<Guid> CreateRecoveryRequestAsync(Guid targetAccountId, VerifiedStoreKitTransaction transaction,
        string? reason, DateTimeOffset createdAt, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        await using (var account = new NpgsqlCommand("SELECT account_id FROM trust.accounts WHERE account_id=$1 FOR UPDATE;", connection, db))
        {
            account.Parameters.AddWithValue(targetAccountId);
            if (await account.ExecuteScalarAsync(cancellationToken) is null) throw TrustException.Unauthorized();
        }
        Guid? existingId = null;
        var environmentMissing = false;
        await using (var existing = new NpgsqlCommand("SELECT recovery_request_id,environment FROM trust.storekit_recovery_requests WHERE target_account_id=$1 AND original_transaction_id=$2 AND old_app_account_token=$3 AND status IN ('pending','blocked') FOR UPDATE;", connection, db))
        {
            existing.Parameters.AddWithValue(targetAccountId); existing.Parameters.AddWithValue(transaction.OriginalTransactionId); existing.Parameters.AddWithValue(transaction.AppAccountToken);
            await using var reader = await existing.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                existingId = reader.GetGuid(0);
                environmentMissing = reader.IsDBNull(1);
            }
        }
        if (existingId is { } priorId)
        {
            if (environmentMissing)
            {
                await using var updateLegacy = new NpgsqlCommand("UPDATE trust.storekit_recovery_requests SET transaction_id=$2,product_id=$3,environment=$4,expires_at=$5,revoked_at=$6,status='pending',blocked_reason=NULL,updated_at=$7 WHERE recovery_request_id=$1;", connection, db);
                updateLegacy.Parameters.AddWithValue(priorId); updateLegacy.Parameters.AddWithValue(transaction.TransactionId);
                updateLegacy.Parameters.AddWithValue(transaction.ProductId); updateLegacy.Parameters.AddWithValue(transaction.Environment);
                updateLegacy.Parameters.AddWithValue(transaction.ExpiresAt); updateLegacy.Parameters.AddWithValue((object?)transaction.RevokedAt ?? DBNull.Value);
                updateLegacy.Parameters.AddWithValue(createdAt); await updateLegacy.ExecuteNonQueryAsync(cancellationToken);
            }
                await db.CommitAsync(cancellationToken);
                return priorId;
        }
        if (await ReadApprovedAliasAsync(connection, db, transaction.OriginalTransactionId, transaction.AppAccountToken, targetAccountId, cancellationToken))
            throw new TrustException("recovery_already_approved", "This purchase is already linked to this Trust account.");

        var requestId = Guid.NewGuid();
        await using (var insert = new NpgsqlCommand("INSERT INTO trust.storekit_recovery_requests (recovery_request_id,target_account_id,original_transaction_id,old_app_account_token,transaction_id,product_id,environment,expires_at,revoked_at,reason,status,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'pending',$11,$11);", connection, db))
        {
            insert.Parameters.AddWithValue(requestId); insert.Parameters.AddWithValue(targetAccountId);
            insert.Parameters.AddWithValue(transaction.OriginalTransactionId); insert.Parameters.AddWithValue(transaction.AppAccountToken);
            insert.Parameters.AddWithValue(transaction.TransactionId); insert.Parameters.AddWithValue(transaction.ProductId);
            insert.Parameters.AddWithValue(transaction.Environment); insert.Parameters.AddWithValue(transaction.ExpiresAt);
            insert.Parameters.AddWithValue((object?)transaction.RevokedAt ?? DBNull.Value);
            insert.Parameters.AddWithValue((object?)reason ?? DBNull.Value); insert.Parameters.AddWithValue(createdAt);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        await db.CommitAsync(cancellationToken);
        return requestId;
    }

    public async Task<Guid> CreatePhoneOwnershipRecoveryRequestAsync(Guid targetAccountId, string? reason,
        DateTimeOffset createdAt, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        await using (var account = new NpgsqlCommand("SELECT account_id FROM trust.accounts WHERE account_id=$1 FOR UPDATE;", connection, db))
        {
            account.Parameters.AddWithValue(targetAccountId);
            if (await account.ExecuteScalarAsync(cancellationToken) is null) throw TrustException.Unauthorized();
        }
        await using (var existing = new NpgsqlCommand("SELECT recovery_request_id FROM trust.phone_support_recovery_requests WHERE target_account_id=$1 AND status IN ('pending','blocked') FOR UPDATE;", connection, db))
        {
            existing.Parameters.AddWithValue(targetAccountId);
            if (await existing.ExecuteScalarAsync(cancellationToken) is Guid existingId)
            {
                await db.CommitAsync(cancellationToken);
                return existingId;
            }
        }
        var requestId = Guid.NewGuid();
        await using (var insert = new NpgsqlCommand("INSERT INTO trust.phone_support_recovery_requests (recovery_request_id,target_account_id,reason,status,created_at,updated_at) VALUES ($1,$2,$3,'pending',$4,$4);", connection, db))
        {
            insert.Parameters.AddWithValue(requestId); insert.Parameters.AddWithValue(targetAccountId);
            insert.Parameters.AddWithValue((object?)reason ?? DBNull.Value); insert.Parameters.AddWithValue(createdAt);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        await db.CommitAsync(cancellationToken);
        return requestId;
    }

    public async Task<bool> HasApprovedAliasAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("SELECT EXISTS (SELECT 1 FROM trust.storekit_approved_subscription_aliases WHERE original_transaction_id=$1 AND old_app_account_token=$2 AND target_account_id=$3);", connection);
        command.Parameters.AddWithValue(originalTransactionId); command.Parameters.AddWithValue(oldAppAccountToken); command.Parameters.AddWithValue(targetAccountId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    public async Task BlockRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId,
        string reason, DateTimeOffset updatedAt, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("UPDATE trust.storekit_recovery_requests SET status='blocked',blocked_reason=$4,updated_at=$5 WHERE original_transaction_id=$1 AND old_app_account_token=$2 AND target_account_id=$3 AND status IN ('pending','blocked');", connection);
        command.Parameters.AddWithValue(originalTransactionId); command.Parameters.AddWithValue(oldAppAccountToken);
        command.Parameters.AddWithValue(targetAccountId); command.Parameters.AddWithValue(reason[..Math.Min(reason.Length, 80)]);
        command.Parameters.AddWithValue(updatedAt); await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<StoreKitRecoveryRequest?> FindRecoveryRequestAsync(string originalTransactionId,
        Guid oldAppAccountToken, Guid targetAccountId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("SELECT recovery_request_id,target_account_id,original_transaction_id,old_app_account_token,transaction_id,product_id,environment,expires_at,revoked_at,status,created_at,blocked_reason FROM trust.storekit_recovery_requests WHERE original_transaction_id=$1 AND old_app_account_token=$2 AND target_account_id=$3 AND status IN ('pending','blocked');", connection);
        command.Parameters.AddWithValue(originalTransactionId); command.Parameters.AddWithValue(oldAppAccountToken); command.Parameters.AddWithValue(targetAccountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new StoreKitRecoveryRequest(reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2), reader.GetGuid(3),
            reader.GetString(4), reader.GetString(5), reader.IsDBNull(6) ? null : reader.GetString(6), reader.GetFieldValue<DateTimeOffset>(7),
            reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8), reader.GetString(9),
            reader.GetFieldValue<DateTimeOffset>(10), reader.IsDBNull(11) ? null : reader.GetString(11));
    }

    public async Task<Guid> ApproveRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId,
        Func<StoreKitRecoveryRequest, CancellationToken, Task<VerifiedStoreKitTransaction>> getAuthoritativeCurrentTransaction,
        DateTimeOffset approvedAt, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var db = await connection.BeginTransactionAsync(cancellationToken);
        await using (var timeout = new NpgsqlCommand("SET LOCAL statement_timeout = '12s';", connection, db))
            await timeout.ExecuteNonQueryAsync(cancellationToken);
        await using (var ownerLock = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtextextended($1, 0));", connection, db))
        {
            ownerLock.Parameters.AddWithValue(originalTransactionId);
            await ownerLock.ExecuteNonQueryAsync(cancellationToken);
        }
        StoreKitRecoveryRequest recoveryRequest;
        await using (var request = new NpgsqlCommand("SELECT recovery_request_id,product_id,environment FROM trust.storekit_recovery_requests WHERE target_account_id=$1 AND original_transaction_id=$2 AND old_app_account_token=$3 AND status IN ('pending','blocked') FOR UPDATE;", connection, db))
        {
            request.Parameters.AddWithValue(targetAccountId); request.Parameters.AddWithValue(originalTransactionId); request.Parameters.AddWithValue(oldAppAccountToken);
            await using var reader = await request.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) throw new TrustException("recovery_request_not_found", "No pending Support request matches this exact purchase and account.");
            recoveryRequest = new(reader.GetGuid(0), targetAccountId, originalTransactionId, oldAppAccountToken,
                string.Empty, reader.GetString(1), reader.IsDBNull(2) ? null : reader.GetString(2), DateTimeOffset.MinValue, null, "pending", approvedAt);
        }
        await using (var accountLock = new NpgsqlCommand("SELECT account_id FROM trust.accounts WHERE account_id=$1 FOR UPDATE;", connection, db))
        {
            accountLock.Parameters.AddWithValue(targetAccountId);
            if (await accountLock.ExecuteScalarAsync(cancellationToken) is null) throw TrustException.Unauthorized();
        }
        await using (var target = new NpgsqlCommand("SELECT EXISTS (SELECT 1 FROM trust.age_assurance_blocked_accounts WHERE account_id=$1), EXISTS (SELECT 1 FROM trust.age_assurance_privacy_holds WHERE account_id=$1);", connection, db))
        {
            target.Parameters.AddWithValue(targetAccountId);
            await using var reader = await target.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken) && (reader.GetBoolean(0) || reader.GetBoolean(1)))
                throw new TrustException("recovery_target_restricted", "A restricted Trust account cannot receive purchase recovery.");
        }
        VerifiedStoreKitTransaction authoritativeCurrentTransaction;
        try
        {
            authoritativeCurrentTransaction = await getAuthoritativeCurrentTransaction(recoveryRequest, cancellationToken);
        }
        catch (TrustException exception) when (exception.Code is "recovery_authority_unavailable" or "recovery_purchase_inactive" or "recovery_purchase_mismatch")
        {
            var status = exception.Code == "recovery_authority_unavailable" ? "blocked" : "rejected";
            var reason = exception.Code == "recovery_authority_unavailable" ? "authority_unavailable" : "purchase_inactive";
            await using var updateCase = new NpgsqlCommand("UPDATE trust.storekit_recovery_requests SET status=$2,blocked_reason=$3,updated_at=$4 WHERE recovery_request_id=$1;", connection, db);
            updateCase.Parameters.AddWithValue(recoveryRequest.Id); updateCase.Parameters.AddWithValue(status);
            updateCase.Parameters.AddWithValue(reason); updateCase.Parameters.AddWithValue(approvedAt);
            await updateCase.ExecuteNonQueryAsync(cancellationToken);
            await db.CommitAsync(cancellationToken);
            throw;
        }
        if (authoritativeCurrentTransaction.OriginalTransactionId != originalTransactionId
            || authoritativeCurrentTransaction.AppAccountToken != oldAppAccountToken
            || authoritativeCurrentTransaction.ProductId != recoveryRequest.ProductId
            || authoritativeCurrentTransaction.Environment != recoveryRequest.Environment
            || authoritativeCurrentTransaction.RevokedAt is not null
            || authoritativeCurrentTransaction.ExpiresAt <= approvedAt)
        {
            await using var reject = new NpgsqlCommand("UPDATE trust.storekit_recovery_requests SET status='rejected',blocked_reason='purchase_mismatch',updated_at=$2 WHERE recovery_request_id=$1;", connection, db);
            reject.Parameters.AddWithValue(recoveryRequest.Id); reject.Parameters.AddWithValue(approvedAt);
            await reject.ExecuteNonQueryAsync(cancellationToken);
            await db.CommitAsync(cancellationToken);
            throw new TrustException("recovery_purchase_mismatch", "Apple's current purchase does not match this Support request.");
        }
        var owner = await ReadOwnerAsync(connection, db, originalTransactionId, cancellationToken);
        if (owner is { } currentOwner && currentOwner.AccountId != targetAccountId)
        {
            await using var reject = new NpgsqlCommand("UPDATE trust.storekit_recovery_requests SET status='rejected',blocked_reason='active_owner_conflict',updated_at=$2 WHERE recovery_request_id=$1;", connection, db);
            reject.Parameters.AddWithValue(recoveryRequest.Id); reject.Parameters.AddWithValue(approvedAt);
            await reject.ExecuteNonQueryAsync(cancellationToken);
            await db.CommitAsync(cancellationToken);
            throw new TrustException("recovery_owner_conflict", "This purchase is still linked to another active Trust account.");
        }
        await using (var alias = new NpgsqlCommand("INSERT INTO trust.storekit_approved_subscription_aliases (original_transaction_id,old_app_account_token,target_account_id,recovery_request_id,approved_at) VALUES ($1,$2,$3,$4,$5);", connection, db))
        {
            alias.Parameters.AddWithValue(originalTransactionId); alias.Parameters.AddWithValue(oldAppAccountToken);
            alias.Parameters.AddWithValue(targetAccountId); alias.Parameters.AddWithValue(recoveryRequest.Id); alias.Parameters.AddWithValue(approvedAt);
            await alias.ExecuteNonQueryAsync(cancellationToken);
        }
        if (owner is null)
        {
            await using var insertOwner = new NpgsqlCommand("INSERT INTO trust.storekit_subscription_owners (original_transaction_id,account_id,app_account_token,created_at) VALUES ($1,$2,$3,$4);", connection, db);
            insertOwner.Parameters.AddWithValue(originalTransactionId); insertOwner.Parameters.AddWithValue(targetAccountId);
            insertOwner.Parameters.AddWithValue(oldAppAccountToken); insertOwner.Parameters.AddWithValue(approvedAt);
            await insertOwner.ExecuteNonQueryAsync(cancellationToken);
        }
        await using (var update = new NpgsqlCommand("UPDATE trust.storekit_recovery_requests SET status='approved',blocked_reason=NULL,updated_at=$2 WHERE recovery_request_id=$1;", connection, db))
        {
            update.Parameters.AddWithValue(recoveryRequest.Id); update.Parameters.AddWithValue(approvedAt); await update.ExecuteNonQueryAsync(cancellationToken);
        }
        await db.CommitAsync(cancellationToken);
        return recoveryRequest.Id;
    }

    private static async Task<bool> ReadApprovedAliasAsync(NpgsqlConnection connection, NpgsqlTransaction db,
        string originalTransactionId, Guid oldToken, Guid targetAccountId, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand("SELECT EXISTS (SELECT 1 FROM trust.storekit_approved_subscription_aliases WHERE original_transaction_id=$1 AND old_app_account_token=$2 AND target_account_id=$3);", connection, db);
        command.Parameters.AddWithValue(originalTransactionId); command.Parameters.AddWithValue(oldToken); command.Parameters.AddWithValue(targetAccountId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }
}

public sealed class MemoryStoreKitEntitlementStore(ITrustStore accounts) : IStoreKitEntitlementStore
{
    private readonly Dictionary<Guid, Guid> _tokens = [];
    private readonly Dictionary<string, Guid> _owners = [];
    private readonly Dictionary<string, Guid> _ownerTokens = [];
    private readonly Dictionary<string, VerifiedStoreKitTransaction> _transactions = [];
    private readonly Dictionary<Guid, StoreKitRecoveryRequest> _recoveryRequests = [];
    private readonly Dictionary<Guid, PhoneOwnershipRecoveryRequest> _phoneRecoveryRequests = [];
    private readonly Dictionary<(string OriginalId, Guid OldToken), Guid> _approvedAliases = [];
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
            var approvedAlias = _approvedAliases.TryGetValue((transaction.OriginalTransactionId, transaction.AppAccountToken), out var aliasTarget)
                && aliasTarget == accountId;
            if (!_tokens.TryGetValue(accountId, out token) || (token != transaction.AppAccountToken && !approvedAlias))
            {
                return StoreKitApplyOutcome.NotApplied;
            }

            if (_owners.TryGetValue(transaction.OriginalTransactionId, out var owner)
                && (owner != accountId || (_ownerTokens[transaction.OriginalTransactionId] != transaction.AppAccountToken && !approvedAlias)))
            {
                return StoreKitApplyOutcome.LinkedToAnotherAccount;
            }

            _owners[transaction.OriginalTransactionId] = accountId;
            _ownerTokens[transaction.OriginalTransactionId] = transaction.AppAccountToken;
            if (!_transactions.TryGetValue(transaction.TransactionId, out var existing)
                || transaction.SignedAt > existing.SignedAt
                || (transaction.SignedAt == existing.SignedAt && (existing.RevokedAt is null || transaction.RevokedAt is not null)))
            {
                _transactions[transaction.TransactionId] = transaction;
            }
        }

        await RefreshAsync(accountId, DateTimeOffset.UtcNow, cancellationToken);
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
                || (_ownerTokens[transaction.OriginalTransactionId] != transaction.AppAccountToken
                    && (!_approvedAliases.TryGetValue((transaction.OriginalTransactionId, transaction.AppAccountToken), out var aliasTarget)
                        || aliasTarget != accountId)))
            {
                return false;
            }

            if (!_transactions.TryGetValue(transaction.TransactionId, out var existing)
                || transaction.SignedAt > existing.SignedAt
                || (transaction.SignedAt == existing.SignedAt && (existing.RevokedAt is null || transaction.RevokedAt is not null)))
            {
                _transactions[transaction.TransactionId] = transaction;
            }
        }

        await RefreshAsync(accountId, DateTimeOffset.UtcNow, cancellationToken);
        return true;
    }

    private async Task RefreshAsync(Guid accountId, DateTimeOffset now, CancellationToken cancellationToken)
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
                .ThenByDescending(item => item.RevokedAt is not null)
                .ThenByDescending(item => item.TransactionId, StringComparer.Ordinal)
                .FirstOrDefault();
        }

        if (latest is null)
        {
            return;
        }

        var active = latest.RevokedAt is null && latest.ExpiresAt > now;
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
            await RefreshAsync(accountId, DateTimeOffset.UtcNow, cancellationToken);
        }
    }

    public Task RefreshAccountCoverageAsync(Guid accountId, DateTimeOffset now, CancellationToken cancellationToken) =>
        RefreshAsync(accountId, now, cancellationToken);

    public Task<DateTimeOffset?> GetActiveEntitlementExpiryAsync(Guid accountId, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var latest = _transactions.Values.Where(transaction => _owners.GetValueOrDefault(transaction.OriginalTransactionId) == accountId)
                .OrderByDescending(transaction => transaction.SignedAt)
                .ThenByDescending(transaction => transaction.RevokedAt is not null)
                .ThenByDescending(transaction => transaction.TransactionId, StringComparer.Ordinal).FirstOrDefault();
            return Task.FromResult<DateTimeOffset?>(latest is not null && latest.RevokedAt is null
                ? latest.ExpiresAt : null);
        }
    }

    public async Task<Guid> CreateRecoveryRequestAsync(Guid targetAccountId, VerifiedStoreKitTransaction transaction,
        string? reason, DateTimeOffset createdAt, CancellationToken cancellationToken)
    {
        if (await accounts.FindAccountAsync(targetAccountId, cancellationToken) is null) throw TrustException.Unauthorized();
        lock (_gate)
        {
            var existing = _recoveryRequests.Values.FirstOrDefault(request => request.TargetAccountId == targetAccountId
                && request.OriginalTransactionId == transaction.OriginalTransactionId
                && request.OldAppAccountToken == transaction.AppAccountToken && (request.Status is "pending" or "blocked"));
            if (existing is not null) return existing.Id;
            if (_approvedAliases.ContainsKey((transaction.OriginalTransactionId, transaction.AppAccountToken)))
                throw new TrustException("recovery_already_approved", "This purchase is already linked to a Trust account.");
            var requestId = Guid.NewGuid();
            _recoveryRequests[requestId] = new(requestId, targetAccountId, transaction.OriginalTransactionId,
                transaction.AppAccountToken, transaction.TransactionId, transaction.ProductId, transaction.Environment, transaction.ExpiresAt,
                transaction.RevokedAt, "pending", createdAt);
            return requestId;
        }
    }

    public async Task<Guid> CreatePhoneOwnershipRecoveryRequestAsync(Guid targetAccountId, string? reason,
        DateTimeOffset createdAt, CancellationToken cancellationToken)
    {
        if (await accounts.FindAccountAsync(targetAccountId, cancellationToken) is null) throw TrustException.Unauthorized();
        lock (_gate)
        {
            var existing = _phoneRecoveryRequests.Values.FirstOrDefault(request => request.TargetAccountId == targetAccountId
                && (request.Status is "pending" or "blocked"));
            if (existing is not null) return existing.Id;
            var requestId = Guid.NewGuid();
            _phoneRecoveryRequests[requestId] = new(requestId, targetAccountId, "pending", createdAt, reason);
            return requestId;
        }
    }

    public Task<bool> HasApprovedAliasAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId, CancellationToken cancellationToken)
    {
        lock (_gate) return Task.FromResult(_approvedAliases.TryGetValue((originalTransactionId, oldAppAccountToken), out var target) && target == targetAccountId);
    }

    public Task<StoreKitRecoveryRequest?> FindRecoveryRequestAsync(string originalTransactionId,
        Guid oldAppAccountToken, Guid targetAccountId, CancellationToken cancellationToken)
    {
        lock (_gate) return Task.FromResult(_recoveryRequests.Values.FirstOrDefault(item => item.OriginalTransactionId == originalTransactionId
            && item.OldAppAccountToken == oldAppAccountToken && item.TargetAccountId == targetAccountId
            && (item.Status is "pending" or "blocked")));
    }

    public Task BlockRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken, Guid targetAccountId,
        string reason, DateTimeOffset updatedAt, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var request = _recoveryRequests.Values.FirstOrDefault(item => item.TargetAccountId == targetAccountId
                && item.OriginalTransactionId == originalTransactionId && item.OldAppAccountToken == oldAppAccountToken
                && (item.Status is "pending" or "blocked")) ?? throw new TrustException("recovery_request_not_found", "No pending Support request matches this exact purchase and account.");
            _recoveryRequests[request.Id] = request with { Status = "blocked", BlockedReason = reason };
        }
        return Task.CompletedTask;
    }

    public async Task<Guid> ApproveRecoveryAsync(string originalTransactionId, Guid oldAppAccountToken,
        Guid targetAccountId,
        Func<StoreKitRecoveryRequest, CancellationToken, Task<VerifiedStoreKitTransaction>> getAuthoritativeCurrentTransaction,
        DateTimeOffset approvedAt, CancellationToken cancellationToken)
    {
        StoreKitRecoveryRequest request;
        lock (_gate)
        {
            request = _recoveryRequests.Values.FirstOrDefault(item => item.TargetAccountId == targetAccountId
                && item.OriginalTransactionId == originalTransactionId && item.OldAppAccountToken == oldAppAccountToken
                && (item.Status is "pending" or "blocked")) ?? throw new TrustException("recovery_request_not_found", "No pending Support request matches this exact purchase and account.");
        }
        var authoritativeCurrentTransaction = await getAuthoritativeCurrentTransaction(request, cancellationToken);
        if (authoritativeCurrentTransaction.OriginalTransactionId != originalTransactionId
            || authoritativeCurrentTransaction.AppAccountToken != oldAppAccountToken
            || authoritativeCurrentTransaction.ProductId != request.ProductId
            || authoritativeCurrentTransaction.Environment != request.Environment
            || authoritativeCurrentTransaction.RevokedAt is not null
            || authoritativeCurrentTransaction.ExpiresAt <= approvedAt)
            throw new TrustException("recovery_purchase_inactive", "Apple did not confirm an active subscription for this exact purchase.");
        lock (_gate)
        {
            request = _recoveryRequests.GetValueOrDefault(request.Id)
                ?? throw new TrustException("recovery_request_not_found", "No pending Support request matches this exact purchase and account.");
            if (_owners.TryGetValue(originalTransactionId, out var activeOwner) && activeOwner != targetAccountId)
                throw new TrustException("recovery_owner_conflict", "This purchase is still linked to another active Trust account.");
            var existingAlias = _approvedAliases.Where(pair => pair.Key.OriginalId == originalTransactionId).Select(pair => (Guid?)pair.Value).FirstOrDefault();
            if (existingAlias is { } existingTarget && existingTarget != targetAccountId)
                throw new TrustException("recovery_owner_conflict", "This purchase already has an approved recovery for another Trust account.");
            _approvedAliases[(originalTransactionId, oldAppAccountToken)] = targetAccountId;
            if (!_owners.ContainsKey(originalTransactionId))
            {
                _owners[originalTransactionId] = targetAccountId;
                _ownerTokens[originalTransactionId] = oldAppAccountToken;
            }
            _recoveryRequests[request.Id] = request with { Status = "approved", BlockedReason = null };
            return request.Id;
        }
    }
}
