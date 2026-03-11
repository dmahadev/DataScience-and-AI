# =============================================================================
# DocuMagic – Amazon Aurora PostgreSQL (RDBMS Tier)
# Relational data: users, organisations, document catalog, audit, billing, ACL
# =============================================================================

# ---------------------------------------------------------------------------
# Security group for Aurora cluster
# ---------------------------------------------------------------------------
resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.documagic.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "PostgreSQL from Lambda functions"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = { Name = "${local.name_prefix}-aurora-sg" }
}

# ---------------------------------------------------------------------------
# DB Subnet Group
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "documagic" {
  name        = "${lower(local.name_prefix)}-aurora-subnet-group"
  subnet_ids  = aws_subnet.private[*].id
  description = "Subnet group for DocuMagic Aurora PostgreSQL"

  tags = { Name = "${local.name_prefix}-aurora-subnet-group" }
}

# ---------------------------------------------------------------------------
# DB Cluster Parameter Group
# ---------------------------------------------------------------------------
resource "aws_rds_cluster_parameter_group" "documagic" {
  name        = "${lower(local.name_prefix)}-aurora-cluster-params"
  family      = "aurora-postgresql15"
  description = "DocuMagic Aurora PostgreSQL 15 cluster parameters"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,auto_explain"
  }

  parameter {
    name  = "auto_explain.log_min_duration"
    value = "5000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = { Name = "${local.name_prefix}-aurora-cluster-params" }
}

# ---------------------------------------------------------------------------
# DB Instance Parameter Group
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "documagic" {
  name        = "${lower(local.name_prefix)}-aurora-instance-params"
  family      = "aurora-postgresql15"
  description = "DocuMagic Aurora PostgreSQL 15 instance parameters"

  parameter {
    name  = "log_temp_files"
    value = "1024"
  }

  parameter {
    name  = "work_mem"
    value = "65536"
  }

  tags = { Name = "${local.name_prefix}-aurora-instance-params" }
}

# ---------------------------------------------------------------------------
# Master credentials in Secrets Manager
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "aurora_master" {
  name                    = "${local.name_prefix}/aurora/master-credentials"
  description             = "Aurora PostgreSQL master credentials for DocuMagic"
  recovery_window_in_days = var.environment == "production" ? 30 : 7

  tags = { Name = "${local.name_prefix}-aurora-master-secret" }
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = aws_secretsmanager_secret.aurora_master.id

  secret_string = jsonencode({
    username = "documagic_admin"
    password = random_password.aurora_master.result
    engine   = "postgres"
    host     = aws_rds_cluster.documagic.endpoint
    port     = 5432
    dbname   = "documagic"
  })
}

resource "random_password" "aurora_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# App-user credentials (least-privilege runtime account)
resource "aws_secretsmanager_secret" "aurora_app" {
  name                    = "${local.name_prefix}/aurora/app-credentials"
  description             = "Aurora PostgreSQL application user credentials"
  recovery_window_in_days = var.environment == "production" ? 30 : 7

  tags = { Name = "${local.name_prefix}-aurora-app-secret" }
}

resource "aws_secretsmanager_secret_version" "aurora_app" {
  secret_id = aws_secretsmanager_secret.aurora_app.id

  secret_string = jsonencode({
    username = "documagic_app"
    password = random_password.aurora_app.result
    engine   = "postgres"
    host     = aws_rds_cluster.documagic.endpoint
    port     = 5432
    dbname   = "documagic"
  })
}

resource "random_password" "aurora_app" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ---------------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# ---------------------------------------------------------------------------
resource "aws_rds_cluster" "documagic" {
  cluster_identifier = "${lower(local.name_prefix)}-aurora"

  engine         = "aurora-postgresql"
  engine_version = var.rds_engine_version
  database_name  = "documagic"

  master_username = "documagic_admin"
  master_password = random_password.aurora_master.result

  db_subnet_group_name            = aws_db_subnet_group.documagic.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.documagic.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.aurora.arn

  backup_retention_period      = var.rds_backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  deletion_protection             = var.environment == "production"
  skip_final_snapshot             = var.environment != "production"
  final_snapshot_identifier       = "${lower(local.name_prefix)}-aurora-final-snapshot"
  copy_tags_to_snapshot           = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  iam_database_authentication_enabled = true

  serverlessv2_scaling_configuration {
    min_capacity = var.rds_serverless_min_capacity
    max_capacity = var.rds_serverless_max_capacity
  }

  tags = { Name = "${local.name_prefix}-aurora" }

  depends_on = [aws_cloudwatch_log_group.aurora]
}

