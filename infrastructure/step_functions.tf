# =============================================================================
# DocuMagic – AWS Step Functions
# Document AI Processing Pipeline state machine
# =============================================================================

resource "aws_sfn_state_machine" "document_pipeline" {
  name     = "${local.name_prefix}-document-pipeline"
  role_arn = aws_iam_role.step_functions.arn
  type     = "STANDARD"

  # ---------------------------------------------------------------------------
  # Pipeline definition:
  #   1. Validate Input
  #   2. Start Textract Job (async)
  #   3. Wait for Textract Completion
  #   4. Invoke Bedrock for enrichment (parallel: summary + entity extraction)
  #   5. Index in OpenSearch
  #   6. Update DynamoDB document status
  #   7. Publish EventBridge completion event
  # ---------------------------------------------------------------------------
  definition = jsonencode({
    Comment = "DocuMagic Document AI Processing Pipeline"
    StartAt = "ValidateInput"
    States = {

      ValidateInput = {
        Type    = "Task"
        Comment = "Validate that the required fields are present"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.textract_processor.arn
          "Payload.$"  = "$"
          InvocationType = "RequestResponse"
        }
        ResultPath = "$.validation"
        Next       = "StartTextractJob"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "JobFailed"
          ResultPath  = "$.error"
        }]
        Retry = [{
          ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 2
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
      }

      StartTextractJob = {
        Type    = "Task"
        Comment = "Trigger async Textract document analysis"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.textract_processor.arn
          "Payload.$"  = "$"
          InvocationType = "RequestResponse"
        }
        ResultSelector = {
          "jobId.$" = "$.Payload.jobId"
        }
        ResultPath = "$.textract"
        Next       = "WaitForTextract"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "JobFailed"
          ResultPath  = "$.error"
        }]
        Retry = [{
          ErrorEquals = ["Lambda.ServiceException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
      }

      WaitForTextract = {
        Type    = "Wait"
        Comment = "Wait for SNS notification from Textract (poll fallback)"
        Seconds = 30
        Next    = "CheckTextractStatus"
      }

      CheckTextractStatus = {
        Type    = "Task"
        Comment = "Poll Textract job status"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.textract_processor.arn
          "Payload.$"  = "$"
          InvocationType = "RequestResponse"
        }
        ResultSelector = {
          "status.$"    = "$.Payload.status"
          "outputKey.$" = "$.Payload.outputKey"
        }
        ResultPath = "$.textractStatus"
        Next       = "IsTextractComplete"
        Retry = [{
          ErrorEquals = ["Lambda.ServiceException"]
          IntervalSeconds = 5
          MaxAttempts     = 5
          BackoffRate     = 1.5
        }]
      }

      IsTextractComplete = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.textractStatus.status"
            StringEquals = "SUCCEEDED"
            Next         = "EnrichDocument"
          },
          {
            Variable     = "$.textractStatus.status"
            StringEquals = "FAILED"
            Next         = "JobFailed"
          }
        ]
        Default = "WaitForTextract"
      }

      EnrichDocument = {
        Type    = "Parallel"
        Comment = "Run Bedrock summarisation + Comprehend entity extraction in parallel"
        Branches = [
          {
            StartAt = "BedrockSummarise"
            States = {
              BedrockSummarise = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"
                Parameters = {
                  FunctionName = aws_lambda_function.bedrock_processor.arn
                  "Payload.$"  = "$"
                  InvocationType = "RequestResponse"
                }
                ResultSelector = {
                  "summary.$"  = "$.Payload.summary"
                  "topics.$"   = "$.Payload.topics"
                }
                End = true
                Retry = [{
                  ErrorEquals = ["Lambda.TooManyRequestsException", "Bedrock.ThrottlingException"]
                  IntervalSeconds = 10
                  MaxAttempts     = 3
                  BackoffRate     = 2.0
                }]
              }
            }
          },
          {
            StartAt = "ComprehendEntities"
            States = {
              ComprehendEntities = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"
                Parameters = {
                  FunctionName = aws_lambda_function.bedrock_processor.arn
                  "Payload.$"  = "$"
                  InvocationType = "RequestResponse"
                }
                ResultSelector = {
                  "entities.$"  = "$.Payload.entities"
                  "sentiment.$" = "$.Payload.sentiment"
                }
                End = true
                Retry = [{
                  ErrorEquals = ["Lambda.ServiceException"]
                  IntervalSeconds = 5
                  MaxAttempts     = 3
                  BackoffRate     = 2.0
                }]
              }
            }
          }
        ]
        ResultPath = "$.enrichment"
        Next       = "IndexInOpenSearch"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "JobFailed"
          ResultPath  = "$.error"
        }]
      }

      IndexInOpenSearch = {
        Type    = "Task"
        Comment = "Index enriched document chunks in OpenSearch"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.opensearch_indexer.arn
          "Payload.$"  = "$"
          InvocationType = "RequestResponse"
        }
        ResultPath = "$.indexing"
        Next       = "UpdateDocumentStatus"
        Catch = [{
          ErrorEquals = ["States.TaskFailed"]
          Next        = "JobFailed"
          ResultPath  = "$.error"
        }]
        Retry = [{
          ErrorEquals = ["Lambda.ServiceException"]
          IntervalSeconds = 5
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
      }

      UpdateDocumentStatus = {
        Type    = "Task"
        Comment = "Update document status in DynamoDB to COMPLETED"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.documents.id
          Key = {
            "documentId" = { "S.$" = "$.documentId" }
            "version"    = { "N"   = "1" }
          }
          UpdateExpression = "SET #s = :status, updatedAt = :now"
          ExpressionAttributeNames = {
            "#s" = "status"
          }
          ExpressionAttributeValues = {
            ":status" = { "S" = "COMPLETED" }
            ":now"    = { "S.$" = "$$.Execution.StartTime" }
          }
        }
        ResultPath = null
        Next       = "PublishCompletionEvent"
        Retry = [{
          ErrorEquals = ["DynamoDB.ProvisionedThroughputExceededException"]
          IntervalSeconds = 2
          MaxAttempts     = 5
          BackoffRate     = 2.0
        }]
      }

      PublishCompletionEvent = {
        Type     = "Task"
        Comment  = "Publish pipeline completion event to EventBridge"
        Resource = "arn:aws:states:::events:putEvents"
        Parameters = {
          Entries = [{
            EventBusName = aws_cloudwatch_event_bus.documagic.name
            Source       = "documagic.pipeline"
            DetailType   = "DocumentProcessingCompleted"
            "Detail.$"   = "States.JsonToString($)"
          }]
        }
        ResultPath = null
        End        = true
      }

      JobFailed = {
        Type  = "Task"
        Comment = "Update document status to FAILED and publish error event"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.documents.id
          Key = {
            "documentId" = { "S.$" = "$.documentId" }
            "version"    = { "N"   = "1" }
          }
          UpdateExpression = "SET #s = :status"
          ExpressionAttributeNames = {
            "#s" = "status"
          }
          ExpressionAttributeValues = {
            ":status" = { "S" = "FAILED" }
          }
        }
        ResultPath = null
        Next       = "PipelineFailed"
      }

      PipelineFailed = {
        Type  = "Fail"
        Cause = "Document pipeline processing failed"
        Error = "PipelineError"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-document-pipeline" }

  depends_on = [
    aws_iam_role_policy.step_functions,
    aws_cloudwatch_log_group.step_functions
  ]
}
