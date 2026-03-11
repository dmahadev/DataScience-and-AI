# =============================================================================
# DocuMagic – Input Variables
# =============================================================================

# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment (development | staging | production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be one of: development, staging, production."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the DocuMagic VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (at least 2 for MSK / OpenSearch)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# ---------------------------------------------------------------------------
# Cognito
# ---------------------------------------------------------------------------
variable "cognito_callback_urls" {
  description = "Allowed OAuth callback URLs for Cognito App Client"
  type        = list(string)
  default     = ["https://localhost:3000/callback"]
}

variable "cognito_logout_urls" {
  description = "Allowed OAuth logout URLs for Cognito App Client"
  type        = list(string)
  default     = ["https://localhost:3000/logout"]
}

# ---------------------------------------------------------------------------
# MSK (Kafka)
# ---------------------------------------------------------------------------
variable "msk_kafka_version" {
  description = "Kafka version for the MSK cluster"
  type        = string
  default     = "3.5.1"
}

variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m5.large"
}

variable "msk_broker_count" {
  description = "Number of MSK broker nodes (must be a multiple of AZs)"
  type        = number
  default     = 3
}

variable "msk_ebs_volume_size" {
  description = "EBS volume size (GiB) per MSK broker"
  type        = number
  default     = 100
}

# ---------------------------------------------------------------------------
# OpenSearch
# ---------------------------------------------------------------------------
variable "opensearch_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "opensearch_instance_type" {
  description = "OpenSearch data node instance type"
  type        = string
  default     = "r6g.large.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch data nodes"
  type        = number
  default     = 2
}

variable "opensearch_ebs_volume_size" {
  description = "EBS volume size (GiB) per OpenSearch node"
  type        = number
  default     = 100
}

# ---------------------------------------------------------------------------
# Lambda
# ---------------------------------------------------------------------------
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Default Lambda timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Default Lambda memory size in MB"
  type        = number
  default     = 512
}

# ---------------------------------------------------------------------------
# Bedrock
# ---------------------------------------------------------------------------
variable "bedrock_foundation_model_id" {
  description = "Bedrock foundation model ID used for knowledge base embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "bedrock_agent_model_id" {
  description = "Bedrock foundation model ID used for the Bedrock Agent"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

# ---------------------------------------------------------------------------
# API Gateway
# ---------------------------------------------------------------------------
variable "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "v1"
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
variable "s3_raw_bucket_name" {
  description = "Name of the S3 bucket for raw ingested documents (must be globally unique)"
  type        = string
  default     = ""
}

variable "s3_processed_bucket_name" {
  description = "Name of the S3 bucket for processed/enriched documents"
  type        = string
  default     = ""
}

variable "s3_knowledge_base_bucket_name" {
  description = "Name of the S3 bucket used as Bedrock knowledge-base data source"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
variable "enable_logging" {
  description = "Enable CloudWatch logging for all services"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch metrics and alarms"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------
variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
  default     = "ops@documagic.example.com"
}

# ---------------------------------------------------------------------------
# RDS / Aurora PostgreSQL (RDBMS tier)
# ---------------------------------------------------------------------------
variable "rds_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "rds_serverless_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity in ACUs (1 ACU = 2 GiB RAM)"
  type        = number
  default     = 0.5
}

variable "rds_serverless_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity in ACUs"
  type        = number
  default     = 16.0
}

variable "rds_reader_count" {
  description = "Number of Aurora read replicas"
  type        = number
  default     = 1
}

variable "rds_backup_retention_days" {
  description = "Aurora automated backup retention period in days"
  type        = number
  default     = 14
}
