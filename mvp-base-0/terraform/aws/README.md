# Terraform AWS Infrastructure for DocVerifier Fabric Network

This directory contains production-grade Terraform infrastructure-as-code for deploying a Hyperledger Fabric network on AWS.

## 📋 Overview

### Architecture

```
┌─────────────────────────────────────────────────────┐
│              AWS VPC (10.0.0.0/16)                 │
├─────────────────────────────────────────────────────┤
│  PUBLIC SUBNETS (Internet-facing)                   │
│  ├─ Application Load Balancer (ALB)                │
│  └─ NAT Gateways (egress for private subnets)      │
│                                                      │
│  PRIVATE SUBNETS (No direct internet access)        │
│  ├─ 3 Orderers (Raft consensus, t3.medium)        │
│  ├─ 3 Peers (multi-org, t3.large)                 │
│  ├─ 3 CAs (Certificate Authorities, t3.small)     │
│  ├─ Backend API (Node.js, t3.medium)              │
│  └─ Monitoring (Prometheus + Grafana, t3.medium)  │
│                                                      │
│  DATABASE TIER                                       │
│  ├─ RDS Aurora MongoDB (Multi-AZ, encrypted)      │
│  └─ ElastiCache Redis (session cache)              │
│                                                      │
│  STORAGE TIER                                        │
│  ├─ S3 Backup Buckets (versioned, encrypted)       │
│  ├─ KMS Encryption Keys                            │
│  └─ CloudWatch Logs (retention policy)             │
│                                                      │
│  MONITORING & SECURITY                              │
│  ├─ CloudWatch Dashboards & Alarms                 │
│  ├─ SNS Topics (alert notifications)               │
│  └─ Security Groups (firewall rules)               │
└─────────────────────────────────────────────────────┘
```

### Components

| Component | Purpose | Instances | Configuration |
|-----------|---------|-----------|----------------|
| **Orderers** | Blockchain consensus (Raft) | 3 | t3.medium, 100GB EBS |
| **Peers** | Transaction validators (multi-org) | 3 | t3.large, 200GB EBS |
| **CAs** | Certificate authorities | 3 | t3.small, 50GB EBS |
| **Backend API** | DocVerifier REST API | 1 | t3.medium, 100GB EBS |
| **Monitoring** | Prometheus + Grafana | 1 | t3.medium, 100GB EBS |
| **RDS** | MongoDB Aurora (Multi-AZ) | 2 | db.r5.large instances |
| **ElastiCache** | Redis session cache | 1 | cache.t3.micro |
| **ALB** | HTTPS load balancer | 1 | Across public subnets |

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with appropriate permissions:
   - EC2, RDS, S3, KMS, CloudWatch, VPC, IAM, ALB, ElastiCache

2. **Tools Installed**:
   - Terraform >= 1.5
   - AWS CLI >= 2.x
   - SSH client

3. **AWS Credentials Configured**:
   ```bash
   aws configure
   # or export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
   ```

### Deployment Steps

#### 1. Initialize Terraform Variables

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Critical variables to customize**:
- `alert_email` - Email for CloudWatch alerts (REQUIRED)
- `db_password` - Strong RDS password (REQUIRED)
- `ssh_key_name` - Existing EC2 key pair (or leave empty to generate)
- `aws_region` - AWS region for deployment
- `project_name` - Unique identifier for resources

#### 2. Initialize Terraform

```bash
terraform init
```

This downloads AWS provider and initializes state backend.

#### 3. Review Infrastructure Plan

```bash
terraform plan -out=tfplan
```

Review planned resources before creating anything. Key resources:
- 11 EC2 instances (3 orderers, 3 peers, 3 CAs, 1 backend, 1 monitoring)
- 1 RDS Aurora MongoDB cluster
- 1 ElastiCache Redis cluster
- 3 S3 buckets (backups, logs, Terraform state)
- VPC with networking, security groups, ALB
- CloudWatch dashboards and alarms

#### 4. Apply Infrastructure

```bash
terraform apply tfplan
```

**Estimated time**: 15-25 minutes

The output will display important information:
- VPC ID, Subnet IDs, Security Group IDs
- Private IP addresses of all instances
- RDS endpoint, ElastiCache endpoint
- ALB DNS name
- S3 bucket names
- KMS key ID

#### 5. Verify Deployment

```bash
# Save outputs to file
terraform output -json > infrastructure.json

# Check EC2 instances
aws ec2 describe-instances --filters "Name=tag:Name,Values=docverifier-*" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]' \
  --output table

# Check RDS status
aws rds describe-db-clusters --db-cluster-identifier docverifier-fabric-mongodb \
  --query 'DBClusters[0].[Status,Endpoint]'

# Check ALB health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw backend_target_group_arn)
```

## 📁 File Structure

