# terraform/aws/outputs.tf
# Consolidated outputs for all infrastructure components

# ============================================================================
# VPC and Networking Outputs
# ============================================================================

output "vpc_id" {
  value       = aws_vpc.fabric.id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = aws_vpc.fabric.cidr_block
  description = "VPC CIDR block"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs"
}

# ============================================================================
# Security Groups
# ============================================================================

output "security_group_alb_id" {
  value       = aws_security_group.alb.id
  description = "ALB security group ID"
}

output "security_group_orderers_id" {
  value       = aws_security_group.orderers.id
  description = "Orderers security group ID"
}

output "security_group_peers_id" {
  value       = aws_security_group.peers.id
  description = "Peers security group ID"
}

output "security_group_cas_id" {
  value       = aws_security_group.cas.id
  description = "CAs security group ID"
}

output "security_group_backend_id" {
  value       = aws_security_group.backend.id
  description = "Backend security group ID"
}

output "security_group_rds_id" {
  value       = aws_security_group.rds.id
  description = "RDS security group ID"
}

output "security_group_elasticache_id" {
  value       = aws_security_group.elasticache.id
  description = "ElastiCache security group ID"
}

# ============================================================================
# EC2 Instances - Orderers
# ============================================================================

output "orderer_instance_ids" {
  value       = aws_instance.orderers[*].id
  description = "Orderer instance IDs"
}

output "orderer_private_ips" {
  value       = aws_instance.orderers[*].private_ip
  description = "Orderer private IP addresses"
}

output "orderer_private_dns" {
  value       = aws_instance.orderers[*].private_dns
  description = "Orderer private DNS names"
}

# ============================================================================
# EC2 Instances - Peers
# ============================================================================

output "peer_instance_ids" {
  value       = aws_instance.peers[*].id
  description = "Peer instance IDs"
}

output "peer_private_ips" {
  value       = aws_instance.peers[*].private_ip
  description = "Peer private IP addresses"
}

output "peer_private_dns" {
  value       = aws_instance.peers[*].private_dns
  description = "Peer private DNS names"
}

# ============================================================================
# EC2 Instances - Certificate Authorities
# ============================================================================

output "ca_instance_ids" {
  value       = aws_instance.cas[*].id
  description = "CA instance IDs"
}

output "ca_private_ips" {
  value       = aws_instance.cas[*].private_ip
  description = "CA private IP addresses"
}

# ============================================================================
# EC2 Instances - Backend and Monitoring
# ============================================================================

output "backend_instance_id" {
  value       = aws_instance.backend.id
  description = "Backend API instance ID"
}

output "backend_private_ip" {
  value       = aws_instance.backend.private_ip
  description = "Backend API private IP"
}

output "backend_private_dns" {
  value       = aws_instance.backend.private_dns
  description = "Backend API private DNS"
}

output "monitoring_instance_id" {
  value       = aws_instance.monitoring.id
  description = "Monitoring instance ID"
}

output "monitoring_private_ip" {
  value       = aws_instance.monitoring.private_ip
  description = "Monitoring private IP"
}

output "monitoring_private_dns" {
  value       = aws_instance.monitoring.private_dns
  description = "Monitoring private DNS"
}

# ============================================================================
# Database Outputs
# ============================================================================

output "rds_cluster_endpoint" {
  value       = aws_rds_cluster.fabric_mongodb.endpoint
  description = "RDS cluster endpoint (write endpoint)"
}

output "rds_reader_endpoint" {
  value       = aws_rds_cluster.fabric_mongodb.reader_endpoint
  description = "RDS reader endpoint (read replicas)"
}

output "rds_cluster_identifier" {
  value       = aws_rds_cluster.fabric_mongodb.cluster_identifier
  description = "RDS cluster identifier"
}

output "rds_database_name" {
  value       = aws_rds_cluster.fabric_mongodb.database_name
  description = "RDS database name"
}

output "elasticache_endpoint" {
  value       = aws_elasticache_cluster.fabric.cache_nodes[0].address
  description = "ElastiCache Redis endpoint"
}

output "elasticache_port" {
  value       = aws_elasticache_cluster.fabric.port
  description = "ElastiCache Redis port"
}

output "elasticache_cluster_id" {
  value       = aws_elasticache_cluster.fabric.cluster_id
  description = "ElastiCache cluster ID"
}

# ============================================================================
# Storage Outputs
# ============================================================================

output "s3_backup_bucket" {
  value       = aws_s3_bucket.backups.id
  description = "S3 bucket for backups"
}

output "s3_backup_bucket_arn" {
  value       = aws_s3_bucket.backups.arn
  description = "S3 backup bucket ARN"
}

output "s3_backup_bucket_region" {
  value       = aws_s3_bucket.backups.region
  description = "S3 backup bucket region"
}

output "s3_backup_logs_bucket" {
  value       = aws_s3_bucket.backup_logs.id
  description = "S3 bucket for backup access logs"
}

output "s3_terraform_state_bucket" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket for Terraform state"
}

output "s3_alb_logs_bucket" {
  value       = aws_s3_bucket.alb_logs.id
  description = "S3 bucket for ALB access logs"
}

# ============================================================================
# Encryption and Security Outputs
# ============================================================================

