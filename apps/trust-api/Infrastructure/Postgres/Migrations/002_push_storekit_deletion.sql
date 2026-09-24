CREATE TABLE IF NOT EXISTS trust.push_devices (
    installation_id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    apns_token text NOT NULL,
    environment text NOT NULL,
    bundle_id text NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    last_seen_at timestamptz NOT NULL,
    invalidated_at timestamptz NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT ck_push_devices_environment
        CHECK (environment IN ('production', 'sandbox'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_push_devices_account_token
    ON trust.push_devices (account_id, apns_token);

CREATE INDEX IF NOT EXISTS ix_push_devices_account
    ON trust.push_devices (account_id)
    WHERE enabled;

CREATE TABLE IF NOT EXISTS trust.storekit_account_tokens (
    account_id uuid PRIMARY KEY REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    app_account_token uuid NOT NULL UNIQUE,
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS trust.storekit_subscription_owners (
    original_transaction_id text PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    app_account_token uuid NOT NULL,
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS trust.storekit_transactions (
    transaction_id text PRIMARY KEY,
    original_transaction_id text NOT NULL
        REFERENCES trust.storekit_subscription_owners (original_transaction_id) ON DELETE CASCADE,
    account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    product_id text NOT NULL,
    environment text NOT NULL,
    signed_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz NULL,
    received_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_storekit_transactions_subscription_signed
    ON trust.storekit_transactions (original_transaction_id, signed_at DESC);
