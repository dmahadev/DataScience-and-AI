# DocuMagic – Agentic AI Architecture: Terraform Infrastructure

This directory contains the complete **Terraform Infrastructure-as-Code (IaC)** for the
DocuMagic Agentic AI platform. Every AWS service visible in the architecture diagram is
configured and wired together here.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    DocuMagic – Agentic AI Architecture                      │
│                                                                             │
│  Ingestion Channels          Ingestion Gateway & Service                    │
│  ┌──────────────────┐        ┌────────────────────────────┐                 │
│  │ AWS Amplify       │──────▶│ Amazon API Gateway          │                │
│  │ REST API          │       │ Amazon Cognito (auth)       │                │
│  │ S3 / Azure Blob   │       └────────────┬───────────────┘                 │
│  │ Email (SMTP)      │                    │                                 │
│  └──────────────────┘                     ▼                                 │
│                              ┌────────────────────────────┐                 │
│                              │  Event Streaming Layer      │                 │
│                              │  Amazon MSK (Kafka)         │                 │
│                              └────────────┬───────────────┘                 │
│                                           ▼                                 │
│  ┌────────────────────────────────────────────────────────┐                 │
│  │            Document AI Processing Pipeline              │                 │
│  │  Amazon Textract ──▶ AWS Lambda ──▶ Amazon Bedrock     │                 │
│  │  Amazon OpenSearch Service ──▶ DynamoDB                │                 │
│  └────────────────────────────────────────────────────────┘                 │
│            │                                                                │
│            ▼                                                                │
│  ┌─────────────────────────────────────────────────────────┐                │
│  │              Knowledge Transformation                    │                │
│  │  Amazon Bedrock ──▶ Amazon Comprehend ──▶ DynamoDB      │                │
│  └─────────────────────────────────────────────────────────┘                │
│            │                                                                │
│            ▼                                                                │
│  ┌─────────────────────────────────────────────────────────┐                │
│  │               Storage & Retrieval                        │                │
│  │  RAG APIs ──▶ OpenSearch / Bedrock KB                   │                │
│  │  A2A APIs ──▶ Bedrock Agent / Agent Alias               │                │
│  └─────────────────────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Terraform File Structure

| File | Services Configured |
|---|---|
| `main.tf` | Provider, Terraform version, backend, locals, data sources |
| `variables.tf` | All input variables with defaults |
| `outputs.tf` | All resource identifiers exported as outputs |
| `networking.tf` | VPC, subnets, NAT gateways, route tables, security groups, VPC endpoints |
| `iam.tf` | IAM roles and inline policies for Lambda, Step Functions, Bedrock, EventBridge, Textract |
| `s3.tf` | Raw-ingest, processed, knowledge-base, and Amplify-artifacts S3 buckets |
| `cognito.tf` | Cognito User Pool, Identity Pool, App Client (browser + M2M), Resource Server, User Groups |
| `api_gateway.tf` | REST API, Cognito authorizer, resources/methods/integrations, deployment, usage plan |
| `msk.tf` | MSK Kafka cluster, MSK configuration, MSK Connect S3 sink connector |
| `lambda.tf` | Five Lambda functions: textract-processor, bedrock-processor, opensearch-indexer, rag-api, a2a-api |
| `textract.tf` | Textract async SNS topic, subscriptions, SSM parameters |
| `bedrock.tf` | Bedrock Knowledge Base (OpenSearch Serverless vector store), Agent, Agent Alias, Data Source |
| `opensearch.tf` | OpenSearch Service domain (VPC, encryption, auto-tune, logging) |
| `opensearch_indexes.tf` | Index mappings stored in SSM Parameter Store, ISM rollover policy |
| `rds.tf` | Aurora PostgreSQL 15 Serverless v2 cluster, RDS Proxy, KMS key, Secrets Manager, CloudWatch alarms |
| `dynamodb.tf` | Seven DynamoDB tables: documents, sessions, knowledge-base, agent-conversations, agent-tasks, rate-limits, tenant-config |
| `step_functions.tf` | Document AI processing state machine (7-step pipeline) |
| `eventbridge.tf` | Custom event bus, four EventBridge rules, SNS pipeline-events topic |
| `amplify.tf` | Amplify App, main/staging branches, environment variables |
| `comprehend.tf` | Comprehend IAM role, SSM parameters, optional custom classifier |
| `cloudwatch.tf` | SNS alarms topic, log groups (9), metric alarms (7), CloudWatch dashboard |

---

## Prerequisites

