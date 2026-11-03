ALTER TABLE trust.phone_challenges
    ADD COLUMN IF NOT EXISTS challenge_id uuid NULL,
    ADD COLUMN IF NOT EXISTS request_id uuid NULL,
    ADD COLUMN IF NOT EXISTS purpose text NOT NULL DEFAULT 'onboarding',
    ADD COLUMN IF NOT EXISTS delivery_state text NOT NULL DEFAULT 'sent';

ALTER TABLE trust.phone_challenges ALTER COLUMN challenge_id SET DEFAULT gen_random_uuid();
UPDATE trust.phone_challenges SET challenge_id = gen_random_uuid() WHERE challenge_id IS NULL;
ALTER TABLE trust.phone_challenges ALTER COLUMN challenge_id SET NOT NULL;

CREATE TABLE IF NOT EXISTS trust.phone_verification_operations (
    account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    request_id uuid NOT NULL,
    challenge_id uuid NOT NULL,
    phone_e164 text NOT NULL,
    purpose text NOT NULL,
    verification_state text NOT NULL,
    delivery_state text NOT NULL,
    expires_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    PRIMARY KEY (account_id, request_id)
);
