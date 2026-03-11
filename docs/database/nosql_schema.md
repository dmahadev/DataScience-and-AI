# DocuMagic – NoSQL Database Design (Amazon DynamoDB)

## Design Principles

DynamoDB is the **hot operational layer** for the DocuMagic Agentic AI platform. It stores data that must be accessed with **single-digit millisecond latency at any scale** and does not require complex joins. All tables use **on-demand (PAY_PER_REQUEST)** billing, server-side encryption (SSE), and point-in-time recovery.

The design follows DynamoDB best practices:
- **Single-table design** where query patterns are well-understood and co-located
- **Sparse indexes** (GSIs) only for patterns that need alternative access paths
- **Composite sort keys** to support range queries and pagination
- **TTL** on ephemeral data to control storage costs automatically

---

## Table Inventory

| Table | Primary Key | Sort Key | Purpose |
|---|---|---|---|
| `documents` | `documentId` (S) | `version` (N) | Document metadata + pipeline state |
| `sessions` | `sessionId` (S) | — | RAG conversation sessions |
| `knowledge-base` | `chunkId` (S) | — | KB chunk metadata |
| `agent-conversations` | `sessionId` (S) | `turnIndex` (N) | Multi-turn agent dialogue |
| `agent-tasks` | `taskId` (S) | — | Agentic task queue |
| `rate-limits` | `compositeKey` (S) | `windowStart` (S) | API rate limiting |
| `tenant-config` | `orgId` (S) | `configKey` (S) | Per-tenant configuration |

---

## Table 1: `documents`

**Description:** Operational document record. Updated throughout the AI processing pipeline. The Aurora PostgreSQL table holds the authoritative master copy; this table is the hot read path for Lambda functions.

### Key Schema

| Attribute | Type | Role | Notes |
|---|---|---|---|
| `documentId` | String | Partition Key (PK) | UUID |
| `version` | Number | Sort Key (SK) | Starts at `1`; incremented on reprocessing |
| `userId` | String | GSI PK | Cognito `sub` |
| `status` | String | GSI PK | Pipeline state |
| `createdAt` | String | GSI SK | ISO 8601 timestamp |

### Item Shape (DynamoDB JSON)

```json
{
  "documentId":       { "S": "doc-uuid-1234" },
  "version":          { "N": "1" },
  "userId":           { "S": "usr-cognito-sub" },
  "orgId":            { "S": "org-uuid-9999" },
  "status":           { "S": "completed" },
  "fileName":         { "S": "contract_2026.pdf" },
  "fileType":         { "S": "application/pdf" },
  "fileSizeBytes":    { "N": "2048576" },
  "s3Bucket":         { "S": "documagic-prod-raw-ingest-123456789012" },
  "s3Key":            { "S": "uploads/usr-sub/doc-uuid-1234/contract_2026.pdf" },
  "pageCount":        { "N": "12" },
  "textractJobId":    { "S": "textract-job-abc" },
  "pipelineRunId":    { "S": "arn:aws:states:us-west-2:123:execution:pipeline/run-id" },
  "language":         { "S": "en" },
  "summary":          { "S": "Service agreement between…" },
  "topics":           { "SS": ["legal", "contract", "employment"] },
  "sentiment":        { "S": "NEUTRAL" },
  "piiDetected":      { "BOOL": false },
  "opensearchDocId":  { "S": "os-doc-id-abc" },
  "createdAt":        { "S": "2026-03-10T17:45:00Z" },
  "updatedAt":        { "S": "2026-03-10T17:51:00Z" },
  "expiresAt":        { "N": "1788393600" }
}
```

### Global Secondary Indexes (GSIs)

| GSI Name | PK | SK | Projection | Query Pattern |
|---|---|---|---|---|
| `userId-createdAt-index` | `userId` | `createdAt` | ALL | List all documents for a user |
| `status-createdAt-index` | `status` | `createdAt` | INCLUDE (documentId, userId, s3Key, version) | Admin: find all PROCESSING documents |

### Access Patterns

| # | Pattern | Operation | Key |
|---|---|---|---|
| 1 | Get latest document by ID | GetItem | PK=documentId, SK=max version |
| 2 | Get specific document version | GetItem | PK=documentId, SK=version |
| 3 | List user documents (newest first) | Query GSI | PK=userId, SK=createdAt DESC |
| 4 | Find all PROCESSING documents | Query GSI | PK="processing", SK=createdAt |
| 5 | Update pipeline status | UpdateItem | PK=documentId, SK=version |

