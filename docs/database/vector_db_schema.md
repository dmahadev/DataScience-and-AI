# DocuMagic – Vector Database Design (Amazon OpenSearch Service + OpenSearch Serverless)

## Overview

DocuMagic uses **two complementary OpenSearch deployments** for vector search and full-text retrieval:

| Deployment | Service | Purpose |
|---|---|---|
| **Managed Domain** (`opensearch.tf`) | Amazon OpenSearch Service | Lambda-driven document search, full-text + knn hybrid retrieval, audit logs, entity registry |
| **Serverless Collection** (`bedrock.tf`) | Amazon OpenSearch Serverless | Bedrock Knowledge Base vector store (only option supported by Bedrock KB) |

Both deployments are VPC-private, encrypted at rest and in transit, and accessible only via IAM role authentication.

---

## Embedding Model

All dense vector fields use embeddings produced by **Amazon Titan Text Embed v2**:
- **Dimension:** 1536
- **Model ID:** `amazon.titan-embed-text-v2:0`
- **Similarity metric:** cosine similarity (`cosinesimil` — the correct `space_type` for the faiss engine; the Lucene engine uses `cosinesimilarity`)
- **Index algorithm:** HNSW (Hierarchical Navigable Small World) via the `faiss` engine

---

## OpenSearch Service – Index Catalogue

### Index 1: `documagic-documents`

**Purpose:** Full-text + dense-vector hybrid search over complete processed documents. Supports keyword search, semantic similarity, entity-based faceting, and filtered retrieval.

**Created by:** `opensearch-indexer` Lambda after Step Functions pipeline completes.

#### Index Settings

```json
{
  "index": {
    "knn": true,
    "knn.algo_param.ef_search": 512,
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "5s",
    "analysis": {
      "analyzer": {
        "document_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "stop", "porter_stem"]
        }
      }
    }
  }
}
```

#### Field Mappings

| Field | Type | Analyzer / Config | Purpose |
|---|---|---|---|
| `documentId` | `keyword` | — | Exact-match lookup, join to DynamoDB |
| `userId` | `keyword` | — | User-scoped filtering |
| `orgId` | `keyword` | — | Tenant isolation |
| `version` | `integer` | — | Document version |
| `fileName` | `text` + `keyword` sub-field | `standard` | Full-text search + exact match |
| `fileType` | `keyword` | — | Filter by MIME type |
| `rawText` | `text` | `document_analyzer` | Full-text search with stemming |
| `summary` | `text` | `document_analyzer` | Summary full-text search |
| `entities` | `nested` | — | Nested entity objects |
| `entities.text` | `text` | — | Entity surface form |
| `entities.type` | `keyword` | — | PERSON, ORG, LOC, DATE, … |
| `entities.score` | `float` | — | Confidence score |
| `keyPhrases` | `text` | — | Key phrase text |
| `sentiment` | `keyword` | — | POSITIVE/NEGATIVE/NEUTRAL/MIXED |
| `topics` | `keyword` | — | Topic tags (multi-value) |
| `categories` | `keyword` | — | Category tags (multi-value) |
| `piiDetected` | `boolean` | — | PII flag for access control |
| `language` | `keyword` | — | ISO language code |
| `embedding` | `knn_vector` | dim=1536, HNSW, cosine, faiss | Dense vector for semantic search |
| `createdAt` | `date` | `strict_date_optional_time` | Time-range filtering |
| `updatedAt` | `date` | `strict_date_optional_time` | |
| `indexedAt` | `date` | `strict_date_optional_time` | |

#### Sample Query – Hybrid Search (BM25 + knn)

```json
POST /documagic-documents/_search
{
  "size": 10,
  "_source": ["documentId", "fileName", "summary", "topics", "sentiment"],
  "query": {
    "bool": {
      "filter": [
        { "term": { "orgId": "org-uuid-9999" } },
        { "term": { "status": "completed" } }
      ],
      "should": [
        {
          "multi_match": {
            "query": "notice period termination clause",
            "fields": ["rawText^1", "summary^2", "keyPhrases^1.5"],
            "type": "best_fields",
            "boost": 0.5
          }
        },
        {
          "knn": {
            "embedding": {
              "vector": [0.0234, -0.1456, "…1536 dims…"],
              "k": 20,
              "boost": 2.0
            }
          }
        }
      ]
    }
  },
  "highlight": {
    "fields": {
      "rawText":  { "fragment_size": 200, "number_of_fragments": 3 },
      "summary":  { "fragment_size": 150, "number_of_fragments": 1 }
    }
  },
  "aggs": {
    "topics": { "terms": { "field": "topics", "size": 20 } },
    "sentiment": { "terms": { "field": "sentiment" } }
  }
}
```

---

### Index 2: `documagic-kb-chunks`

**Purpose:** RAG retrieval — stores fixed-size text chunks with their dense vector embeddings. Used by the `rag-api` Lambda for retrieval-augmented generation before invoking Bedrock Claude.

**Created by:** `opensearch-indexer` Lambda (chunking step) + Bedrock Knowledge Base sync.

