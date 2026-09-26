CREATE TABLE IF NOT EXISTS trust.connection_requests (
    request_id uuid PRIMARY KEY,
    sender_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    recipient_id uuid NOT NULL REFERENCES trust.accounts (account_id) ON DELETE CASCADE,
    status text NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CHECK (sender_id <> recipient_id),
    CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'expired'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_connection_requests_pending_pair
    ON trust.connection_requests (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id))
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ix_connection_requests_recipient_status
    ON trust.connection_requests (recipient_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_connection_requests_sender_status
    ON trust.connection_requests (sender_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_connection_requests_pair_status
    ON trust.connection_requests (sender_id, recipient_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS ix_connection_requests_pending_expiry
    ON trust.connection_requests (expires_at) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ix_connection_requests_terminal_retention
    ON trust.connection_requests (updated_at) WHERE status <> 'pending';
