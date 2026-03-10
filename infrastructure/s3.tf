# =============================================================================
# DocuMagic – S3 Buckets
# raw-ingest | processed | knowledge-base | amplify-artifacts
# =============================================================================

locals {
  account_id = data.aws_caller_identity.current.account_id

  raw_bucket_name  = var.s3_raw_bucket_name != "" ? var.s3_raw_bucket_name : "${lower(local.name_prefix)}-raw-ingest-${local.account_id}"
  proc_bucket_name = var.s3_processed_bucket_name != "" ? var.s3_processed_bucket_name : "${lower(local.name_prefix)}-processed-${local.account_id}"
  kb_bucket_name   = var.s3_knowledge_base_bucket_name != "" ? var.s3_knowledge_base_bucket_name : "${lower(local.name_prefix)}-knowledge-base-${local.account_id}"
}

# ---------------------------------------------------------------------------
# 1. Raw Ingest Bucket – stores documents uploaded via API / Amplify / email
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "raw_ingest" {
  bucket        = local.raw_bucket_name
  force_destroy = var.environment != "production"

  tags = { Name = "${local.name_prefix}-raw-ingest" }
}

resource "aws_s3_bucket_versioning" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw_ingest" {
  bucket                  = aws_s3_bucket.raw_ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id

  rule {
    id     = "archive-raw"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    expiration {
      days = 365
    }
  }
}

# Trigger Lambda on new document uploads
resource "aws_s3_bucket_notification" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.textract_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_textract]
}

resource "aws_lambda_permission" "s3_invoke_textract" {
  statement_id  = "AllowS3InvokeTextract"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_ingest.arn
}

# ---------------------------------------------------------------------------
# 2. Processed Bucket – stores Textract output and enriched documents
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "processed" {
  bucket        = local.proc_bucket_name
  force_destroy = var.environment != "production"

  tags = { Name = "${local.name_prefix}-processed" }
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "archive-processed"
    status = "Enabled"

    transition {
      days          = 60
      storage_class = "INTELLIGENT_TIERING"
    }

    expiration {
      days = 730
    }
  }
}

# ---------------------------------------------------------------------------
# 3. Knowledge-Base Bucket – Bedrock knowledge-base data source
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "knowledge_base" {
  bucket        = local.kb_bucket_name
  force_destroy = var.environment != "production"

  tags = { Name = "${local.name_prefix}-knowledge-base" }
}

resource "aws_s3_bucket_versioning" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "knowledge_base" {
  bucket                  = aws_s3_bucket.knowledge_base.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bedrock must be allowed to read from this bucket
resource "aws_s3_bucket_policy" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockKBAccess"
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.knowledge_base.arn,
        "${aws_s3_bucket.knowledge_base.arn}/*"
      ]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# 4. Amplify Artifacts Bucket – CI/CD build artifacts
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "amplify_artifacts" {
  bucket        = "${lower(local.name_prefix)}-amplify-artifacts-${local.account_id}"
  force_destroy = true

  tags = { Name = "${local.name_prefix}-amplify-artifacts" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "amplify_artifacts" {
  bucket = aws_s3_bucket.amplify_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "amplify_artifacts" {
  bucket                  = aws_s3_bucket.amplify_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
