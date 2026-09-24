-- Circle v1 (M1): additive alignment for Off share, Hidden presence, look/view kinds,
-- invite RNG + expiry. All changes are additive/backward compatible with 001-005.

-- 1) ShareResting.Off is a new value of the existing `resting` text column on trust.shares.
--    No column/constraint change is required: the column has never had a CHECK, and existing
--    rows keep their current 'until_they_look' / 'always' values. New joins default to 'off'
--    at the application layer (TrustEngine / ShareState.Default).

-- 2) Presence triad adds `hidden` alongside unknown/home/away.
ALTER TABLE trust.current_home_presence
    DROP CONSTRAINT IF EXISTS current_home_presence_state_check;

ALTER TABLE trust.current_home_presence
    ADD CONSTRAINT current_home_presence_state_check
    CHECK (state IN ('unknown', 'home', 'away', 'hidden'));

-- 3) look_events gains a `kind` discriminator (look | view). Existing rows are historical
--    Looks, so the default backfills them without a data migration.
ALTER TABLE trust.look_events
    ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'look';

ALTER TABLE trust.look_events
    DROP CONSTRAINT IF EXISTS look_events_kind_check;

ALTER TABLE trust.look_events
    ADD CONSTRAINT look_events_kind_check
    CHECK (kind IN ('look', 'view'));

-- Speeds up the 30-minute View dedupe lookup (viewer -> subject, most recent first).
CREATE INDEX IF NOT EXISTS ix_looks_viewer_subject_kind_time
    ON trust.look_events (viewer_id, subject_id, kind, at DESC);

-- 4) Invite RNG hygiene: invites now expire. Existing pending/consumed invites are
--    grandfathered with a NULL expiry (treated as already-expired by the application
--    the next time they are evaluated, since a NULL expiry never satisfies "not expired"
--    for newly created invites -- new invites always set expires_at explicitly).
ALTER TABLE trust.invites
    ADD COLUMN IF NOT EXISTS expires_at timestamptz NULL;
