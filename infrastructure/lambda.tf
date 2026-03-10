# =============================================================================
# DocuMagic – Lambda Functions
# textract-processor | bedrock-processor | opensearch-indexer | rag-api | a2a-api
# =============================================================================
#
# NOTE: Each function expects a deployment package at the path referenced by
# `filename`. During CI/CD replace these local paths with data sources that
# fetch the artifact from S3, or use `s3_bucket` / `s3_key` attributes.
#
# The archive_file data source below creates a minimal stub ZIP that allows
# `terraform plan` to succeed before actual code is available.

locals {
  lambda_env_common = {
    ENVIRONMENT              = var.environment
    AWS_REGION_NAME          = var.aws_region
    S3_RAW_BUCKET            = aws_s3_bucket.raw_ingest.id
    S3_PROCESSED_BUCKET      = aws_s3_bucket.processed.id
    S3_KB_BUCKET             = aws_s3_bucket.knowledge_base.id
    DYNAMODB_DOCUMENTS_TABLE = aws_dynamodb_table.documents.id
    DYNAMODB_SESSIONS_TABLE  = aws_dynamodb_table.sessions.id
    DYNAMODB_KB_TABLE        = aws_dynamodb_table.knowledge_base.id
    OPENSEARCH_ENDPOINT      = "https://${aws_opensearch_domain.documagic.endpoint}"
    BEDROCK_MODEL_ID         = var.bedrock_agent_model_id
    BEDROCK_KB_ID            = aws_bedrockagent_knowledge_base.documagic.id
    EVENTBRIDGE_BUS_NAME     = aws_cloudwatch_event_bus.documagic.name
    STEP_FUNCTION_ARN        = aws_sfn_state_machine.document_pipeline.arn
    TEXTRACT_SNS_ROLE_ARN    = aws_iam_role.textract_sns.arn
    TEXTRACT_SNS_TOPIC_ARN   = aws_sns_topic.textract_completion.arn
  }
}

# ---------------------------------------------------------------------------
# Stub deployment package (replaced by real code in CI/CD)
# ---------------------------------------------------------------------------
data "archive_file" "lambda_stub" {
  type        = "zip"
  output_path = "${path.module}/.lambda_stub.zip"

  source {
    content  = "def handler(event, context): return {'statusCode': 200, 'body': 'stub'}"
    filename = "lambda_function.py"
  }
}

# ---------------------------------------------------------------------------
# 1. Textract Processor Lambda
#    Triggered by: S3 (new upload) or API Gateway POST /documents
#    Calls: Amazon Textract (async), publishes EventBridge event on completion
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "textract_processor" {
  function_name = "${local.name_prefix}-textract-processor"
  description   = "Triggers async Textract jobs for newly uploaded documents"

  role    = aws_iam_role.lambda_execution.arn
  runtime = var.lambda_runtime
  handler = "lambda_function.handler"
  timeout = var.lambda_timeout
  memory_size = var.lambda_memory_size

  filename         = data.archive_file.lambda_stub.output_path
  source_code_hash = data.archive_file.lambda_stub.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(local.lambda_env_common, {
      FUNCTION_NAME = "textract-processor"
    })
  }

  tracing_config { mode = "Active" }

  layers = []

  tags = { Name = "${local.name_prefix}-textract-processor" }

  depends_on = [
    aws_iam_role_policy.lambda_shared,
    aws_cloudwatch_log_group.lambda_textract_processor
  ]
}

resource "aws_cloudwatch_log_group" "lambda_textract_processor" {
  name              = "/aws/lambda/${local.name_prefix}-textract-processor"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# 2. Bedrock Processor Lambda
#    Triggered by: Step Functions, EventBridge (Textract completion)
#    Calls: Amazon Bedrock (Claude), Amazon Comprehend, DynamoDB, S3
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "bedrock_processor" {
  function_name = "${local.name_prefix}-bedrock-processor"
  description   = "Invokes Bedrock Claude for document enrichment and entity extraction"

  role        = aws_iam_role.lambda_execution.arn
  runtime     = var.lambda_runtime
  handler     = "lambda_function.handler"
  timeout     = var.lambda_timeout
  memory_size = 1024

  filename         = data.archive_file.lambda_stub.output_path
  source_code_hash = data.archive_file.lambda_stub.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(local.lambda_env_common, {
      FUNCTION_NAME = "bedrock-processor"
    })
  }

  tracing_config { mode = "Active" }

  tags = { Name = "${local.name_prefix}-bedrock-processor" }

  depends_on = [
    aws_iam_role_policy.lambda_shared,
    aws_cloudwatch_log_group.lambda_bedrock_processor
  ]
}

