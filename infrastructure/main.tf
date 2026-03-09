# Terraform Configuration for DocuMagic Architecture

provider "aws" {
  region = "us-west-2"
}

# Variables
variable "app_name" {
  default = "DocuMagic"
}

# S3 Bucket
resource "aws_s3_bucket" "documagic_bucket" {
  bucket = "${var.app_name}-bucket"
  acl    = "private"
}

# DynamoDB
resource "aws_dynamodb_table" "documagic_table" {
  name         = "${var.app_name}-table"
  billing_mode = "PAY_PER_REQUEST"
  attribute {
    name = "id"
    type = "S"
  }
}

# Lambda Function
resource "aws_lambda_function" "documagic_lambda" {
  function_name = "${var.app_name}-lambda"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.handler"
  source_code_hash = filebase64sha256("path/to/your/lambda.zip")
}

# API Gateway
resource "aws_api_gateway_rest_api" "documagic_api" {
  name        = "${var.app_name}-api"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "documagic_user_pool" {
  name = "${var.app_name}-user-pool"
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "documagic_event_rule" {
  name = "${var.app_name}-event-rule"
  event_pattern = jsonencode({
    "source": ["my.source"],
  })
}

# Step Functions
resource "aws_sfn_state_machine" "documagic_state_machine" {
  name     = "${var.app_name}-state-machine"
  role_arn = aws_iam_role.step_function_role.arn
  definition = jsonencode({
    "StartAt": "MyState",
    "States": {
      "MyState": {
        "Type": "Pass",
        "End": true
      }
    }
  })
}

# Bedrock Configuration (Example)
resource "aws_bedrock_model" "documagic_bedrock_model" {
  model_id = "example-bedrock-model"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.app_name}-lambda-role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }]
  })
}
