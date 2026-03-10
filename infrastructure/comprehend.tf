# =============================================================================
# DocuMagic – Amazon Comprehend
# IAM permissions and configuration for NLP enrichment
# (Comprehend is called directly from Lambda; no provisioned resources needed)
# =============================================================================

# ---------------------------------------------------------------------------
# Comprehend IAM policy is already included in iam.tf (lambda_shared policy).
# This file documents the Comprehend usage and provides SSM configuration.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# SSM Parameters – Comprehend configuration
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "comprehend_language_code" {
  name        = "/documagic/comprehend/language_code"
  type        = "String"
  value       = "en"
  description = "Default language code for Amazon Comprehend NLP operations"

  tags = { Name = "${local.name_prefix}-comprehend-lang" }
}

resource "aws_ssm_parameter" "comprehend_entity_types" {
  name        = "/documagic/comprehend/entity_types"
  type        = "StringList"
  value       = "PERSON,ORGANIZATION,LOCATION,DATE,QUANTITY,TITLE,EVENT,OTHER"
  description = "Entity types to extract using Amazon Comprehend"

  tags = { Name = "${local.name_prefix}-comprehend-entities" }
}

resource "aws_ssm_parameter" "comprehend_pii_entity_types" {
  name        = "/documagic/comprehend/pii_entity_types"
  type        = "StringList"
  value       = "NAME,EMAIL,PHONE,ADDRESS,SSN,BANK_ACCOUNT_NUMBER,CREDIT_DEBIT_NUMBER"
  description = "PII entity types to redact using Amazon Comprehend Detect PII Entities"

  tags = { Name = "${local.name_prefix}-comprehend-pii" }
}

# ---------------------------------------------------------------------------
# Comprehend Custom Classifier (optional – for document type classification)
# ---------------------------------------------------------------------------
# Uncomment and configure after training data is available in S3.
#
# resource "aws_comprehend_document_classifier" "document_type" {
#   name                    = "${local.name_prefix}-doc-classifier"
#   data_access_role_arn    = aws_iam_role.comprehend.arn
#   language_code           = "en"
#   mode                    = "MULTI_CLASS"
#
#   input_data_config {
#     data_format = "COMPREHEND_CSV"
#     s3_uri      = "s3://${aws_s3_bucket.knowledge_base.id}/training/classifier/"
#   }
#
#   output_data_config {
#     s3_uri = "s3://${aws_s3_bucket.processed.id}/comprehend/classifier-output/"
#   }
#
#   tags = { Name = "${local.name_prefix}-doc-classifier" }
# }

# ---------------------------------------------------------------------------
# Comprehend IAM role (for async batch jobs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "comprehend" {
  name = "${local.name_prefix}-comprehend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "comprehend.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "comprehend" {
  name = "${local.name_prefix}-comprehend-policy"
  role = aws_iam_role.comprehend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/*",
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/comprehend/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}
