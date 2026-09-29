CREATE TABLE IF NOT EXISTS trust.age_assurance_cleanup_jobs (
    account_id uuid PRIMARY KEY,
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    lease_token uuid,
    lease_until timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((lease_token IS NULL) = (lease_until IS NULL))
);

CREATE INDEX IF NOT EXISTS ix_age_assurance_cleanup_jobs_due
    ON trust.age_assurance_cleanup_jobs (next_attempt_at, lease_until, account_id);

-- Backfill pending rows from earlier versions before the retry worker starts.
INSERT INTO trust.age_assurance_cleanup_jobs (account_id)
SELECT account_id FROM trust.age_assurance_blocked_accounts
UNION
SELECT link.account_id
FROM trust.age_assurance_app_transactions link
INNER JOIN trust.age_assurance_revoked_app_transactions revoked
    USING (app_transaction_hash, environment)
ON CONFLICT (account_id) DO NOTHING;
