# =============================================================================
# DocuMagic – CloudWatch: Log Groups, Metric Alarms, Dashboard, SNS
# =============================================================================

# ---------------------------------------------------------------------------
# SNS Topic for alarms
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name              = "${local.name_prefix}-alarms"
  kms_master_key_id = "alias/aws/sns"

  tags = { Name = "${local.name_prefix}-alarms" }
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------------------------------------------------------
# Log Groups
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${local.name_prefix}-document-pipeline"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/aws/mskconnect/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "opensearch_index" {
  name              = "/aws/opensearch/${local.name_prefix}/index-slow-logs"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "opensearch_search" {
  name              = "/aws/opensearch/${local.name_prefix}/search-slow-logs"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "opensearch_app" {
  name              = "/aws/opensearch/${local.name_prefix}/application-logs"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# CloudWatch Metric Alarms
# ---------------------------------------------------------------------------

# Lambda – Textract processor errors
resource "aws_cloudwatch_metric_alarm" "lambda_textract_errors" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-textract-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Textract processor Lambda is throwing too many errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.textract_processor.function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Lambda – RAG API throttling
resource "aws_cloudwatch_metric_alarm" "lambda_rag_throttles" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-rag-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "RAG API Lambda is being throttled"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.rag_api.function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

# Lambda – A2A API duration (p99 > 10 s)
resource "aws_cloudwatch_metric_alarm" "lambda_a2a_duration" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-a2a-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  extended_statistic  = "p99"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  threshold           = 10000 # ms
  alarm_description   = "A2A API Lambda p99 duration exceeds 10 seconds"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.a2a_api.function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

# API Gateway – 5xx errors
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-apigw-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway is returning too many 5xx errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.documagic.name
    Stage   = aws_api_gateway_stage.documagic.stage_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Step Functions – execution failures
resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-sfn-execution-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Document pipeline Step Functions has multiple execution failures"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.document_pipeline.arn
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# OpenSearch – cluster status red
resource "aws_cloudwatch_metric_alarm" "opensearch_red" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-cluster-red"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "OpenSearch cluster status is RED"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.documagic.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# MSK – under-replicated partitions
resource "aws_cloudwatch_metric_alarm" "msk_under_replicated" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-msk-under-replicated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "MSK cluster has under-replicated partitions"
  treat_missing_data  = "notBreaching"

  dimensions = {
    "Cluster Name" = aws_msk_cluster.documagic.cluster_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# CloudWatch Dashboard
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "documagic" {
  count          = var.enable_enhanced_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# DocuMagic – Agentic AI Architecture Dashboard\nEnvironment: **${var.environment}** | Region: **${var.aws_region}**"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "API Gateway – Request Count"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.documagic.name, "Stage", var.api_gateway_stage_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "API Gateway – Latency (p99)"
          period = 300
          stat   = "p99"
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.documagic.name, "Stage", var.api_gateway_stage_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "API Gateway – 5xx Errors"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.documagic.name, "Stage", var.api_gateway_stage_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Lambda – Invocations"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.textract_processor.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.bedrock_processor.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.opensearch_indexer.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.rag_api.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.a2a_api.function_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Lambda – Errors"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.textract_processor.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.bedrock_processor.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.rag_api.function_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Step Functions – Executions"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", aws_sfn_state_machine.document_pipeline.arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.document_pipeline.arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.document_pipeline.arn]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "OpenSearch – Cluster Health"
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/ES", "ClusterStatus.green", "DomainName", aws_opensearch_domain.documagic.domain_name, "ClientId", data.aws_caller_identity.current.account_id],
            ["AWS/ES", "ClusterStatus.yellow", "DomainName", aws_opensearch_domain.documagic.domain_name, "ClientId", data.aws_caller_identity.current.account_id],
            ["AWS/ES", "ClusterStatus.red", "DomainName", aws_opensearch_domain.documagic.domain_name, "ClientId", data.aws_caller_identity.current.account_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "MSK – Bytes In/Out"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/Kafka", "BytesInPerSec", "Cluster Name", aws_msk_cluster.documagic.cluster_name],
            ["AWS/Kafka", "BytesOutPerSec", "Cluster Name", aws_msk_cluster.documagic.cluster_name]
          ]
        }
      }
    ]
  })
}
