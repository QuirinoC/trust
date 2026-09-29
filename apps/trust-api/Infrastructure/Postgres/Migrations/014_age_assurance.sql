CREATE TABLE IF NOT EXISTS trust.age_assurance_app_transactions (
    app_transaction_hash text NOT NULL CHECK (length(app_transaction_hash) = 64),
    environment text NOT NULL,
    account_id uuid NOT NULL,
    PRIMARY KEY (app_transaction_hash, environment, account_id)
);

CREATE INDEX IF NOT EXISTS ix_age_assurance_app_transactions_account
    ON trust.age_assurance_app_transactions (account_id);

CREATE TABLE IF NOT EXISTS trust.age_assurance_notifications (
    notification_id uuid PRIMARY KEY,
    app_transaction_hash text NOT NULL CHECK (length(app_transaction_hash) = 64),
    environment text NOT NULL,
    signed_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS trust.age_assurance_revoked_app_transactions (
    app_transaction_hash text NOT NULL CHECK (length(app_transaction_hash) = 64),
    environment text NOT NULL,
    notification_id uuid NOT NULL,
    revoked_at timestamptz NOT NULL,
    PRIMARY KEY (app_transaction_hash, environment)
);
