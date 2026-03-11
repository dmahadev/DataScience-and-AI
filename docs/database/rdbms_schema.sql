-- =============================================================================
-- DocuMagic – RDBMS Schema (Amazon Aurora PostgreSQL 15)
-- =============================================================================
-- Database: documagic
-- Schema:   public (default) + app (application tables)
--
-- Purpose: Relational tier providing ACID guarantees for structured master data
-- that requires complex joins, referential integrity, transactional consistency,
-- and compliance-grade audit trails.
--
-- Connection is managed through RDS Proxy (IAM authentication, TLS required).
-- Run as the documagic_admin superuser then grant app-role to documagic_app.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";       -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";        -- crypt(), digest()
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- query performance
CREATE EXTENSION IF NOT EXISTS "btree_gin";       -- GIN indexes on scalars

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app;
SET search_path = app, public;

-- ---------------------------------------------------------------------------
-- Application role (used by Lambda via RDS Proxy)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'documagic_app') THEN
    CREATE ROLE documagic_app LOGIN;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA app TO documagic_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO documagic_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO documagic_app;

-- =============================================================================
-- TABLE: organisations
-- Tenant/organisation master record. Multi-tenant SaaS model.
-- =============================================================================
CREATE TABLE app.organisations (
    org_id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name             TEXT        NOT NULL,
    slug             TEXT        NOT NULL UNIQUE,        -- URL-safe identifier
    plan_tier        TEXT        NOT NULL DEFAULT 'free'
                     CHECK (plan_tier IN ('free', 'starter', 'professional', 'enterprise')),
    status           TEXT        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'suspended', 'cancelled', 'pending_verification')),
    -- limits (per plan)
    max_users        INTEGER     NOT NULL DEFAULT 5,
    max_documents    BIGINT      NOT NULL DEFAULT 100,
    max_storage_gb   NUMERIC(10,2) NOT NULL DEFAULT 1.00,
    max_api_calls_per_month BIGINT NOT NULL DEFAULT 10000,
    -- contact
    owner_email      TEXT        NOT NULL,
    support_email    TEXT,
    -- billing
    stripe_customer_id   TEXT UNIQUE,
    billing_cycle_start  DATE,
    -- feature flags (jsonb for extensibility)
    feature_flags    JSONB       NOT NULL DEFAULT '{}',
    metadata         JSONB       NOT NULL DEFAULT '{}',
    -- timestamps
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ             -- soft delete
);

CREATE INDEX idx_organisations_slug    ON app.organisations (slug);
CREATE INDEX idx_organisations_plan    ON app.organisations (plan_tier) WHERE deleted_at IS NULL;
CREATE INDEX idx_organisations_status  ON app.organisations (status) WHERE deleted_at IS NULL;
CREATE INDEX idx_organisations_created ON app.organisations (created_at DESC);

COMMENT ON TABLE app.organisations IS
    'Tenant/organisation master record for DocuMagic multi-tenant SaaS.';

-- =============================================================================
-- TABLE: users
-- Application user accounts, synced from Amazon Cognito.
-- =============================================================================
CREATE TABLE app.users (
    user_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cognito_sub      TEXT        NOT NULL UNIQUE,   -- Cognito user pool sub claim
    org_id           UUID        NOT NULL REFERENCES app.organisations (org_id) ON DELETE RESTRICT,
    email            TEXT        NOT NULL,
    email_verified   BOOLEAN     NOT NULL DEFAULT FALSE,
    given_name       TEXT,
    family_name      TEXT,
    display_name     TEXT        GENERATED ALWAYS AS (
                       COALESCE(given_name || ' ' || family_name, email)
                     ) STORED,
    role             TEXT        NOT NULL DEFAULT 'member'
                     CHECK (role IN ('owner', 'admin', 'member', 'viewer', 'api_client')),
    status           TEXT        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'inactive', 'suspended', 'pending_invitation')),
    -- profile
    avatar_url       TEXT,
    timezone         TEXT        DEFAULT 'UTC',
    locale           TEXT        DEFAULT 'en-US',
    preferences      JSONB       NOT NULL DEFAULT '{}',
    -- usage counters (rolling)
    documents_uploaded_count  BIGINT NOT NULL DEFAULT 0,
    api_calls_this_month      BIGINT NOT NULL DEFAULT 0,
    -- timestamps
    last_login_at    TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ             -- soft delete

    CONSTRAINT unique_email_per_org UNIQUE (org_id, email)
);

