-- NULL marks an existing hourly budget: do not grant correction grace until it rolls.
ALTER TABLE trust.sms_send_budgets ADD COLUMN phone_attempts text[];
ALTER TABLE trust.sms_send_budgets ADD CONSTRAINT sms_phone_attempts_bounded
    CHECK (phone_attempts IS NULL OR (scope_key LIKE 'account:%' AND cardinality(phone_attempts) <= 8));