---

## Table 2: `sessions`

**Description:** User RAG conversation sessions. Each session holds the conversation history for multi-turn queries against the knowledge base.

### Key Schema

| Attribute | Type | Role | Notes |
|---|---|---|---|
| `sessionId` | String | Partition Key | UUID |
| `userId` | String | GSI PK | |
| `updatedAt` | String | GSI SK | ISO 8601 |

### Item Shape

```json
{
  "sessionId":    { "S": "sess-uuid-5678" },
  "userId":       { "S": "usr-cognito-sub" },
  "orgId":        { "S": "org-uuid-9999" },
  "title":        { "S": "Questions about Q4 contract" },
  "status":       { "S": "active" },
  "messageCount": { "N": "6" },
  "documentIds":  { "SS": ["doc-uuid-1234", "doc-uuid-5678"] },
  "agentId":      { "S": "bedrock-agent-id" },
  "agentAliasId": { "S": "bedrock-alias-id" },
  "startedAt":    { "S": "2026-03-10T18:00:00Z" },
  "updatedAt":    { "S": "2026-03-10T18:12:00Z" },
  "expiresAt":    { "N": "1788393600" }
}
```

### Access Patterns

| # | Pattern | Operation | Key |
|---|---|---|---|
| 1 | Get session by ID | GetItem | PK=sessionId |
| 2 | List recent sessions for user | Query GSI | PK=userId, SK=updatedAt DESC |
| 3 | Create new session | PutItem | PK=new UUID |
| 4 | Append message / update state | UpdateItem | PK=sessionId |

---

## Table 3: `knowledge-base`

**Description:** Registry of document chunks that have been embedded and stored in OpenSearch / Bedrock KB. Allows Lambda to track which chunks are indexed and detect drift.

### Key Schema

| Attribute | Type | Role |
|---|---|---|
| `chunkId` | String | Partition Key |
| `documentId` | String | GSI PK |
| `indexedAt` | String | GSI SK |

### Item Shape

```json
{
  "chunkId":        { "S": "chunk-uuid-abc" },
  "documentId":     { "S": "doc-uuid-1234" },
  "orgId":          { "S": "org-uuid-9999" },
  "chunkIndex":     { "N": "3" },
  "chunkTotal":     { "N": "24" },
  "tokenCount":     { "N": "487" },
  "embeddingModelId": { "S": "amazon.titan-embed-text-v2:0" },
  "opensearchIndexName": { "S": "documagic-kb-chunks" },
  "opensearchDocId":    { "S": "os-chunk-id-xyz" },
  "bedrockKbId":    { "S": "bedrock-kb-id" },
  "text":           { "S": "The contractor agrees to…" },
  "sourceSection":  { "S": "Section 4.2" },
  "sourcePage":     { "N": "7" },
  "indexedAt":      { "S": "2026-03-10T17:53:00Z" }
}
```

---

## Table 4: `agent-conversations`

**Description:** Full multi-turn conversation history between users and Bedrock agents. Each item is a single turn (message + response) in a conversation session.

### Key Schema

| Attribute | Type | Role | Notes |
|---|---|---|---|
| `sessionId` | String | Partition Key | |
| `turnIndex` | Number | Sort Key | 1-based; monotonically increasing |
| `userId` | String | GSI PK | |
| `startedAt` | String | GSI SK | |
| `agentId` | String | GSI PK | |
| `updatedAt` | String | GSI SK | |

### Item Shape

