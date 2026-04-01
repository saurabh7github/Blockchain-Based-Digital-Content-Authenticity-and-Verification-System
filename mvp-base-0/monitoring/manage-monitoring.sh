#!/usr/bin/env bash
set -euo pipefail

# Monitoring Stack Management Script
# Usage: ./manage-monitoring.sh [start|stop|restart|status|logs]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")}" && pwd)"
MONITORING_DIR="${SCRIPT_DIR}"

# Detect the monitoring docker-compose file
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Error: docker-compose.yml not found in $MONITORING_DIR"
  exit 1
fi

show_usage() {
  cat <<EOF
Monitoring Stack Manager

Usage: $0 [COMMAND]

Commands:
  start       - Start all monitoring services (Prometheus, Grafana, Alertmanager)
  stop        - Stop all monitoring services
  restart     - Restart all monitoring services
  status      - Show status of all monitoring services
  logs        - Show live logs from all services
  logs-prom   - Show Prometheus logs only
  logs-grafana - Show Grafana logs only
  logs-alert  - Show Alertmanager logs only
  health      - Check health of monitoring endpoints
  clean       - Remove stopped containers and volumes (WARNING: deletes data)

Examples:
  $0 start          # Start monitoring
  $0 logs           # View all logs
  $0 health         # Check if metrics endpoints are accessible
EOF
}

start_monitoring() {
  echo "🚀 Starting monitoring stack..."
  docker-compose -f "$COMPOSE_FILE" up -d

  # Wait for services to be healthy
  echo "⏳ Waiting for services to be ready..."
  sleep 5

  status_monitoring

  echo ""
  echo "✅ Monitoring stack started successfully!"
  echo ""
  echo "Access points:"
  echo "  • Prometheus:     http://localhost:9090"
  echo "  • Grafana:        http://localhost:3001 (admin/admin123)"
  echo "  • Alertmanager:   http://localhost:9093"
  echo "  • Node Exporter:  http://localhost:9100"
  echo ""
}

stop_monitoring() {
  echo "🛑 Stopping monitoring stack..."
  docker-compose -f "$COMPOSE_FILE" down
  echo "✅ Monitoring stack stopped"
}

restart_monitoring() {
  echo "🔄 Restarting monitoring stack..."
  stop_monitoring
  sleep 2
  start_monitoring
}

status_monitoring() {
  echo "📊 Monitoring Stack Status:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  docker-compose -f "$COMPOSE_FILE" ps
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

show_logs() {
  echo "📜 Monitoring Stack Logs (streaming)..."
  docker-compose -f "$COMPOSE_FILE" logs -f
}

show_logs_component() {
  local component=$1
  docker-compose -f "$COMPOSE_FILE" logs -f "$component"
}

check_health() {
  echo "🏥 Checking monitoring endpoint health..."
  echo ""

  endpoints=(
    "Prometheus:http://localhost:9090/-/healthy"
    "Grafana:http://localhost:3000/api/health"
    "Alertmanager:http://localhost:9093/-/healthy"
    "Node Exporter:http://localhost:9100/"
  )

  for endpoint in "${endpoints[@]}"; do
    IFS=':' read -r name url <<< "$endpoint"
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|404"; then
      echo "✅ $name is healthy"
    else
      status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
      echo "❌ $name returned status $status"
    fi
  done

  echo ""
  echo "📊 Checking Prometheus targets..."
  TARGETS=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length')
  UP=$(curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health=="up")] | length')
  echo "   Total targets: $TARGETS"
  echo "   Healthy targets: $UP"
  if [ "$TARGETS" -gt 0 ] && [ "$UP" -eq "$TARGETS" ]; then
    echo "   ✅ All targets are healthy"
  else
    echo "   ⚠️  Some targets are unhealthy. Check http://localhost:9090/targets"
  fi

  echo ""
  echo "🚨 Checking active alerts..."
  ALERTS=$(curl -s http://localhost:9093/api/v1/alerts | jq '.data | length')
  if [ "$ALERTS" -eq 0 ]; then
    echo "   ✅ No active alerts"
  else
    echo "   ⚠️  $ALERTS active alerts:"
    curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | {alertname: .labels.alertname, severity: .labels.severity, status: .status}' | head -20
  fi
}

clean_monitoring() {
  echo "⚠️  WARNING: This will delete all monitoring data (Prometheus TSDB, Grafana dashboards)"
  read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm

  if [ "$confirm" = "yes" ]; then
    echo "🗑️  Cleaning monitoring stack..."
    docker-compose -f "$COMPOSE_FILE" down -v
    echo "✅ Monitoring stack cleaned and volumes removed"
  else
    echo "❌ Operation cancelled"
  fi
}

# Main command dispatch
COMMAND="${1:-start}"

case "$COMMAND" in
  start)
    start_monitoring
    ;;
  stop)
    stop_monitoring
    ;;
  restart)
    restart_monitoring
    ;;
  status)
    status_monitoring
    ;;
  logs)
    show_logs
    ;;
  logs-prom)
    show_logs_component "prometheus"
    ;;
  logs-grafana)
    show_logs_component "grafana"
    ;;
  logs-alert)
    show_logs_component "alertmanager"
    ;;
  health)
    check_health
    ;;
  clean)
    clean_monitoring
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo ""
    show_usage
    exit 1
    ;;
esac
