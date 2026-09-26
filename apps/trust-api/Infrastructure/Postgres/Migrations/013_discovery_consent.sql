ALTER TABLE trust.accounts
    ADD COLUMN IF NOT EXISTS discovery_consent_version integer NULL;

ALTER TABLE trust.accounts
    DROP CONSTRAINT IF EXISTS accounts_discovery_consent_version_check;

ALTER TABLE trust.accounts
    ADD CONSTRAINT accounts_discovery_consent_version_check CHECK (
        discovery_consent_version IS NULL OR discovery_consent_version = 1
    );
