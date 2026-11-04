CREATE TABLE IF NOT EXISTS trust.storekit_recovery_requests (
    recovery_request_id uuid PRIMARY KEY,
    target_account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    original_transaction_id text NOT NULL,
    old_app_account_token uuid NOT NULL,
    transaction_id text NOT NULL,
    product_id text NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz NULL,
    reason text NULL CHECK (reason IS NULL OR length(reason) <= 500),
    status text NOT NULL CHECK (status IN ('pending', 'blocked', 'approved', 'rejected')),
    blocked_reason text NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_storekit_recovery_pending
    ON trust.storekit_recovery_requests (created_at)
    WHERE status IN ('pending', 'blocked');

CREATE UNIQUE INDEX IF NOT EXISTS ux_storekit_recovery_pending_claim
    ON trust.storekit_recovery_requests (target_account_id, original_transaction_id, old_app_account_token)
    WHERE status IN ('pending', 'blocked');

CREATE TABLE IF NOT EXISTS trust.storekit_approved_subscription_aliases (
    original_transaction_id text NOT NULL,
    old_app_account_token uuid NOT NULL,
    target_account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    recovery_request_id uuid NOT NULL,
    approved_at timestamptz NOT NULL,
    PRIMARY KEY (original_transaction_id, old_app_account_token, target_account_id),
    UNIQUE (original_transaction_id, old_app_account_token)
);
