-- An earlier draft of 007 dropped timed_until after it had already been applied locally.
-- The live API still SELECTs that column, so put it back when it is missing.
-- The new API does not read or write it. Pause stays in pause_until / restores_to.

ALTER TABLE trust.shares
    ADD COLUMN IF NOT EXISTS timed_until timestamptz NULL;
