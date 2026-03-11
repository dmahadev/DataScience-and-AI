# =============================================================================
# DocuMagic – DynamoDB Tables (NoSQL Tier)
# ─────────────────────────────────────────────────────────────────────────────
# Core tables (document pipeline):
#   1. documents       – document metadata, Textract job status, enrichment state
#   2. sessions        – user conversation / chat sessions for multi-turn RAG
#   3. knowledge-base  – ingested KB chunk records and embeddings metadata
#
# Agentic AI tables:
#   4. agent-conversations – full multi-turn conversation history per agent session
#   5. agent-tasks         – agentic task queue, status, and result tracking
#
# Platform tables:
#   6. rate-limits     – sliding-window API rate-limit counters (TTL-driven)
#   7. tenant-config   – per-organisation (tenant) configuration and feature flags
# =============================================================================

# ---------------------------------------------------------------------------
# 1. Documents Table – document metadata, Textract job status, enrichment state
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "documents" {
  name         = "${local.name_prefix}-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "documentId"
  range_key    = "version"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "documentId"
    type = "S"
  }

  attribute {
    name = "version"
    type = "N"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # GSI: look up all documents for a user
  global_secondary_index {
    name            = "userId-createdAt-index"
    hash_key        = "userId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # GSI: look up all documents in a given status (e.g., PROCESSING)
  global_secondary_index {
    name            = "status-createdAt-index"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "INCLUDE"
    non_key_attributes = ["documentId", "userId", "s3Key", "version"]
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${local.name_prefix}-documents" }
}

# ---------------------------------------------------------------------------
# 2. Sessions Table – user conversation / chat sessions for multi-turn RAG
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "sessions" {
  name         = "${local.name_prefix}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"

  attribute {
    name = "sessionId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "updatedAt"
    type = "S"
  }

  global_secondary_index {
    name            = "userId-updatedAt-index"
    hash_key        = "userId"
    range_key       = "updatedAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${local.name_prefix}-sessions" }
}

# ---------------------------------------------------------------------------
# 3. Knowledge-Base Table – record of ingested KB chunks, embeddings metadata
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "knowledge_base" {
  name         = "${local.name_prefix}-knowledge-base"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "chunkId"

  attribute {
    name = "chunkId"
    type = "S"
  }

  attribute {
    name = "documentId"
    type = "S"
  }

  attribute {
    name = "indexedAt"
    type = "S"
  }

  global_secondary_index {
    name            = "documentId-indexedAt-index"
    hash_key        = "documentId"
    range_key       = "indexedAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-knowledge-base" }
}

# =============================================================================
# 4. Agent Conversations Table
#    Access patterns:
#      - Get conversation by sessionId (PK)
#      - List all turns in a conversation ordered by turnIndex (SK)
#      - List all conversations for a user (GSI: userId-startedAt)
#      - List all conversations for a Bedrock agent (GSI: agentId-updatedAt)
# =============================================================================
resource "aws_dynamodb_table" "agent_conversations" {
  name         = "${local.name_prefix}-agent-conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"
  range_key    = "turnIndex"

  attribute {
    name = "sessionId"
    type = "S"
  }

  attribute {
    name = "turnIndex"
    type = "N"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "agentId"
    type = "S"
  }

  attribute {
    name = "startedAt"
    type = "S"
  }

  attribute {
    name = "updatedAt"
    type = "S"
  }

  # GSI: all conversations for a user, sorted by start time
  global_secondary_index {
    name            = "userId-startedAt-index"
    hash_key        = "userId"
    range_key       = "startedAt"
    projection_type = "INCLUDE"
    non_key_attributes = ["sessionId", "agentId", "status", "title", "updatedAt"]
  }

  # GSI: all conversations for a specific agent, sorted by last update
  global_secondary_index {
    name            = "agentId-updatedAt-index"
    hash_key        = "agentId"
    range_key       = "updatedAt"
    projection_type = "INCLUDE"
    non_key_attributes = ["sessionId", "userId", "status", "turnIndex"]
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${local.name_prefix}-agent-conversations" }
}

# =============================================================================
# 5. Agent Tasks Table
#    Access patterns:
#      - Get task by taskId (PK)
#      - List all tasks for a session (GSI: sessionId-createdAt)
#      - List tasks in a given status (GSI: status-createdAt) for workers
#      - List tasks assigned to an agent (GSI: agentId-createdAt)
# =============================================================================
resource "aws_dynamodb_table" "agent_tasks" {
  name         = "${local.name_prefix}-agent-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "taskId"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "taskId"
    type = "S"
  }

  attribute {
    name = "sessionId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "agentId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # GSI: all tasks for a conversation session, ordered by creation time
  global_secondary_index {
    name            = "sessionId-createdAt-index"
    hash_key        = "sessionId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # GSI: pending / in-flight tasks across all sessions (worker polling)
  global_secondary_index {
    name            = "status-createdAt-index"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "INCLUDE"
    non_key_attributes = ["taskId", "sessionId", "agentId", "taskType", "priority"]
  }

  # GSI: tasks routed to a specific agent
  global_secondary_index {
    name            = "agentId-createdAt-index"
    hash_key        = "agentId"
    range_key       = "createdAt"
    projection_type = "INCLUDE"
    non_key_attributes = ["taskId", "sessionId", "status", "taskType"]
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${local.name_prefix}-agent-tasks" }
}

# =============================================================================
# 6. Rate Limits Table
#    Access pattern:
#      - Get / update counter by compositeKey = "{orgId}#{userId}#{endpoint}"
#      - TTL expires counters at the end of the window automatically
#    Single-table design: no GSIs needed – access is always by primary key.
# =============================================================================
resource "aws_dynamodb_table" "rate_limits" {
  name         = "${local.name_prefix}-rate-limits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "compositeKey"
  range_key    = "windowStart"

  attribute {
    name = "compositeKey"
    type = "S"
  }

  attribute {
    name = "windowStart"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "${local.name_prefix}-rate-limits" }
}

# =============================================================================
# 7. Tenant Config Table
#    Access patterns:
#      - Get config for an org (PK = orgId, SK = configKey)
#      - List all config keys for an org (Query PK)
#      - List all orgs with a given plan tier (GSI: planTier-orgId)
# =============================================================================
resource "aws_dynamodb_table" "tenant_config" {
  name         = "${local.name_prefix}-tenant-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orgId"
  range_key    = "configKey"

  attribute {
    name = "orgId"
    type = "S"
  }

  attribute {
    name = "configKey"
    type = "S"
  }

  attribute {
    name = "planTier"
    type = "S"
  }

  # GSI: list all organisations on a given plan tier
  global_secondary_index {
    name            = "planTier-orgId-index"
    hash_key        = "planTier"
    range_key       = "orgId"
    projection_type = "INCLUDE"
    non_key_attributes = ["configKey", "configValue", "updatedAt", "featureFlags"]
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-tenant-config" }
}

# ---------------------------------------------------------------------------
# DynamoDB Stream ARN output (stream enabled on the documents table above)
# ---------------------------------------------------------------------------
# To consume the stream, create an aws_lambda_event_source_mapping pointing
# to aws_dynamodb_table.documents.stream_arn using aws_lambda_function.bedrock_processor.
# This pattern forwards document state changes to downstream processors
# without polling DynamoDB directly.
