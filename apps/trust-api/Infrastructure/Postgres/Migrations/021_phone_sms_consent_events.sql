CREATE TABLE IF NOT EXISTS trust.phone_sms_consent_events (
    consent_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    phone_e164 text NOT NULL,
    disclosure_key text,
    disclosure_version integer CHECK (disclosure_version IS NULL OR disclosure_version > 0),
    consented_at timestamptz NOT NULL,
    source text NOT NULL,
    action text CHECK (action IS NULL OR action IN ('send_code', 'resend_code')),
    CHECK ((disclosure_key IS NULL) = (disclosure_version IS NULL)),
    CHECK ((action IS NULL) = (disclosure_version IS NULL))
);

CREATE INDEX IF NOT EXISTS ix_phone_sms_consent_events_account_time
    ON trust.phone_sms_consent_events (account_id, consented_at, consent_id);
