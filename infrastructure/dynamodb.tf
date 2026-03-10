# =============================================================================
# DocuMagic – DynamoDB Tables
# documents | sessions | knowledge-base
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

# ---------------------------------------------------------------------------
# DynamoDB Stream ARN output (stream enabled on the documents table above)
# ---------------------------------------------------------------------------
# To consume the stream, create an aws_lambda_event_source_mapping pointing
# to aws_dynamodb_table.documents.stream_arn using aws_lambda_function.bedrock_processor.
# This pattern forwards document state changes to downstream processors
# without polling DynamoDB directly.
