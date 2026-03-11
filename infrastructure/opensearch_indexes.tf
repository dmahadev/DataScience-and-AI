# =============================================================================
# DocuMagic – OpenSearch Index Templates & Vector Mappings
# Provisioned via null_resource / local-exec after cluster is ready
#
# Covers:
#   1. documagic-documents   – full-text + knn dense vector (1536 dims)
#   2. documagic-kb-chunks   – RAG knowledge-base chunks with knn embedding
#   3. documagic-audit-logs  – operational / compliance audit trail (no vector)
#   4. documagic-entities    – extracted named entities for faceted search
# =============================================================================

# ---------------------------------------------------------------------------
# SSM parameter storing the OpenSearch endpoint (consumed by scripts & Lambda)
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "opensearch_endpoint" {
  name        = "/documagic/opensearch/endpoint"
  type        = "String"
  value       = "https://${aws_opensearch_domain.documagic.endpoint}"
  description = "DocuMagic OpenSearch Service domain HTTPS endpoint"

  tags = { Name = "${local.name_prefix}-opensearch-endpoint" }
}

resource "aws_ssm_parameter" "opensearch_kb_collection_endpoint" {
  name        = "/documagic/opensearch/kb_collection_endpoint"
  type        = "String"
  value       = aws_opensearchserverless_collection.documagic.collection_endpoint
  description = "DocuMagic OpenSearch Serverless KB collection endpoint"

  tags = { Name = "${local.name_prefix}-opensearch-kb-endpoint" }
}

# ---------------------------------------------------------------------------
# Index mappings stored as SSM parameters (applied by opensearch_init.sh)
# ---------------------------------------------------------------------------

# 1. documagic-documents index mapping
resource "aws_ssm_parameter" "os_index_documents_mapping" {
  name        = "/documagic/opensearch/indexes/documents/mapping"
  type        = "String"
  description = "Index mapping for documagic-documents (full-text + vector search)"

  value = jsonencode({
    settings = {
      index = {
        knn             = true
        knn_algo_param  = { ef_search = 512 }
        number_of_shards   = 3
        number_of_replicas = 1
        refresh_interval   = "5s"
        analysis = {
          analyzer = {
            document_analyzer = {
              type      = "custom"
              tokenizer = "standard"
              filter    = ["lowercase", "stop", "porter_stem"]
            }
          }
        }
      }
    }
    mappings = {
      properties = {
        # --- identity ---
        documentId = { type = "keyword" }
        userId     = { type = "keyword" }
        orgId      = { type = "keyword" }
        version    = { type = "integer" }

        # --- file metadata ---
        fileName     = { type = "text", analyzer = "standard", fields = { keyword = { type = "keyword", ignore_above = 512 } } }
        fileType     = { type = "keyword" }
        fileSizeBytes = { type = "long" }
        s3Key        = { type = "keyword" }
        s3Bucket     = { type = "keyword" }
        pageCount    = { type = "integer" }

        # --- status & pipeline ---
        status             = { type = "keyword" }
        textractJobId      = { type = "keyword" }
        processingPipelineId = { type = "keyword" }

        # --- content (full-text) ---
        rawText = {
          type     = "text"
          analyzer = "document_analyzer"
          term_vector = "with_positions_offsets"
        }
        summary    = { type = "text", analyzer = "document_analyzer" }
        highlights = { type = "text", analyzer = "document_analyzer" }
        language   = { type = "keyword" }

        # --- NLP enrichment (Comprehend / Bedrock) ---
        entities = {
          type = "nested"
          properties = {
            text  = { type = "text" }
            type  = { type = "keyword" }
            score = { type = "float" }
            beginOffset = { type = "integer" }
            endOffset   = { type = "integer" }
          }
        }
        keyPhrases = { type = "text" }
        sentiment  = { type = "keyword" }
        sentimentScore = {
          properties = {
            positive = { type = "float" }
            negative = { type = "float" }
            neutral  = { type = "float" }
            mixed    = { type = "float" }
          }
        }
        topics     = { type = "keyword" }
        categories = { type = "keyword" }
        piiDetected = { type = "boolean" }
        piiEntityTypes = { type = "keyword" }

        # --- vector embedding (1536-dim Titan Text Embed v2) ---
        # space_type "cosinesimil" is the correct value for the faiss engine;
        # "cosinesimilarity" is only used with the lucene engine.
        embedding = {
          type      = "knn_vector"
          dimension = 1536
          method = {
            name       = "hnsw"
            space_type = "cosinesimil"   # faiss engine cosine similarity
            engine     = "faiss"
            parameters = {
              ef_construction = 512
              m               = 16
            }
          }
        }

        # --- timestamps ---
        createdAt   = { type = "date", format = "strict_date_optional_time||epoch_millis" }
        updatedAt   = { type = "date", format = "strict_date_optional_time||epoch_millis" }
        indexedAt   = { type = "date", format = "strict_date_optional_time||epoch_millis" }
        expiresAt   = { type = "date", format = "strict_date_optional_time||epoch_millis" }
      }
    }
  })

  tags = { Name = "${local.name_prefix}-os-documents-mapping" }
}

