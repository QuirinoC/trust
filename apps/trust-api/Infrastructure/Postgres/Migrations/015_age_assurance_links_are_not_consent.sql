-- App transaction registration proves app ownership only. It is not a consent
-- timestamp and must never be compared with a consent-revocation signature time.
ALTER TABLE trust.age_assurance_app_transactions
    DROP COLUMN IF EXISTS linked_at;
