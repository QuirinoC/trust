-- Allow look_events.kind = 'removed' so revoke can append a Log row.
ALTER TABLE trust.look_events
    DROP CONSTRAINT IF EXISTS look_events_kind_check;

ALTER TABLE trust.look_events
    ADD CONSTRAINT look_events_kind_check
    CHECK (kind IN ('look', 'view', 'removed'));
