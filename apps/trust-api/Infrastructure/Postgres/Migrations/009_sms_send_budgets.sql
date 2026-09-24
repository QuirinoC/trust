CREATE TABLE IF NOT EXISTS trust.sms_send_budgets (
    scope_key text PRIMARY KEY,
    window_started_at timestamptz NOT NULL,
    send_count integer NOT NULL,
    last_sent_at timestamptz NULL
);
