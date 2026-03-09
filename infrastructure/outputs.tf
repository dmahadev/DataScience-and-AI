# Terraform Outputs for Key Resources

output "s3_bucket_name" {
  value = aws_s3_bucket.my_bucket.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.my_table.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.my_function.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.my_api.id
}
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.my_user_pool.id
}

output "step_function_arn" {
  value = aws_sfn_state_machine.my_state_machine.arn
}

output "other_resource_identifier" {
  value = aws_resource.my_resource.id
}
}