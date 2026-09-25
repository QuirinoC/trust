ALTER TABLE trust.accounts
    ADD COLUMN IF NOT EXISTS avatar_kind text NULL,
    ADD COLUMN IF NOT EXISTS avatar_preset_id text NULL,
    ADD COLUMN IF NOT EXISTS avatar_version uuid NULL;

ALTER TABLE trust.accounts
    DROP CONSTRAINT IF EXISTS accounts_avatar_shape_check;

ALTER TABLE trust.accounts
    ADD CONSTRAINT accounts_avatar_shape_check CHECK (
        (avatar_kind IS NULL AND avatar_preset_id IS NULL AND avatar_version IS NULL)
        OR (avatar_kind = 'preset' AND avatar_preset_id IS NOT NULL AND avatar_version IS NULL)
        OR (avatar_kind = 'photo' AND avatar_preset_id IS NULL AND avatar_version IS NOT NULL)
    );

CREATE TABLE IF NOT EXISTS trust.profile_avatar_photos (
    account_id uuid PRIMARY KEY REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    version uuid NOT NULL,
    jpeg bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (account_id, version)
);
