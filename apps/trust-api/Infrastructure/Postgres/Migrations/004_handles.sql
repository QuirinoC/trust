ALTER TABLE trust.accounts
    ADD COLUMN IF NOT EXISTS handle text NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_accounts_handle
    ON trust.accounts (handle)
    WHERE handle IS NOT NULL;
