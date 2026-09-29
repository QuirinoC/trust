CREATE TABLE IF NOT EXISTS trust.age_assurance_blocked_accounts (
    account_id uuid NOT NULL,
    app_transaction_hash text NOT NULL CHECK (length(app_transaction_hash) = 64),
    environment text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, app_transaction_hash, environment)
);

CREATE INDEX IF NOT EXISTS ix_age_assurance_blocked_accounts_transaction
    ON trust.age_assurance_blocked_accounts (app_transaction_hash, environment);
