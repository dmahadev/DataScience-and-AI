# =============================================================================
# DocuMagic – Amazon OpenSearch Service
# Managed domain for semantic search and document indexing
# =============================================================================

resource "aws_opensearch_domain" "documagic" {
  domain_name    = "${lower(local.name_prefix)}-search"
  engine_version = var.opensearch_version

  # ---------------------------------------------------------------------------
  # Cluster configuration
  # ---------------------------------------------------------------------------
  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    dedicated_master_enabled = true
    dedicated_master_type    = "r6g.large.search"
    dedicated_master_count   = 3
    zone_awareness_enabled   = true

    zone_awareness_config {
      availability_zone_count = min(var.opensearch_instance_count, 3)
    }
  }

  # ---------------------------------------------------------------------------
  # Storage
  # ---------------------------------------------------------------------------
  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_ebs_volume_size
    throughput  = 250
    iops        = 3000
  }

  # ---------------------------------------------------------------------------
  # Encryption
  # ---------------------------------------------------------------------------
  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  # ---------------------------------------------------------------------------
  # Networking (VPC)
  # ---------------------------------------------------------------------------
  vpc_options {
    subnet_ids         = slice(aws_subnet.private[*].id, 0, min(var.opensearch_instance_count, length(aws_subnet.private)))
    security_group_ids = [aws_security_group.opensearch.id]
  }

  # ---------------------------------------------------------------------------
  # Access policy
  # ---------------------------------------------------------------------------
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.lambda_execution.arn,
            aws_iam_role.bedrock_kb.arn
          ]
        }
        Action   = "es:ESHttp*"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${lower(local.name_prefix)}-search/*"
      }
    ]
  })

  # ---------------------------------------------------------------------------
  # Advanced options
  # ---------------------------------------------------------------------------
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "override_main_response_version"         = "false"
  }

  advanced_security_options {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = false

    master_user_options {
      master_user_arn = aws_iam_role.lambda_execution.arn
    }
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # ---------------------------------------------------------------------------
  # Logging
  # ---------------------------------------------------------------------------
  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.opensearch_index.arn}:*"
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = var.enable_logging
  }

  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.opensearch_search.arn}:*"
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled                  = var.enable_logging
  }

  log_publishing_options {
    cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.opensearch_app.arn}:*"
    log_type                 = "ES_APPLICATION_LOGS"
    enabled                  = var.enable_logging
  }

  # ---------------------------------------------------------------------------
  # Auto-tune
  # ---------------------------------------------------------------------------
  auto_tune_options {
    desired_state       = "ENABLED"
    rollback_on_disable = "NO_ROLLBACK"

    maintenance_schedule {
      start_at                       = "2024-01-01T03:00:00Z"
      cron_expression_for_recurrence = "cron(0 3 ? * SUN *)"

      duration {
        value = 4
        unit  = "HOURS"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Software updates
  # ---------------------------------------------------------------------------
  software_update_options {
    auto_software_update_enabled = true
  }

  tags = { Name = "${lower(local.name_prefix)}-search" }

  depends_on = [
    aws_cloudwatch_log_group.opensearch_index,
    aws_cloudwatch_log_group.opensearch_search,
    aws_cloudwatch_log_group.opensearch_app,
    aws_iam_role_policy.lambda_shared
  ]
}

# ---------------------------------------------------------------------------
# Resource-based policy allowing OpenSearch to write to CloudWatch
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${local.name_prefix}-opensearch-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "es.amazonaws.com"
      }
      Action = [
        "logs:PutLogEvents",
        "logs:PutLogEventsBatch",
        "logs:CreateLogStream"
      ]
      Resource = "arn:aws:logs:*"
    }]
  })
}

# ---------------------------------------------------------------------------
# Index templates & mappings (managed via null_resource / local-exec in CI/CD)
# ---------------------------------------------------------------------------
# Index: documagic-documents
#   Stores processed document text, metadata, and dense vector embeddings
#   for semantic similarity search.
#
# Index: documagic-knowledge-base
#   Stores knowledge-base chunks with vector embeddings for RAG retrieval.
#
# Run the following after cluster is available:
#   ./scripts/opensearch_init.sh <OPENSEARCH_ENDPOINT>
