ALTER TABLE trust.phone_challenges
    ADD COLUMN IF NOT EXISTS expected_phone_e164 text NULL;
