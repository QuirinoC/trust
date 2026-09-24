ALTER TABLE trust.accounts
    ADD COLUMN IF NOT EXISTS phone_e164 text NULL,
    ADD COLUMN IF NOT EXISTS phone_verified_at timestamptz NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_accounts_phone_e164
    ON trust.accounts (phone_e164)
    WHERE phone_e164 IS NOT NULL AND phone_verified_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS trust.phone_challenges (
    account_id uuid PRIMARY KEY REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    phone_e164 text NOT NULL,
    code_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    sent_at timestamptz NOT NULL,
    send_count integer NOT NULL DEFAULT 1,
    window_started_at timestamptz NOT NULL
);
