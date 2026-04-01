# terraform/aws/compute.tf
# EC2 Instances for Fabric Network Components

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key Pair for EC2 instances
resource "aws_key_pair" "fabric" {
  key_name   = "${var.project_name}-key"
  public_key = file("~/.ssh/id_rsa.pub")

  tags = {
    Name = "${var.project_name}-key"
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "fabric_ec2_role" {
  name_prefix = "fabric-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for EC2 instances (CloudWatch, Secrets Manager, S3)
resource "aws_iam_role_policy" "fabric_ec2_policy" {
  name   = "fabric-ec2-policy"
  role   = aws_iam_role.fabric_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:docverifier/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.backup_bucket_prefix}-*",
          "arn:aws:s3:::${var.backup_bucket_prefix}-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "fabric_ec2" {
  role = aws_iam_role.fabric_ec2_role.name
}

# Orderer Instances (3 nodes for Raft consensus)
resource "aws_instance" "orderers" {
  count                    = 3
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.orderer_instance_type
  subnet_id                = aws_subnet.private[count.index].id
  vpc_security_group_ids   = [aws_security_group.orderers.id]
  iam_instance_profile     = aws_iam_instance_profile.fabric_ec2.name
  key_name                 = aws_key_pair.fabric.key_name
  monitoring               = var.enable_detailed_monitoring
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-orderer-${count.index}"
    Role = "orderer"
  }

  depends_on = [aws_nat_gateway.fabric]
}

# Peer Instances (3 nodes, one per organization)
resource "aws_instance" "peers" {
  count                    = 3
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.peer_instance_type
  subnet_id                = aws_subnet.private[count.index].id
  vpc_security_group_ids   = [aws_security_group.peers.id]
  iam_instance_profile     = aws_iam_instance_profile.fabric_ec2.name
  key_name                 = aws_key_pair.fabric.key_name
  monitoring               = var.enable_detailed_monitoring
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 200
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-peer-${count.index}"
    Role = "peer"
  }

  depends_on = [aws_nat_gateway.fabric]
}

# CA Instances (3 Certificate Authorities)
resource "aws_instance" "cas" {
  count                    = 3
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.ca_instance_type
  subnet_id                = aws_subnet.private[count.index].id
  vpc_security_group_ids   = [aws_security_group.cas.id]
  iam_instance_profile     = aws_iam_instance_profile.fabric_ec2.name
  key_name                 = aws_key_pair.fabric.key_name
  monitoring               = var.enable_detailed_monitoring
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-ca-${count.index}"
    Role = "ca"
  }

  depends_on = [aws_nat_gateway.fabric]
}

# Backend API Instance
resource "aws_instance" "backend" {
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.backend_instance_type
  subnet_id                = aws_subnet.private[0].id
  vpc_security_group_ids   = [aws_security_group.backend.id]
  iam_instance_profile     = aws_iam_instance_profile.fabric_ec2.name
  key_name                 = aws_key_pair.fabric.key_name
  monitoring               = var.enable_detailed_monitoring
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-backend"
    Role = "backend"
  }

  depends_on = [aws_nat_gateway.fabric]
}

# Monitoring Instance
resource "aws_instance" "monitoring" {
  ami                      = data.aws_ami.ubuntu.id
  instance_type            = var.monitoring_instance_type
  subnet_id                = aws_subnet.private[1].id
  vpc_security_group_ids   = [aws_security_group.backend.id]
  iam_instance_profile     = aws_iam_instance_profile.fabric_ec2.name
  key_name                 = aws_key_pair.fabric.key_name
  monitoring               = var.enable_detailed_monitoring
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-monitoring"
    Role = "monitoring"
  }

  depends_on = [aws_nat_gateway.fabric]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "orderer_instance_ids" {
  value       = aws_instance.orderers[*].id
  description = "Orderer instance IDs"
}

output "orderer_private_ips" {
  value       = aws_instance.orderers[*].private_ip
  description = "Orderer private IPs"
}

output "peer_instance_ids" {
  value       = aws_instance.peers[*].id
  description = "Peer instance IDs"
}

output "peer_private_ips" {
  value       = aws_instance.peers[*].private_ip
  description = "Peer private IPs"
}

output "ca_instance_ids" {
  value       = aws_instance.cas[*].id
  description = "CA instance IDs"
}

output "backend_instance_id" {
  value       = aws_instance.backend.id
  description = "Backend instance ID"
}

output "backend_private_ip" {
  value       = aws_instance.backend.private_ip
  description = "Backend private IP"
}

output "monitoring_instance_id" {
  value       = aws_instance.monitoring.id
  description = "Monitoring instance ID"
}

output "monitoring_private_ip" {
  value       = aws_instance.monitoring.private_ip
  description = "Monitoring private IP"
}
