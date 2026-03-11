# DocuMagic – Documentation Index

Welcome to the **DocuMagic Agentic AI** documentation. All project documentation is organised in this `docs/` directory.

---

## 📄 Solution Architecture Document

> **Start here** for a complete end-to-end overview of the system.

| Document | Description | Download |
|---|---|---|
| [**Solution Architecture**](solution-architecture.md) | Full solution architecture: components, data flows, security, scalability, deployment, cost model | [Raw / Download](https://raw.githubusercontent.com/dmahadev/DataScience-and-AI/copilot/add-data-processing-pipeline/docs/solution-architecture.md) |

---

## 🗄️ Database Design

> Three-tier database architecture for Vector DB, RDBMS, and NoSQL.

| Document | Description |
|---|---|
| [Database Overview](database/README.md) | Three-tier architecture overview, data flows, security matrix |
| [Vector DB Schema](database/vector_db_schema.md) | OpenSearch index mappings, knn configuration, hybrid search queries |
| [RDBMS Schema (SQL)](database/rdbms_schema.sql) | Aurora PostgreSQL 15 DDL: tables, indexes, partitions, triggers, views |
| [NoSQL Schema](database/nosql_schema.md) | DynamoDB table designs, GSIs, access patterns, item shapes |

---

## 🏗️ Infrastructure

> Terraform IaC documentation.

| Document | Description |
|---|---|
| [Infrastructure README](../infrastructure/README.md) | Terraform file structure, quick start, variables reference, AWS services |

---

## 📦 Repository Structure

```
DataScience-and-AI/
├── docs/
│   ├── README.md                   ← This file (documentation index)
│   ├── solution-architecture.md    ← Full solution architecture document
│   └── database/
│       ├── README.md               ← Three-tier database overview
│       ├── vector_db_schema.md     ← OpenSearch / Vector DB design
│       ├── rdbms_schema.sql        ← Aurora PostgreSQL DDL
│       └── nosql_schema.md         ← DynamoDB table design
├── infrastructure/
│   ├── README.md                   ← Terraform usage guide
│   ├── main.tf                     ← Provider, backend, locals
│   ├── variables.tf                ← All input variables
│   ├── outputs.tf                  ← All resource outputs
│   ├── networking.tf               ← VPC, subnets, security groups
│   ├── rds.tf                      ← Aurora PostgreSQL cluster
│   ├── dynamodb.tf                 ← DynamoDB tables (7)
│   ├── opensearch.tf               ← OpenSearch Service domain
│   ├── opensearch_indexes.tf       ← Index mappings + ISM policies
│   ├── bedrock.tf                  ← Bedrock Knowledge Base + Agent
│   ├── lambda.tf                   ← Lambda functions (5)
│   ├── step_functions.tf           ← Processing state machine
│   ├── api_gateway.tf              ← REST API + Cognito authoriser
│   ├── cognito.tf                  ← User Pool + Identity Pool
│   ├── msk.tf                      ← Kafka cluster + Connect
│   ├── s3.tf                       ← S3 buckets
│   ├── eventbridge.tf              ← Event bus + rules
│   ├── cloudwatch.tf               ← Logs, alarms, dashboard
│   ├── iam.tf                      ← IAM roles + policies
│   ├── amplify.tf                  ← Frontend hosting
│   ├── comprehend.tf               ← NLP service config
│   └── textract.tf                 ← Document extraction config
├── src/                            ← FastAPI Python microservice
│   ├── api/                        ← REST API routes, config, models
│   ├── agents/                     ← Ingestion, Processing, Bedrock agents
│   ├── pipeline/                   ← Orchestrator + step definitions
│   └── utils/                      ← AWS utilities, structured logging
├── k8s/                            ← Kubernetes manifests (ConfigMap, HPA)
├── Dockerfile                      ← Multi-stage container build
└── requirements.txt                ← Python dependencies
```

---

_Last updated: 2026-03-11_