#### Index Settings

```json
{
  "index": {
    "knn": true,
    "knn.algo_param.ef_search": 256,
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "10s"
  }
}
```

#### Field Mappings

| Field | Type | Config | Purpose |
|---|---|---|---|
| `chunkId` | `keyword` | — | Unique chunk identifier |
| `documentId` | `keyword` | — | Parent document reference |
| `orgId` | `keyword` | — | Tenant isolation |
| `text` | `text` | `standard` | Chunk text (up to 512 tokens) |
| `chunkIndex` | `integer` | — | Position within document |
| `chunkTotal` | `integer` | — | Total chunks in document |
| `tokenCount` | `integer` | — | Token count for cost estimation |
| `sourceTitle` | `text` + `keyword` | — | Parent document title |
| `sourceFileName` | `keyword` | — | Original file name |
| `sourceSection` | `keyword` | — | Document section (e.g. "Section 4.2") |
| `sourcePage` | `integer` | — | Page number |
| `embedding` | `knn_vector` | dim=1536, HNSW, cosine, faiss | Dense vector for knn retrieval |
| `language` | `keyword` | — | ISO language code |
| `topics` | `keyword` | — | Inherited from parent document |
| `modelId` | `keyword` | — | Embedding model used |
| `indexedAt` | `date` | ISO 8601 | When chunk was indexed |

#### Sample Query – Pure knn Retrieval (RAG)

```json
POST /documagic-kb-chunks/_search
{
  "size": 5,
  "_source": ["chunkId", "documentId", "text", "sourceTitle", "sourcePage"],
  "query": {
    "bool": {
      "filter": [
        { "term": { "orgId": "org-uuid-9999" } }
      ],
      "must": [
        {
          "knn": {
            "embedding": {
              "vector": [0.0234, -0.1456, "…1536 dims…"],
              "k": 5
            }
          }
        }
      ]
    }
  }
}
```

---

### Index 3: `documagic-audit-logs`

**Purpose:** Operational and compliance audit log. High-volume append-only index with time-based rollover managed by an ISM (Index State Management) policy.

**Created by:** `rag-api`, `textract-processor`, `bedrock-processor` Lambdas on every significant operation.

#### Field Mappings

| Field | Type | Purpose |
|---|---|---|
| `eventId` | `keyword` | Unique event identifier |
| `eventType` | `keyword` | `document.upload`, `query.rag`, `agent.invoke`, … |
| `eventSource` | `keyword` | Lambda function name / service |
| `userId` | `keyword` | Actor identity |
| `orgId` | `keyword` | Tenant |
| `userEmail` | `keyword` | Denormalised for query convenience |
| `ipAddress` | `ip` | Source IP (IP range queries) |
| `resourceType` | `keyword` | `document`, `session`, `agent`, … |
| `resourceId` | `keyword` | ID of the acted-upon resource |
| `httpMethod` | `keyword` | POST, GET, DELETE |
| `httpPath` | `keyword` | `/v1/query`, `/v1/documents` |
| `httpStatusCode` | `integer` | HTTP response status |
| `requestId` | `keyword` | API Gateway / Lambda request ID |
| `durationMs` | `long` | Elapsed time in milliseconds |
| `outcome` | `keyword` | `success`, `failure`, `error` |
| `errorCode` | `keyword` | Application error code |
| `timestamp` | `date` | Event timestamp (index sort key) |

#### ISM Policy – Rollover & Retention

```
hot (active writes)
  → rollover when: age > 30 days OR size > 50 GB
warm (reduced replicas = 0)
  → delete when: total age > 90 days
```

---

### Index 4: `documagic-entities`

**Purpose:** Aggregated named entity registry. Enables faceted search ("find all documents mentioning Acme Corp"), entity frequency analytics, and knowledge graph construction.

**Created by:** `bedrock-processor` Lambda (aggregates entities after Comprehend enrichment).

#### Field Mappings

| Field | Type | Purpose |
|---|---|---|
| `entityId` | `keyword` | Canonical entity ID (hash of type + normalizedText) |
| `entityText` | `text` + `keyword` | Surface form (search + exact) |
| `entityType` | `keyword` | PERSON, ORGANIZATION, LOCATION, DATE, … |
| `normalizedText` | `keyword` | Lowercased, trimmed form |
| `documentIds` | `keyword` | Array of document IDs where entity appears |
| `orgId` | `keyword` | Tenant isolation |
| `occurrenceCount` | `integer` | Total mentions across all documents |
| `avgConfidence` | `float` | Mean Comprehend confidence score |
| `firstSeenAt` | `date` | First document ingestion timestamp |
| `lastSeenAt` | `date` | Most recent occurrence |

---

## OpenSearch Serverless – Bedrock Knowledge Base Collection

**Collection:** `documagic-production-kb` (type: `VECTORSEARCH`)

**Purpose:** Used exclusively as the Bedrock Knowledge Base vector store. Bedrock manages chunking, embedding, and indexing automatically when documents are synced from the S3 knowledge-base bucket.

### Index: `documagic-kb-index`

