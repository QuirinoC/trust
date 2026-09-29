ALTER TABLE trust.presence_grants
    ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 0;

ALTER TABLE trust.presence_grants
    ADD CONSTRAINT presence_grants_revision_nonnegative CHECK (revision >= 0);

ALTER TABLE trust.current_home_presence
    ADD COLUMN IF NOT EXISTS transition_id uuid NOT NULL DEFAULT gen_random_uuid();
