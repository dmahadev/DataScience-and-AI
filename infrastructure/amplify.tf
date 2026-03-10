# =============================================================================
# DocuMagic – AWS Amplify
# Frontend hosting for the DocuMagic web application
# =============================================================================

resource "aws_amplify_app" "documagic" {
  name        = local.name_prefix
  description = "DocuMagic Agentic AI – frontend web application"

  # Build specification – adjust to your frontend framework (React / Next.js)
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  # Rewrites / redirects – SPA catch-all
  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json)$)([^.]+$)/>"
    target = "/index.html"
    status = "200"
  }

  # Security headers
  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }

  environment_variables = {
    REACT_APP_API_URL              = "https://${aws_api_gateway_rest_api.documagic.id}.execute-api.${var.aws_region}.amazonaws.com/${var.api_gateway_stage_name}"
    REACT_APP_AWS_REGION           = var.aws_region
    REACT_APP_COGNITO_USER_POOL_ID = aws_cognito_user_pool.documagic.id
    REACT_APP_COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.documagic.id
    REACT_APP_S3_RAW_BUCKET        = aws_s3_bucket.raw_ingest.id
    REACT_APP_ENVIRONMENT          = var.environment
  }

  # Enable branch auto-detection
  enable_auto_branch_creation = true
  enable_branch_auto_deletion = true

  auto_branch_creation_config {
    enable_pull_request_preview = true
    enable_auto_build           = true
    stage                       = "DEVELOPMENT"
  }

  tags = { Name = "${local.name_prefix}-amplify" }
}

# ---------------------------------------------------------------------------
# Production branch
# ---------------------------------------------------------------------------
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.documagic.id
  branch_name = "main"
  stage       = "PRODUCTION"

  enable_auto_build          = true
  enable_pull_request_preview = false

  environment_variables = {
    REACT_APP_ENVIRONMENT = "production"
  }

  tags = { Name = "${local.name_prefix}-amplify-main" }
}

# ---------------------------------------------------------------------------
# Staging branch
# ---------------------------------------------------------------------------
resource "aws_amplify_branch" "staging" {
  app_id      = aws_amplify_app.documagic.id
  branch_name = "staging"
  stage       = "BETA"

  enable_auto_build           = true
  enable_pull_request_preview = true

  environment_variables = {
    REACT_APP_ENVIRONMENT = "staging"
  }

  tags = { Name = "${local.name_prefix}-amplify-staging" }
}
