# =============================================================================
# DocuMagic – Amazon Textract Configuration
# SNS topic for async job completion | S3 trigger already in s3.tf
# =============================================================================

# ---------------------------------------------------------------------------
# SNS Topic – Textract async job completion notifications
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "textract_completion" {
  name              = "${local.name_prefix}-textract-completion"
  kms_master_key_id = "alias/aws/sns"

  tags = { Name = "${local.name_prefix}-textract-completion" }
}

# Allow Textract to publish to this topic
resource "aws_sns_topic_policy" "textract_completion" {
  arn = aws_sns_topic.textract_completion.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowTextractPublish"
      Effect = "Allow"
      Principal = {
        Service = "textract.amazonaws.com"
      }
      Action   = "sns:Publish"
      Resource = aws_sns_topic.textract_completion.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# SNS → Lambda subscription (Bedrock processor picks up Textract results)
# ---------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "textract_to_bedrock" {
  topic_arn = aws_sns_topic.textract_completion.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.bedrock_processor.arn
}

resource "aws_lambda_permission" "sns_invoke_bedrock" {
  statement_id  = "AllowSNSInvokeBedrock"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bedrock_processor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.textract_completion.arn
}

# ---------------------------------------------------------------------------
# SSM Parameters – Textract configuration stored as Parameters
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "textract_feature_types" {
  name        = "/documagic/textract/feature_types"
  type        = "StringList"
  value       = "TABLES,FORMS,SIGNATURES,LAYOUT"
  description = "Textract feature types to extract from documents"

  tags = { Name = "${local.name_prefix}-textract-feature-types" }
}

resource "aws_ssm_parameter" "textract_output_prefix" {
  name        = "/documagic/textract/output_s3_prefix"
  type        = "String"
  value       = "textract-output/"
  description = "S3 key prefix for Textract async job output"

  tags = { Name = "${local.name_prefix}-textract-output-prefix" }
}