```json
{
  "sessionId":      { "S": "sess-uuid-5678" },
  "turnIndex":      { "N": "3" },
  "userId":         { "S": "usr-cognito-sub" },
  "orgId":          { "S": "org-uuid-9999" },
  "agentId":        { "S": "bedrock-agent-id" },
  "agentAliasId":   { "S": "bedrock-alias-id" },
  "status":         { "S": "completed" },
  "title":          { "S": "Employment contract review" },
  "role":           { "S": "user" },
  "userMessage":    { "S": "What is the notice period?" },
  "agentResponse":  { "S": "The notice period is 30 days as per Section 4.2." },
  "citations": {
    "L": [
      { "M": {
          "documentId": { "S": "doc-uuid-1234" },
          "chunkId":    { "S": "chunk-uuid-abc" },
          "excerpt":    { "S": "…notice period of 30 days…" },
          "page":       { "N": "7" }
      }}
    ]
  },
  "inputTokens":    { "N": "312" },
  "outputTokens":   { "N": "87" },
  "latencyMs":      { "N": "1240" },
  "startedAt":      { "S": "2026-03-10T18:00:00Z" },
  "updatedAt":      { "S": "2026-03-10T18:00:02Z" },
  "expiresAt":      { "N": "1788393600" }
}
```

### Access Patterns

| # | Pattern | Operation | Key |
|---|---|---|---|
| 1 | Get all turns in a conversation | Query | PK=sessionId |
| 2 | Get latest N turns (pagination) | Query | PK=sessionId, SK DESC, Limit N |
| 3 | List user conversations (newest first) | Query GSI | PK=userId, SK=startedAt DESC |
| 4 | List conversations for an agent | Query GSI | PK=agentId, SK=updatedAt DESC |

---

## Table 5: `agent-tasks`

**Description:** Agentic task queue. When the Bedrock Agent or A2A API needs to route work to a sub-agent or trigger async processing, a task record is created here. Workers poll the `status-createdAt` GSI to pick up pending tasks.

### Key Schema

| Attribute | Type | Role |
|---|---|---|
| `taskId` | String | Partition Key |
| `sessionId` | String | GSI PK |
| `status` | String | GSI PK |
| `agentId` | String | GSI PK |
| `createdAt` | String | GSI SK |

### Item Shape

```json
{
  "taskId":         { "S": "task-uuid-789" },
  "sessionId":      { "S": "sess-uuid-5678" },
  "userId":         { "S": "usr-cognito-sub" },
  "orgId":          { "S": "org-uuid-9999" },
  "agentId":        { "S": "bedrock-agent-id" },
  "taskType":       { "S": "document_qa" },
  "status":         { "S": "pending" },
  "priority":       { "N": "5" },
  "input": {
    "M": {
      "question":   { "S": "Summarise all NDA clauses" },
      "documentIds": { "SS": ["doc-uuid-1234"] }
    }
  },
  "output":         { "NULL": true },
  "errorMessage":   { "NULL": true },
  "attemptCount":   { "N": "0" },
  "maxAttempts":    { "N": "3" },
  "createdAt":      { "S": "2026-03-10T18:00:00Z" },
  "updatedAt":      { "S": "2026-03-10T18:00:00Z" },
  "expiresAt":      { "N": "1788393600" }
}
```

### Access Patterns

| # | Pattern | Operation | Key |
|---|---|---|---|
| 1 | Get task by ID | GetItem | PK=taskId |
| 2 | List tasks for a session | Query GSI | PK=sessionId, SK=createdAt |
| 3 | Poll for pending tasks (workers) | Query GSI | PK="pending", SK=createdAt ASC, Limit 10 |
| 4 | Claim task (optimistic lock) | UpdateItem + ConditionExpression | status = "pending" |
| 5 | List tasks for a specific agent | Query GSI | PK=agentId, SK=createdAt DESC |

---

## Table 6: `rate-limits`

**Description:** Sliding-window rate-limit counters. Uses atomic `ADD` UpdateItem operations to increment counts. TTL automatically expires counters at the end of each window.

### Key Schema

| Attribute | Type | Role | Example |
|---|---|---|---|
| `compositeKey` | String | Partition Key | `org-uuid-9999#usr-sub#POST/query` |
| `windowStart` | String | Sort Key | `2026-03-10T18:00:00Z` (minute boundary) |

### Item Shape

```json
{
  "compositeKey":  { "S": "org-uuid-9999#usr-sub#POST/query" },
  "windowStart":   { "S": "2026-03-10T18:05:00Z" },
  "orgId":         { "S": "org-uuid-9999" },
  "userId":        { "S": "usr-sub" },
  "endpoint":      { "S": "POST/query" },
  "requestCount":  { "N": "47" },
  "tokenCount":    { "N": "12400" },
  "windowSeconds": { "N": "60" },
  "limitRpm":      { "N": "60" },
  "expiresAt":     { "N": "1788391260" }
}
```

