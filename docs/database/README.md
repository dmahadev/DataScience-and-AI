# DocuMagic – Database Design

This directory contains the complete database design for the **DocuMagic Agentic AI** platform across three complementary database tiers.

---

## Three-Tier Database Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DocuMagic Database Tiers                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  VECTOR DB  –  Amazon OpenSearch Service + OpenSearch Serverless     │   │
│  │                                                                      │   │
│  │  documagic-documents   Hybrid (BM25 + knn) document search          │   │
│  │  documagic-kb-chunks   RAG retrieval chunks (1536-dim HNSW)         │   │
│  │  documagic-audit-logs  Compliance audit trail (ISM rollover)        │   │
│  │  documagic-entities    Named entity registry for faceted search      │   │
│  │  Bedrock KB Collection OpenSearch Serverless vector store            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  RDBMS  –  Amazon Aurora PostgreSQL 15 (Serverless v2)              │   │
│  │                                                                      │   │
│  │  organisations         Multi-tenant master record                   │   │
│  │  users                 User accounts (synced from Cognito)          │   │
│  │  documents             Relational document catalog                  │   │
│  │  document_permissions  Fine-grained ACL                             │   │
│  │  api_keys              External integration keys                    │   │
│  │  webhook_subscriptions Outbound event notifications                 │   │
│  │  billing_events        Usage ledger (partitioned by month)          │   │
│  │  audit_log             Compliance audit (partitioned by quarter)    │   │
│  │  pipeline_runs         Step Functions execution history             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  NoSQL  –  Amazon DynamoDB (PAY_PER_REQUEST, SSE, PITR)             │   │
│  │                                                                      │   │
│  │  documents             Hot operational document state               │   │
│  │  sessions              RAG conversation sessions                    │   │
│  │  knowledge-base        KB chunk registry                            │   │
│  │  agent-conversations   Multi-turn agent dialogue history            │   │
│  │  agent-tasks           Agentic task queue                           │   │
│  │  rate-limits           Sliding-window API rate counters             │   │
│  │  tenant-config         Per-org configuration & feature flags        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Design Rationale – When to Use Each Tier

| Requirement | Tier | Reason |
|---|---|---|
| Semantic similarity search | **Vector DB** | knn over dense embeddings |
| Full-text search + faceting | **Vector DB** | BM25 + aggregations |
| RAG retrieval | **Vector DB** | knn chunks, Bedrock KB |
| Compliance audit trail | **Vector DB** | High-volume append + time-series |
| User / org master data | **RDBMS** | Referential integrity, joins |
| Document permissions (ACL) | **RDBMS** | Complex join queries |
| Usage billing | **RDBMS** | ACID transactions, partition pruning |
| Pipeline execution history | **RDBMS** | Duration calculations, reporting |
| Sub-millisecond document status | **NoSQL** | Single-digit ms at scale |
| Multi-turn session state | **NoSQL** | Key-value at Lambda speed |
| Agent task queue | **NoSQL** | Atomic conditional updates |
| Rate limiting | **NoSQL** | Atomic ADD + TTL |
| Per-tenant feature flags | **NoSQL** | Simple key-value lookup |

---

## File Index

| File | Contents |
|---|---|
| `README.md` | This overview document |
| `rdbms_schema.sql` | Aurora PostgreSQL DDL: tables, indexes, partitions, triggers, views |
| `nosql_schema.md` | DynamoDB table designs, access patterns, item shapes |
| `vector_db_schema.md` | OpenSearch index mappings, knn configuration, sample queries |

---

## Terraform Configuration

The database infrastructure is provisioned by these Terraform files in `infrastructure/`:

| Terraform File | Resources |
|---|---|
| `rds.tf` | Aurora cluster, RDS Proxy, parameter groups, KMS key, Secrets Manager, CloudWatch alarms |
| `dynamodb.tf` | 7 DynamoDB tables with GSIs, DynamoDB Streams on 2 tables |
| `opensearch.tf` | OpenSearch Service domain (VPC, fine-grained access control, auto-tune) |
| `opensearch_indexes.tf` | Index mappings (stored in SSM), ISM policies |
| `bedrock.tf` | OpenSearch Serverless collection (Bedrock KB vector store) |

---

## Data Flow Between Tiers

```
Document Upload
      │
      ▼
[S3 raw-ingest] ──trigger──► [Lambda: textract-processor]
                                      │
                                      ▼
                              [DynamoDB: documents]  ← status = "textract_pending"
                                      │
                              [Textract async job]
                                      │
                              [SNS completion topic]
                                      │
                                      ▼
                              [Lambda: bedrock-processor]
                              ├── Bedrock Claude (summarise)
                              └── Comprehend (entities)
                                      │
                                      ▼
                       ┌─────────────────────────────────┐
                       │    [Lambda: opensearch-indexer] │
                       ├── PUT /documagic-documents       │  ← Vector DB
                       ├── PUT /documagic-kb-chunks       │  ← Vector DB
                       ├── PUT /documagic-entities        │  ← Vector DB
                       └─────────────────────────────────┘
                                      │
                                      ▼
                              [DynamoDB: documents]  ← status = "completed"
                              [DynamoDB: knowledge-base] ← chunk registry
                                      │
                              [DynamoDB Stream] ──► [Lambda] ──► [Aurora: documents]
                                                                 ← sync to RDBMS
```

**RAG Query Path:**
```
User → API Gateway → [Lambda: rag-api]
  ├── DynamoDB: sessions (get/update conversation)
  ├── OpenSearch: documagic-kb-chunks (knn retrieval) OR
  │   Bedrock KB RetrieveAndGenerate API
  └── Bedrock Claude (generate answer with citations)
       └── DynamoDB: sessions (save turn)
            └── DynamoDB: agent-conversations (append turn)
                 └── Aurora: audit_log (compliance record)
```

---

## Security Summary

| Control | Vector DB | RDBMS | NoSQL |
|---|---|---|---|
| Encryption at rest | AWS KMS | Customer KMS | AWS-managed SSE |
| Encryption in transit | TLS 1.2+ | TLS (enforced) | TLS (enforced via VPC endpoint) |
| Network isolation | VPC private | VPC private | VPC endpoint |
| Authentication | IAM roles | IAM + Secrets Manager | IAM roles |
| Backup / recovery | N/A (replicated) | Automated backups + PITR | PITR enabled |
| Audit | CloudWatch slow logs | Aurora PostgreSQL logs | DynamoDB Streams |
| Multi-tenancy | `orgId` filter on all queries | Row-level org_id column | Partition key includes orgId |

---

## Initial Setup Sequence

```bash
# 1. Apply Terraform to provision all database infrastructure
cd infrastructure/
terraform apply

# 2. Initialize Aurora schema (run SQL as documagic_admin)
psql "$(aws secretsmanager get-secret-value \
  --secret-id DocuMagic-production/aurora/master-credentials \
  --query SecretString --output text | jq -r .host)" \
  -U documagic_admin -d documagic \
  -f ../docs/database/rdbms_schema.sql

# 3. Initialize OpenSearch indexes
ENDPOINT=$(aws ssm get-parameter \
  --name /documagic/opensearch/endpoint \
  --query Parameter.Value --output text)

./scripts/opensearch_init.sh "$ENDPOINT"

# 4. Trigger first Bedrock KB ingestion
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "$(aws ssm get-parameter \
    --name /documagic/bedrock/knowledge_base_id \
    --query Parameter.Value --output text)" \
  --data-source-id "$(terraform output -raw bedrock_knowledge_base_id)"
```

---

_Last updated: 2026-03-11_