```
terraform/aws/
├── main.tf              # VPC, subnets, internet gateway, routing
├── variables.tf         # Input variables and defaults
├── compute.tf           # EC2 instances and IAM roles
├── database.tf          # RDS Aurora, ElastiCache, databases
├── storage.tf           # S3 buckets, KMS encryption, CloudWatch Logs
├── loadbalancer.tf      # ALB, target groups, listener rules
├── monitoring.tf        # CloudWatch alarms, SNS topics, dashboards
├── outputs.tf           # Output values for reference
├── terraform.tfvars.example  # Example variables (copy to terraform.tfvars)
└── README.md            # This file
```

### File Purposes

| File | Contents | Key Resources |
|------|----------|---------------|
| `main.tf` | Networking foundation | VPC, Subnets, IGW, Route Tables, Security Groups |
| `compute.tf` | Compute resources | EC2 instances, IAM roles/policies, instance profiles |
| `database.tf` | Data layer | RDS Aurora, ElastiCache, RDS monitoring |
| `storage.tf` | Persistent storage | S3 buckets, KMS keys, CloudWatch logs |
| `loadbalancer.tf` | Traffic distribution | ALB, target groups, listeners, SSL |
| `monitoring.tf` | Observability | CloudWatch alarms, SNS, dashboards |
| `outputs.tf` | Reference values | IP addresses, endpoints, DNS names |

## 🔧 Configuration

### Network Customization

Edit `terraform.tfvars` to change network layout:

```hcl
# Change VPC CIDR
vpc_cidr = "172.16.0.0/16"

# Change public subnets
public_subnets = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]

# Change private subnets
private_subnets = ["172.16.11.0/24", "172.16.12.0/24", "172.16.13.0/24"]
```

### Instance Types

Modify instance types in `terraform.tfvars`:

```hcl
# Production (recommended)
orderer_instance_type = "m5.large"      # More resources for consensus
peer_instance_type = "m5.xlarge"        # Larger ledger storage
ca_instance_type = "t3.medium"          # CAs are lightweight

# Cost-optimized development
orderer_instance_type = "t3.micro"
peer_instance_type = "t3.small"
ca_instance_type = "t3.micro"
```

### Database Sizing

```hcl
# Large production deployment
rds_instance_class = "db.r5.2xlarge"    # High memory for large ledger
rds_allocated_storage = 1000            # 1TB storage

# Development environment
rds_instance_class = "db.t3.small"
rds_allocated_storage = 20
```

## 🛡️ Security Features

### Built-in Security

1. **Encryption at Rest**
   - RDS Aurora: AWS KMS encryption
   - S3: Bucket encryption with customer-managed KMS key
   - EBS: Encrypted volumes on all instances
   - ElastiCache: Redis with transit encryption

2. **Network Security**
   - Private subnets for all Fabric components
   - Security groups with restrictive ingress rules
   - NACLs for additional network layer control
   - ALB for HTTPS termination

3. **Access Control**
   - IAM roles with least privilege (EC2 can access S3, Secrets Manager, KMS)
   - SSH access restricted to specific security groups
   - RDS: IAM database authentication (optional)

4. **Audit & Compliance**
   - CloudWatch Logs for all services
   - CloudTrail logging (optional - enable separately)
   - VPC Flow Logs (optional)
   - 30-day log retention by default

### Recommended Post-Deployment Actions

1. **Enable additional logging**:
   ```bash
   aws redrive enable-logging --cluster-identifier docverifier-fabric-mongodb
   ```

2. **Set up SNS alert subscriptions**:
   - Subscribe to critical alerts SNS topic
   - Configure email or PagerDuty integration

3. **Configure AWS Secrets Manager**:
   - Store Fabric certificates and keys
   - Rotate secrets regularly

4. **Set up backup policy**:
   - Enable cross-region S3 replication
   - Test backup restoration procedures

## 📊 Outputs & Reference

After `terraform apply`, reference important values:

```bash
# Get all outputs in JSON format
terraform output -json

# Get specific output
terraform output alb_dns_name
terraform output rds_cluster_endpoint
terraform output s3_backup_bucket

# Get deployment summary
terraform output deployment_summary
```

Key outputs for next steps:

| Output | Use Case |
|--------|----------|
| `alb_dns_name` | Configure DNS CNAME record |
| `rds_cluster_endpoint` | Configure backend database connection |
| `elasticache_endpoint:port` | Configure session cache |
| `backend_private_ip` | SSH access to backend |
| `orderer_private_ips` | Fabric network configuration |
| `s3_backup_bucket` | Configure backup agent |

## 🔄 Terraform State Management

### Local State (Development)

By default, state is stored locally in `terraform.tfstate`:

```bash
# View state
terraform state list
terraform state show aws_instance.backend
```

### Remote State (Production Recommended)

Uncomment backend in `main.tf` to use S3 + DynamoDB:

