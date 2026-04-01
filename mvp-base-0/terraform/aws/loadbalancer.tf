# terraform/aws/loadbalancer.tf
# Application Load Balancer for HTTPS Termination and Routing

# ============================================================================
# Application Load Balancer
# ============================================================================

resource "aws_lb" "fabric" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = true
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb-logs"
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-alb"
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# ============================================================================
# Target Groups
# ============================================================================

# Backend API Target Group
resource "aws_lb_target_group" "backend_api" {
  name        = "${var.project_name}-backend-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.fabric.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-backend-tg"
  }
}

# Register backend instance with target group
resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend_api.arn
  target_id        = aws_instance.backend.id
  port             = 5000
}

# Monitoring/Grafana Target Group
resource "aws_lb_target_group" "monitoring" {
  name        = "${var.project_name}-monitoring-tg"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.fabric.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-monitoring-tg"
  }
}

# Register monitoring instance with target group
resource "aws_lb_target_group_attachment" "monitoring" {
  target_group_arn = aws_lb_target_group.monitoring.arn
  target_id        = aws_instance.monitoring.id
  port             = 3001
}

# ============================================================================
# SSL/TLS Certificate (self-signed for this template - use ACM in production)
# ============================================================================

# NOTE: In production, use AWS Certificate Manager (ACM) for managed certificates
# For this template, we provide a variable for an existing certificate ARN
variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate in AWS Certificate Manager. Leave empty to create self-signed."
  type        = string
  default     = ""
}

# Self-signed certificate (development only)
resource "tls_private_key" "fabric_api" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "fabric_api" {
  private_key_pem = tls_private_key.fabric_api.private_key_pem

  subject {
    common_name  = "api.${var.project_name}.internal"
    organization = "DocVerifier"
  }

  validity_period_hours = 8760  # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "fabric_api" {
  private_key      = tls_private_key.fabric_api.private_key_pem
  certificate_body = tls_self_signed_cert.fabric_api.cert_pem

  tags = {
    Name = "${var.project_name}-api-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# ALB Listeners
# ============================================================================

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.fabric.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.fabric.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn != "" ? var.ssl_certificate_arn : aws_acm_certificate.fabric_api.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_api.arn
  }

  depends_on = [aws_acm_certificate.fabric_api]
}

# ============================================================================
# ALB Rules (Path-based routing)
# ============================================================================

# Route /api/* to backend
resource "aws_lb_listener_rule" "api_routes" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Route /health to backend
resource "aws_lb_listener_rule" "health_check" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_api.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

# Route /metrics to backend
resource "aws_lb_listener_rule" "metrics" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_api.arn
  }

  condition {
    path_pattern {
      values = ["/metrics"]
    }
  }
}

# Route /grafana/* to monitoring
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.monitoring.arn
  }

  condition {
    path_pattern {
      values = ["/grafana", "/grafana/*"]
    }
  }
}

# ============================================================================
# S3 Bucket for ALB Access Logs
# ============================================================================

resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project_name}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-alb-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow ELB service account to write logs
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowELBRootAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::127311923021:root"  # ELB service account for us-east-1
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# Lifecycle for log cleanup
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "alb_dns_name" {
  value       = aws_lb.fabric.dns_name
  description = "DNS name of the ALB"
}

output "alb_arn" {
  value       = aws_lb.fabric.arn
  description = "ARN of the ALB"
}

output "alb_zone_id" {
  value       = aws_lb.fabric.zone_id
  description = "Zone ID of the ALB"
}

output "backend_target_group_arn" {
  value       = aws_lb_target_group.backend_api.arn
  description = "Backend API target group ARN"
}

output "monitoring_target_group_arn" {
  value       = aws_lb_target_group.monitoring.arn
  description = "Monitoring target group ARN"
}
