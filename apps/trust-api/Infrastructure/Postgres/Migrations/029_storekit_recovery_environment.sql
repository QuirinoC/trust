ALTER TABLE trust.storekit_recovery_requests
    ADD COLUMN IF NOT EXISTS environment text NULL
        CHECK (environment IS NULL OR environment IN ('Production', 'Sandbox'));

ALTER TABLE trust.storekit_recovery_requests
    ADD COLUMN IF NOT EXISTS blocked_reason text NULL;

ALTER TABLE trust.storekit_recovery_requests
    DROP CONSTRAINT IF EXISTS storekit_recovery_requests_status_check;

ALTER TABLE trust.storekit_recovery_requests
    ADD CONSTRAINT storekit_recovery_requests_status_check
        CHECK (status IN ('pending', 'blocked', 'approved', 'rejected'));

DROP INDEX IF EXISTS trust.ix_storekit_recovery_pending;
CREATE INDEX ix_storekit_recovery_pending
    ON trust.storekit_recovery_requests (created_at)
    WHERE status IN ('pending', 'blocked');

DROP INDEX IF EXISTS trust.ux_storekit_recovery_pending_claim;
CREATE UNIQUE INDEX ux_storekit_recovery_pending_claim
    ON trust.storekit_recovery_requests (target_account_id, original_transaction_id, old_app_account_token)
    WHERE status IN ('pending', 'blocked');

UPDATE trust.storekit_recovery_requests
SET status = 'blocked', blocked_reason = 'environment_unknown'
WHERE environment IS NULL AND status IN ('pending', 'blocked');
