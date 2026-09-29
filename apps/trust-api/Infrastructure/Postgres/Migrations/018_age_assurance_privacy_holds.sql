CREATE TABLE IF NOT EXISTS trust.age_assurance_privacy_holds (
    account_id uuid PRIMARY KEY,
    held_at timestamptz NOT NULL,
    policy_version text NOT NULL,
    reason text NOT NULL CHECK (reason = 'client_reported_age_restriction')
);