1. [Terraform >= 1.5](https://developer.hashicorp.com/terraform/install)
2. AWS credentials with permissions to create all services listed above
3. AWS CLI configured (`aws configure`)
4. (Optional) An S3 bucket and DynamoDB table for remote Terraform state

---

## Quick Start

```bash
# 1. Clone and navigate
cd infrastructure/

# 2. Initialise Terraform
terraform init

# 3. Review the plan
terraform plan \
  -var="environment=development" \
  -var="aws_region=us-west-2" \
  -var="alarm_email=ops@example.com"

# 4. Apply
terraform apply \
  -var="environment=development" \
  -var="aws_region=us-west-2" \
  -var="alarm_email=ops@example.com"
```

---

## Key Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-west-2` | AWS region |
| `environment` | `production` | `development` / `staging` / `production` |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `msk_instance_type` | `kafka.m5.large` | MSK broker instance type |
| `msk_broker_count` | `3` | Number of Kafka brokers |
| `opensearch_instance_type` | `r6g.large.search` | OpenSearch data node type |
| `opensearch_instance_count` | `2` | Number of OpenSearch nodes |
| `rds_engine_version` | `15.4` | Aurora PostgreSQL engine version |
| `rds_serverless_min_capacity` | `0.5` | Aurora Serverless v2 minimum ACUs |
| `rds_serverless_max_capacity` | `16.0` | Aurora Serverless v2 maximum ACUs |
| `rds_reader_count` | `1` | Number of Aurora read replicas |
| `rds_backup_retention_days` | `14` | Aurora automated backup retention |
| `bedrock_agent_model_id` | `anthropic.claude-3-sonnet-20240229-v1:0` | Claude model for Bedrock Agent |
| `lambda_runtime` | `python3.11` | Lambda runtime |
| `log_retention_days` | `30` | CloudWatch log retention |
| `enable_enhanced_monitoring` | `true` | Deploy CloudWatch alarms and dashboard |
| `alarm_email` | `ops@documagic.example.com` | Alert email address |

---

## AWS Services Configured

### Ingestion Channels
- **AWS Amplify** – React/Next.js frontend with Cognito-backed authentication
- **Amazon API Gateway** – REST endpoints for document upload, RAG query, A2A invocation
- **Amazon S3** – Raw-ingest bucket (triggers Lambda on upload), processed, knowledge-base buckets

### Authentication and Authorization
- **Amazon Cognito User Pool** – email/password + TOTP MFA, user groups (Admins / Users)
- **Amazon Cognito Identity Pool** – grants temporary AWS credentials to authenticated users
- **API Gateway Cognito Authorizer** – JWT validation on all protected endpoints

### Event Streaming
- **Amazon MSK (Kafka)** – 3-broker cluster with TLS/IAM auth, `documagic.documents.*` topics
- **MSK Connect** – S3 sink connector archives all Kafka events to the processed bucket

### Document AI Processing Pipeline
- **Amazon Textract** – async document analysis (TABLES, FORMS, SIGNATURES, LAYOUT)
- **AWS Lambda (x5)** – textract-processor, bedrock-processor, opensearch-indexer, rag-api, a2a-api
- **Amazon Bedrock (Claude)** – document summarisation, Q&A, knowledge enrichment
- **Amazon OpenSearch Service** – semantic search, vector similarity, dense retrieval
- **AWS Step Functions** – 7-step orchestration: Validate → Textract → Enrich (Parallel) → Index → DynamoDB → EventBridge

### Knowledge Transformation
- **Amazon Bedrock Knowledge Base** – OpenSearch Serverless vector store with S3 data source
- **Amazon Comprehend** – entity extraction, sentiment analysis, PII detection
- **Amazon DynamoDB (x7)** – documents, sessions, knowledge-base, agent-conversations, agent-tasks, rate-limits, tenant-config

### Database Tier
- **Amazon Aurora PostgreSQL 15 Serverless v2** – relational master data (organisations, users, documents, billing, audit), with RDS Proxy for Lambda connection pooling
- **Amazon OpenSearch Service (4 indexes)** – hybrid BM25+knn document search, RAG chunk store, audit logs, entity registry
- **Amazon OpenSearch Serverless** – Bedrock Knowledge Base vector store (required by Bedrock KB API)
- **Amazon DynamoDB (7 tables)** – hot operational data at single-digit millisecond latency

See [`../docs/database/README.md`](../docs/database/README.md) for the full database design documentation.

### Orchestration and Events
- **AWS Step Functions** – STANDARD state machine with parallel enrichment, retries, error handling
- **Amazon EventBridge** – custom bus, 4 rules (S3 → pipeline, completion, failure, nightly sync)
- **Amazon SNS** – alarms topic, pipeline-events topic, Textract-completion topic

### Observability
- **Amazon CloudWatch** – 9 log groups, 7 metric alarms, 1 multi-service dashboard

---

## Security Considerations

- All S3 buckets are **private** with public access blocked and SSE-KMS encryption
- All Lambda functions run inside the **VPC** (private subnets)
- MSK uses **TLS + IAM authentication** (no plaintext)
- OpenSearch is **VPC-only** with HTTPS enforced (TLS 1.2+)
- IAM follows **least-privilege**: each role only has the permissions it needs
- Cognito enforces **MFA** (optional for users, configurable per group)
- DynamoDB tables have **Point-in-Time Recovery** and **SSE** enabled
- Lambda environment variables reference SSM Parameter Store paths (no hardcoded secrets)

---

## Post-Deployment Steps

1. **Upload Lambda code** – replace the stub ZIPs with real deployment packages from S3
2. **Create Kafka topics** – run `kafka-topics.sh` commands documented in `msk.tf`
3. **Initialise OpenSearch indexes** – run `./scripts/opensearch_init.sh <ENDPOINT>`
4. **Sync Cognito callback URLs** – update `cognito_callback_urls` to the real Amplify domain
5. **Upload MSK Connect plugin** – upload the Kafka S3 connector ZIP to the Amplify artifacts bucket
6. **Trigger first KB ingestion** – place documents in `s3://<KB_BUCKET>/` and start ingestion

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| `NoSuchBucket` on `terraform apply` | S3 bucket names must be globally unique; set `s3_raw_bucket_name` / `s3_processed_bucket_name` / `s3_knowledge_base_bucket_name` |
| MSK `InvalidConfiguration` | Ensure `msk_broker_count` is a multiple of the number of AZs |
| OpenSearch `ValidationException` | `opensearch_instance_count` must be >= 2 for zone awareness |
| Lambda stub ZIP errors | Replace `data.archive_file.lambda_stub` with real S3 artifact sources |
| Bedrock throttling | Increase concurrency limits or enable Provisioned Throughput for your model |
| Provider not found | Ensure `terraform init` completed successfully with `~> 5.0` AWS provider |

---

## Contributing

1. Create a feature branch
2. Run `terraform fmt -recursive` and `terraform validate`
3. Submit a pull request with a description of the changes

---

_Last updated: 2026-03-10_
