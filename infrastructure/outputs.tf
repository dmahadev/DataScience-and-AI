# =============================================================================
# DocuMagic – Terraform Outputs
# =============================================================================

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.documagic.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------
output "s3_raw_bucket_name" {
  description = "S3 bucket for raw document ingestion"
  value       = aws_s3_bucket.raw_ingest.id
}

output "s3_processed_bucket_name" {
  description = "S3 bucket for processed documents"
  value       = aws_s3_bucket.processed.id
}

output "s3_knowledge_base_bucket_name" {
  description = "S3 bucket used as Bedrock knowledge-base data source"
  value       = aws_s3_bucket.knowledge_base.id
}

# ---------------------------------------------------------------------------
# Cognito
# ---------------------------------------------------------------------------
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.documagic.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.documagic.arn
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.documagic.id
  sensitive   = true
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = aws_cognito_identity_pool.documagic.id
}

# ---------------------------------------------------------------------------
# API Gateway
# ---------------------------------------------------------------------------
output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.documagic.id
}

output "api_gateway_invoke_url" {
  description = "Base URL to invoke the REST API"
  value       = "https://${aws_api_gateway_rest_api.documagic.id}.execute-api.${var.aws_region}.amazonaws.com/${var.api_gateway_stage_name}"
}

# ---------------------------------------------------------------------------
# MSK
# ---------------------------------------------------------------------------
output "msk_cluster_arn" {
  description = "MSK Kafka cluster ARN"
  value       = aws_msk_cluster.documagic.arn
}

output "msk_bootstrap_brokers_tls" {
  description = "TLS bootstrap broker endpoints for MSK"
  value       = aws_msk_cluster.documagic.bootstrap_brokers_tls
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Lambda
# ---------------------------------------------------------------------------
output "lambda_textract_processor_arn" {
  description = "ARN of the Textract processor Lambda"
  value       = aws_lambda_function.textract_processor.arn
}

output "lambda_bedrock_processor_arn" {
  description = "ARN of the Bedrock processor Lambda"
  value       = aws_lambda_function.bedrock_processor.arn
}

output "lambda_opensearch_indexer_arn" {
  description = "ARN of the OpenSearch indexer Lambda"
  value       = aws_lambda_function.opensearch_indexer.arn
}

output "lambda_rag_api_arn" {
  description = "ARN of the RAG API Lambda"
  value       = aws_lambda_function.rag_api.arn
}

output "lambda_a2a_api_arn" {
  description = "ARN of the Agent-to-Agent API Lambda"
  value       = aws_lambda_function.a2a_api.arn
}

# ---------------------------------------------------------------------------
# OpenSearch
# ---------------------------------------------------------------------------
output "opensearch_endpoint" {
  description = "OpenSearch Service domain endpoint"
  value       = aws_opensearch_domain.documagic.endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = aws_opensearch_domain.documagic.dashboard_endpoint
}

# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------
output "dynamodb_documents_table_name" {
  description = "DynamoDB table for document metadata"
  value       = aws_dynamodb_table.documents.id
}

output "dynamodb_documents_stream_arn" {
  description = "DynamoDB Stream ARN for the documents table"
  value       = aws_dynamodb_table.documents.stream_arn
}

output "dynamodb_sessions_table_name" {
  description = "DynamoDB table for user sessions"
  value       = aws_dynamodb_table.sessions.id
}

output "dynamodb_knowledge_base_table_name" {
  description = "DynamoDB table for knowledge-base records"
  value       = aws_dynamodb_table.knowledge_base.id
}

# ---------------------------------------------------------------------------
# Step Functions
# ---------------------------------------------------------------------------
output "step_function_arn" {
  description = "ARN of the document-processing Step Functions state machine"
  value       = aws_sfn_state_machine.document_pipeline.arn
}

# ---------------------------------------------------------------------------
# Bedrock
# ---------------------------------------------------------------------------
output "bedrock_knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  value       = aws_bedrockagent_knowledge_base.documagic.id
}

output "bedrock_agent_id" {
  description = "Bedrock Agent ID"
  value       = aws_bedrockagent_agent.documagic.agent_id
}

# ---------------------------------------------------------------------------
# EventBridge
# ---------------------------------------------------------------------------
output "eventbridge_bus_arn" {
  description = "Custom EventBridge bus ARN"
  value       = aws_cloudwatch_event_bus.documagic.arn
}

# ---------------------------------------------------------------------------
# Amplify
# ---------------------------------------------------------------------------
output "amplify_app_id" {
  description = "Amplify App ID"
  value       = aws_amplify_app.documagic.id
}

output "amplify_default_domain" {
  description = "Default Amplify domain"
  value       = aws_amplify_app.documagic.default_domain
}

# ---------------------------------------------------------------------------
# CloudWatch
# ---------------------------------------------------------------------------
output "sns_alarm_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = aws_sns_topic.alarms.arn
}

# ---------------------------------------------------------------------------
# RDBMS – Aurora PostgreSQL
# ---------------------------------------------------------------------------
output "aurora_cluster_endpoint" {
  description = "Aurora PostgreSQL writer endpoint"
  value       = aws_rds_cluster.documagic.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint"
  value       = aws_rds_cluster.documagic.reader_endpoint
}

output "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.documagic.cluster_identifier
}

output "aurora_rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for Lambda connection pooling"
  value       = aws_db_proxy.documagic.endpoint
}

output "aurora_master_secret_arn" {
  description = "Secrets Manager ARN for Aurora master credentials"
  value       = aws_secretsmanager_secret.aurora_master.arn
  sensitive   = true
}

output "aurora_app_secret_arn" {
  description = "Secrets Manager ARN for Aurora application user credentials"
  value       = aws_secretsmanager_secret.aurora_app.arn
  sensitive   = true
}

# ---------------------------------------------------------------------------
# NoSQL – Additional DynamoDB tables
# ---------------------------------------------------------------------------
output "dynamodb_agent_conversations_table_name" {
  description = "DynamoDB table for agent conversation history"
  value       = aws_dynamodb_table.agent_conversations.id
}

output "dynamodb_agent_tasks_table_name" {
  description = "DynamoDB table for agentic task queue"
  value       = aws_dynamodb_table.agent_tasks.id
}

output "dynamodb_agent_tasks_stream_arn" {
  description = "DynamoDB Stream ARN for the agent-tasks table"
  value       = aws_dynamodb_table.agent_tasks.stream_arn
}

output "dynamodb_rate_limits_table_name" {
  description = "DynamoDB table for API rate-limit counters"
  value       = aws_dynamodb_table.rate_limits.id
}

output "dynamodb_tenant_config_table_name" {
  description = "DynamoDB table for per-tenant configuration"
  value       = aws_dynamodb_table.tenant_config.id
}

# ---------------------------------------------------------------------------
# Vector DB – OpenSearch index metadata
# ---------------------------------------------------------------------------
output "opensearch_documents_index_ssm_path" {
  description = "SSM path holding the documagic-documents index mapping"
  value       = aws_ssm_parameter.os_index_documents_mapping.name
}

output "opensearch_kb_chunks_index_ssm_path" {
  description = "SSM path holding the documagic-kb-chunks index mapping"
  value       = aws_ssm_parameter.os_index_kb_chunks_mapping.name
}

output "opensearch_audit_logs_index_ssm_path" {
  description = "SSM path holding the documagic-audit-logs index mapping"
  value       = aws_ssm_parameter.os_index_audit_logs_mapping.name
}

output "opensearch_entities_index_ssm_path" {
  description = "SSM path holding the documagic-entities index mapping"
  value       = aws_ssm_parameter.os_index_entities_mapping.name
}