Bedrock creates and manages this index automatically. The field mapping below reflects Bedrock's schema requirements:

| Field | Type | Notes |
|---|---|---|
| `embedding` | `knn_vector` | dim=1536, Titan Text Embed v2 |
| `text` | `text` | Chunk content |
| `metadata` | `object` | Source S3 path, document title, page |

#### Retrieval via Bedrock RetrieveAndGenerate API

```python
import boto3

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime", region_name="us-west-2")

response = bedrock_agent_runtime.retrieve_and_generate(
    input={"text": "What is the notice period?"},
    retrieveAndGenerateConfiguration={
        "type": "KNOWLEDGE_BASE",
        "knowledgeBaseConfiguration": {
            "knowledgeBaseId": "KB_ID",
            "modelArn": "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
            "retrievalConfiguration": {
                "vectorSearchConfiguration": {
                    "numberOfResults": 5,
                    "overrideSearchType": "HYBRID"
                }
            }
        }
    }
)
```

---

## Index Initialization Script

All OpenSearch Service indexes are initialized by `scripts/opensearch_init.sh`, which:

1. Reads index mappings from SSM Parameter Store
2. Creates index templates with the correct knn settings
3. Applies the ISM policy to `documagic-audit-logs`
4. Creates initial aliases (`documagic-audit-logs-write` → `documagic-audit-logs-000001`)

```bash
#!/bin/bash
# Usage: ./scripts/opensearch_init.sh https://<OPENSEARCH_ENDPOINT>
ENDPOINT=$1
AWS_REGION=us-west-2

# Helper: sign requests with AWS SigV4
function es_request() {
  local method=$1 path=$2 body=$3
  aws es describe-elasticsearch-domains --domain-names dummy 2>/dev/null  # ensure creds
  curl -s -XPUT \
    --aws-sigv4 "aws:amz:${AWS_REGION}:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "${ENDPOINT}${path}"
}

# Retrieve mappings from SSM
DOCS_MAPPING=$(aws ssm get-parameter \
  --name "/documagic/opensearch/indexes/documents/mapping" \
  --query "Parameter.Value" --output text)

KB_MAPPING=$(aws ssm get-parameter \
  --name "/documagic/opensearch/indexes/kb-chunks/mapping" \
  --query "Parameter.Value" --output text)

AUDIT_MAPPING=$(aws ssm get-parameter \
  --name "/documagic/opensearch/indexes/audit-logs/mapping" \
  --query "Parameter.Value" --output text)

ENTITY_MAPPING=$(aws ssm get-parameter \
  --name "/documagic/opensearch/indexes/entities/mapping" \
  --query "Parameter.Value" --output text)

# Create indexes
es_request PUT "/documagic-documents"   "$DOCS_MAPPING"
es_request PUT "/documagic-kb-chunks"   "$KB_MAPPING"
es_request PUT "/documagic-audit-logs-000001" "$AUDIT_MAPPING"
es_request PUT "/documagic-entities"    "$ENTITY_MAPPING"

# Create alias for audit log rollover
es_request POST "/_aliases" '{
  "actions": [
    { "add": { "index": "documagic-audit-logs-000001", "alias": "documagic-audit-logs-write", "is_write_index": true } },
    { "add": { "index": "documagic-audit-logs-000001", "alias": "documagic-audit-logs" } }
  ]
}'

echo "OpenSearch indexes initialized successfully."
```

---

## Performance Tuning

### HNSW Parameters

| Parameter | Documents Index | KB Chunks Index | Rationale |
|---|---|---|---|
| `ef_construction` | 512 | 256 | Higher = better recall, slower indexing |
| `m` | 16 | 16 | Graph connectivity; 16 is optimal for 1536-dim |
| `ef_search` | 512 | 256 | Higher = better recall, slower queries |

### Recommended Instance Sizing

| Workload | Instance Type | Storage | Rationale |
|---|---|---|---|
| < 10 M documents | `r6g.large.search` × 2 | 100 GiB each | Development / small production |
| 10–50 M documents | `r6g.xlarge.search` × 4 | 200 GiB each | Medium production |
| 50 M+ documents | `r6g.2xlarge.search` × 6 | 500 GiB each | Large enterprise |

### Query Performance Tips

- Always **filter by `orgId`** before knn to reduce the search space and enforce tenant isolation
- Use `_source` includes to return only needed fields (avoid `rawText` in list views)
- Set `ef_search` dynamically in query params for latency vs recall trade-off
- Use the **Bedrock RetrieveAndGenerate** API for RAG instead of calling OpenSearch directly — it applies hybrid search + re-ranking automatically

---

## Security

| Control | Configuration |
|---|---|
| Encryption at rest | AWS-managed KMS key |
| Encryption in transit | HTTPS only, TLS 1.2 minimum |
| Network | VPC-only (no public access) |
| Authentication | Fine-grained access control (IAM ARN-based) |
| Authorization | Index-level permissions per IAM role |
| Audit | CloudWatch slow-query and application logs |
| PII | `piiDetected` field used to gate access; raw PII is redacted before indexing |
