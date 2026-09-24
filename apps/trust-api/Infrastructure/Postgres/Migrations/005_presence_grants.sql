-- Presence grants: Home/Away visibility without coordinates.
-- Home coords stay on the subject's device; server stores label + current state only.

CREATE TABLE IF NOT EXISTS trust.presence_grants (
    subject_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    trustee_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    enabled boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL,
    PRIMARY KEY (subject_id, trustee_id),
    CHECK (subject_id <> trustee_id)
);

CREATE INDEX IF NOT EXISTS ix_presence_grants_trustee
    ON trust.presence_grants (trustee_id) WHERE enabled;

CREATE TABLE IF NOT EXISTS trust.home_places (
    account_id uuid PRIMARY KEY REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    place_id uuid NOT NULL,
    label text NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS trust.current_home_presence (
    account_id uuid PRIMARY KEY REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    place_id uuid NULL,
    state text NOT NULL,
    last_changed_at timestamptz NOT NULL,
    last_signal_at timestamptz NULL,
    CHECK (state IN ('unknown', 'home', 'away'))
);

CREATE TABLE IF NOT EXISTS trust.home_promises (
    promise_id uuid PRIMARY KEY,
    subject_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    trustee_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    place_id uuid NOT NULL,
    deadline_at timestamptz NOT NULL,
    status text NOT NULL,
    resolved_at timestamptz NULL,
    created_at timestamptz NOT NULL,
    CHECK (subject_id <> trustee_id),
    CHECK (status IN ('active', 'resolved', 'overdue', 'no_signal'))
);

CREATE INDEX IF NOT EXISTS ix_home_promises_pair
    ON trust.home_promises (subject_id, trustee_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_home_promises_due
    ON trust.home_promises (deadline_at)
    WHERE status = 'active';
