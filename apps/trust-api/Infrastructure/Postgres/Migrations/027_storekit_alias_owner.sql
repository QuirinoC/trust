CREATE UNIQUE INDEX IF NOT EXISTS ux_storekit_recovery_alias_original_owner
    ON trust.storekit_approved_subscription_aliases (original_transaction_id);
