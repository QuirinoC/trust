ALTER TABLE trust.push_devices
    ADD COLUMN IF NOT EXISTS app_language text NOT NULL DEFAULT 'en';

ALTER TABLE trust.push_devices
    DROP CONSTRAINT IF EXISTS ck_push_devices_app_language;

ALTER TABLE trust.push_devices
    ADD CONSTRAINT ck_push_devices_app_language
    CHECK (app_language IN ('en', 'de', 'fr', 'ja', 'pt-BR', 'zh-Hans'));
