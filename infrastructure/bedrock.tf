# =============================================================================
# DocuMagic – Amazon Bedrock
# Knowledge Base (OpenSearch vector store) | Agent | Agent Alias
# =============================================================================

# ---------------------------------------------------------------------------
# Bedrock Knowledge Base
# ---------------------------------------------------------------------------
# NOTE on OpenSearch topology:
#   - This Knowledge Base uses OpenSearch *Serverless* (collection below) –
#     the only storage backend supported by Bedrock KB for vector search.
#   - opensearch.tf provisions an OpenSearch *Service* (managed) domain used
#     by Lambda (rag-api, opensearch-indexer) for full-text and semantic
#     document search. Both services coexist and serve different query paths.
# ---------------------------------------------------------------------------
resource "aws_bedrockagent_knowledge_base" "documagic" {
  name        = "${local.name_prefix}-knowledge-base"
  description = "DocuMagic vector knowledge base for RAG document retrieval"
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_foundation_model_id}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.documagic.arn
      vector_index_name = "documagic-kb-index"
      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = { Name = "${local.name_prefix}-knowledge-base" }

  depends_on = [
    aws_iam_role_policy.bedrock_kb,
    aws_opensearchserverless_access_policy.kb
  ]
}

# ---------------------------------------------------------------------------
# Knowledge Base Data Source (S3)
# ---------------------------------------------------------------------------
resource "aws_bedrockagent_data_source" "s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.documagic.id
  name              = "${local.name_prefix}-kb-s3-datasource"
  description       = "S3 knowledge-base bucket as Bedrock data source"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.knowledge_base.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 512
        overlap_percentage = 20
      }
    }
  }
}

# ---------------------------------------------------------------------------
# OpenSearch Serverless Collection (vector store for Knowledge Base)
# ---------------------------------------------------------------------------
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${lower(local.name_prefix)}-enc-policy"
  type        = "encryption"
  description = "Encryption policy for DocuMagic KB collection"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${lower(local.name_prefix)}-kb"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${lower(local.name_prefix)}-net-policy"
  type        = "network"
  description = "Network policy for DocuMagic KB collection"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${lower(local.name_prefix)}-kb"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${lower(local.name_prefix)}-kb"]
      }
    ]
    AllowFromPublic = false
  }])
}

resource "aws_opensearchserverless_access_policy" "kb" {
  name        = "${lower(local.name_prefix)}-kb-access"
  type        = "data"
  description = "Data access policy for Bedrock KB role"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${lower(local.name_prefix)}-kb"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${lower(local.name_prefix)}-kb/*"]
        Permission   = [
          "aoss:CreateIndex",
          "aoss:UpdateIndex",
          "aoss:DescribeIndex",
          "aoss:ReadDocument",
          "aoss:WriteDocument"
        ]
      }
    ]
    Principal = [aws_iam_role.bedrock_kb.arn, aws_iam_role.lambda_execution.arn]
  }])
}

resource "aws_opensearchserverless_collection" "documagic" {
  name        = "${lower(local.name_prefix)}-kb"
  type        = "VECTORSEARCH"
  description = "Vector store for DocuMagic Knowledge Base"

  tags = { Name = "${local.name_prefix}-kb-collection" }

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]
}

# ---------------------------------------------------------------------------
# Bedrock Agent
# ---------------------------------------------------------------------------
resource "aws_bedrockagent_agent" "documagic" {
  agent_name              = "${local.name_prefix}-agent"
  description             = "DocuMagic Agentic AI – orchestrates document understanding and Q&A"
  agent_resource_role_arn = aws_iam_role.bedrock_kb.arn
  foundation_model        = var.bedrock_agent_model_id
  idle_session_ttl_in_seconds = 600

  instruction = <<-EOT
    You are DocuMagic, an intelligent document-processing assistant.
    Your capabilities include:
    - Extracting, analyzing, and summarizing documents
    - Answering questions based on ingested documents using retrieval-augmented generation
    - Routing complex requests to specialist sub-agents
    - Identifying entities, key phrases, and sentiment in documents
    Always cite the source document when answering questions.
    If you cannot find relevant information, say so clearly.
  EOT

  tags = { Name = "${local.name_prefix}-agent" }

  depends_on = [aws_iam_role_policy.bedrock_kb]
}

# Associate Knowledge Base with the Agent
resource "aws_bedrockagent_agent_knowledge_base_association" "documagic" {
  agent_id             = aws_bedrockagent_agent.documagic.agent_id
  description          = "Primary knowledge base for document Q&A"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.documagic.id
  knowledge_base_state = "ENABLED"
}

# ---------------------------------------------------------------------------
# Bedrock Agent Alias (versioned deployment)
# ---------------------------------------------------------------------------
resource "aws_bedrockagent_agent_alias" "documagic" {
  agent_id         = aws_bedrockagent_agent.documagic.agent_id
  agent_alias_name = "${local.name_prefix}-agent-live"
  description      = "Live production alias for DocuMagic Agent"

  tags = { Name = "${local.name_prefix}-agent-alias" }
}

# ---------------------------------------------------------------------------
# SSM Parameters – Bedrock configuration
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "bedrock_kb_id" {
  name        = "/documagic/bedrock/knowledge_base_id"
  type        = "String"
  value       = aws_bedrockagent_knowledge_base.documagic.id
  description = "Bedrock Knowledge Base ID for DocuMagic"

  tags = { Name = "${local.name_prefix}-bedrock-kb-id" }
}

resource "aws_ssm_parameter" "bedrock_agent_id" {
  name        = "/documagic/bedrock/agent_id"
  type        = "String"
  value       = aws_bedrockagent_agent.documagic.agent_id
  description = "Bedrock Agent ID for DocuMagic"

  tags = { Name = "${local.name_prefix}-bedrock-agent-id" }
}

resource "aws_ssm_parameter" "bedrock_agent_alias_id" {
  name        = "/documagic/bedrock/agent_alias_id"
  type        = "String"
  value       = aws_bedrockagent_agent_alias.documagic.agent_alias_id
  description = "Bedrock Agent Alias ID for DocuMagic"

  tags = { Name = "${local.name_prefix}-bedrock-agent-alias-id" }
}
