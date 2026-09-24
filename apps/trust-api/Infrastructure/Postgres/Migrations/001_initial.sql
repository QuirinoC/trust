CREATE SCHEMA IF NOT EXISTS trust;

CREATE TABLE IF NOT EXISTS trust.schema_migrations (
    name text PRIMARY KEY,
    applied_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS trust.accounts (
    account_id uuid PRIMARY KEY,
    provider text NOT NULL,
    provider_subject text NOT NULL,
    display_name text NOT NULL,
    has_circle boolean NOT NULL DEFAULT false,
    circle_source text NULL,
    created_at timestamptz NOT NULL,
    UNIQUE (provider, provider_subject)
);

CREATE TABLE IF NOT EXISTS trust.invites (
    invite_id uuid PRIMARY KEY,
    code text NOT NULL UNIQUE,
    creator_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    status text NOT NULL,
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS trust.memberships (
    membership_id uuid PRIMARY KEY,
    person_a uuid NOT NULL REFERENCES trust.accounts (account_id),
    person_b uuid NOT NULL REFERENCES trust.accounts (account_id),
    status text NOT NULL,
    created_at timestamptz NOT NULL,
    CHECK (person_a < person_b),
    UNIQUE (person_a, person_b)
);

CREATE INDEX IF NOT EXISTS ix_memberships_person_a
    ON trust.memberships (person_a, status);

CREATE INDEX IF NOT EXISTS ix_memberships_person_b
    ON trust.memberships (person_b, status);

CREATE TABLE IF NOT EXISTS trust.shares (
    grantor_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    grantee_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    resting text NOT NULL,
    timed_until timestamptz NULL,
    PRIMARY KEY (grantor_id, grantee_id)
);

CREATE TABLE IF NOT EXISTS trust.presence (
    account_id uuid PRIMARY KEY REFERENCES trust.accounts (account_id),
    last_active_at timestamptz NOT NULL,
    battery_percent integer NOT NULL,
    is_charging boolean NOT NULL,
    got_home_at timestamptz NULL,
    checked_in_at timestamptz NULL
);

CREATE TABLE IF NOT EXISTS trust.location_points (
    point_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    recorded_at timestamptz NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_location_account_time
    ON trust.location_points (account_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS trust.look_events (
    look_id uuid PRIMARY KEY,
    viewer_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    subject_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    at timestamptz NOT NULL,
    history_window_hours integer NOT NULL,
    included_live boolean NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_looks_viewer_time
    ON trust.look_events (viewer_id, at DESC);

CREATE INDEX IF NOT EXISTS ix_looks_subject_time
    ON trust.look_events (subject_id, at DESC);

CREATE TABLE IF NOT EXISTS trust.active_looks (
    viewer_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    subject_id uuid NOT NULL REFERENCES trust.accounts (account_id),
    look_id uuid NOT NULL REFERENCES trust.look_events (look_id),
    history_window_hours integer NOT NULL,
    opened_at timestamptz NOT NULL,
    PRIMARY KEY (viewer_id, subject_id)
);