resource "aws_cloudwatch_log_group" "lambda_bedrock_processor" {
  name              = "/aws/lambda/${local.name_prefix}-bedrock-processor"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# 3. OpenSearch Indexer Lambda
#    Triggered by: Step Functions (after Bedrock enrichment)
#    Calls: OpenSearch Service (index enriched document chunks)
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "opensearch_indexer" {
  function_name = "${local.name_prefix}-opensearch-indexer"
  description   = "Indexes enriched document chunks into OpenSearch for RAG retrieval"

  role        = aws_iam_role.lambda_execution.arn
  runtime     = var.lambda_runtime
  handler     = "lambda_function.handler"
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  filename         = data.archive_file.lambda_stub.output_path
  source_code_hash = data.archive_file.lambda_stub.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(local.lambda_env_common, {
      FUNCTION_NAME        = "opensearch-indexer"
      OPENSEARCH_INDEX     = "documagic-documents"
      OPENSEARCH_KB_INDEX  = "documagic-knowledge-base"
    })
  }

  tracing_config { mode = "Active" }

  tags = { Name = "${local.name_prefix}-opensearch-indexer" }

  depends_on = [
    aws_iam_role_policy.lambda_shared,
    aws_cloudwatch_log_group.lambda_opensearch_indexer
  ]
}

resource "aws_cloudwatch_log_group" "lambda_opensearch_indexer" {
  name              = "/aws/lambda/${local.name_prefix}-opensearch-indexer"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# 4. RAG API Lambda
#    Triggered by: API Gateway POST /query and GET /documents/{documentId}
#    Calls: Bedrock RetrieveAndGenerate, OpenSearch, DynamoDB
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "rag_api" {
  function_name = "${local.name_prefix}-rag-api"
  description   = "Retrieval-Augmented Generation API – answers questions from the knowledge base"

  role        = aws_iam_role.lambda_execution.arn
  runtime     = var.lambda_runtime
  handler     = "lambda_function.handler"
  timeout     = 60
  memory_size = 1024

  filename         = data.archive_file.lambda_stub.output_path
  source_code_hash = data.archive_file.lambda_stub.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(local.lambda_env_common, {
      FUNCTION_NAME    = "rag-api"
      OPENSEARCH_INDEX = "documagic-documents"
    })
  }

  tracing_config { mode = "Active" }

  tags = { Name = "${local.name_prefix}-rag-api" }

  depends_on = [
    aws_iam_role_policy.lambda_shared,
    aws_cloudwatch_log_group.lambda_rag_api
  ]
}

resource "aws_cloudwatch_log_group" "lambda_rag_api" {
  name              = "/aws/lambda/${local.name_prefix}-rag-api"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# 5. Agent-to-Agent (A2A) API Lambda
#    Triggered by: API Gateway POST /agents/{agentId}/invoke
#    Calls: Bedrock Agent, other Lambda functions (fan-out)
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "a2a_api" {
  function_name = "${local.name_prefix}-a2a-api"
  description   = "Agent-to-Agent API – routes requests between AI agents"

  role        = aws_iam_role.lambda_execution.arn
  runtime     = var.lambda_runtime
  handler     = "lambda_function.handler"
  timeout     = 120
  memory_size = 512

  filename         = data.archive_file.lambda_stub.output_path
  source_code_hash = data.archive_file.lambda_stub.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(local.lambda_env_common, {
      FUNCTION_NAME      = "a2a-api"
      BEDROCK_AGENT_ID   = aws_bedrockagent_agent.documagic.agent_id
      BEDROCK_AGENT_ALIAS_ID = aws_bedrockagent_agent_alias.documagic.agent_alias_id
    })
  }

  tracing_config { mode = "Active" }

  tags = { Name = "${local.name_prefix}-a2a-api" }

  depends_on = [
    aws_iam_role_policy.lambda_shared,
    aws_cloudwatch_log_group.lambda_a2a_api
  ]
}

resource "aws_cloudwatch_log_group" "lambda_a2a_api" {
  name              = "/aws/lambda/${local.name_prefix}-a2a-api"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# MSK → Lambda event source mapping (Kafka consumer)
# ---------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "msk_to_textract" {
  event_source_arn  = aws_msk_cluster.documagic.arn
  function_name     = aws_lambda_function.textract_processor.arn
  starting_position = "LATEST"

  topics = ["documagic.documents.ingest"]

  batch_size                         = 100
  maximum_batching_window_in_seconds = 30

  source_access_configuration {
    type = "VPC_SUBNET"
    uri  = "subnet:${aws_subnet.private[0].id}"
  }

  source_access_configuration {
    type = "VPC_SECURITY_GROUP"
    uri  = "security_group:${aws_security_group.msk.id}"
  }
}
