# terraform/aws/monitoring.tf
# CloudWatch Metrics, Alarms, and SNS Notifications

# ============================================================================
# SNS Topics for Alerts
# ============================================================================

resource "aws_sns_topic" "fabric_alerts" {
  name              = "${var.project_name}-alerts"
  kms_master_key_id = aws_kms_key.fabric.id

  tags = {
    Name = "${var.project_name}-alerts-topic"
  }
}

resource "aws_sns_topic_subscription" "fabric_alerts_email" {
  topic_arn = aws_sns_topic.fabric_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # Email subscription requires manual confirmation
}

# Critical alerts topic (for PagerDuty integration)
resource "aws_sns_topic" "fabric_critical_alerts" {
  name              = "${var.project_name}-critical-alerts"
  kms_master_key_id = aws_kms_key.fabric.id

  tags = {
    Name = "${var.project_name}-critical-alerts-topic"
  }
}

resource "aws_sns_topic_subscription" "fabric_critical_alerts_email" {
  topic_arn = aws_sns_topic.fabric_critical_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ============================================================================
# CloudWatch Alarms - EC2 Instances
# ============================================================================

# Orderer Instance Alarms
resource "aws_cloudwatch_metric_alarm" "orderer_cpu" {
  count               = 3
  alarm_name          = "${var.project_name}-orderer-${count.index}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when orderer ${count.index} CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.fabric_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.orderers[count.index].id
  }
}

# Orderer Memory Alarms
resource "aws_cloudwatch_metric_alarm" "orderer_memory" {
  count               = 3
  alarm_name          = "${var.project_name}-orderer-${count.index}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "Alert when orderer ${count.index} memory exceeds 85%"
  alarm_actions       = [aws_sns_topic.fabric_critical_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.orderers[count.index].id
  }
}

# Peer Instance Alarms
resource "aws_cloudwatch_metric_alarm" "peer_cpu" {
  count               = 3
  alarm_name          = "${var.project_name}-peer-${count.index}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when peer ${count.index} CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.fabric_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.peers[count.index].id
  }
}

# Status Check Failed Alarms
resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  count               = 11  # 3 orderers + 3 peers + 3 CAs + 1 backend + 1 monitoring
  alarm_name          = "${var.project_name}-instance-${count.index}-status-check"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Alert when instance status check fails"
  alarm_actions       = [aws_sns_topic.fabric_critical_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = try(
      concat(
        aws_instance.orderers[*].id,
        aws_instance.peers[*].id,
        aws_instance.cas[*].id,
        [aws_instance.backend.id],
        [aws_instance.monitoring.id]
      )[count.index],
      "unknown"
    )
  }

  depends_on = [
    aws_instance.orderers,
    aws_instance.peers,
    aws_instance.cas,
    aws_instance.backend,
    aws_instance.monitoring
  ]
}

# ============================================================================
# CloudWatch Alarms - RDS
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when RDS CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.fabric_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.fabric_mongodb.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project_name}-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "800"  # 80% of max
  alarm_description   = "Alert when RDS connections exceed 80% of max"
  alarm_actions       = [aws_sns_topic.fabric_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.fabric_mongodb.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project_name}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10737418240"  # 10 GB
  alarm_description   = "Alert when RDS free storage drops below 10GB"
  alarm_actions       = [aws_sns_topic.fabric_critical_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.fabric_mongodb.cluster_identifier
  }
}

# ============================================================================
# CloudWatch Alarms - Load Balancer
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "alb_target_health" {
  alarm_name          = "${var.project_name}-alb-unhealthy-targets"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Alert when ALB has unhealthy targets"
  alarm_actions       = [aws_sns_topic.fabric_critical_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.fabric.arn_suffix
    TargetGroup  = aws_lb_target_group.backend_api.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_request_count" {
  alarm_name          = "${var.project_name}-alb-no-requests"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when ALB receives no requests (possible outage)"
  alarm_actions       = [aws_sns_topic.fabric_critical_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.fabric.arn_suffix
  }
}

# ============================================================================
# CloudWatch Dashboards
# ============================================================================

resource "aws_cloudwatch_dashboard" "fabric_overview" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", label = "Avg CPU" }],
            [".", ".", { stat = "Maximum", label = "Max CPU" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EC2 CPU Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
            [".", "DatabaseConnections", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            [".", "RequestCount", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Load Balancer Performance"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "fabric_network" {
  dashboard_name = "${var.project_name}-network"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "NetworkIn", { stat = "Sum" }],
            [".", "NetworkOut", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Network Traffic"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "ProcessedBytes", { stat = "Sum" }],
            [".", "ActiveConnectionCount", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ALB Connections & Throughput"
        }
      }
    ]
  })
}

# ============================================================================
# Outputs
# ============================================================================

output "sns_alerts_topic_arn" {
  value       = aws_sns_topic.fabric_alerts.arn
  description = "SNS topic ARN for general alerts"
}

output "sns_critical_alerts_topic_arn" {
  value       = aws_sns_topic.fabric_critical_alerts.arn
  description = "SNS topic ARN for critical alerts"
}

output "cloudwatch_dashboard_overview" {
  value       = aws_cloudwatch_dashboard.fabric_overview.dashboard_name
  description = "CloudWatch dashboard URL"
}
