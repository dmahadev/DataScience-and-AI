# =============================================================================
# DocuMagic – Amazon MSK (Managed Streaming for Apache Kafka)
# Event Streaming Layer – Kafka / Pub-Sub
# =============================================================================

# ---------------------------------------------------------------------------
# MSK Configuration
# ---------------------------------------------------------------------------
resource "aws_msk_configuration" "documagic" {
  name              = "${local.name_prefix}-msk-config"
  kafka_versions    = [var.msk_kafka_version]
  description       = "DocuMagic MSK Kafka configuration"

  server_properties = <<-EOT
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=6
    num.replica.fetchers=2
    replica.lag.time.max.ms=30000
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    socket.send.buffer.bytes=102400
    unclean.leader.election.enable=false
    log.retention.hours=168
    log.segment.bytes=1073741824
    log.retention.check.interval.ms=300000
    zookeeper.session.timeout.ms=18000
  EOT
}

# ---------------------------------------------------------------------------
# MSK Cluster
# ---------------------------------------------------------------------------
resource "aws_msk_cluster" "documagic" {
  cluster_name           = "${local.name_prefix}-msk"
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = var.msk_broker_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = slice(aws_subnet.private[*].id, 0, min(var.msk_broker_count, length(aws_subnet.private)))
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.msk_ebs_volume_size

        provisioned_throughput {
          enabled           = true
          volume_throughput = 250
        }
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.documagic.arn
    revision = aws_msk_configuration.documagic.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
    tls {}
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = var.enable_logging
        log_group = aws_cloudwatch_log_group.msk.name
      }
      s3 {
        enabled = false
      }
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  tags = { Name = "${local.name_prefix}-msk" }

  depends_on = [aws_cloudwatch_log_group.msk]
}

# ---------------------------------------------------------------------------
# MSK Topics (via Kafka provider – illustrative; normally managed via scripts)
# ---------------------------------------------------------------------------
# Topic definitions are documented below; use the AWS CLI or Kafka admin
# scripts to create them after the cluster is provisioned:
#
#   kafka-topics.sh --create --bootstrap-server <BROKERS> \
#     --topic documagic.documents.ingest --partitions 6 --replication-factor 3
#
#   kafka-topics.sh --create --bootstrap-server <BROKERS> \
#     --topic documagic.documents.processed --partitions 6 --replication-factor 3
#
#   kafka-topics.sh --create --bootstrap-server <BROKERS> \
#     --topic documagic.knowledge.updates --partitions 3 --replication-factor 3
#
#   kafka-topics.sh --create --bootstrap-server <BROKERS> \
#     --topic documagic.events.dlq --partitions 3 --replication-factor 3

# ---------------------------------------------------------------------------
# MSK Connect – S3 Sink Connector (archive all Kafka events to S3)
# ---------------------------------------------------------------------------
resource "aws_mskconnect_connector" "s3_sink" {
  name = "${local.name_prefix}-s3-sink"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 4

      scale_in_policy {
        cpu_utilization_percentage = 20
      }
      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"                    = "io.confluent.connect.s3.S3SinkConnector"
    "tasks.max"                          = "4"
    "topics"                             = "documagic.documents.ingest,documagic.documents.processed"
    "s3.region"                          = var.aws_region
    "s3.bucket.name"                     = aws_s3_bucket.processed.id
    "s3.part.size"                       = "67108864"
    "flush.size"                         = "1000"
    "storage.class"                      = "io.confluent.connect.s3.storage.S3Storage"
    "format.class"                       = "io.confluent.connect.s3.format.json.JsonFormat"
    "schema.compatibility"               = "NONE"
    "partitioner.class"                  = "io.confluent.connect.storage.partitioner.TimeBasedPartitioner"
    "path.format"                        = "'{year}'=''{MM}'=''{dd}'=''{HH}''"
    "locale"                             = "en_US"
    "timezone"                           = "UTC"
    "timestamp.extractor"                = "RecordField"
    "timestamp.field"                    = "timestamp"
    "rotate.interval.ms"                 = "3600000"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.documagic.bootstrap_brokers_tls

      vpc {
        security_groups = [aws_security_group.msk.id]
        subnets         = aws_subnet.private[*].id
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.s3_connector.arn
      revision = aws_mskconnect_custom_plugin.s3_connector.latest_revision
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect.arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = var.enable_logging
        log_group = aws_cloudwatch_log_group.msk_connect.name
      }
    }
  }
}

# Custom plugin (the Kafka Connect S3 connector JAR must be uploaded to S3)
resource "aws_mskconnect_custom_plugin" "s3_connector" {
  name         = "${local.name_prefix}-s3-connector-plugin"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn     = aws_s3_bucket.amplify_artifacts.arn
      file_key       = "kafka-connectors/confluentinc-kafka-connect-s3-10.5.4.zip"
      object_version = null
    }
  }
}

# IAM role for MSK Connect workers
resource "aws_iam_role" "msk_connect" {
  name = "${local.name_prefix}-msk-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "kafkaconnect.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "${local.name_prefix}-msk-connect-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = [
          aws_msk_cluster.documagic.arn,
          "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${aws_msk_cluster.documagic.cluster_name}/*",
          "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:group/${aws_msk_cluster.documagic.cluster_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/*",
          aws_s3_bucket.amplify_artifacts.arn,
          "${aws_s3_bucket.amplify_artifacts.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.msk_connect.arn}:*"
      }
    ]
  })
}