### Access Pattern

| # | Pattern | Operation |
|---|---|---|
| 1 | Increment + check limit (atomic) | UpdateItem with ADD + ConditionExpression |
| 2 | Get current window count | GetItem |
| 3 | Expire old windows | DynamoDB TTL (automatic) |

---

## Table 7: `tenant-config`

**Description:** Per-organisation (tenant) configuration and feature flags. Flexible schema using `configKey` as sort key to store arbitrary configuration entries under each organisation.

### Key Schema

| Attribute | Type | Role |
|---|---|---|
| `orgId` | String | Partition Key |
| `configKey` | String | Sort Key |
| `planTier` | String | GSI PK |

### Reserved `configKey` values

| configKey | Type | Description |
|---|---|---|
| `PLAN_LIMITS` | Map | Rate limits, storage quotas per plan |
| `FEATURE_FLAGS` | Map | Enabled/disabled feature toggles |
| `WEBHOOK_CONFIG` | Map | Default webhook retry settings |
| `BEDROCK_CONFIG` | Map | Model ID overrides, max tokens |
| `OPENSEARCH_CONFIG` | Map | Index name overrides, knn params |
| `NOTIFICATION_PREFS` | Map | Email / Slack alert preferences |
| `BRANDING` | Map | Logo URL, primary colour, custom domain |

### Item Shape

```json
{
  "orgId":        { "S": "org-uuid-9999" },
  "configKey":    { "S": "FEATURE_FLAGS" },
  "planTier":     { "S": "enterprise" },
  "configValue": {
    "M": {
      "piiRedaction":       { "BOOL": true },
      "advancedAnalytics":  { "BOOL": true },
      "customModels":       { "BOOL": false },
      "webhooksEnabled":    { "BOOL": true },
      "a2aAgents":          { "BOOL": true }
    }
  },
  "featureFlags": {
    "SS": ["piiRedaction", "advancedAnalytics", "webhooksEnabled", "a2aAgents"]
  },
  "updatedAt":    { "S": "2026-03-01T00:00:00Z" },
  "updatedBy":    { "S": "usr-admin-sub" }
}
```

### Access Patterns

| # | Pattern | Operation |
|---|---|---|
| 1 | Get all config for an org | Query | PK=orgId |
| 2 | Get specific config entry | GetItem | PK=orgId, SK=configKey |
| 3 | Update a config entry | PutItem / UpdateItem | PK=orgId, SK=configKey |
| 4 | List all Enterprise orgs | Query GSI | PK="enterprise" |

---

## Capacity Planning

All tables use **PAY_PER_REQUEST** billing. Switch to **PROVISIONED** with auto-scaling for production workloads above ~50 writes/sec to optimise cost.

### Estimated item sizes

| Table | Avg Item Size | Expected Items (Year 1) | Estimated Storage |
|---|---|---|---|
| documents | 2 KB | 5 M | 10 GB |
| sessions | 1 KB | 2 M | 2 GB |
| knowledge-base | 3 KB | 50 M | 150 GB |
| agent-conversations | 4 KB | 20 M | 80 GB |
| agent-tasks | 2 KB | 10 M (TTL clears old) | 5 GB |
| rate-limits | 256 B | 10 K active | < 1 MB |
| tenant-config | 512 B | 10 K | < 1 MB |

---

## DynamoDB Streams

| Table | Stream Enabled | Consumer | Purpose |
|---|---|---|---|
| `documents` | `NEW_AND_OLD_IMAGES` | Lambda (bedrock-processor) | Forward document state changes to downstream enrichment |
| `agent-tasks` | `NEW_AND_OLD_IMAGES` | Lambda (a2a-api) | Trigger task dispatch when new tasks are inserted |

---

## Security

- **Server-side encryption (SSE)** enabled on all tables (AWS-managed keys)
- **Point-in-Time Recovery (PITR)** on all tables except `rate-limits`
- **IAM policies** grant Lambda only the specific DynamoDB actions needed (no `*`)
- **VPC endpoint** for DynamoDB keeps all traffic off the public internet
- **Attribute-level encryption** for PII fields should be applied at the application layer using the AWS Encryption SDK before writing to DynamoDB
