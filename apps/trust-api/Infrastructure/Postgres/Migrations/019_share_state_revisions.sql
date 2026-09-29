ALTER TABLE trust.shares
    ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 0;

ALTER TABLE trust.shares
    ADD CONSTRAINT shares_revision_nonnegative CHECK (revision >= 0);