CREATE INDEX idx_users_cognito_sub ON app.users (cognito_sub);
CREATE INDEX idx_users_org_id      ON app.users (org_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_email       ON app.users (email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_role        ON app.users (org_id, role) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_created     ON app.users (created_at DESC);

COMMENT ON TABLE app.users IS
    'Application user accounts synced from Amazon Cognito User Pool.';

-- =============================================================================
-- TABLE: documents
-- Master document catalog – relational source of truth for document lifecycle.
-- DynamoDB holds hot/operational state; this table is the authoritative record.
-- =============================================================================
CREATE TABLE app.documents (
    document_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id           UUID        NOT NULL REFERENCES app.organisations (org_id) ON DELETE RESTRICT,
    uploaded_by      UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE RESTRICT,
    -- file info
    file_name        TEXT        NOT NULL,
    file_type        TEXT        NOT NULL,            -- MIME type
    file_extension   TEXT        NOT NULL,            -- pdf, docx, png, …
    file_size_bytes  BIGINT      NOT NULL,
    page_count       INTEGER,
    -- storage location
    s3_bucket        TEXT        NOT NULL,
    s3_key           TEXT        NOT NULL,
    s3_version_id    TEXT,
    -- pipeline state
    status           TEXT        NOT NULL DEFAULT 'uploaded'
                     CHECK (status IN (
                       'uploaded', 'queued', 'processing', 'textract_pending',
                       'enriching', 'indexing', 'completed', 'failed', 'archived', 'deleted'
                     )),
    pipeline_run_id  TEXT,                            -- Step Functions execution ID
    textract_job_id  TEXT,
    -- content summary
    language         TEXT,
    page_count_confirmed INTEGER,
    word_count       INTEGER,
    has_tables       BOOLEAN,
    has_forms        BOOLEAN,
    has_signatures   BOOLEAN,
    pii_detected     BOOLEAN     DEFAULT FALSE,
    -- enrichment
    summary          TEXT,
    topics           TEXT[],
    categories       TEXT[],
    sentiment        TEXT        CHECK (sentiment IN ('POSITIVE','NEGATIVE','NEUTRAL','MIXED')),
    -- versioning
    version          INTEGER     NOT NULL DEFAULT 1,
    parent_document_id UUID      REFERENCES app.documents (document_id),
    -- access
    is_public        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- retention
    retain_until     DATE,                            -- legal hold / retention policy
    -- timestamps
    uploaded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at     TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archived_at      TIMESTAMPTZ,
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_documents_org_status   ON app.documents (org_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_documents_uploaded_by  ON app.documents (uploaded_by) WHERE deleted_at IS NULL;
CREATE INDEX idx_documents_uploaded_at  ON app.documents (org_id, uploaded_at DESC);
CREATE INDEX idx_documents_status       ON app.documents (status) WHERE deleted_at IS NULL;
CREATE INDEX idx_documents_pipeline     ON app.documents (pipeline_run_id) WHERE pipeline_run_id IS NOT NULL;
CREATE INDEX idx_documents_topics       ON app.documents USING GIN (topics);
CREATE INDEX idx_documents_categories   ON app.documents USING GIN (categories);
CREATE INDEX idx_documents_pii          ON app.documents (org_id, pii_detected) WHERE pii_detected = TRUE;
CREATE INDEX idx_documents_full_text    ON app.documents USING GIN (to_tsvector('english', file_name || ' ' || COALESCE(summary, '')));

COMMENT ON TABLE app.documents IS
    'Relational master catalog of documents; DynamoDB holds hot operational state.';

-- =============================================================================
-- TABLE: document_permissions
-- Fine-grained ACL – who can read/write/share/delete each document.
-- =============================================================================
CREATE TABLE app.document_permissions (
    permission_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id      UUID        NOT NULL REFERENCES app.documents (document_id) ON DELETE CASCADE,
    -- grantee (exactly one of these must be set)
    user_id          UUID        REFERENCES app.users (user_id) ON DELETE CASCADE,
    org_id           UUID        REFERENCES app.organisations (org_id) ON DELETE CASCADE,
    -- permission level
    permission       TEXT        NOT NULL
                     CHECK (permission IN ('viewer', 'commenter', 'editor', 'owner')),
    -- who granted it
    granted_by       UUID        NOT NULL REFERENCES app.users (user_id),
    granted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at       TIMESTAMPTZ,
    -- share link
    share_token      TEXT UNIQUE,                     -- UUID token for link-based sharing

    CONSTRAINT doc_perm_grantee_check CHECK (
        (user_id IS NOT NULL)::int + (org_id IS NOT NULL)::int = 1
    )
);

CREATE INDEX idx_doc_perm_document ON app.document_permissions (document_id);
CREATE INDEX idx_doc_perm_user     ON app.document_permissions (user_id)   WHERE user_id IS NOT NULL;
CREATE INDEX idx_doc_perm_org      ON app.document_permissions (org_id)    WHERE org_id  IS NOT NULL;
CREATE UNIQUE INDEX idx_doc_perm_unique_user ON app.document_permissions (document_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_doc_perm_unique_org  ON app.document_permissions (document_id, org_id)  WHERE org_id  IS NOT NULL;

COMMENT ON TABLE app.document_permissions IS
    'Fine-grained ACL for document access control.';

-- =============================================================================
-- TABLE: api_keys
-- API keys for external integrations and machine-to-machine access.
-- =============================================================================
CREATE TABLE app.api_keys (
    key_id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id           UUID        NOT NULL REFERENCES app.organisations (org_id) ON DELETE CASCADE,
    created_by       UUID        NOT NULL REFERENCES app.users (user_id),
    name             TEXT        NOT NULL,
    description      TEXT,
    -- the actual key is stored hashed; the plaintext is shown only at creation time
    key_prefix       TEXT        NOT NULL,            -- first 8 chars, e.g. "dm_live_"
    key_hash         TEXT        NOT NULL UNIQUE,     -- bcrypt hash of the full key
    -- scopes
    scopes           TEXT[]      NOT NULL DEFAULT '{"documents:read"}',
    -- rate limits override (null = use org defaults)
    rate_limit_rpm   INTEGER,
    rate_limit_rpd   INTEGER,
    -- lifecycle
    status           TEXT        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'revoked', 'expired')),
    last_used_at     TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at       TIMESTAMPTZ,
    revoked_by       UUID        REFERENCES app.users (user_id)
);

CREATE INDEX idx_api_keys_org    ON app.api_keys (org_id) WHERE status = 'active';
CREATE INDEX idx_api_keys_prefix ON app.api_keys (key_prefix);
CREATE INDEX idx_api_keys_hash   ON app.api_keys (key_hash);

COMMENT ON TABLE app.api_keys IS
    'API keys for external/M2M access. The plaintext key is never stored.';

-- =============================================================================
-- TABLE: webhook_subscriptions
-- Outbound webhook endpoints that receive DocuMagic event notifications.
-- =============================================================================
CREATE TABLE app.webhook_subscriptions (
    webhook_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id           UUID        NOT NULL REFERENCES app.organisations (org_id) ON DELETE CASCADE,
    created_by       UUID        NOT NULL REFERENCES app.users (user_id),
    name             TEXT        NOT NULL,
    endpoint_url     TEXT        NOT NULL,
    -- HMAC secret for payload signing (stored encrypted)
    signing_secret   TEXT        NOT NULL,
    -- event filtering
    event_types      TEXT[]      NOT NULL DEFAULT '{"document.completed"}',
    -- delivery settings
    status           TEXT        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'paused', 'disabled')),
    retry_count      INTEGER     NOT NULL DEFAULT 3,
    timeout_seconds  INTEGER     NOT NULL DEFAULT 30,
    -- health
    last_triggered_at   TIMESTAMPTZ,
    last_success_at     TIMESTAMPTZ,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    -- timestamps
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhooks_org    ON app.webhook_subscriptions (org_id) WHERE status = 'active';
CREATE INDEX idx_webhooks_events ON app.webhook_subscriptions USING GIN (event_types);

COMMENT ON TABLE app.webhook_subscriptions IS
    'Outbound webhook endpoints for DocuMagic event delivery.';

-- =============================================================================
-- TABLE: billing_events
-- Immutable ledger of chargeable actions (usage-based billing).
-- =============================================================================
CREATE TABLE app.billing_events (
    event_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id           UUID        NOT NULL REFERENCES app.organisations (org_id) ON DELETE RESTRICT,
    user_id          UUID        REFERENCES app.users (user_id),
    -- event classification
    event_type       TEXT        NOT NULL
                     CHECK (event_type IN (
                       'document_upload', 'document_textract_page', 'bedrock_input_token',
                       'bedrock_output_token', 'opensearch_query', 'api_call', 'storage_gb_hour'
                     )),
    -- quantity
    quantity         NUMERIC(18,6) NOT NULL DEFAULT 1,
    unit             TEXT        NOT NULL,            -- pages, tokens, calls, gb_hours
    unit_price_usd   NUMERIC(12,8),
    total_usd        NUMERIC(12,4) GENERATED ALWAYS AS (quantity * COALESCE(unit_price_usd, 0)) STORED,
    -- reference
    document_id      UUID        REFERENCES app.documents (document_id),
    request_id       TEXT,
    -- billing period
    billing_period   TEXT        NOT NULL,            -- YYYY-MM
    -- timestamps
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (occurred_at);

-- Monthly partitions (create 12 months ahead, drop old ones)
CREATE TABLE app.billing_events_2025_01 PARTITION OF app.billing_events
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE app.billing_events_2025_02 PARTITION OF app.billing_events
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE app.billing_events_2026_01 PARTITION OF app.billing_events
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE app.billing_events_2026_02 PARTITION OF app.billing_events
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE app.billing_events_2026_03 PARTITION OF app.billing_events
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE INDEX idx_billing_org_period ON app.billing_events (org_id, billing_period);
CREATE INDEX idx_billing_type       ON app.billing_events (event_type, occurred_at DESC);
CREATE INDEX idx_billing_document   ON app.billing_events (document_id) WHERE document_id IS NOT NULL;

COMMENT ON TABLE app.billing_events IS
    'Immutable usage ledger for usage-based billing. Partitioned by month.';

-- =============================================================================
-- TABLE: audit_log
-- Compliance-grade audit trail for all write operations (PostgreSQL side).
-- High-volume reads go to OpenSearch audit-log index.
-- =============================================================================
CREATE TABLE app.audit_log (
    log_id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- actor
    org_id           UUID        REFERENCES app.organisations (org_id),
    user_id          UUID        REFERENCES app.users (user_id),
    api_key_id       UUID        REFERENCES app.api_keys (key_id),
    ip_address       INET,
    user_agent       TEXT,
    -- action
    action           TEXT        NOT NULL,            -- e.g. document.upload, user.login
    resource_type    TEXT        NOT NULL,
    resource_id      TEXT,
    -- outcome
    outcome          TEXT        NOT NULL CHECK (outcome IN ('success', 'failure', 'error')),
    http_status_code INTEGER,
    error_code       TEXT,
    error_message    TEXT,
    -- payload snapshot (hashed for integrity)
    changes_json     JSONB,                           -- {before: {…}, after: {…}}
    request_id       TEXT,
    -- timestamp
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (occurred_at);

CREATE TABLE app.audit_log_2025_q1 PARTITION OF app.audit_log
    FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');
CREATE TABLE app.audit_log_2025_q2 PARTITION OF app.audit_log
    FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');
CREATE TABLE app.audit_log_2026_q1 PARTITION OF app.audit_log
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
CREATE TABLE app.audit_log_2026_q2 PARTITION OF app.audit_log
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

CREATE INDEX idx_audit_org_time      ON app.audit_log (org_id, occurred_at DESC);
CREATE INDEX idx_audit_user_time     ON app.audit_log (user_id, occurred_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX idx_audit_resource      ON app.audit_log (resource_type, resource_id, occurred_at DESC);
CREATE INDEX idx_audit_action        ON app.audit_log (action, occurred_at DESC);
CREATE INDEX idx_audit_outcome       ON app.audit_log (outcome) WHERE outcome != 'success';

COMMENT ON TABLE app.audit_log IS
    'Compliance-grade audit log for all write operations. Partitioned by quarter.';

-- =============================================================================
-- TABLE: pipeline_runs
-- Execution history of the document processing Step Functions pipeline.
-- =============================================================================
CREATE TABLE app.pipeline_runs (
    run_id           TEXT        PRIMARY KEY,         -- Step Functions execution ARN suffix
    document_id      UUID        NOT NULL REFERENCES app.documents (document_id) ON DELETE CASCADE,
    org_id           UUID        NOT NULL REFERENCES app.organisations (org_id),
    -- state machine
    state_machine_arn TEXT       NOT NULL,
    execution_arn    TEXT        NOT NULL UNIQUE,
    -- stages
    status           TEXT        NOT NULL DEFAULT 'running'
                     CHECK (status IN ('running', 'succeeded', 'failed', 'timed_out', 'aborted')),
    current_state    TEXT,
    -- timing
    started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    succeeded_at     TIMESTAMPTZ,
    failed_at        TIMESTAMPTZ,
    duration_ms      INTEGER     GENERATED ALWAYS AS (
                       EXTRACT(EPOCH FROM (COALESCE(succeeded_at, failed_at) - started_at)) * 1000
                     ) STORED,
    -- error
    error_cause      TEXT,
    error_details    JSONB,
    -- retry tracking
    attempt_number   INTEGER     NOT NULL DEFAULT 1,
    -- stage durations (ms)
    textract_duration_ms  INTEGER,
    bedrock_duration_ms   INTEGER,
    opensearch_duration_ms INTEGER
);

CREATE INDEX idx_pipeline_document ON app.pipeline_runs (document_id);
CREATE INDEX idx_pipeline_org      ON app.pipeline_runs (org_id, started_at DESC);
CREATE INDEX idx_pipeline_status   ON app.pipeline_runs (status) WHERE status = 'running';

COMMENT ON TABLE app.pipeline_runs IS
    'Execution history of the document AI processing pipeline.';

-- =============================================================================
-- Triggers – updated_at maintenance
-- =============================================================================
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_organisations_updated_at
  BEFORE UPDATE ON app.organisations
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_documents_updated_at
  BEFORE UPDATE ON app.documents
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_webhook_updated_at
  BEFORE UPDATE ON app.webhook_subscriptions
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- =============================================================================
-- Views – convenience
-- =============================================================================

-- Active users with their organisation name
CREATE VIEW app.v_active_users AS
SELECT
    u.user_id,
    u.cognito_sub,
    u.email,
    u.display_name,
    u.role,
    u.status AS user_status,
    o.org_id,
    o.name     AS org_name,
    o.plan_tier,
    o.status   AS org_status,
    u.last_login_at,
    u.created_at
FROM app.users        u
JOIN app.organisations o ON o.org_id = u.org_id
WHERE u.deleted_at IS NULL
  AND o.deleted_at IS NULL;

-- Document processing funnel (last 30 days)
CREATE VIEW app.v_document_funnel AS
SELECT
    org_id,
    DATE_TRUNC('day', uploaded_at) AS day,
    COUNT(*) FILTER (WHERE status = 'uploaded')   AS uploaded,
    COUNT(*) FILTER (WHERE status = 'processing') AS processing,
    COUNT(*) FILTER (WHERE status = 'completed')  AS completed,
    COUNT(*) FILTER (WHERE status = 'failed')     AS failed,
    ROUND(AVG(EXTRACT(EPOCH FROM (processed_at - uploaded_at))), 1) AS avg_processing_sec
FROM app.documents
WHERE uploaded_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, DATE_TRUNC('day', uploaded_at);

-- Monthly usage summary per organisation
CREATE VIEW app.v_monthly_usage AS
SELECT
    org_id,
    billing_period,
    event_type,
    SUM(quantity)   AS total_quantity,
    SUM(total_usd)  AS total_usd
FROM app.billing_events
GROUP BY org_id, billing_period, event_type;
