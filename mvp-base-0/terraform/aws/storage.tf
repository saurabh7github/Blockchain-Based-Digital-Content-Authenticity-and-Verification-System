# terraform/aws/storage.tf
# S3 Backup Storage and KMS Encryption

# ============================================================================
# KMS Encryption Keys
# ============================================================================

# Master KMS Key for all encryption
resource "aws_kms_key" "fabric" {
  description             = "KMS key for DocVerifier Fabric encryption"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-kms-key"
  }
}

resource "aws_kms_alias" "fabric" {
  name          = "alias/${var.project_name}-encryption"
  target_key_id = aws_kms_key.fabric.key_id
}

# ============================================================================
# S3 Backup Bucket
# ============================================================================

# S3 Bucket for backups
resource "aws_s3_bucket" "backups" {
  bucket = "${var.backup_bucket_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "${var.project_name}-backups"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for backup retention
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = var.enable_backup_versioning ? "Enabled" : "Suspended"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.fabric.arn
    }
    bucket_key_enabled = true
  }
}

# Enable access logging
resource "aws_s3_bucket_logging" "backups" {
  bucket = aws_s3_bucket.backups.id

  target_bucket = aws_s3_bucket.backup_logs.id
  target_prefix = "backup-access-logs/"
}

# Lifecycle policy for automatic cleanup
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "glacier-archive"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}

# MFA Delete protection (optional - requires MFA for object deletion)
resource "aws_s3_bucket_versioning" "backups_mfa" {
  count  = var.rds_deletion_protection ? 1 : 0
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Enabled"
  }

  depends_on = [aws_s3_bucket_public_access_block.backups]
}

# Bucket policy to allow EC2 instances to read/write
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2Backup"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.fabric_ec2_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      },
      {
        Sid    = "DenyUnencryptedObjectUploads"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.backups.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

# ============================================================================
# S3 Backup Logs Bucket
# ============================================================================

resource "aws_s3_bucket" "backup_logs" {
  bucket = "${var.backup_bucket_prefix}-logs-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "${var.project_name}-backup-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "backup_logs" {
  bucket = aws_s3_bucket.backup_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle for log cleanup
resource "aws_s3_bucket_lifecycle_configuration" "backup_logs" {
  bucket = aws_s3_bucket.backup_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# ============================================================================
# S3 Bucket for Terraform State (Optional backend)
# ============================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-terraform-state"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.fabric.arn
    }
  }
}

# DynamoDB table for Terraform state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "${var.project_name}-terraform-locks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-terraform-locks"
  }
}

# ============================================================================
# CloudWatch Logs
# ============================================================================

resource "aws_cloudwatch_log_group" "fabric" {
  name              = "/aws/fabric/${var.project_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = aws_kms_key.fabric.arn

  tags = {
    Name = "${var.project_name}-logs"
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/aws/backend/${var.project_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = aws_kms_key.fabric.arn

  tags = {
    Name = "${var.project_name}-backend-logs"
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "kms_key_id" {
  value       = aws_kms_key.fabric.key_id
  description = "KMS key ID for encryption"
}

output "s3_backup_bucket" {
  value       = aws_s3_bucket.backups.id
  description = "S3 bucket for backups"
}

output "s3_backup_bucket_arn" {
  value       = aws_s3_bucket.backups.arn
  description = "S3 backup bucket ARN"
}

output "terraform_state_bucket" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket for Terraform state"
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.fabric.name
  description = "CloudWatch log group for Fabric"
}