# ---------------------------------------------------------------------------
# Aurora Instances (Serverless v2 writer + reader)
# ---------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier         = aws_rds_cluster.documagic.id
  identifier                 = "${lower(local.name_prefix)}-aurora-writer"
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.documagic.engine
  engine_version             = aws_rds_cluster.documagic.engine_version
  db_parameter_group_name    = aws_db_parameter_group.documagic.name
  db_subnet_group_name       = aws_db_subnet_group.documagic.name
  auto_minor_version_upgrade = true
  publicly_accessible        = false

  performance_insights_enabled          = var.enable_enhanced_monitoring
  performance_insights_retention_period = var.enable_enhanced_monitoring ? 7 : null

  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring.arn : null

  tags = { Name = "${local.name_prefix}-aurora-writer" }
}

resource "aws_rds_cluster_instance" "reader" {
  count = var.rds_reader_count

  cluster_identifier         = aws_rds_cluster.documagic.id
  identifier                 = "${lower(local.name_prefix)}-aurora-reader-${count.index + 1}"
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.documagic.engine
  engine_version             = aws_rds_cluster.documagic.engine_version
  db_parameter_group_name    = aws_db_parameter_group.documagic.name
  db_subnet_group_name       = aws_db_subnet_group.documagic.name
  auto_minor_version_upgrade = true
  publicly_accessible        = false

  performance_insights_enabled          = var.enable_enhanced_monitoring
  performance_insights_retention_period = var.enable_enhanced_monitoring ? 7 : null

  monitoring_interval = var.enable_enhanced_monitoring ? 60 : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring.arn : null

  tags = { Name = "${local.name_prefix}-aurora-reader-${count.index + 1}" }
}

# ---------------------------------------------------------------------------
# KMS key for Aurora encryption
# ---------------------------------------------------------------------------
resource "aws_kms_key" "aurora" {
  description             = "KMS key for DocuMagic Aurora PostgreSQL encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Name = "${local.name_prefix}-aurora-kms" }
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${lower(local.name_prefix)}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

# ---------------------------------------------------------------------------
# CloudWatch log group for Aurora
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "aurora" {
  name              = "/aws/rds/cluster/${lower(local.name_prefix)}-aurora/postgresql"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# IAM role for RDS Enhanced Monitoring
# ---------------------------------------------------------------------------
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# IAM policy – allow Lambda to get DB secret + use IAM auth
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_rds" {
  name = "${local.name_prefix}-lambda-rds"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetAuroraSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.aurora_master.arn,
          aws_secretsmanager_secret.aurora_app.arn
        ]
      },
      {
        Sid      = "RDSIAMAuth"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.documagic.cluster_resource_id}/documagic_app"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.aurora.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# RDS Proxy (connection pooling for Lambda cold starts)
# ---------------------------------------------------------------------------
resource "aws_db_proxy" "documagic" {
  name                   = "${lower(local.name_prefix)}-rds-proxy"
  debug_logging          = var.environment != "production"
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.aurora.id]
  vpc_subnet_ids         = aws_subnet.private[*].id

  auth {
    auth_scheme               = "SECRETS"
    description               = "App user credentials"
    iam_auth                  = "REQUIRED"
    secret_arn                = aws_secretsmanager_secret.aurora_app.arn
  }

  tags = { Name = "${local.name_prefix}-rds-proxy" }
}

resource "aws_db_proxy_default_target_group" "documagic" {
  db_proxy_name = aws_db_proxy.documagic.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "documagic" {
  db_cluster_identifier = aws_rds_cluster.documagic.cluster_identifier
  db_proxy_name         = aws_db_proxy.documagic.name
  target_group_name     = aws_db_proxy_default_target_group.documagic.name
}

resource "aws_iam_role" "rds_proxy" {
  name = "${local.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "rds_proxy" {
  name = "${local.name_prefix}-rds-proxy-policy"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.aurora_app.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.aurora.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CloudWatch alarms for Aurora
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora writer CPU utilization is above 80%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.documagic.cluster_identifier
    Role                = "WRITER"
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 900
  alarm_description   = "Aurora connection count is critically high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.documagic.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "aurora_freeable_memory" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-aurora-low-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 104857600 # 100 MB in bytes
  alarm_description   = "Aurora freeable memory is critically low"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.documagic.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# NOTE: random_password resources here use the hashicorp/random provider
# declared in main.tf required_providers block.
# ---------------------------------------------------------------------------