```hcl
terraform {
  backend "s3" {
    bucket         = "docverifier-terraform-state-123456789"
    key            = "fabric/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

Then initialize:
```bash
terraform init
```

## 📈 Monitoring & Maintenance

### CloudWatch Dashboards

Access monitoring dashboards:

```bash
# Print dashboard URLs
terraform output cloudwatch_dashboard_overview
terraform output cloudwatch_dashboard_network
```

Or access via AWS Console:
- Dashboards → docverifier-fabric-overview
- Dashboards → docverifier-fabric-network

### Key Metrics to Monitor

- **EC2**: CPU usage, network throughput, status checks
- **RDS**: CPU, connections, storage space, replication lag
- **ALB**: Target health, request count, response times
- **ElastiCache**: CPU, network bytes, evictions

### Alarms

Configured alarms send notifications to SNS:
- High CPU on any instance (>80% for 10 minutes)
- High memory on orderers (>85%)
- RDS connection limit approaching (>80%)
- RDS low free storage (<10GB)
- ALB unhealthy targets
- ALB no request activity (possible outage)

## 🛠️ Troubleshooting

### Instance Connectivity Issues

```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxx \
  --query 'SecurityGroups[0].IpPermissions'

# Check route tables
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxx"

# Verify NAT gateway
aws ec2 describe-nat-gateways \
  --filter "Name=subnet-id,Values=subnet-xxxxxxxx"
```

### RDS Connection Issues

```bash
# Check cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier docverifier-fabric-mongodb

# Check instances
aws rds describe-db-instances | grep "docverifier"

# View RDS events
aws rds describe-events --duration 60
```

### ALB Health Check Failures

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Check ALB logs (in S3)
aws s3 ls s3://docverifier-alb-logs-123456789/alb-logs/

# Verify backend instance is running
aws ec2 describe-instances --instance-ids i-xxxxxxxx
```

## 💰 Cost Estimation

### Monthly Costs (Approximate)

| Component | Instance | Hours/Month | Rate | Cost |
|-----------|----------|-------------|------|------|
| Orderers | 3 × t3.medium | 730 | $0.0416/hr | $91 |
| Peers | 3 × t3.large | 730 | $0.0832/hr | $183 |
| CAs | 3 × t3.small | 730 | $0.0208/hr | $46 |
| Backend | 1 × t3.medium | 730 | $0.0416/hr | $30 |
| Monitoring | 1 × t3.medium | 730 | $0.0416/hr | $30 |
| **EC2 Total** | | | | **$380** |
| RDS Aurora | db.r5.large | 730 | $1.125/hr | $821 |
| ElastiCache | cache.t3.micro | 730 | $0.017/hr | $12 |
| **Database Total** | | | | **$833** |
| S3 Storage | 100GB | | $0.023/GB | $2.30 |
| Data Transfer | 1TB/month | | $0.09/GB | $90 |
| **Storage Total** | | | | **$92** |
| ALB | | 730 | $0.0225/hr | $16 |
| CloudWatch | Logs + Metrics | | | $30 |
| **Networking/Monitoring** | | | | **$46** |
| **TOTAL MONTHLY** | | | | **~$1,351** |

Costs vary by region. Use [AWS Pricing Calculator](https://calculator.aws/) for accurate estimates.

### Cost Optimization Tips

1. Use Reserved Instances for long-term deployments (30-40% savings)
2. Scale down during development (use t3.small orderers, t3.micro cache)
3. Enable S3 Intelligent-Tiering for backups
4. Use AWS Compute Savings Plans
5. Monitor and alert on unexpected costs

## 🔄 Scaling & Updates

### Scaling Instances

To use larger instances:

```bash
# Update terraform.tfvars
peer_instance_type = "m5.xlarge"

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### Updating Terraform Code

To merge upstream improvements:

```bash
# Plan changes
terraform plan

# Review output carefully
# Apply if changes are acceptable
terraform apply
```

## 🗑️ Cleanup

To destroy all infrastructure:

```bash
# CAUTION: This will delete ALL resources
terraform destroy

# Confirm the deletion
# Type 'yes' when prompted
```

**Important**: This will delete:
- All EC2 instances
- RDS cluster (unless deletion protection is enabled)
- S3 buckets and all backups
- VPC and networking

Manually delete if needed:
- S3 buckets (data loss risk - verify backups first)
- KMS keys (follow proper key deletion procedures)

## 📚 Additional Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)
- [DocVerifier Documentation](/docs/)

## 📞 Support

For issues or questions:

1. Check Terraform output for specific error messages
2. Review AWS CloudTrail for API errors
3. Consult with team on AWS permissions
4. Check network connectivity and security groups

---

**Last Updated**: 2026-03-26
**Terraform Version**: >= 1.5
**AWS Provider Version**: ~> 5.0
