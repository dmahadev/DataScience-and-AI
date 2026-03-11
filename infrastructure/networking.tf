# =============================================================================
# DocuMagic – Networking (VPC, Subnets, Security Groups)
# Required by: MSK, OpenSearch Service, Lambda in VPC
# =============================================================================

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "documagic" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.documagic.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.documagic.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Tier = "public"
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "documagic" {
  vpc_id = aws_vpc.documagic.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ---------------------------------------------------------------------------
# NAT Gateway (one per public subnet for HA)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "documagic" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.documagic]
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.documagic.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.documagic.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.documagic.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.documagic[count.index % length(aws_nat_gateway.documagic)].id
  }

  tags = {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# Lambda security group
resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.documagic.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
  }
}

# MSK security group
resource "aws_security_group" "msk" {
  name        = "${local.name_prefix}-msk-sg"
  description = "Security group for MSK Kafka cluster"
  vpc_id      = aws_vpc.documagic.id

  ingress {
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "Kafka TLS from Lambda"
  }

  ingress {
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "ZooKeeper from Lambda"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-msk-sg"
  }
}

# OpenSearch security group
resource "aws_security_group" "opensearch" {
  name        = "${local.name_prefix}-opensearch-sg"
  description = "Security group for OpenSearch Service domain"
  vpc_id      = aws_vpc.documagic.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "HTTPS from Lambda"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-opensearch-sg"
  }
}

# VPC Endpoints – keep traffic off the public internet
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.documagic.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.documagic.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${local.name_prefix}-dynamodb-endpoint"
  }
}
