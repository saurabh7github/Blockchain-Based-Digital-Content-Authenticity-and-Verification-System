terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use remote state storage
  # backend "s3" {
  #   bucket         = "docverifier-terraform-state"
  #   key            = "fabric/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "DocVerifier"
      Environment = var.environment
      CreatedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# ============================================================================
# VPC AND NETWORKING
# ============================================================================

# Create VPC
resource "aws_vpc" "fabric" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "fabric" {
  vpc_id = aws_vpc.fabric.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.fabric.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.fabric.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count  = length(var.private_subnets)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.fabric]
}

# NAT Gateways (one per private subnet)
resource "aws_nat_gateway" "fabric" {
  count         = length(var.private_subnets)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.fabric]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.fabric.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.fabric.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Public Route Table Association
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (one per AZ for high availability)
resource "aws_route_table" "private" {
  count  = length(var.private_subnets)
  vpc_id = aws_vpc.fabric.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.fabric[count.index].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  }
}

# Private Route Table Association
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

# Security Group for Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "fabric-alb-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere (redirect to HTTPS)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Security Group for Orderers
resource "aws_security_group" "orderers" {
  name_prefix = "fabric-orderers-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port   = 7050
    to_port     = 7050
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
    description = "Orderer gRPC from ALB"
  }

  ingress {
    from_port       = 7050
    to_port         = 7050
    protocol        = "tcp"
    security_groups = [aws_security_group.peers.id]
    description     = "Orderer gRPC from peers"
  }

  ingress {
    from_port   = 17050
    to_port     = 17050
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Orderer operations/metrics"
  }

  # Allow inter-orderer communication
  ingress {
    from_port       = 7050
    to_port         = 7052
    protocol        = "tcp"
    self            = true
    description     = "Inter-orderer communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-orderers-sg"
  }
}

# Security Group for Peers
resource "aws_security_group" "peers" {
  name_prefix = "fabric-peers-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port   = 7051
    to_port     = 7051
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
    description = "Peer gRPC from ALB"
  }

  ingress {
    from_port       = 7051
    to_port         = 7051
    protocol        = "tcp"
    self            = true
    description     = "Peer-to-peer communication"
  }

  ingress {
    from_port   = 17051
    to_port     = 17051
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Peer operations/metrics"
  }

  # Event listener port
  ingress {
    from_port   = 7053
    to_port     = 7053
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Peer event listener"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-peers-sg"
  }
}

# Security Group for CAs
resource "aws_security_group" "cas" {
  name_prefix = "fabric-cas-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port   = 7054
    to_port     = 7054
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "CA API port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-cas-sg"
  }
}

# Security Group for Backend API
resource "aws_security_group" "backend" {
  name_prefix = "fabric-backend-"
  vpc_id      = aws_vpc.fabric.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
    description = "Backend API from ALB"
  }

  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Node exporter metrics"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-backend-sg"
  }
}

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

# ============================================================================
# OUTPUTS
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

output "security_group_orderers_id" {
  value       = aws_security_group.orderers.id
  description = "Orderers security group ID"
}

output "security_group_peers_id" {
  value       = aws_security_group.peers.id
  description = "Peers security group ID"
}

output "security_group_backend_id" {
  value       = aws_security_group.backend.id
  description = "Backend security group ID"
}

output "security_group_rds_id" {
  value       = aws_security_group.rds.id
  description = "RDS security group ID"
}