# 2. documagic-kb-chunks index mapping (RAG knowledge-base chunks)
resource "aws_ssm_parameter" "os_index_kb_chunks_mapping" {
  name        = "/documagic/opensearch/indexes/kb-chunks/mapping"
  type        = "String"
  description = "Index mapping for documagic-kb-chunks (RAG retrieval chunks)"

  value = jsonencode({
    settings = {
      index = {
        knn             = true
        knn_algo_param  = { ef_search = 256 }
        number_of_shards   = 3
        number_of_replicas = 1
        refresh_interval   = "10s"
      }
    }
    mappings = {
      properties = {
        # --- identity ---
        chunkId    = { type = "keyword" }
        documentId = { type = "keyword" }
        userId     = { type = "keyword" }
        orgId      = { type = "keyword" }

        # --- chunk content ---
        text          = { type = "text", analyzer = "standard" }
        chunkIndex    = { type = "integer" }
        chunkTotal    = { type = "integer" }
        tokenCount    = { type = "integer" }
        startCharOffset = { type = "integer" }
        endCharOffset   = { type = "integer" }

        # --- source document ---
        sourceTitle    = { type = "text", fields = { keyword = { type = "keyword" } } }
        sourceFileName = { type = "keyword" }
        sourceSection  = { type = "keyword" }
        sourcePage     = { type = "integer" }

        # --- vector embedding (1536-dim) ---
        # space_type "cosinesimil" is correct for faiss engine (not "cosinesimilarity")
        embedding = {
          type      = "knn_vector"
          dimension = 1536
          method = {
            name       = "hnsw"
            space_type = "cosinesimil"   # faiss engine cosine similarity
            engine     = "faiss"
            parameters = {
              ef_construction = 256
              m               = 16
            }
          }
        }

        # --- metadata ---
        language    = { type = "keyword" }
        topics      = { type = "keyword" }
        categories  = { type = "keyword" }
        indexedAt   = { type = "date", format = "strict_date_optional_time||epoch_millis" }
        modelId     = { type = "keyword" }
        embeddingModelVersion = { type = "keyword" }
      }
    }
  })

  tags = { Name = "${local.name_prefix}-os-kb-chunks-mapping" }
}

# 3. documagic-audit-logs index mapping
resource "aws_ssm_parameter" "os_index_audit_logs_mapping" {
  name        = "/documagic/opensearch/indexes/audit-logs/mapping"
  type        = "String"
  description = "Index mapping for documagic-audit-logs (compliance & operational audit)"

  value = jsonencode({
    settings = {
      index = {
        number_of_shards   = 2
        number_of_replicas = 1
        refresh_interval   = "30s"
      }
    }
    mappings = {
      properties = {
        # --- event identity ---
        eventId     = { type = "keyword" }
        eventType   = { type = "keyword" }
        eventSource = { type = "keyword" }

        # --- actor ---
        userId    = { type = "keyword" }
        orgId     = { type = "keyword" }
        userEmail = { type = "keyword" }
        userAgent = { type = "text" }
        ipAddress = { type = "ip" }

        # --- resource ---
        resourceType = { type = "keyword" }
        resourceId   = { type = "keyword" }
        resourceName = { type = "keyword" }

        # --- request / response ---
        httpMethod      = { type = "keyword" }
        httpPath        = { type = "keyword" }
        httpStatusCode  = { type = "integer" }
        requestId       = { type = "keyword" }
        correlationId   = { type = "keyword" }
        durationMs      = { type = "long" }

        # --- outcome ---
        outcome       = { type = "keyword" }
        errorCode     = { type = "keyword" }
        errorMessage  = { type = "text" }

        # --- payload snapshot ---
        requestSnapshot  = { type = "object", enabled = false }
        responseSnapshot = { type = "object", enabled = false }

        # --- timestamp ---
        timestamp = { type = "date", format = "strict_date_optional_time||epoch_millis" }
        ttl       = { type = "date", format = "strict_date_optional_time||epoch_millis" }
      }
    }
  })

  tags = { Name = "${local.name_prefix}-os-audit-logs-mapping" }
}

# 4. documagic-entities index mapping (named entity registry for faceted search)
resource "aws_ssm_parameter" "os_index_entities_mapping" {
  name        = "/documagic/opensearch/indexes/entities/mapping"
  type        = "String"
  description = "Index mapping for documagic-entities (entity registry for faceted search)"

  value = jsonencode({
    settings = {
      index = {
        number_of_shards   = 2
        number_of_replicas = 1
        refresh_interval   = "30s"
      }
    }
    mappings = {
      properties = {
        entityId    = { type = "keyword" }
        entityText  = { type = "text", fields = { keyword = { type = "keyword" } } }
        entityType  = { type = "keyword" }
        normalizedText = { type = "keyword" }
        documentIds = { type = "keyword" }
        orgId       = { type = "keyword" }
        occurrenceCount = { type = "integer" }
        avgConfidence   = { type = "float" }
        firstSeenAt     = { type = "date", format = "strict_date_optional_time||epoch_millis" }
        lastSeenAt      = { type = "date", format = "strict_date_optional_time||epoch_millis" }
      }
    }
  })

  tags = { Name = "${local.name_prefix}-os-entities-mapping" }
}

# ---------------------------------------------------------------------------
# Index lifecycle policy (ISM) – stored as SSM, applied by opensearch_init.sh
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "os_ism_policy" {
  name        = "/documagic/opensearch/ism/audit-logs-rollover"
  type        = "String"
  description = "OpenSearch ISM policy for audit-log index rollover and retention"

  value = jsonencode({
    policy = {
      description    = "Rollover audit-logs monthly; delete after 90 days"
      default_state  = "hot"
      states = [
        {
          name   = "hot"
          actions = [
            {
              rollover = {
                min_index_age  = "30d"
                min_size       = "50gb"
              }
            }
          ]
          transitions = [
            {
              state_name = "warm"
              conditions = { min_rollover_age = "1d" }
            }
          ]
        },
        {
          name    = "warm"
          actions = [{ replica_count = { number_of_replicas = 0 } }]
          transitions = [
            {
              state_name = "delete"
              conditions = { min_index_age = "90d" }
            }
          ]
        },
        {
          name    = "delete"
          actions = [{ delete = {} }]
          transitions = []
        }
      ]
    }
  })

  tags = { Name = "${local.name_prefix}-os-ism-audit-rollover" }
}
