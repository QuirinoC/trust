using Npgsql;
using TrustApi.Configuration;
using TrustApi.Domain;

namespace TrustApi.Infrastructure.Postgres;

public sealed class PostgresTrustStore(string connectionString) : ITrustStore
{
    private const string AccountColumns =
        "account_id, provider, provider_subject, display_name, has_circle, circle_source, created_at, phone_e164, phone_verified_at, handle";

    private readonly string _connectionString = PostgresConnectionString.Normalize(connectionString);

    public Task<Account?> FindAccountAsync(Guid id, CancellationToken cancellationToken) =>
        QueryAccountAsync(
            $"SELECT {AccountColumns} FROM trust.accounts WHERE account_id = $1",
            cmd => cmd.Parameters.AddWithValue(id),
            cancellationToken);

    public Task<Account?> FindByProviderAsync(
        string provider,
        string subject,
        CancellationToken cancellationToken) =>
        QueryAccountAsync(
            $"SELECT {AccountColumns} FROM trust.accounts WHERE provider = $1 AND provider_subject = $2",
            cmd =>
            {
                cmd.Parameters.AddWithValue(provider);
                cmd.Parameters.AddWithValue(subject);
            },
            cancellationToken);

    public async Task<Account> UpsertAccountAsync(Account account, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.accounts (account_id, provider, provider_subject, display_name, has_circle, circle_source, created_at, handle)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (provider, provider_subject) DO UPDATE
                SET display_name = EXCLUDED.display_name
            RETURNING account_id, provider, provider_subject, display_name, has_circle, circle_source, created_at, phone_e164, phone_verified_at, handle;
            """,
            connection);
        command.Parameters.AddWithValue(account.Id);
        command.Parameters.AddWithValue(account.Provider);
        command.Parameters.AddWithValue(account.ProviderSubject);
        command.Parameters.AddWithValue(account.DisplayName);
        command.Parameters.AddWithValue(account.HasCircle);
        command.Parameters.AddWithValue((object?)account.CircleSource ?? DBNull.Value);
        command.Parameters.AddWithValue(account.CreatedAt);
        command.Parameters.AddWithValue((object?)account.Handle ?? DBNull.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return ReadAccount(reader);
    }

    public async Task UpdateAccountAsync(Account account, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.accounts
            SET display_name = $2, has_circle = $3, circle_source = $4, handle = $5
            WHERE account_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(account.Id);
        command.Parameters.AddWithValue(account.DisplayName);
        command.Parameters.AddWithValue(account.HasCircle);
        command.Parameters.AddWithValue((object?)account.CircleSource ?? DBNull.Value);
        command.Parameters.AddWithValue((object?)account.Handle ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<Account>> ListConnectedAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT a.account_id, a.provider, a.provider_subject, a.display_name, a.has_circle, a.circle_source, a.created_at, a.phone_e164, a.phone_verified_at, a.handle
            FROM trust.memberships m
            JOIN trust.accounts a ON a.account_id = CASE WHEN m.person_a = $1 THEN m.person_b ELSE m.person_a END
            WHERE m.status = 'active' AND (m.person_a = $1 OR m.person_b = $1);
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var people = new List<Account>();
        while (await reader.ReadAsync(cancellationToken))
        {
            people.Add(ReadAccount(reader));
        }

        return people;
    }

    public async Task<int> ActiveMembershipCountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT COUNT(*) FROM trust.memberships WHERE status = 'active' AND (person_a = $1 OR person_b = $1);",
            connection);
        command.Parameters.AddWithValue(accountId);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToInt32(result);
    }

    public async Task<bool> AreConnectedAsync(Guid a, Guid b, CancellationToken cancellationToken)
    {
        var (left, right) = Order(a, b);
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT 1 FROM trust.memberships WHERE person_a = $1 AND person_b = $2 AND status = 'active';",
            connection);
        command.Parameters.AddWithValue(left);
        command.Parameters.AddWithValue(right);
        return await command.ExecuteScalarAsync(cancellationToken) is not null;
    }

    public async Task InsertMembershipAsync(Guid a, Guid b, CancellationToken cancellationToken)
    {
        var (left, right) = Order(a, b);
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.memberships (membership_id, person_a, person_b, status, created_at)
            VALUES ($1, $2, $3, 'active', $4)
            ON CONFLICT (person_a, person_b) DO UPDATE SET status = 'active';
            """,
            connection);
        command.Parameters.AddWithValue(Guid.NewGuid());
        command.Parameters.AddWithValue(left);
        command.Parameters.AddWithValue(right);
        command.Parameters.AddWithValue(DateTimeOffset.UtcNow);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task RevokeMembershipAsync(Guid a, Guid b, CancellationToken cancellationToken)
    {
        var (left, right) = Order(a, b);
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "UPDATE trust.memberships SET status = 'revoked' WHERE person_a = $1 AND person_b = $2;",
            connection);
        command.Parameters.AddWithValue(left);
        command.Parameters.AddWithValue(right);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<ShareState> GetShareAsync(Guid grantor, Guid grantee, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT resting, pause_until, restores_to FROM trust.shares WHERE grantor_id = $1 AND grantee_id = $2;",
            connection);
        command.Parameters.AddWithValue(grantor);
        command.Parameters.AddWithValue(grantee);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ShareState.Default;
        }

        return new ShareState(
            ParseResting(reader.GetString(0)),
            reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1),
            reader.IsDBNull(2) ? null : ParseResting(reader.GetString(2)));
    }

    public async Task UpsertShareAsync(Guid grantor, Guid grantee, ShareState state, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.shares (grantor_id, grantee_id, resting, pause_until, restores_to)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (grantor_id, grantee_id) DO UPDATE
                SET resting = EXCLUDED.resting,
                    pause_until = EXCLUDED.pause_until,
                    restores_to = EXCLUDED.restores_to;
            """,
            connection);
        command.Parameters.AddWithValue(grantor);
        command.Parameters.AddWithValue(grantee);
        command.Parameters.AddWithValue(FormatResting(state.Resting));
        command.Parameters.AddWithValue((object?)state.PauseUntil ?? DBNull.Value);
        command.Parameters.AddWithValue(state.RestoresTo is { } restores ? FormatResting(restores) : DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task RestoreExpiredPausesAsync(DateTimeOffset now, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.shares
            SET resting = CASE
                    WHEN restores_to = 'always' THEN 'always'
                    ELSE 'until_they_look'
                END,
                pause_until = NULL,
                restores_to = NULL
            WHERE resting = 'paused'
              AND pause_until IS NOT NULL
              AND pause_until <= $1;
            """,
            connection);
        command.Parameters.AddWithValue(now);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<Presence> GetPresenceAsync(
        Guid accountId,
        DateTimeOffset fallbackNow,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT last_active_at, battery_percent, is_charging, got_home_at, checked_in_at FROM trust.presence WHERE account_id = $1;",
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return new Presence(fallbackNow.AddMinutes(-10), 80, false, null, null);
        }

        return new Presence(
            reader.GetFieldValue<DateTimeOffset>(0),
            reader.GetInt32(1),
            reader.GetBoolean(2),
            reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4));
    }

    public async Task UpsertPresenceAsync(Guid accountId, Presence presence, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.presence (account_id, last_active_at, battery_percent, is_charging, got_home_at, checked_in_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (account_id) DO UPDATE SET
                last_active_at = EXCLUDED.last_active_at,
                battery_percent = EXCLUDED.battery_percent,
                is_charging = EXCLUDED.is_charging,
                got_home_at = EXCLUDED.got_home_at,
                checked_in_at = EXCLUDED.checked_in_at;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(presence.LastActiveAt);
        command.Parameters.AddWithValue(presence.BatteryPercent);
        command.Parameters.AddWithValue(presence.IsCharging);
        command.Parameters.AddWithValue((object?)presence.GotHomeAt ?? DBNull.Value);
        command.Parameters.AddWithValue((object?)presence.CheckedInAt ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task IngestLocationAsync(Guid accountId, LocationFix fix, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "INSERT INTO trust.location_points (account_id, recorded_at, latitude, longitude) VALUES ($1, $2, $3, $4);",
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(fix.Timestamp);
        command.Parameters.AddWithValue(fix.Latitude);
        command.Parameters.AddWithValue(fix.Longitude);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task PruneLocationsAsync(Guid accountId, DateTimeOffset olderThan, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            DELETE FROM trust.location_points
            WHERE account_id = $1
              AND recorded_at < $2;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(olderThan);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task ClearLocationsAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "DELETE FROM trust.location_points WHERE account_id = $1;",
            connection);
        command.Parameters.AddWithValue(accountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<LocationFix>> UnlockLocationsAsync(
        Guid accountId,
        DateTimeOffset from,
        DateTimeOffset to,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT recorded_at, latitude, longitude
            FROM trust.location_points
            WHERE account_id = $1 AND recorded_at >= $2 AND recorded_at <= $3
            ORDER BY recorded_at ASC;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(from);
        command.Parameters.AddWithValue(to);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var trail = new List<LocationFix>();
        while (await reader.ReadAsync(cancellationToken))
        {
            trail.Add(ReadFix(reader));
        }

        return trail;
    }

    public async Task<LocationFix?> LatestLocationAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT recorded_at, latitude, longitude
            FROM trust.location_points
            WHERE account_id = $1
            ORDER BY recorded_at DESC
            LIMIT 1;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return ReadFix(reader);
    }

    public async Task InsertLookEventAsync(LookEvent look, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.look_events (look_id, viewer_id, subject_id, at, history_window_hours, included_live, kind)
            VALUES ($1, $2, $3, $4, $5, $6, $7);
            """,
            connection);
        command.Parameters.AddWithValue(look.Id);
        command.Parameters.AddWithValue(look.ViewerId);
        command.Parameters.AddWithValue(look.SubjectId);
        command.Parameters.AddWithValue(look.At);
        command.Parameters.AddWithValue(look.HistoryWindowHours);
        command.Parameters.AddWithValue(look.IncludedLive);
        command.Parameters.AddWithValue(FormatLookKind(look.Kind));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<LookEvent>> ListLooksAsync(
        Guid accountId,
        DateTimeOffset since,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT e.look_id, e.viewer_id, v.display_name, e.subject_id, s.display_name, e.at, e.history_window_hours, e.included_live, e.kind
            FROM trust.look_events e
            JOIN trust.accounts v ON v.account_id = e.viewer_id
            JOIN trust.accounts s ON s.account_id = e.subject_id
            WHERE (e.viewer_id = $1 OR e.subject_id = $1) AND e.at >= $2
            ORDER BY e.at DESC;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(since);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var events = new List<LookEvent>();
        while (await reader.ReadAsync(cancellationToken))
        {
            events.Add(new LookEvent(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetGuid(3),
                reader.GetString(4),
                reader.GetFieldValue<DateTimeOffset>(5),
                reader.GetInt32(6),
                reader.GetBoolean(7),
                ParseLookKind(reader.GetString(8))));
        }

        return events;
    }

    public async Task<int> LooksTodayAsync(Guid viewerId, DateTimeOffset startOfDay, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT COUNT(*) FROM trust.look_events WHERE viewer_id = $1 AND at >= $2;",
            connection);
        command.Parameters.AddWithValue(viewerId);
        command.Parameters.AddWithValue(startOfDay);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task PruneAllLocationsAsync(DateTimeOffset olderThan, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            DELETE FROM trust.location_points AS lp
            WHERE lp.recorded_at < $1
               OR NOT EXISTS (
                    SELECT 1
                    FROM trust.shares AS s
                    WHERE s.grantor_id = lp.account_id
                      AND s.resting IN ('always', 'until_they_look', 'paused')
               );
            """,
            connection);
        command.Parameters.AddWithValue(olderThan);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public Task<Invite?> FindInviteByCodeAsync(string code, CancellationToken cancellationToken) =>
        QueryInviteAsync(
            "SELECT invite_id, code, creator_id, status, created_at, expires_at FROM trust.invites WHERE code = $1",
            cmd => cmd.Parameters.AddWithValue(code),
            cancellationToken);

    public Task<Invite?> FindPendingInviteAsync(Guid creatorId, CancellationToken cancellationToken) =>
        QueryInviteAsync(
            "SELECT invite_id, code, creator_id, status, created_at, expires_at FROM trust.invites WHERE creator_id = $1 AND status = 'pending' ORDER BY created_at DESC LIMIT 1",
            cmd => cmd.Parameters.AddWithValue(creatorId),
            cancellationToken);

    public async Task InsertInviteAsync(Invite invite, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "INSERT INTO trust.invites (invite_id, code, creator_id, status, created_at, expires_at) VALUES ($1, $2, $3, $4, $5, $6);",
            connection);
        command.Parameters.AddWithValue(invite.Id);
        command.Parameters.AddWithValue(invite.Code);
        command.Parameters.AddWithValue(invite.CreatorId);
        command.Parameters.AddWithValue(invite.Status);
        command.Parameters.AddWithValue(invite.CreatedAt);
        command.Parameters.AddWithValue((object?)invite.ExpiresAt ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task MarkInviteConsumedAsync(Guid inviteId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "UPDATE trust.invites SET status = 'consumed' WHERE invite_id = $1;",
            connection);
        command.Parameters.AddWithValue(inviteId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        // Lock the account row first so a push registration cannot insert a child
        // between these deletes and the account delete.
        await using (var lockRow = new NpgsqlCommand(
            "SELECT account_id FROM trust.accounts WHERE account_id = $1 FOR UPDATE;",
            connection,
            transaction))
        {
            lockRow.Parameters.AddWithValue(accountId);
            if (await lockRow.ExecuteScalarAsync(cancellationToken) is null)
            {
                await transaction.CommitAsync(cancellationToken);
                return;
            }
        }

        // Each delete is its own command: Npgsql rejects more than one statement
        // in a prepared command.
        string[] statements =
        [
            """
            DELETE FROM trust.active_looks
            WHERE viewer_id = $1 OR subject_id = $1
               OR look_id IN (
                    SELECT look_id FROM trust.look_events WHERE viewer_id = $1 OR subject_id = $1);
            """,
            "DELETE FROM trust.look_events WHERE viewer_id = $1 OR subject_id = $1;",
            "DELETE FROM trust.location_points WHERE account_id = $1;",
            "DELETE FROM trust.presence WHERE account_id = $1;",
            "DELETE FROM trust.shares WHERE grantor_id = $1 OR grantee_id = $1;",
            "DELETE FROM trust.memberships WHERE person_a = $1 OR person_b = $1;",
            "DELETE FROM trust.invites WHERE creator_id = $1;",
            "DELETE FROM trust.phone_challenges WHERE account_id = $1;",
            "DELETE FROM trust.storekit_transactions WHERE account_id = $1;",
            "DELETE FROM trust.storekit_subscription_owners WHERE account_id = $1;",
            "DELETE FROM trust.storekit_account_tokens WHERE account_id = $1;",
            "DELETE FROM trust.home_promises WHERE subject_id = $1 OR trustee_id = $1;",
            "DELETE FROM trust.current_home_presence WHERE account_id = $1;",
            "DELETE FROM trust.home_places WHERE account_id = $1;",
            "DELETE FROM trust.presence_grants WHERE subject_id = $1 OR trustee_id = $1;",
            "DELETE FROM trust.push_devices WHERE account_id = $1;",
            "DELETE FROM trust.accounts WHERE account_id = $1;"
        ];
        foreach (var statement in statements)
        {
            await using var command = new NpgsqlCommand(statement, connection, transaction);
            command.Parameters.AddWithValue(accountId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var budget = new NpgsqlCommand(
            "DELETE FROM trust.sms_send_budgets WHERE scope_key = $1;",
            connection,
            transaction))
        {
            budget.Parameters.AddWithValue(SmsSendBudget.AccountKey(accountId));
            await budget.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    public Task<Account?> FindByVerifiedPhoneAsync(string phoneE164, CancellationToken cancellationToken) =>
        QueryAccountAsync(
            $"SELECT {AccountColumns} FROM trust.accounts WHERE phone_e164 = $1 AND phone_verified_at IS NOT NULL",
            cmd => cmd.Parameters.AddWithValue(phoneE164),
            cancellationToken);

    public async Task SetVerifiedPhoneAsync(
        Guid accountId,
        string phoneE164,
        DateTimeOffset verifiedAt,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.accounts
            SET phone_e164 = $2, phone_verified_at = $3
            WHERE account_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(phoneE164);
        command.Parameters.AddWithValue(verifiedAt);
        try
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw TrustException.PhoneInUse();
        }
    }

    public Task<Account?> FindByHandleAsync(string handle, CancellationToken cancellationToken) =>
        QueryAccountAsync(
            $"SELECT {AccountColumns} FROM trust.accounts WHERE handle = $1",
            cmd => cmd.Parameters.AddWithValue(handle),
            cancellationToken);

    public async Task SetHandleAsync(
        Guid accountId,
        string handle,
        string displayName,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.accounts
            SET handle = $2, display_name = $3
            WHERE account_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        command.Parameters.AddWithValue(handle);
        command.Parameters.AddWithValue(displayName);
        try
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            throw TrustException.HandleInUse();
        }
    }

    public async Task<PhoneChallenge?> GetPhoneChallengeAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT account_id, phone_e164, code_hash, expires_at, attempts, sent_at, send_count, window_started_at
            FROM trust.phone_challenges
            WHERE account_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return ReadChallenge(reader);
    }

    public async Task UpsertPhoneChallengeAsync(PhoneChallenge challenge, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
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
            """,
            connection);
        command.Parameters.AddWithValue(challenge.AccountId);
        command.Parameters.AddWithValue(challenge.PhoneE164);
        command.Parameters.AddWithValue(challenge.CodeHash);
        command.Parameters.AddWithValue(challenge.ExpiresAt);
        command.Parameters.AddWithValue(challenge.Attempts);
        command.Parameters.AddWithValue(challenge.SentAt);
        command.Parameters.AddWithValue(challenge.SendCount);
        command.Parameters.AddWithValue(challenge.WindowStartedAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task ClearPhoneChallengeAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "DELETE FROM trust.phone_challenges WHERE account_id = $1;",
            connection);
        command.Parameters.AddWithValue(accountId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<SmsSendBudget?> GetSmsSendBudgetAsync(string scopeKey, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT scope_key, window_started_at, send_count, last_sent_at
            FROM trust.sms_send_budgets
            WHERE scope_key = $1;
            """,
            connection);
        command.Parameters.AddWithValue(scopeKey);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new SmsSendBudget(
            reader.GetString(0),
            reader.GetFieldValue<DateTimeOffset>(1),
            reader.GetInt32(2),
            reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3));
    }

    public async Task UpsertSmsSendBudgetAsync(SmsSendBudget budget, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.sms_send_budgets (scope_key, window_started_at, send_count, last_sent_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (scope_key) DO UPDATE SET
                window_started_at = EXCLUDED.window_started_at,
                send_count = EXCLUDED.send_count,
                last_sent_at = EXCLUDED.last_sent_at;
            """,
            connection);
        command.Parameters.AddWithValue(budget.ScopeKey);
        command.Parameters.AddWithValue(budget.WindowStartedAt);
        command.Parameters.AddWithValue(budget.SendCount);
        command.Parameters.AddWithValue((object?)budget.LastSentAt ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task SetPresenceGrantAsync(
        Guid subjectId,
        Guid trusteeId,
        bool enabled,
        DateTimeOffset updatedAt,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.presence_grants (subject_id, trustee_id, enabled, updated_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (subject_id, trustee_id) DO UPDATE SET
                enabled = EXCLUDED.enabled,
                updated_at = EXCLUDED.updated_at;
            """,
            connection);
        command.Parameters.AddWithValue(subjectId);
        command.Parameters.AddWithValue(trusteeId);
        command.Parameters.AddWithValue(enabled);
        command.Parameters.AddWithValue(updatedAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<PresenceGrant?> GetPresenceGrantAsync(
        Guid subjectId,
        Guid trusteeId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT subject_id, trustee_id, enabled, updated_at
            FROM trust.presence_grants
            WHERE subject_id = $1 AND trustee_id = $2;
            """,
            connection);
        command.Parameters.AddWithValue(subjectId);
        command.Parameters.AddWithValue(trusteeId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new PresenceGrant(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetBoolean(2),
            reader.GetFieldValue<DateTimeOffset>(3));
    }

    public async Task UpsertHomePlaceAsync(HomePlace place, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.home_places (account_id, place_id, label, updated_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (account_id) DO UPDATE SET
                place_id = EXCLUDED.place_id,
                label = EXCLUDED.label,
                updated_at = EXCLUDED.updated_at;
            """,
            connection);
        command.Parameters.AddWithValue(place.AccountId);
        command.Parameters.AddWithValue(place.PlaceId);
        command.Parameters.AddWithValue(place.Label);
        command.Parameters.AddWithValue(place.UpdatedAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<HomePlace?> GetHomePlaceAsync(Guid accountId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT account_id, place_id, label, updated_at FROM trust.home_places WHERE account_id = $1;",
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new HomePlace(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetFieldValue<DateTimeOffset>(3));
    }

    public async Task UpsertCurrentHomePresenceAsync(
        CurrentHomePresence presence,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.current_home_presence (account_id, place_id, state, last_changed_at, last_signal_at)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (account_id) DO UPDATE SET
                place_id = EXCLUDED.place_id,
                state = EXCLUDED.state,
                last_changed_at = EXCLUDED.last_changed_at,
                last_signal_at = EXCLUDED.last_signal_at;
            """,
            connection);
        command.Parameters.AddWithValue(presence.AccountId);
        command.Parameters.AddWithValue((object?)presence.PlaceId ?? DBNull.Value);
        command.Parameters.AddWithValue(FormatHomeState(presence.State));
        command.Parameters.AddWithValue(presence.LastChangedAt);
        command.Parameters.AddWithValue((object?)presence.LastSignalAt ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<CurrentHomePresence?> GetCurrentHomePresenceAsync(
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT account_id, place_id, state, last_changed_at, last_signal_at
            FROM trust.current_home_presence
            WHERE account_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(accountId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new CurrentHomePresence(
            reader.GetGuid(0),
            reader.IsDBNull(1) ? null : reader.GetGuid(1),
            ParseHomeState(reader.GetString(2)),
            reader.GetFieldValue<DateTimeOffset>(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4));
    }

    public async Task InsertPromiseAsync(HomePromise promise, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO trust.home_promises (
                promise_id, subject_id, trustee_id, place_id, deadline_at, status, resolved_at, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
            """,
            connection);
        BindPromise(command, promise);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpdatePromiseAsync(HomePromise promise, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            UPDATE trust.home_promises
            SET deadline_at = $5, status = $6, resolved_at = $7
            WHERE promise_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(promise.Id);
        command.Parameters.AddWithValue(promise.SubjectId);
        command.Parameters.AddWithValue(promise.TrusteeId);
        command.Parameters.AddWithValue(promise.PlaceId);
        command.Parameters.AddWithValue(promise.DeadlineAt);
        command.Parameters.AddWithValue(FormatPromiseStatus(promise.Status));
        command.Parameters.AddWithValue((object?)promise.ResolvedAt ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<HomePromise?> GetPromiseAsync(Guid promiseId, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT promise_id, subject_id, trustee_id, place_id, deadline_at, status, resolved_at, created_at
            FROM trust.home_promises
            WHERE promise_id = $1;
            """,
            connection);
        command.Parameters.AddWithValue(promiseId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return ReadPromise(reader);
    }

    public async Task<HomePromise?> GetActivePromiseAsync(
        Guid subjectId,
        Guid trusteeId,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT promise_id, subject_id, trustee_id, place_id, deadline_at, status, resolved_at, created_at
            FROM trust.home_promises
            WHERE subject_id = $1 AND trustee_id = $2 AND status = 'active'
            ORDER BY created_at DESC
            LIMIT 1;
            """,
            connection);
        command.Parameters.AddWithValue(subjectId);
        command.Parameters.AddWithValue(trusteeId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return ReadPromise(reader);
    }

    public async Task<IReadOnlyList<HomePromise>> ListPromisesForPairAsync(
        Guid a,
        Guid b,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT promise_id, subject_id, trustee_id, place_id, deadline_at, status, resolved_at, created_at
            FROM trust.home_promises
            WHERE (subject_id = $1 AND trustee_id = $2) OR (subject_id = $2 AND trustee_id = $1)
            ORDER BY created_at DESC;
            """,
            connection);
        command.Parameters.AddWithValue(a);
        command.Parameters.AddWithValue(b);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var promises = new List<HomePromise>();
        while (await reader.ReadAsync(cancellationToken))
        {
            promises.Add(ReadPromise(reader));
        }

        return promises;
    }

    public async Task<IReadOnlyList<HomePromise>> ListDuePromisesAsync(
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            """
            SELECT promise_id, subject_id, trustee_id, place_id, deadline_at, status, resolved_at, created_at
            FROM trust.home_promises
            WHERE status = 'active' AND deadline_at <= $1;
            """,
            connection);
        command.Parameters.AddWithValue(now);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var promises = new List<HomePromise>();
        while (await reader.ReadAsync(cancellationToken))
        {
            promises.Add(ReadPromise(reader));
        }

        return promises;
    }

    private static void BindPromise(NpgsqlCommand command, HomePromise promise)
    {
        command.Parameters.AddWithValue(promise.Id);
        command.Parameters.AddWithValue(promise.SubjectId);
        command.Parameters.AddWithValue(promise.TrusteeId);
        command.Parameters.AddWithValue(promise.PlaceId);
        command.Parameters.AddWithValue(promise.DeadlineAt);
        command.Parameters.AddWithValue(FormatPromiseStatus(promise.Status));
        command.Parameters.AddWithValue((object?)promise.ResolvedAt ?? DBNull.Value);
        command.Parameters.AddWithValue(promise.CreatedAt);
    }

    private static HomePromise ReadPromise(NpgsqlDataReader reader) =>
        new(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetGuid(2),
            reader.GetGuid(3),
            reader.GetFieldValue<DateTimeOffset>(4),
            ParsePromiseStatus(reader.GetString(5)),
            reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6),
            reader.GetFieldValue<DateTimeOffset>(7));

    private static HomePresenceState ParseHomeState(string value) => value.ToLowerInvariant() switch
    {
        "home" => HomePresenceState.Home,
        "away" => HomePresenceState.Away,
        "hidden" => HomePresenceState.Hidden,
        _ => HomePresenceState.Unknown
    };

    private static string FormatHomeState(HomePresenceState state) => state switch
    {
        HomePresenceState.Home => "home",
        HomePresenceState.Away => "away",
        HomePresenceState.Hidden => "hidden",
        _ => "unknown"
    };

    private static LookKind ParseLookKind(string value) => value.ToLowerInvariant() switch
    {
        "view" => LookKind.View,
        "removed" => LookKind.Removed,
        _ => LookKind.Look
    };

    private static string FormatLookKind(LookKind kind) => kind switch
    {
        LookKind.View => "view",
        LookKind.Removed => "removed",
        _ => "look"
    };

    private static PromiseStatus ParsePromiseStatus(string value) => value.ToLowerInvariant() switch
    {
        "resolved" => PromiseStatus.Resolved,
        "overdue" => PromiseStatus.Overdue,
        "no_signal" => PromiseStatus.NoSignal,
        _ => PromiseStatus.Active
    };

    private static string FormatPromiseStatus(PromiseStatus status) => status switch
    {
        PromiseStatus.Resolved => "resolved",
        PromiseStatus.Overdue => "overdue",
        PromiseStatus.NoSignal => "no_signal",
        _ => "active"
    };

    private async Task<Account?> QueryAccountAsync(
        string sql,
        Action<NpgsqlCommand> bind,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        bind(command);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return ReadAccount(reader);
    }

    private async Task<Invite?> QueryInviteAsync(
        string sql,
        Action<NpgsqlCommand> bind,
        CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        bind(command);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new Invite(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetGuid(2),
            reader.GetString(3),
            reader.GetFieldValue<DateTimeOffset>(4),
            reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5));
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }

    private static Account ReadAccount(NpgsqlDataReader reader) =>
        new(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetBoolean(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.GetFieldValue<DateTimeOffset>(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8),
            reader.IsDBNull(9) ? null : reader.GetString(9));

    private static PhoneChallenge ReadChallenge(NpgsqlDataReader reader) =>
        new(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetFieldValue<DateTimeOffset>(3),
            reader.GetInt32(4),
            reader.GetFieldValue<DateTimeOffset>(5),
            reader.GetInt32(6),
            reader.GetFieldValue<DateTimeOffset>(7));

    private static LocationFix ReadFix(NpgsqlDataReader reader) =>
        new(
            reader.GetFieldValue<DateTimeOffset>(0),
            reader.GetDouble(1),
            reader.GetDouble(2));

    private static (Guid A, Guid B) Order(Guid a, Guid b) =>
        a.CompareTo(b) < 0 ? (a, b) : (b, a);

    private static ShareResting ParseResting(string value) => value.ToLowerInvariant() switch
    {
        "always" => ShareResting.Always,
        "off" => ShareResting.Off,
        "paused" => ShareResting.Paused,
        _ => ShareResting.UntilTheyLook
    };

    private static string FormatResting(ShareResting resting) => resting switch
    {
        ShareResting.Always => "always",
        ShareResting.Off => "off",
        ShareResting.Paused => "paused",
        _ => "until_they_look"
    };
}
