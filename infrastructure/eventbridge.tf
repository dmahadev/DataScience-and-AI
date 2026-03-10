# =============================================================================
# DocuMagic – Amazon EventBridge
# Custom bus | Rules | Targets
# =============================================================================

# ---------------------------------------------------------------------------
# Custom Event Bus
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_bus" "documagic" {
  name = "${local.name_prefix}-event-bus"

  tags = { Name = "${local.name_prefix}-event-bus" }
}

# ---------------------------------------------------------------------------
# Rule 1: S3 new-object via default bus → start Step Functions pipeline
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name           = "${local.name_prefix}-s3-object-created"
  description    = "Triggers document pipeline when a new object is created in the raw-ingest bucket"
  event_bus_name = "default"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.raw_ingest.id]
      }
      object = {
        key = [{ prefix = "uploads/" }]
      }
    }
  })

  tags = { Name = "${local.name_prefix}-s3-object-created" }
}

resource "aws_cloudwatch_event_target" "s3_to_sfn" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "StartDocumentPipeline"
  arn       = aws_sfn_state_machine.document_pipeline.arn
  role_arn  = aws_iam_role.eventbridge_sfn.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
    }
    input_template = <<-EOT
      {
        "documentId": "<key>",
        "s3Bucket": "<bucket>",
        "s3Key": "<key>",
        "sizeBytes": <size>,
        "source": "s3-event"
      }
    EOT
  }
}

# Enable EventBridge notifications on the raw-ingest S3 bucket
resource "aws_s3_bucket_notification" "eventbridge_raw_ingest" {
  bucket      = aws_s3_bucket.raw_ingest.id
  eventbridge = true
}

# ---------------------------------------------------------------------------
# Rule 2: Custom bus – DocumentProcessingCompleted → SNS / downstream
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "pipeline_completed" {
  name           = "${local.name_prefix}-pipeline-completed"
  description    = "Fires when a document pipeline run completes successfully"
  event_bus_name = aws_cloudwatch_event_bus.documagic.name

  event_pattern = jsonencode({
    source      = ["documagic.pipeline"]
    detail-type = ["DocumentProcessingCompleted"]
  })

  tags = { Name = "${local.name_prefix}-pipeline-completed" }
}

resource "aws_cloudwatch_event_target" "pipeline_completed_sns" {
  rule           = aws_cloudwatch_event_rule.pipeline_completed.name
  event_bus_name = aws_cloudwatch_event_bus.documagic.name
  target_id      = "NotifyCompletionSNS"
  arn            = aws_sns_topic.pipeline_events.arn
}

# ---------------------------------------------------------------------------
# Rule 3: Custom bus – DocumentProcessingFailed → alerting
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "pipeline_failed" {
  name           = "${local.name_prefix}-pipeline-failed"
  description    = "Fires when a document pipeline run fails"
  event_bus_name = aws_cloudwatch_event_bus.documagic.name

  event_pattern = jsonencode({
    source      = ["documagic.pipeline"]
    detail-type = ["DocumentProcessingFailed"]
  })

  tags = { Name = "${local.name_prefix}-pipeline-failed" }
}

resource "aws_cloudwatch_event_target" "pipeline_failed_sns" {
  rule           = aws_cloudwatch_event_rule.pipeline_failed.name
  event_bus_name = aws_cloudwatch_event_bus.documagic.name
  target_id      = "AlertFailureSNS"
  arn            = aws_sns_topic.alarms.arn
}

# ---------------------------------------------------------------------------
# Rule 4: Scheduled – nightly knowledge-base sync (Bedrock ingestion job)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "nightly_kb_sync" {
  name                = "${local.name_prefix}-nightly-kb-sync"
  description         = "Triggers nightly Bedrock knowledge-base ingestion job"
  schedule_expression = "cron(0 2 * * ? *)"

  tags = { Name = "${local.name_prefix}-nightly-kb-sync" }
}

resource "aws_cloudwatch_event_target" "nightly_kb_sync_lambda" {
  rule      = aws_cloudwatch_event_rule.nightly_kb_sync.name
  target_id = "NightlyKBSyncLambda"
  arn       = aws_lambda_function.opensearch_indexer.arn

  input = jsonencode({
    action = "sync_knowledge_base"
    source = "scheduled"
  })
}

resource "aws_lambda_permission" "eventbridge_nightly_kb" {
  statement_id  = "AllowEventBridgeNightlyKB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.opensearch_indexer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nightly_kb_sync.arn
}

# ---------------------------------------------------------------------------
# Pipeline events SNS topic
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "pipeline_events" {
  name              = "${local.name_prefix}-pipeline-events"
  kms_master_key_id = "alias/aws/sns"

  tags = { Name = "${local.name_prefix}-pipeline-events" }
}

# Allow EventBridge to publish to the pipeline-events topic
resource "aws_sns_topic_policy" "pipeline_events" {
  arn = aws_sns_topic.pipeline_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgePublish"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "sns:Publish"
      Resource = aws_sns_topic.pipeline_events.arn
    }]
  })
}

# Allow EventBridge to publish to the alarms topic
resource "aws_sns_topic_policy" "alarms_eventbridge" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alarms.arn
      },
      {
        Sid    = "AllowCWAlarmsPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alarms.arn
      }
    ]
  })
}
