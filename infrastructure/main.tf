# =============================================================================
# DocuMagic – Agentic AI Architecture
# Terraform Root Configuration
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to enable remote state (create the bucket + DynamoDB table first)
  # backend "s3" {
  #   bucket         = "documagic-terraform-state"
  #   key            = "documagic/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "documagic-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ---------------------------------------------------------------------------
# Locals – shared naming and tagging helpers
# ---------------------------------------------------------------------------
locals {
  app_name    = "DocuMagic"
  name_prefix = "${local.app_name}-${var.environment}"

  common_tags = {
    Project     = local.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "DocuMagic-Team"
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
