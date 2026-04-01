variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "docverifier-fabric"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnets CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "Private subnets CIDR blocks"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# EC2 Instance Configuration
variable "orderer_instance_type" {
  description = "Instance type for orderers"
  type        = string
  default     = "t3.medium"
}

variable "peer_instance_type" {
  description = "Instance type for peers"
  type        = string
  default     = "t3.large"
}

variable "ca_instance_type" {
  description = "Instance type for CAs"
  type        = string
  default     = "t3.small"
}

variable "backend_instance_type" {
  description = "Instance type for backend API"
  type        = string
  default     = "t3.medium"
}

variable "monitoring_instance_type" {
  description = "Instance type for monitoring"
  type        = string
  default     = "t3.medium"
}

# EC2 AMI Configuration
variable "ami_os" {
  description = "OS for EC2 instances (ubuntu or amazon-linux)"
  type        = string
  default     = "ubuntu"
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# RDS Configuration
variable "rds_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 100
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r5.large"
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 30
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = true
}

# S3 Configuration
variable "backup_bucket_prefix" {
  description = "Prefix for backup S3 bucket name"
  type        = string
  default     = "docverifier-backups"
}

variable "enable_backup_versioning" {
  description = "Enable S3 versioning for backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Days to retain backups before deletion"
  type        = number
  default     = 90
}

# CloudWatch Configuration
variable "log_retention_days" {
  description = "CloudWatch Logs retention period"
  type        = number
  default     = 30
}

# KMS Configuration
variable "kms_deletion_window_in_days" {
  description = "KMS key deletion window"
  type        = number
  default     = 10
}

# Database Configuration
variable "db_username" {
  description = "Master username for RDS MongoDB"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for RDS MongoDB"
  type        = string
  sensitive   = true
}

# EC2 SSH Configuration
variable "ssh_key_name" {
  description = "Name of EC2 Key Pair for SSH access"
  type        = string
  default     = ""  # Leave empty to create a new one or provide existing key name
}

# Monitoring Configuration
variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
  default     = "ops@docverifier.internal"
}

# Tags
variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "DocVerifier"
    Component = "HyperledgerFabric"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "orderer_instance_type" {
  value = var.orderer_instance_type
}

output "peer_instance_type" {
  value = var.peer_instance_type
}

output "rds_instance_class" {
  value = var.rds_instance_class
}

output "aws_region" {
  value = var.aws_region
}
