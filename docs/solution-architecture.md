# DocuMagic – Solution Architecture Document

> **Version:** 1.0.0  
> **Date:** 2026-03-11  
> **Status:** Release  
> **Download:** [Raw Markdown](https://raw.githubusercontent.com/dmahadev/DataScience-and-AI/copilot/add-data-processing-pipeline/docs/solution-architecture.md) · [ZIP Archive](https://github.com/dmahadev/DataScience-and-AI/archive/refs/heads/copilot/add-data-processing-pipeline.zip)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Technology Stack](#3-technology-stack)
4. [Component Reference](#4-component-reference)
   - 4.1 [Frontend – AWS Amplify](#41-frontend--aws-amplify)
   - 4.2 [API Gateway & Authentication](#42-api-gateway--authentication)
   - 4.3 [Event Streaming – Amazon MSK](#43-event-streaming--amazon-msk)
   - 4.4 [Document Processing Pipeline](#44-document-processing-pipeline)
   - 4.5 [AI & Machine Learning Layer](#45-ai--machine-learning-layer)
   - 4.6 [Data & Storage Layer](#46-data--storage-layer)
   - 4.7 [Container Platform](#47-container-platform)
   - 4.8 [Observability & Alerting](#48-observability--alerting)
5. [Database Design](#5-database-design)
   - 5.1 [Vector Database (OpenSearch)](#51-vector-database--amazon-opensearch)
   - 5.2 [RDBMS (Aurora PostgreSQL)](#52-rdbms--amazon-aurora-postgresql)
   - 5.3 [NoSQL (DynamoDB)](#53-nosql--amazon-dynamodb)
6. [Data Flows](#6-data-flows)
   - 6.1 [Document Ingestion Flow](#61-document-ingestion-flow)
   - 6.2 [RAG Query Flow](#62-rag-query-flow)
   - 6.3 [Agentic Task Flow](#63-agentic-task-flow)
7. [Security Architecture](#7-security-architecture)
8. [Scalability & High Availability](#8-scalability--high-availability)
9. [Deployment Guide](#9-deployment-guide)
10. [Cost Model](#10-cost-model)
11. [Decision Log](#11-decision-log)

---

## 1. Executive Summary

**DocuMagic** is a cloud-native, **Agentic AI** platform that transforms unstructured documents into actionable intelligence. It combines state-of-the-art large language models, vector search, and a robust event-driven data pipeline to deliver:

- **Automated document understanding** — PDF, image, Word, and structured-data ingestion via Amazon Textract
- **AI-powered enrichment** — summarisation, entity extraction, sentiment analysis, and PII detection via Amazon Bedrock (Claude) and Amazon Comprehend
- **Retrieval-Augmented Generation (RAG)** — sub-second semantic question-answering grounded in the user's own document corpus
- **Agent-to-Agent (A2A) orchestration** — Bedrock Agents that can delegate sub-tasks to specialist agents and compose complex multi-step workflows
- **Multi-tenant SaaS** — organisation-level isolation, per-tenant feature flags, usage billing, and API rate limiting

The platform is fully managed on **AWS**, provisioned with **Terraform Infrastructure-as-Code**, and containerised with **Docker / Kubernetes** for the data-processing microservice tier.

---

## 2. Architecture Overview

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                     DocuMagic – Agentic AI Architecture                        ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │  INGESTION CHANNELS                                                      │    ║
║  │                                                                          │    ║
║  │  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  ┌────────────┐  │    ║
║  │  │ AWS Amplify │  │  REST API    │  │ S3 / Azure    │  │ Email /    │  │    ║
║  │  │ (React SPA) │  │  (direct)    │  │ Blob Upload   │  │ SMTP       │  │    ║
║  │  └──────┬──────┘  └──────┬───────┘  └───────┬───────┘  └─────┬──────┘  │    ║
║  └─────────┼───────────────┼──────────────────┼────────────────┼──────────┘    ║
║            └───────────────┴──────────────────┴────────────────┘               ║
║                                        │                                        ║
║                                        ▼                                        ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │  INGESTION GATEWAY                                                       │    ║
║  │                                                                          │    ║
║  │  ┌──────────────────────┐    ┌──────────────────────────────────────┐   │    ║
║  │  │  Amazon API Gateway  │    │  Amazon Cognito                      │   │    ║
║  │  │  REST API (v1)       │◄───│  User Pool + Identity Pool + MFA     │   │    ║
║  │  └──────────┬───────────┘    └──────────────────────────────────────┘   │    ║
║  └─────────────┼───────────────────────────────────────────────────────────┘    ║
║                │                                                                ║
║                ▼                                                                ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │  EVENT STREAMING LAYER                                                   │    ║
║  │                                                                          │    ║
║  │  ┌─────────────────────────────────────────────────────────────┐        │    ║
║  │  │  Amazon MSK (Apache Kafka 3.5)                               │        │    ║
║  │  │  ├── documagic.documents.ingested                            │        │    ║
║  │  │  ├── documagic.documents.processed                          │        │    ║
║  │  │  ├── documagic.documents.failed                             │        │    ║
║  │  │  └── documagic.agents.tasks                                 │        │    ║
║  │  └─────────────────────────────────────────────────────────────┘        │    ║
║  └─────────────────────────────────────────────────────────────────────────┘    ║
║                │                                                                ║
║                ▼                                                                ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │  DOCUMENT AI PROCESSING PIPELINE (AWS Step Functions)                   │    ║
║  │                                                                          │    ║
║  │  Validate ──► Textract ──► ┌── Bedrock (summarise) ──┐                  │    ║
║  │                             ├── Comprehend (entities) ─┤► Index ──► Done │    ║
║  │                             └── Comprehend (PII scan) ─┘                 │    ║
║  │                                                                          │    ║
║  │  Lambda functions: textract-processor, bedrock-processor,               │    ║
║  │                    opensearch-indexer, rag-api, a2a-api                  │    ║
║  └─────────────────────────────────────────────────────────────────────────┘    ║
║                │                                                                ║
║        ┌───────┴────────┬─────────────────┐                                    ║
║        ▼                ▼                 ▼                                    ║
║  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────────────────┐   ║
║  │  VECTOR DB   │ │    RDBMS     │ │           NoSQL                       │   ║
║  │              │ │              │ │                                        │   ║
║  │  OpenSearch  │ │  Aurora PG   │ │  DynamoDB (7 tables)                  │   ║
║  │  Service     │ │  Serverless  │ │  documents | sessions | kb-chunks     │   ║
║  │  (4 indexes) │ │  v2 (9 tbl)  │ │  agent-conversations | agent-tasks    │   ║
║  │              │ │              │ │  rate-limits | tenant-config           │   ║
║  │  OSS Coll.   │ │  RDS Proxy   │ │                                        │   ║
║  │  (Bedrock KB)│ │  (pooling)   │ │                                        │   ║
║  └──────────────┘ └──────────────┘ └──────────────────────────────────────┘   ║
║                                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │  OBSERVABILITY                                                           │    ║
║  │  CloudWatch Logs · CloudWatch Metrics · CloudWatch Dashboard            │    ║
║  │  SNS Alarms · EventBridge Bus · X-Ray Tracing (Lambda)                  │    ║
║  └─────────────────────────────────────────────────────────────────────────┘    ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## 3. Technology Stack

### AWS Services

| Category | Service | Version / Config | Purpose |
|---|---|---|---|
| Frontend | AWS Amplify | Gen 2 | React SPA hosting, CI/CD, env config |
| Auth | Amazon Cognito | User Pool + Identity Pool | JWT auth, MFA, federated identity |
| API | Amazon API Gateway | REST API v1 | Rate-limited, Cognito-authorised endpoints |
| Streaming | Amazon MSK | Apache Kafka 3.5.1 | Event-driven document pipeline |
| Compute | AWS Lambda | Python 3.11 | Serverless function execution |
| OCR/Extraction | Amazon Textract | Async | PDF / image / form extraction |
| LLM | Amazon Bedrock (Claude 3 Sonnet) | `anthropic.claude-3-sonnet-20240229-v1:0` | Summarisation, Q&A, agent reasoning |
| Embeddings | Amazon Titan Text Embed v2 | `amazon.titan-embed-text-v2:0` | 1536-dim dense embeddings |
| Agents | Amazon Bedrock Agents | — | Multi-step agentic orchestration |
| NLP | Amazon Comprehend | Managed | Entity, sentiment, PII, key phrase |
| Orchestration | AWS Step Functions | STANDARD | 7-step document processing state machine |
| Events | Amazon EventBridge | Custom bus | Service-to-service event routing |
| Vector DB | Amazon OpenSearch Service | 2.11 | Hybrid (BM25 + knn) document search |
| Vector KB | Amazon OpenSearch Serverless | VECTORSEARCH | Bedrock Knowledge Base vector store |
| RDBMS | Amazon Aurora PostgreSQL | 15.4 Serverless v2 | Relational master data |
| NoSQL | Amazon DynamoDB | On-demand | Hot operational data |
| Object Storage | Amazon S3 | — | Raw, processed, knowledge-base documents |
| Notifications | Amazon SNS | — | Alarms, pipeline events, Textract callbacks |
| Monitoring | Amazon CloudWatch | — | Logs, metrics, alarms, dashboard |
| IAM | AWS IAM | — | Least-privilege roles per service |
| Secrets | AWS Secrets Manager | — | DB credentials, API keys |
| Config | AWS Systems Manager | Parameter Store | Runtime configuration |

### Application Stack

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| API Service | FastAPI | 0.110.0 | REST API framework (Python) |
| API Server | Uvicorn | 0.29.0 | ASGI server |
| Data Models | Pydantic v2 | 2.6.4 | Request/response schema validation |
| AWS SDK | boto3 / botocore | 1.34.69 | AWS service clients |
| Data Processing | pandas | 2.2.1 | Tabular data transformation |
| Columnar Storage | pyarrow | 15.0.2 | Parquet read/write |
| Observability | structlog | 24.1.0 | Structured JSON logging |
| Metrics | prometheus-client | 0.20.0 | Prometheus metrics exposition |
| Resilience | tenacity | 8.2.3 | Retry logic with exponential backoff |
| Container | Docker | Multi-stage | Python 3.11-slim builder + runtime |
| Orchestration | Kubernetes | HPA enabled | 2–10 API pods, 1–5 agent pods |
| IaC | Terraform | ≥ 1.5.0 | AWS infrastructure provisioning |

---

## 4. Component Reference

### 4.1 Frontend – AWS Amplify

**Service:** AWS Amplify (Gen 2)  
**IaC:** `infrastructure/amplify.tf`

AWS Amplify hosts the React single-page application (SPA) and provides:

- Continuous deployment from the `main` branch (production) and `staging` branch
- Environment variable injection (`COGNITO_USER_POOL_ID`, `API_BASE_URL`, etc.)
- CloudFront-backed CDN with HTTPS
- Cognito Hosted UI redirect for OAuth 2.0 login

**Configuration:**

| Variable | Value |
|---|---|
| Framework | React / Next.js (auto-detected) |
| Branches | `main` → production; `staging` → staging |
| Cognito Redirect | `https://<app>.amplifyapp.com/callback` |
| API Base URL | `https://<api-id>.execute-api.us-west-2.amazonaws.com/v1` |

---

### 4.2 API Gateway & Authentication

**Services:** Amazon API Gateway (REST) · Amazon Cognito  
**IaC:** `infrastructure/api_gateway.tf`, `infrastructure/cognito.tf`

#### API Gateway

A REST API with a Cognito JWT authoriser protects all endpoints except `GET /health`. The API proxies requests to the appropriate Lambda function:

| Method | Path | Lambda Target | Description |
|---|---|---|---|
| `POST` | `/v1/documents` | `textract-processor` | Upload a new document |
| `GET` | `/v1/documents/{id}` | `rag-api` | Get document status and metadata |
| `POST` | `/v1/query` | `rag-api` | RAG question-answering |
| `POST` | `/v1/agents/invoke` | `a2a-api` | Invoke Bedrock Agent |
| `GET` | `/v1/health` | `rag-api` | Health check (no auth) |

A **usage plan** enforces rate limiting at the API Gateway level:
- Rate: 1,000 requests/second
- Burst: 2,000 requests
- Quota: 1,000,000 requests/month per API key

#### Amazon Cognito

| Resource | Configuration |
|---|---|
| User Pool | Email-based sign-up, optional TOTP MFA |
| User Groups | `Admins` (full access), `Users` (standard access) |
| Identity Pool | Grants temporary AWS credentials for S3 direct upload |
| App Client (Browser) | Implicit flow, ID + access tokens |
| App Client (M2M) | Client credentials flow for service-to-service |
| Resource Server | Custom OAuth scopes: `documagic/read`, `documagic/write` |

---

### 4.3 Event Streaming – Amazon MSK

**Service:** Amazon MSK (Apache Kafka 3.5.1)  
**IaC:** `infrastructure/msk.tf`

MSK decouples document ingestion from the AI processing pipeline. When a document is accepted by the API, an event is published to Kafka rather than synchronously triggering processing. This provides:

- **Back-pressure handling** – processing catches up at its own pace
- **At-least-once delivery** – Kafka retention ensures no events are lost
- **Replay capability** – failed documents can be reprocessed from the Kafka log

#### Cluster Configuration

| Property | Value |
|---|---|
| Kafka Version | 3.5.1 |
| Broker Count | 3 (multi-AZ) |
| Instance Type | `kafka.m5.large` |
| EBS Storage | 100 GiB per broker |
| Authentication | IAM + TLS (mTLS disabled) |
| Encryption | TLS in-transit + EBS encryption |

#### Topics

| Topic | Partitions | Retention | Description |
|---|---|---|---|
| `documagic.documents.ingested` | 12 | 7 days | New document uploaded events |
| `documagic.documents.processed` | 12 | 7 days | Completed pipeline events |
| `documagic.documents.failed` | 6 | 30 days | Processing failure events |
| `documagic.agents.tasks` | 6 | 1 day | Agent task dispatch events |

#### MSK Connect

An S3 Sink Connector archives all Kafka events to the processed S3 bucket (`s3://<bucket>/kafka-archive/`) for long-term audit and replay.

---

### 4.4 Document Processing Pipeline

**Services:** AWS Step Functions · AWS Lambda · Amazon Textract  
**IaC:** `infrastructure/step_functions.tf`, `infrastructure/lambda.tf`, `infrastructure/textract.tf`

#### Step Functions State Machine

The document processing pipeline is implemented as a **STANDARD** Step Functions state machine with seven steps:

```
                    ┌─────────────┐
                    │  1. Validate │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ 2. Textract │  (async – SNS callback)
                    └──────┬──────┘
                           │
              ┌────────────▼────────────┐
              │   3. Parallel Enrich    │
              │ ┌──────────┐ ┌────────┐ │
              │ │ Bedrock  │ │Comprehend│ │
              │ │(summarise)│ │(NLP)   │ │
              │ └──────────┘ └────────┘ │
              └────────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │  4. Index   │  (OpenSearch)
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │5. DynamoDB  │  (status update)
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │6. EventBridge│  (completion event)
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  7. Done    │
                    └─────────────┘
```

Each step has **configurable retries** (3 attempts, exponential backoff) and **error handlers** that publish failure events to EventBridge.

#### Lambda Functions

| Function | Trigger | Memory | Timeout | Description |
|---|---|---|---|---|
| `textract-processor` | S3 ObjectCreated | 512 MB | 300 s | Starts Textract async job, updates DynamoDB |
| `bedrock-processor` | Step Functions | 512 MB | 300 s | Calls Bedrock Claude for summarisation + enrichment |
| `opensearch-indexer` | Step Functions | 512 MB | 300 s | Creates/updates OpenSearch document and chunk indexes |
| `rag-api` | API Gateway | 512 MB | 300 s | Handles RAG queries, session management |
| `a2a-api` | API Gateway | 512 MB | 300 s | Invokes Bedrock Agent, manages A2A task routing |

All Lambda functions run **inside the VPC** (private subnets), use **IAM roles** (no hardcoded credentials), and log to structured CloudWatch JSON.

---

### 4.5 AI & Machine Learning Layer

**Services:** Amazon Bedrock · Amazon Comprehend  
**IaC:** `infrastructure/bedrock.tf`, `infrastructure/comprehend.tf`

#### Amazon Bedrock – Foundation Models

| Use Case | Model | API |
|---|---|---|
| Document summarisation | Claude 3 Sonnet | `InvokeModel` |
| Q&A / RAG generation | Claude 3 Sonnet | `RetrieveAndGenerate` |
| Agent reasoning | Claude 3 Sonnet | `InvokeAgent` |
| Text embedding | Titan Text Embed v2 | `InvokeModel` |

#### Amazon Bedrock Knowledge Base

The Knowledge Base uses **OpenSearch Serverless** as its vector store. It:
- Automatically chunks S3 documents (fixed-size, 512 tokens, 20% overlap)
- Generates Titan embeddings for each chunk
- Stores vectors in the `documagic-kb-index` index of the Serverless collection
- Supports **hybrid search** (BM25 + knn) via the `HYBRID` override mode

#### Amazon Bedrock Agent

The Bedrock Agent (`documagic-agent`) is an autonomous AI orchestrator that:
- Receives natural language requests from users via the A2A API
- Plans and executes multi-step tasks (e.g., "compare these three contracts")
- Routes sub-tasks to specialist sub-agents
- Retrieves context from the Knowledge Base
- Calls Lambda action groups for external API access

#### Amazon Comprehend

| Feature | Output | Stored In |
|---|---|---|
| Entity recognition | Entity type, text, confidence | OpenSearch `entities` field (nested) |
| Key phrase extraction | Key phrases list | OpenSearch `keyPhrases` field |
| Sentiment analysis | POSITIVE/NEGATIVE/NEUTRAL/MIXED + scores | DynamoDB `documents` + OpenSearch |
| PII detection | PII entity types found | DynamoDB `piiDetected` flag |
| Language detection | ISO language code | DynamoDB + OpenSearch `language` field |

---

### 4.6 Data & Storage Layer

**Services:** Amazon S3 · Amazon DynamoDB · Amazon Aurora PostgreSQL · Amazon OpenSearch  
**IaC:** `infrastructure/s3.tf`, `infrastructure/dynamodb.tf`, `infrastructure/rds.tf`, `infrastructure/opensearch.tf`, `infrastructure/opensearch_indexes.tf`

See [Section 5 – Database Design](#5-database-design) for the full schema documentation.

#### Amazon S3 Buckets

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `raw-ingest` | User-uploaded raw documents | 90-day transition to Glacier |
| `processed` | Textract output, Parquet files, Kafka archive | 1-year retention |
| `knowledge-base` | Documents synced to Bedrock KB | Indefinite |
| `amplify-artifacts` | Frontend build artifacts, MSK Connect plugin | 30-day retention |

All buckets:
- Block all public access
- Server-side encryption with SSE-S3 (raw) or SSE-KMS (processed, KB)
- Versioning enabled
- Access logging enabled

---

### 4.7 Container Platform

**Services:** Docker · Kubernetes (EKS-compatible) · FastAPI  
**Files:** `Dockerfile`, `k8s/`

The **DocuMagic Data Processing API** is a containerised FastAPI microservice that provides a REST interface for direct pipeline triggering from internal services or CI/CD pipelines (separate from the user-facing API Gateway).

#### Container Build

Multi-stage Docker build:

```
Stage 1 (builder):  python:3.11-slim
  └── gcc + libpq-dev (compile-time deps)
  └── pip install -r requirements.txt → /install

Stage 2 (runtime):  python:3.11-slim
  └── non-root user (uid 1001)
  └── Copy /install + src/
  └── Expose :8000
  └── HEALTHCHECK → GET /health
```

#### Kubernetes Resources

| Resource | Configuration |
|---|---|
| Namespace | `documagic` |
| Deployment (api) | `2` replicas, `500m` CPU / `512Mi` RAM request |
| Deployment (agents) | `1` replica, `250m` CPU / `256Mi` RAM request |
| HPA (api) | Min 2 / Max 10 pods, CPU 70% / Memory 80% |
| HPA (agents) | Min 1 / Max 5 pods, CPU 70% / Memory 80% |
| ConfigMap | Runtime environment (non-secret) |
| Service | `ClusterIP` on port 8000 |

#### Pipeline Agents (Python)

| Agent Class | `agent_id` | Description |
|---|---|---|
| `IngestionAgent` | `ingestion` | Validates and registers raw files from S3 |
| `ProcessingAgent` | `processing` | Transforms data, outputs Parquet to S3 |
| `BedrockAgent` | `bedrock` | Invokes Claude for AI summarisation |

The `PipelineOrchestrator` executes agents sequentially:  
`ingest → process → analyse (optional)`

---

### 4.8 Observability & Alerting

**Services:** Amazon CloudWatch · Amazon SNS · Amazon EventBridge  
**IaC:** `infrastructure/cloudwatch.tf`, `infrastructure/eventbridge.tf`

#### CloudWatch Log Groups

| Log Group | Retention | Source |
|---|---|---|
| `/aws/lambda/textract-processor` | 30 days | Lambda |
| `/aws/lambda/bedrock-processor` | 30 days | Lambda |
| `/aws/lambda/opensearch-indexer` | 30 days | Lambda |
| `/aws/lambda/rag-api` | 30 days | Lambda |
| `/aws/lambda/a2a-api` | 30 days | Lambda |
| `/aws/opensearch/index-slow-logs` | 30 days | OpenSearch |
| `/aws/opensearch/search-slow-logs` | 30 days | OpenSearch |
| `/aws/rds/cluster/aurora/postgresql` | 30 days | Aurora |
| `/aws/states/document-pipeline` | 30 days | Step Functions |

#### CloudWatch Alarms

| Alarm | Metric | Threshold | Action |
|---|---|---|---|
| Lambda errors | `Errors` / invocations | > 1% | SNS |
| Lambda duration | `Duration` | > 240 s | SNS |
| OpenSearch CPU | `CPUUtilization` | > 80% | SNS |
| OpenSearch JVM | `JVMMemoryPressure` | > 85% | SNS |
| Aurora CPU | `CPUUtilization` | > 80% | SNS |
| Aurora connections | `DatabaseConnections` | > 900 | SNS |
| Aurora free memory | `FreeableMemory` | < 100 MB | SNS |

#### EventBridge Rules

| Rule | Source | Target | Description |
|---|---|---|---|
| `s3-to-pipeline` | S3 ObjectCreated | Step Functions | Auto-start pipeline on document upload |
| `pipeline-completed` | Step Functions SUCCESS | SNS | Notify on successful processing |
| `pipeline-failed` | Step Functions FAILED | SNS + DLQ | Notify and dead-letter on failure |
| `nightly-kb-sync` | Schedule (03:00 UTC) | Lambda | Re-sync Bedrock Knowledge Base |

---

## 5. Database Design

DocuMagic uses a **three-tier database architecture**, where each tier is optimised for a specific access pattern:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Write path: Lambda → DynamoDB (hot) → Stream → Aurora (cold/relational)   │
│  Read path:  RAG → OpenSearch (vector/text) + DynamoDB (operational)        │
│  Analytics:  Aurora (joins, reports, billing)                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

Detailed schema documentation is in [`docs/database/`](database/README.md):

| File | Contents |
|---|---|
| [`docs/database/README.md`](database/README.md) | Three-tier overview, data flows, security summary |
| [`docs/database/vector_db_schema.md`](database/vector_db_schema.md) | OpenSearch index mappings, knn configuration, sample queries |
| [`docs/database/rdbms_schema.sql`](database/rdbms_schema.sql) | Aurora PostgreSQL DDL (extensions, tables, indexes, triggers, views) |
| [`docs/database/nosql_schema.md`](database/nosql_schema.md) | DynamoDB table designs, GSIs, access patterns, item shapes |

### 5.1 Vector Database – Amazon OpenSearch

**Purpose:** Semantic similarity search, full-text retrieval, RAG chunk store, compliance audit trail, entity registry.

**Two deployments:**

| Deployment | Service | Use Case |
|---|---|---|
| Managed Domain | OpenSearch Service 2.11 | Lambda-driven document + chunk search |
| Serverless Collection | OpenSearch Serverless | Bedrock Knowledge Base (required) |

**Indexes on OpenSearch Service:**

| Index | Shards | Vector Dim | Key Fields |
|---|---|---|---|
| `documagic-documents` | 3+1r | 1536 (knn) | `rawText`, `summary`, `entities`, `embedding` |
| `documagic-kb-chunks` | 3+1r | 1536 (knn) | `text`, `chunkIndex`, `embedding` |
| `documagic-audit-logs` | 2+1r | None | `eventType`, `userId`, `timestamp` |
| `documagic-entities` | 2+1r | None | `entityType`, `normalizedText`, `documentIds` |

**HNSW Parameters:** `ef_construction=512`, `m=16`, space=`cosinesimil`, engine=`faiss`

**Embedding Model:** Amazon Titan Text Embed v2 (`amazon.titan-embed-text-v2:0`) — 1536 dimensions

### 5.2 RDBMS – Amazon Aurora PostgreSQL

**Purpose:** ACID-compliant master data with referential integrity, complex joins, compliance reporting, billing ledger.

**Cluster:** Aurora PostgreSQL 15.4, Serverless v2 (0.5–16 ACU), with RDS Proxy for Lambda connection pooling.

**Tables in `app` schema:**

| Table | Rows (Year 1 est.) | Key Relationships | Notes |
|---|---|---|---|
| `organisations` | 10 K | — | Multi-tenant master record |
| `users` | 100 K | → `organisations` | Synced from Cognito |
| `documents` | 5 M | → `users`, `organisations` | Authoritative document catalog |
| `document_permissions` | 15 M | → `documents`, `users` | Row-level ACL |
| `api_keys` | 500 K | → `organisations`, `users` | External integration |
| `webhook_subscriptions` | 50 K | → `organisations` | Outbound event hooks |
| `billing_events` | 50 M | → `organisations` | Usage ledger (partitioned by month) |
| `audit_log` | 200 M | → `users`, `organisations` | Compliance trail (partitioned by quarter) |
| `pipeline_runs` | 10 M | → `documents` | Step Functions execution history |

**Connection Pooling:** RDS Proxy (IAM auth required, TLS enforced, 50% idle connections)

### 5.3 NoSQL – Amazon DynamoDB

**Purpose:** Sub-millisecond hot operational data: document status, user sessions, agent state, rate limiting.

**7 Tables (all PAY_PER_REQUEST, SSE, PITR):**

| Table | PK | SK | GSIs | Streams |
|---|---|---|---|---|
| `documents` | `documentId` | `version` | `userId-createdAt`, `status-createdAt` | `NEW_AND_OLD_IMAGES` |
| `sessions` | `sessionId` | — | `userId-updatedAt` | — |
| `knowledge-base` | `chunkId` | — | `documentId-indexedAt` | — |
| `agent-conversations` | `sessionId` | `turnIndex` | `userId-startedAt`, `agentId-updatedAt` | — |
| `agent-tasks` | `taskId` | — | `sessionId-createdAt`, `status-createdAt`, `agentId-createdAt` | `NEW_AND_OLD_IMAGES` |
| `rate-limits` | `compositeKey` | `windowStart` | — | — |
| `tenant-config` | `orgId` | `configKey` | `planTier-orgId` | — |

---

## 6. Data Flows

### 6.1 Document Ingestion Flow

```
User / External System
        │
        │  POST /v1/documents (multipart/form-data OR S3 key)
        ▼
  [API Gateway]  ──JWT validate──►  [Cognito]
        │
        ▼
  [Lambda: rag-api]
  ├── Validate file type and size
  ├── Write to S3: raw-ingest bucket
  └── Write to DynamoDB: documents (status=uploaded, version=1)
        │
        │  S3 ObjectCreated event
        ▼
  [EventBridge Rule: s3-to-pipeline]
        │
        ▼
  [Step Functions: document-pipeline]
        │
  ┌─────▼─────────────────────────────────────────────────────────────┐
  │  Step 1: Validate                                                  │
  │    Lambda: textract-processor                                      │
  │    ├── Check MIME type, file size, org quota                       │
  │    └── DynamoDB UpdateItem: status=validating                      │
  │                                                                    │
  │  Step 2: Textract (async)                                          │
  │    ├── StartDocumentAnalysis (TABLES, FORMS, LAYOUT)               │
  │    ├── SNS completion notification → Lambda callback               │
  │    └── DynamoDB UpdateItem: status=textract_pending                │
  │                                                                    │
  │  Step 3: Parallel Enrichment                                       │
  │    ├── Branch A: Lambda: bedrock-processor                         │
  │    │     ├── Bedrock Claude: Summarise extracted text              │
  │    │     └── Bedrock Claude: Extract topics / categories           │
  │    └── Branch B: Lambda: bedrock-processor                         │
  │          ├── Comprehend: DetectEntities                            │
  │          ├── Comprehend: DetectSentiment                           │
  │          ├── Comprehend: DetectKeyPhrases                          │
  │          └── Comprehend: ContainsPiiEntities                       │
  │                                                                    │
  │  Step 4: Index                                                     │
  │    Lambda: opensearch-indexer                                      │
  │    ├── PUT /documagic-documents (full-text + embedding)            │
  │    ├── PUT /documagic-kb-chunks (N chunk records + embeddings)     │
  │    └── PUT /documagic-entities (aggregated entity registry)        │
  │                                                                    │
  │  Step 5: DynamoDB                                                  │
  │    ├── UpdateItem: documents (status=completed)                    │
  │    └── PutItem: knowledge-base (chunk registry records)            │
  │                                                                    │
  │  Step 6: EventBridge                                               │
  │    └── PutEvents: documagic.documents.processed                    │
  │                                                                    │
  │  Step 7: Done                                                      │
  └───────────────────────────────────────────────────────────────────┘
        │
        ▼
  [DynamoDB Stream] ──► [Lambda] ──► [Aurora: documents]
                                     (sync authoritative record)
        │
        ▼
  [MSK: documagic.documents.processed]
  └── MSK Connect S3 Sink: archive to processed bucket
```

### 6.2 RAG Query Flow

```
User
  │  POST /v1/query { "question": "What is the notice period?", "sessionId": "..." }
  ▼
[API Gateway] ──JWT──► [Cognito]
  │
  ▼
[Lambda: rag-api]
  │
  ├── 1. DynamoDB GetItem: sessions (load conversation history)
  │
  ├── 2. Rate limit check
  │       DynamoDB UpdateItem: rate-limits (ADD requestCount + ConditionExpression)
  │       If limit exceeded → 429 Too Many Requests
  │
  ├── 3. Embed user question
  │       Bedrock InvokeModel: Titan Text Embed v2 → 1536-dim vector
  │
  ├── 4a. OpenSearch knn search (direct retrieval)
  │        POST /documagic-kb-chunks/_search
  │        { knn: { embedding: <vector>, k: 5 }, filter: { orgId } }
  │
  │    OR
  │
  ├── 4b. Bedrock RetrieveAndGenerate (managed RAG)
  │        Knowledge Base: HYBRID search (BM25 + knn)
  │        → Returns answer with citations (no separate generation step)
  │
  ├── 5. [If 4a] Bedrock InvokeModel: Claude 3 Sonnet
  │        System: "Answer based only on context. Cite sources."
  │        User: [retrieved chunks] + [question]
  │        → Generated answer with citations
  │
  ├── 6. DynamoDB UpdateItem: sessions (append turn, update messageCount)
  │
  ├── 7. DynamoDB PutItem: agent-conversations (persist full turn)
  │
  └── 8. OpenSearch index: audit-logs (log event for compliance)
          └── Return { answer, citations, sessionId, latencyMs }
```

### 6.3 Agentic Task Flow

```
User
  │  POST /v1/agents/invoke { "message": "Compare contracts A and B", "sessionId": "..." }
  ▼
[API Gateway] ──JWT──► [Cognito]
  │
  ▼
[Lambda: a2a-api]
  │
  ├── 1. DynamoDB PutItem: agent-tasks (status=pending, taskType=compare_documents)
  │
  ├── 2. Bedrock InvokeAgent
  │       agentId: documagic-agent
  │       agentAliasId: documagic-agent-live
  │       sessionId: <user sessionId>
  │       inputText: "Compare contracts A and B"
  │       └── Agent reasons internally:
  │             ├── Plan: retrieve doc-A chunks, retrieve doc-B chunks, compare
  │             ├── Action: Retrieve from Knowledge Base (doc-A)
  │             ├── Action: Retrieve from Knowledge Base (doc-B)
  │             ├── Action: Lambda action group (get_document_metadata)
  │             └── Generate: comparative analysis with citations
  │
  ├── 3. DynamoDB UpdateItem: agent-tasks (status=completed, output=<response>)
  │
  ├── 4. DynamoDB PutItem: agent-conversations (append agent turn)
  │
  └── 5. Return { agentResponse, citations, taskId }
```

---

## 7. Security Architecture

### Defence-in-Depth Model

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1 – Edge                                                      │
│  CloudFront WAF rules · API Gateway throttling · Cognito MFA        │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 2 – Network                                                   │
│  VPC private subnets · No public Lambda · OpenSearch VPC-only       │
│  Security groups (allow only: Lambda→RDS:5432, Lambda→OS:443)       │
│  VPC Endpoints: DynamoDB, S3, Secrets Manager, SSM, Bedrock         │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 3 – Identity & Access                                         │
│  IAM roles (least-privilege) · No long-lived credentials            │
│  RDS Proxy IAM auth · Cognito JWT (RS256, 1-hour expiry)            │
│  Secrets Manager rotation for Aurora master password                 │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 4 – Data                                                      │
│  S3 SSE-KMS · Aurora KMS CMK · DynamoDB AWS-managed SSE             │
│  OpenSearch encrypt-at-rest + node-to-node TLS                      │
│  PII detection (Comprehend) + redaction before OpenSearch index      │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 5 – Application                                               │
│  orgId tenant isolation on every query · Pydantic input validation  │
│  DynamoDB rate limiting (atomic ADD + ConditionExpression)           │
│  Tenancy header validation in Lambda authoriser                      │
├─────────────────────────────────────────────────────────────────────┤
│  Layer 6 – Audit & Compliance                                        │
│  OpenSearch: documagic-audit-logs (every API call logged)            │
│  Aurora: audit_log table (partitioned, 7-year retention)             │
│  CloudWatch Logs + DynamoDB Streams for operational audit            │
│  CloudTrail (AWS API audit) – configured externally                  │
└─────────────────────────────────────────────────────────────────────┘
```

### Security Controls Matrix

| Control | Vector DB | RDBMS | NoSQL | Lambda | API GW |
|---|---|---|---|---|---|
| Encryption at rest | Customer KMS (OS) | Customer KMS | AWS-managed | — | N/A |
| Encryption in transit | TLS 1.2+ | TLS (enforced) | TLS via VPC ep. | HTTPS | TLS 1.2+ |
| Network isolation | VPC private | VPC private | VPC endpoint | VPC private | N/A |
| Authentication | IAM ARN | IAM + Secrets Mgr | IAM | Cognito JWT | Cognito JWT |
| Authorisation | IAM index perms | PostgreSQL roles | IAM actions | JWT claims | Usage plan |
| Backup | Replicated | Automated + PITR | PITR | — | N/A |
| Audit | CW slow logs | PG logs + audit_log | DDB Streams | CW Logs | CW Access Log |
| Multi-tenancy | `orgId` filter | `org_id` RLS | Partition key | JWT `org_id` | API key |

---

## 8. Scalability & High Availability

### Horizontal Scaling

| Component | Scaling Mechanism | Min | Max |
|---|---|---|---|
| Lambda functions | Automatic (concurrency) | 0 | 1,000 (account limit) |
| API Service (K8s) | HPA (CPU 70% / Memory 80%) | 2 pods | 10 pods |
| Agent Workers (K8s) | HPA (CPU 70%) | 1 pod | 5 pods |
| Aurora Serverless v2 | ACU auto-scaling | 0.5 ACU | 16 ACU |
| OpenSearch | Manual (instance type + count) | 2 nodes | N nodes |
| DynamoDB | On-demand (automatic) | — | — |
| MSK | Manual (broker count / instance type) | 3 brokers | — |

### High Availability Design

| Component | AZ Strategy | Failover RTO |
|---|---|---|
| API Gateway | Multi-AZ (managed) | < 60 s |
| Cognito | Multi-AZ (managed) | < 60 s |
| Lambda | Multi-AZ (managed) | < 10 s |
| MSK | 3 brokers across 3 AZs | < 30 s (leader election) |
| Aurora | Writer + 1 reader replica across 2 AZs | < 30 s (automated failover) |
| DynamoDB | Multi-AZ (managed, 3 replicas) | < 10 s |
| OpenSearch | 2+ nodes across 2 AZs, 3 dedicated masters | < 60 s |
| S3 | 11 nines durability, cross-AZ redundant | N/A |

### Disaster Recovery

| RTO Target | RPO Target | Strategy |
|---|---|---|
| < 1 hour | < 5 minutes | Aurora PITR + DynamoDB PITR + S3 versioning |
| < 4 hours | < 1 hour | Cross-region S3 replication (optional, enable per org) |

---

## 9. Deployment Guide

### Prerequisites

```bash
# Required tools
terraform --version   # >= 1.5.0
aws --version         # AWS CLI v2
kubectl version       # >= 1.28 (optional, for K8s deployment)
docker --version      # >= 24.0 (optional, for container build)
```

### AWS Infrastructure (Terraform)

```bash
# 1. Clone repository
git clone https://github.com/dmahadev/DataScience-and-AI.git
cd DataScience-and-AI/infrastructure

# 2. Initialise providers
terraform init

# 3. Review the plan (development environment)
terraform plan \
  -var="environment=development" \
  -var="aws_region=us-west-2" \
  -var="alarm_email=ops@example.com" \
  -var="rds_serverless_min_capacity=0.5" \
  -var="rds_serverless_max_capacity=4"

# 4. Apply
terraform apply \
  -var="environment=development" \
  -var="aws_region=us-west-2" \
  -var="alarm_email=ops@example.com"
```

### Database Initialisation

```bash
# 1. Initialise Aurora PostgreSQL schema
AURORA_HOST=$(aws secretsmanager get-secret-value \
  --secret-id "DocuMagic-production/aurora/master-credentials" \
  --query "SecretString" --output text | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])")

psql "host=${AURORA_HOST} dbname=documagic user=documagic_admin sslmode=require" \
  -f ../docs/database/rdbms_schema.sql

# 2. Initialise OpenSearch indexes
OPENSEARCH_ENDPOINT=$(aws ssm get-parameter \
  --name "/documagic/opensearch/endpoint" \
  --query "Parameter.Value" --output text)

./scripts/opensearch_init.sh "${OPENSEARCH_ENDPOINT}"

# 3. Trigger Bedrock Knowledge Base first ingestion
KB_ID=$(aws ssm get-parameter \
  --name "/documagic/bedrock/knowledge_base_id" \
  --query "Parameter.Value" --output text)

DS_ID=$(terraform output -raw bedrock_knowledge_base_id)

aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "${KB_ID}" \
  --data-source-id "${DS_ID}"
```

### Container Deployment (Kubernetes)

```bash
# 1. Build container image
docker build -t documagic-api:1.0.0 .

# 2. Push to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-west-2.amazonaws.com

docker tag documagic-api:1.0.0 \
  <account-id>.dkr.ecr.us-west-2.amazonaws.com/documagic-api:1.0.0

docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/documagic-api:1.0.0

# 3. Deploy to Kubernetes
kubectl create namespace documagic
kubectl apply -f k8s/

# 4. Verify deployment
kubectl get pods -n documagic
kubectl get hpa -n documagic
```

### Post-Deployment Checklist

- [ ] Upload Lambda function code packages (replace stub ZIPs with real packages)
- [ ] Create Kafka topics (`documagic.documents.*`, `documagic.agents.tasks`)
- [ ] Update Cognito callback URLs to real Amplify domain
- [ ] Upload MSK Connect plugin JAR to Amplify artifacts bucket
- [ ] Set `alarm_email` to real ops email address
- [ ] Enable CloudTrail (account-level audit, outside Terraform scope)
- [ ] Set up cross-region S3 replication for DR (if required)
- [ ] Test end-to-end document ingestion flow

---

## 10. Cost Model

Estimated monthly cost for a **development** environment (us-west-2):

| Service | Config | Est. Monthly Cost (USD) |
|---|---|---|
| Amazon MSK | 3× `kafka.m5.large` | ~$430 |
| Amazon OpenSearch Service | 2× `r6g.large.search`, 100 GiB | ~$350 |
| Aurora PostgreSQL | Serverless v2 (avg 1 ACU) + 1 reader | ~$80 |
| Lambda | 1M invocations, 512 MB, 10 s avg | ~$15 |
| API Gateway | 1M requests | ~$4 |
| DynamoDB | On-demand, 10 GB storage | ~$5 |
| S3 | 100 GB stored, 1M requests | ~$5 |
| Bedrock Claude 3 Sonnet | 1M input + 200K output tokens | ~$25 |
| Bedrock Titan Embed v2 | 10M tokens | ~$10 |
| Cognito | 1,000 MAU | ~$0 (free tier) |
| CloudWatch | Logs + Alarms + Dashboard | ~$20 |
| **Total (development)** | | **~$944 / month** |

> **Production note:** MSK and OpenSearch dominate cost. For production with scale, MSK can be right-sized to `kafka.m5.xlarge` and OpenSearch to `r6g.xlarge.search` with more nodes (~$1,500–$2,500/month depending on document volume).

---

## 11. Decision Log

| ID | Decision | Alternatives Considered | Rationale |
|---|---|---|---|
| D-01 | Aurora PostgreSQL for RDBMS | RDS PostgreSQL single-AZ, Cloud Spanner | Serverless v2 cost-scales to zero; PITR; easy Terraform provisioning |
| D-02 | OpenSearch for Vector DB | Pinecone, pgvector (in Aurora), Qdrant | Native AWS; IAM auth; supports hybrid BM25+knn; Bedrock KB integration |
| D-03 | Two OpenSearch deployments | Single managed domain for both | Bedrock KB requires Serverless; managed domain gives more knn tuning control |
| D-04 | DynamoDB for hot data | Redis/ElastiCache, MongoDB | Truly serverless; PITR; DynamoDB Streams for CDC; no connection management |
| D-05 | MSK over EventBridge Pipes | SQS, SNS, EventBridge Pipes | Kafka gives replay, ordered partitions, high-throughput at scale |
| D-06 | RDS Proxy | Direct Aurora connection | Lambda cold starts exhaust Aurora connections; Proxy provides pooling + IAM auth |
| D-07 | Step Functions STANDARD | Express, direct Lambda chaining | STANDARD gives full execution history; compensating transactions; human approval steps |
| D-08 | Titan Text Embed v2 | OpenAI text-embedding-3-large, Cohere | Native Bedrock; no data egress; 1536 dims is sufficient; Bedrock KB integrates natively |
| D-09 | FastAPI + Python | Flask, Go, Node.js | Team expertise; boto3 ecosystem; Pydantic v2 for schema validation |
| D-10 | Terraform | AWS CDK, Pulumi, CloudFormation | Mature HCL; strong provider; easy local dev; team familiarity |

---

_Last updated: 2026-03-11_  
_Maintained by: DocuMagic Team_  
_Repository: [dmahadev/DataScience-and-AI](https://github.com/dmahadev/DataScience-and-AI)_
