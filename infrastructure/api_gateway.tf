# =============================================================================
# DocuMagic – API Gateway (REST)
# Ingestion endpoint | RAG query | Agent-to-Agent | Cognito Authorizer
# =============================================================================

resource "aws_api_gateway_rest_api" "documagic" {
  name        = "${local.name_prefix}-api"
  description = "DocuMagic Agentic AI – REST API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${local.name_prefix}-api" }
}

# ---------------------------------------------------------------------------
# Cognito JWT Authorizer
# ---------------------------------------------------------------------------
resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${local.name_prefix}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.documagic.id
  type                   = "COGNITO_USER_POOLS"
  identity_source        = "method.request.header.Authorization"
  provider_arns          = [aws_cognito_user_pool.documagic.arn]
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

# /documents
resource "aws_api_gateway_resource" "documents" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_rest_api.documagic.root_resource_id
  path_part   = "documents"
}

# /documents/{documentId}
resource "aws_api_gateway_resource" "document_id" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_resource.documents.id
  path_part   = "{documentId}"
}

# /query
resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_rest_api.documagic.root_resource_id
  path_part   = "query"
}

# /agents
resource "aws_api_gateway_resource" "agents" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_rest_api.documagic.root_resource_id
  path_part   = "agents"
}

# /agents/{agentId}
resource "aws_api_gateway_resource" "agent_id" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_resource.agents.id
  path_part   = "{agentId}"
}

# /agents/{agentId}/invoke
resource "aws_api_gateway_resource" "agent_invoke" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_resource.agent_id.id
  path_part   = "invoke"
}

# /health
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  parent_id   = aws_api_gateway_rest_api.documagic.root_resource_id
  path_part   = "health"
}

# ---------------------------------------------------------------------------
# Methods & Integrations
# ---------------------------------------------------------------------------

# POST /documents – submit a document for ingestion
resource "aws_api_gateway_method" "documents_post" {
  rest_api_id   = aws_api_gateway_rest_api.documagic.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_integration" "documents_post" {
  rest_api_id             = aws_api_gateway_rest_api.documagic.id
  resource_id             = aws_api_gateway_resource.documents.id
  http_method             = aws_api_gateway_method.documents_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.textract_processor.invoke_arn
}

resource "aws_lambda_permission" "apigw_textract" {
  statement_id  = "AllowAPIGWInvokeTextract"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.documagic.execution_arn}/*/*"
}

# GET /documents/{documentId} – retrieve document status
resource "aws_api_gateway_method" "document_get" {
  rest_api_id   = aws_api_gateway_rest_api.documagic.id
  resource_id   = aws_api_gateway_resource.document_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.path.documentId"      = true
  }
}

resource "aws_api_gateway_integration" "document_get" {
  rest_api_id             = aws_api_gateway_rest_api.documagic.id
  resource_id             = aws_api_gateway_resource.document_id.id
  http_method             = aws_api_gateway_method.document_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.rag_api.invoke_arn
}

# POST /query – RAG query against the knowledge base
resource "aws_api_gateway_method" "query_post" {
  rest_api_id   = aws_api_gateway_rest_api.documagic.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_integration" "query_post" {
  rest_api_id             = aws_api_gateway_rest_api.documagic.id
  resource_id             = aws_api_gateway_resource.query.id
  http_method             = aws_api_gateway_method.query_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.rag_api.invoke_arn
}

resource "aws_lambda_permission" "apigw_rag" {
  statement_id  = "AllowAPIGWInvokeRAG"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rag_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.documagic.execution_arn}/*/*"
}

# POST /agents/{agentId}/invoke – Agent-to-Agent (A2A) invocation
resource "aws_api_gateway_method" "agent_invoke_post" {
  rest_api_id   = aws_api_gateway_rest_api.documagic.id
  resource_id   = aws_api_gateway_resource.agent_invoke.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.path.agentId"         = true
  }
}

resource "aws_api_gateway_integration" "agent_invoke_post" {
  rest_api_id             = aws_api_gateway_rest_api.documagic.id
  resource_id             = aws_api_gateway_resource.agent_invoke.id
  http_method             = aws_api_gateway_method.agent_invoke_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.a2a_api.invoke_arn
}

resource "aws_lambda_permission" "apigw_a2a" {
  statement_id  = "AllowAPIGWInvokeA2A"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.a2a_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.documagic.execution_arn}/*/*"
}

# GET /health – unauthenticated health probe
resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.documagic.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health_get" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "health_get_200" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "health_get_200" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method
  status_code = "200"
  depends_on  = [aws_api_gateway_integration.health_get]
}

# ---------------------------------------------------------------------------
# Deployment & Stage
# ---------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "documagic" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.documents.id,
      aws_api_gateway_resource.query.id,
      aws_api_gateway_resource.agents.id,
      aws_api_gateway_method.documents_post.id,
      aws_api_gateway_method.query_post.id,
      aws_api_gateway_method.agent_invoke_post.id,
      aws_api_gateway_method.health_get.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.documents_post,
    aws_api_gateway_integration.query_post,
    aws_api_gateway_integration.agent_invoke_post,
    aws_api_gateway_integration.health_get,
  ]
}

resource "aws_api_gateway_stage" "documagic" {
  deployment_id = aws_api_gateway_deployment.documagic.id
  rest_api_id   = aws_api_gateway_rest_api.documagic.id
  stage_name    = var.api_gateway_stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  xray_tracing_enabled = true

  tags = { Name = "${local.name_prefix}-api-stage-${var.api_gateway_stage_name}" }
}

# Enable detailed metrics for all methods
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.documagic.id
  stage_name  = aws_api_gateway_stage.documagic.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = var.environment != "production"
    throttling_burst_limit = 500
    throttling_rate_limit  = 1000
  }
}

# ---------------------------------------------------------------------------
# Usage Plan & API Key (for external integrations / REST API channel)
# ---------------------------------------------------------------------------
resource "aws_api_gateway_api_key" "documagic" {
  name    = "${local.name_prefix}-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "documagic" {
  name        = "${local.name_prefix}-usage-plan"
  description = "Default usage plan for DocuMagic API"

  api_stages {
    api_id = aws_api_gateway_rest_api.documagic.id
    stage  = aws_api_gateway_stage.documagic.stage_name
  }

  quota_settings {
    limit  = 50000
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 200
    rate_limit  = 100
  }
}

resource "aws_api_gateway_usage_plan_key" "documagic" {
  key_id        = aws_api_gateway_api_key.documagic.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.documagic.id
}
