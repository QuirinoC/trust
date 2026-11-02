CREATE TABLE IF NOT EXISTS trust.phone_support_recovery_requests (
    recovery_request_id uuid PRIMARY KEY,
    target_account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    reason text NULL CHECK (reason IS NULL OR length(reason) <= 500),
    status text NOT NULL CHECK (status IN ('pending', 'blocked', 'approved', 'rejected')),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_phone_support_recovery_pending
    ON trust.phone_support_recovery_requests (created_at)
    WHERE status IN ('pending', 'blocked');

CREATE UNIQUE INDEX IF NOT EXISTS ux_phone_support_recovery_pending_account
    ON trust.phone_support_recovery_requests (target_account_id)
    WHERE status IN ('pending', 'blocked');
