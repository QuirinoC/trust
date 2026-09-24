-- Trust 1.0: server-owned Pause. Applied by the new API on its own boot.
-- The previous process still SELECTs timed_until ("For a while", a live countdown).
-- Leave that column in place so a rolling deploy does not crash the old process.
-- The new API does not read or write it. Pause lives in pause_until / restores_to.

ALTER TABLE trust.shares
    ADD COLUMN IF NOT EXISTS pause_until timestamptz NULL;

ALTER TABLE trust.shares
    ADD COLUMN IF NOT EXISTS restores_to text NULL;

ALTER TABLE trust.shares
    DROP CONSTRAINT IF EXISTS shares_restores_to_check;

ALTER TABLE trust.shares
    ADD CONSTRAINT shares_restores_to_check
    CHECK (restores_to IS NULL OR restores_to IN ('until_they_look', 'always'));

ALTER TABLE trust.look_events
    DROP CONSTRAINT IF EXISTS look_events_kind_check;

ALTER TABLE trust.look_events
    ADD CONSTRAINT look_events_kind_check
    CHECK (kind IN ('look', 'view', 'removed'));