output "kms_key_id" {
  value       = aws_kms_key.fabric.key_id
  description = "KMS key ID for encryption"
}

output "kms_key_arn" {
  value       = aws_kms_key.fabric.arn
  description = "KMS key ARN"
}

output "kms_key_alias" {
  value       = aws_kms_alias.fabric.name
  description = "KMS key alias"
}

# ============================================================================
# Load Balancer Outputs
# ============================================================================

output "alb_dns_name" {
  value       = aws_lb.fabric.dns_name
  description = "ALB DNS name"
}

output "alb_arn" {
  value       = aws_lb.fabric.arn
  description = "ALB ARN"
}

output "alb_zone_id" {
  value       = aws_lb.fabric.zone_id
  description = "ALB Zone ID (for Route 53)"
}

output "backend_target_group_arn" {
  value       = aws_lb_target_group.backend_api.arn
  description = "Backend target group ARN"
}

output "monitoring_target_group_arn" {
  value       = aws_lb_target_group.monitoring.arn
  description = "Monitoring target group ARN"
}

# ============================================================================
# Monitoring and Alerting Outputs
# ============================================================================

output "sns_alerts_topic_arn" {
  value       = aws_sns_topic.fabric_alerts.arn
  description = "SNS topic ARN for general alerts"
}

output "sns_critical_alerts_topic_arn" {
  value       = aws_sns_topic.fabric_critical_alerts.arn
  description = "SNS topic ARN for critical alerts"
}

output "cloudwatch_log_group_fabric" {
  value       = aws_cloudwatch_log_group.fabric.name
  description = "CloudWatch log group for Fabric"
}

output "cloudwatch_log_group_backend" {
  value       = aws_cloudwatch_log_group.backend.name
  description = "CloudWatch log group for backend"
}

output "cloudwatch_dashboard_overview" {
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.fabric_overview.dashboard_name}"
  description = "CloudWatch dashboard overview URL"
}

output "cloudwatch_dashboard_network" {
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.fabric_network.dashboard_name}"
  description = "CloudWatch dashboard network URL"
}

# ============================================================================
# Deployment Information
# ============================================================================

output "deployment_summary" {
  value = {
    infrastructure = {
      vpc_cidr      = aws_vpc.fabric.cidr_block
      region        = var.aws_region
      az_count      = length(data.aws_availability_zones.available.names)
    }
    compute = {
      orderers = {
        count          = 3
        instance_type  = var.orderer_instance_type
        private_ips    = aws_instance.orderers[*].private_ip
      }
      peers = {
        count          = 3
        instance_type  = var.peer_instance_type
        private_ips    = aws_instance.peers[*].private_ip
      }
      cas = {
        count          = 3
        instance_type  = var.ca_instance_type
        private_ips    = aws_instance.cas[*].private_ip
      }
      backend = {
        instance_type  = var.backend_instance_type
        private_ip     = aws_instance.backend.private_ip
      }
      monitoring = {
        instance_type  = var.monitoring_instance_type
        private_ip     = aws_instance.monitoring.private_ip
      }
    }
    database = {
      mongodb = {
        endpoint           = aws_rds_cluster.fabric_mongodb.endpoint
        multi_az           = var.rds_multi_az
        backup_retention   = var.rds_backup_retention_days
      }
      redis = {
        endpoint = aws_elasticache_cluster.fabric.cache_nodes[0].address
        port     = aws_elasticache_cluster.fabric.port
      }
    }
    storage = {
      backup_bucket      = aws_s3_bucket.backups.id
      backup_retention   = var.backup_retention_days
      versioning_enabled = var.enable_backup_versioning
    }
    networking = {
      alb_dns_name = aws_lb.fabric.dns_name
      public_subnets = {
        count = length(aws_subnet.public)
        cidr  = var.public_subnets
      }
      private_subnets = {
        count = length(aws_subnet.private)
        cidr  = var.private_subnets
      }
    }
  }
  description = "Complete deployment summary for reference"
}

# ============================================================================
# Configuration Instructions
# ============================================================================

output "next_steps" {
  value = <<-EOT
    1. Verify all resources using AWS Console:
       - EC2 Dashboard: Check all instances running
       - RDS: Check MongoDB cluster is available
       - ALB: Check targets are healthy
       - S3: Verify backup bucket created

    2. Connect to instances via SSH:
       - ssh -i <key.pem> ubuntu@${aws_instance.backend.private_ip}
       - Use VPN or bastion host for private subnet access

    3. Configure Fabric network on instances:
       - Deploy Docker containers with Fabric components
       - Initialize the blockchain network
       - Run integration tests

    4. Monitor deployment:
       - CloudWatch dashboards: ${aws_cloudwatch_dashboard.fabric_overview.dashboard_name}
       - ALB health check: https://${aws_lb.fabric.dns_name}/health

    5. Set up DNS (Route 53):
       - Create CNAME record pointing to ALB DNS: ${aws_lb.fabric.dns_name}
       - Configure SSL certificate in AWS Certificate Manager

    6. Initialize backups:
       - Deploy backup script on instances
       - Schedule automated backups to S3: ${aws_s3_bucket.backups.id}
  EOT
  description = "Deployment next steps and instructions"
}
