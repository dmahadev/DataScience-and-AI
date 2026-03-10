# =============================================================================
# DocuMagic – IAM Roles & Policies
# =============================================================================

# ---------------------------------------------------------------------------
# Shared assume-role policy documents
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "bedrock_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Lambda – base execution role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_execution" {
  name               = "${local.name_prefix}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Inline policy – permissions needed by ALL Lambda functions
resource "aws_iam_role_policy" "lambda_shared" {
  name = "${local.name_prefix}-lambda-shared"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_ingest.arn,
          "${aws_s3_bucket.raw_ingest.arn}/*",
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/*",
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.documents.arn,
          "${aws_dynamodb_table.documents.arn}/index/*",
          aws_dynamodb_table.sessions.arn,
          "${aws_dynamodb_table.sessions.arn}/index/*",
          aws_dynamodb_table.knowledge_base.arn,
          "${aws_dynamodb_table.knowledge_base.arn}/index/*"
        ]
      },
      {
        Sid    = "BedrockAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:RetrieveAndGenerate",
          "bedrock:Retrieve"
        ]
        Resource = "*"
      },
      {
        Sid    = "TextractAccess"
        Effect = "Allow"
        Action = [
          "textract:StartDocumentTextDetection",
          "textract:StartDocumentAnalysis",
          "textract:GetDocumentTextDetection",
          "textract:GetDocumentAnalysis",
          "textract:AnalyzeDocument"
        ]
        Resource = "*"
      },
      {
        Sid    = "ComprehendAccess"
        Effect = "Allow"
        Action = [
          "comprehend:DetectEntities",
          "comprehend:DetectKeyPhrases",
          "comprehend:DetectSentiment",
          "comprehend:ClassifyDocument",
          "comprehend:DetectPiiEntities"
        ]
        Resource = "*"
      },
      {
        Sid    = "OpenSearchAccess"
        Effect = "Allow"
        Action = ["es:ESHttp*"]
        Resource = "${aws_opensearch_domain.documagic.arn}/*"
      },
      {
        Sid    = "MSKAccess"
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers",
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData"
        ]
        Resource = [
          aws_msk_cluster.documagic.arn,
          "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${aws_msk_cluster.documagic.cluster_name}/*",
          "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:group/${aws_msk_cluster.documagic.cluster_name}/*"
        ]
      },
      {
        Sid    = "EventBridgePublish"
        Effect = "Allow"
        Action = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.documagic.arn
      },
      {
        Sid    = "StepFunctionsStart"
        Effect = "Allow"
        Action = ["states:StartExecution"]
        Resource = aws_sfn_state_machine.document_pipeline.arn
      },
      {
        Sid    = "SSMGetParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/documagic/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Step Functions execution role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "step_functions" {
  name               = "${local.name_prefix}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${local.name_prefix}-sfn-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.textract_processor.arn,
          aws_lambda_function.bedrock_processor.arn,
          aws_lambda_function.opensearch_indexer.arn
        ]
      },
      {
        Sid      = "BedrockAccess"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Bedrock knowledge-base / agent role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "bedrock_kb" {
  name               = "${local.name_prefix}-bedrock-kb-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_assume_role.json
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name = "${local.name_prefix}-bedrock-kb-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3KBAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
      {
        Sid      = "OpenSearchAccess"
        Effect   = "Allow"
        Action   = ["es:ESHttp*"]
        Resource = "${aws_opensearch_domain.documagic.arn}/*"
      },
      {
        Sid    = "BedrockEmbeddings"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_foundation_model_id}"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# EventBridge – invoke Step Functions
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge_sfn" {
  name               = "${local.name_prefix}-eventbridge-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  name = "${local.name_prefix}-eventbridge-sfn-policy"
  role = aws_iam_role.eventbridge_sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.document_pipeline.arn
    }]
  })
}

# ---------------------------------------------------------------------------
# Textract – SNS notification role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "textract_sns" {
  name = "${local.name_prefix}-textract-sns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "textract.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "textract_sns" {
  name = "${local.name_prefix}-textract-sns-policy"
  role = aws_iam_role.textract_sns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = aws_sns_topic.textract_completion.arn
    }]
  })
}
