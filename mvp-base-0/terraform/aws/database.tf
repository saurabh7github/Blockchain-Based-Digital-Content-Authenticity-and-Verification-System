# terraform/aws/database.tf
# RDS Aurora MongoDB and ElastiCache Redis Configuration

# ============================================================================
# RDS Aurora MongoDB (Multi-AZ)
# ============================================================================

# RDS Subnet Group for database placement
resource "aws_db_subnet_group" "fabric_db" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# RDS Aurora Cluster (MongoDB API compatible)
resource "aws_rds_cluster" "fabric_mongodb" {
  cluster_identifier              = "${var.project_name}-mongodb"
  engine                          = "aurora-mongodb"
  engine_version                  = "6.0.7"
  database_name                   = "docverifier"
  master_username                 = var.db_username
  master_password                 = var.db_password
  db_subnet_group_name            = aws_db_subnet_group.fabric_db.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.fabric_mongodb.name
  vpc_security_group_ids          = [aws_security_group.rds.id]

  # Backup configuration
  backup_retention_period      = var.rds_backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot        = true

  # High availability
  storage_encrypted                 = true
  kms_key_id                        = aws_kms_key.fabric.arn
  deletion_protection               = var.rds_deletion_protection
  skip_final_snapshot               = false
  final_snapshot_identifier         = "${var.project_name}-mongodb-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  enable_cloudwatch_logs_exports    = ["mongodb"]
  enable_iam_database_authentication = true

  # Performance insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${var.project_name}-mongodb-cluster"
  }

  depends_on = [aws_rds_cluster_parameter_group.fabric_mongodb]
}

# RDS Cluster Parameter Group for Aurora MongoDB
resource "aws_rds_cluster_parameter_group" "fabric_mongodb" {
  family      = "aurora-mongodb6.0"
  name        = "${var.project_name}-mongodb-params"
  description = "Parameter group for DocVerifier MongoDB cluster"

  # Security parameters
  parameter {
    name  = "audit_authorization_success"
    value = "true"
  }

  tags = {
    Name = "${var.project_name}-mongodb-params"
  }
}

# RDS Cluster Instances (Multi-AZ)
resource "aws_rds_cluster_instance" "fabric_mongodb" {
  count              = 2  # Multi-AZ: 1 primary + 1 replica
  cluster_identifier = aws_rds_cluster.fabric_mongodb.id
  instance_class     = var.rds_instance_class
  engine              = aws_rds_cluster.fabric_mongodb.engine
  engine_version      = aws_rds_cluster.fabric_mongodb.engine_version

  # Monitoring
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.fabric.arn
  auto_minor_version_upgrade      = false

  tags = {
    Name = "${var.project_name}-mongodb-instance-${count.index + 1}"
  }
}

# ============================================================================
# ElastiCache Redis (Session Cache)
# ============================================================================

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "fabric" {
  name       = "${var.project_name}-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-cache-subnet-group"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_cluster" "fabric" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379

  # Security & encryption
  subnet_group_name       = aws_elasticache_subnet_group.fabric.name
  security_group_ids      = [aws_security_group.elasticache.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # Maintenance
  maintenance_window = "sun:05:00-sun:06:00"
  notification_topic_arn = aws_sns_topic.fabric_alerts.arn

  tags = {
    Name = "${var.project_name}-redis-cache"
  }

  depends_on = [aws_security_group.elasticache]
}

# ============================================================================
# Security Groups for Databases
# ============================================================================

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "fabric-rds-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
    description     = "MongoDB from backend"
  }

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.peers.id]
    description     = "MongoDB from peers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# Security Group for ElastiCache
resource "aws_security_group" "elasticache" {
  name_prefix = "fabric-elasticache-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
    description     = "Redis from backend"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-elasticache-sg"
  }
}

# ============================================================================
# IAM Role for RDS Enhanced Monitoring
# ============================================================================

resource "aws_iam_role" "rds_monitoring" {
  name_prefix = "fabric-rds-monitoring-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ============================================================================
# Outputs
# ============================================================================

output "rds_cluster_endpoint" {
  value       = aws_rds_cluster.fabric_mongodb.endpoint
  description = "RDS Aurora MongoDB cluster endpoint"
}

output "rds_reader_endpoint" {
  value       = aws_rds_cluster.fabric_mongodb.reader_endpoint
  description = "RDS Aurora MongoDB read replica endpoint"
}

output "rds_database_name" {
  value       = aws_rds_cluster.fabric_mongodb.database_name
  description = "Database name"
}

output "elasticache_endpoint" {
  value       = aws_elasticache_cluster.fabric.cache_nodes[0].address
  description = "ElastiCache Redis cluster endpoint"
}

output "elasticache_port" {
  value       = aws_elasticache_cluster.fabric.port
  description = "ElastiCache Redis cluster port"
}
