# Week 2: Monitoring Stack Implementation

## Overview

Week 2 implements comprehensive production-grade monitoring for the DocVerifier Fabric network using:

- **Prometheus** - Time-series metrics collection and storage
- **Grafana** - Dashboard and visualization platform
- **Alertmanager** - Alert routing and notifications
- **Node Exporter** - System resource metrics (CPU, memory, disk, network)

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│         Metrics Collection & Scraping                        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Prometheus (9090)                                           │
│  ├─ Scrape orderer metrics  (orderer0-2:17050)             │
│  ├─ Scrape peer metrics     (peer0.org1-3:17051+)         │
│  ├─ Scrape backend metrics  (localhost:5000/metrics)      │
│  ├─ Scrape node metrics     (node-exporter:9100)          │
│  └─ 30-day metric retention                                │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│         Visualization & Alerting                             │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Grafana (3001)                - Alertmanager (9093)       │
│  ├─ Fabric Overview Dashboard   ├─ Alert Rules             │
│  ├─ API Metrics Dashboard        ├─ Slack Notifications    │
│  ├─ System Resources Dashboard   ├─ Email Notifications    │
│  ├─ Chaincode Performance        ├─ PagerDuty Integration  │
│  ├─ Active Alerts Display        └─ Inhibition Rules       │
│  └─ Available at http://localhost:3001 (admin/admin123)    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Prerequisites

Ensure the fabric network is running with metrics enabled:

```bash
cd fabric
docker-compose ps
# Should show all orderers, peers, and CouchDB containers
```

Verify metrics endpoints are accessible:

```bash
curl http://orderer0.example.com:17050/metrics | head -20
curl http://peer0.org1.example.com:17051/metrics | head -20
```

### 2. Start Monitoring Stack

```bash
# Navigate to monitoring directory
cd monitoring

# Create environment file for notifications (optional)
cat > .env.local <<EOF
GRAFANA_PASSWORD=your-secure-password
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PAGERDUTY_SERVICE_KEY=your-pagerduty-key
SMTP_HOST=smtp.gmail.com:587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
EOF

# Start monitoring services
docker-compose up -d

# Verify all services are running
docker-compose ps
```

### 3. Access Dashboards

**Grafana** (Dashboards & Visualization):
- URL: http://localhost:3001
- Username: `admin`
- Password: `admin123` (or set via `GRAFANA_PASSWORD`)
- Dashboards available:
  - **Fabric Network Overview** - Orderer/peer health, transaction throughput, latency
  - **API Metrics** - Request rates, response times, error rates
  - **System Resources** - CPU, memory, disk, network I/O
  - **Chaincode Performance** - Execution latency, success rates
  - **Active Alerts** - Current firing and resolved alerts

**Prometheus** (Metrics Database):
- URL: http://localhost:9090
- Query interface for ad-hoc metric searches
- Example queries:
  ```
  up{job="orderer0"}  # Check if orderer0 is up
  rate(broadcast_processed_count[5m])  # Transactions per second
  histogram_quantile(0.95, endorsement_duration_seconds)  # P95 latency
  ```

**Alertmanager** (Alert Management):
- URL: http://localhost:9093
- View active alerts, silences, and alert routing rules

### 4. Backend Metrics Instrumentation

The backend API (/api/analyze, /api/fabric/*) now exposes prometheus metrics at:

```
http://localhost:5000/metrics
```

Metrics collected:
- `http_requests_total` - Total HTTP requests by method, path, status
- `http_request_duration_seconds` - Request latency distribution
- `fabric_documents_anchored_total` - Documents anchored by organization
- `document_analysis_total` - AI analysis requests by engine and result
- `ai_check_duration_seconds` - AI check latency
- `fabric_chaincode_invocation_duration_seconds` - Chaincode execution latency

### 5. Verify Metrics Flow

Check Prometheus datasource connection:

```bash
# From Prometheus UI, go to Status > Configuration
# Should show:
#   - job_name: 'prometheus' (self-monitoring)
#   - job_name: 'orderer0', 'orderer1', 'orderer2'
#   - job_name: 'peer-org1', 'peer-org2', 'peer-org3'
#   - job_name: 'backend-api'
#   - job_name: 'node-exporter'
```

Check if data is being scraped:

```bash
# In Prometheus query interface, run:
up
# Should show 6+ metrics
# All healthy services should have value = 1
```

## Configuration Files

### Prometheus Configuration (`prometheus.yml`)

- **Global settings**: 15s scrape interval, 15s evaluation interval
- **Alerting**: Routes alerts to alertmanager:9093
- **Rule files**: References alerts.yml for alert definitions
- **Scrape configs**:
  - **Orderers** (3): 10s scrape interval, Raft + consensus metrics
  - **Peers** (3): 10s scrape interval, endorsement + chaincode metrics
  - **Backend API**: 15s scrape interval, HTTP + Fabric metrics
  - **System**: Node exporter with CPU, memory, disk, network

### Alert Rules (`alerts.yml`)

**Critical Alerts** (immediate notification):
- `OrdererDown` - Orderer unreachable for 2 minutes
- `RaftClusterUnhealthy` - Less than 2 orderers responding (quorum lost)
- `PeerDown` - Peer unreachable for 2 minutes
- `LedgerHeightDivergence` - Peers diverged by >5 blocks
- `HighMemoryUsage` - Memory >85%
- `DiskSpaceVeryLow` - Disk <10%

**Warning Alerts** (routine notification):
- `HighEndorsementLatency` - P95 latency >2sec
- `HighTransactionRejectionRate` - Rejection rate >5%
- `DiskSpaceLow` - Disk <20%
- `HighAPIErrorRate` - Error rate >1%

**Info Alerts** (metrics tracking):
- `HighDocumentAnchoringRate` - >100 docs/sec
- `AveragingLowEndorsementSuccessRate` - Success rate <99%

### Alertmanager Configuration (`alertmanager.yml`)

**Routing**:
- Critical alerts → Slack (#fabric-critical) + PagerDuty + Email
- Orderer alerts → Slack (#fabric-orderers) + PagerDuty
- Peer alerts → Slack (#fabric-peers)
- SLA alerts → Slack (#fabric-sla)
- Warning alerts → Slack (#fabric-warnings)
- Info alerts → Slack (#fabric-metrics)

**Inhibition Rules**:
- Suppress peer alerts if orderer cluster is down (fix root cause first)
- Suppress ledger divergence if peer is already down
- Suppress latency warnings if service is down

## Dashboards

### 1. Fabric Network Overview

Shows macro health of the distributed network:

| Panel | Metric | Threshold | Action |
|-------|--------|-----------|--------|
| **Orderers Status** | `up{job=~"orderer[0-2]"}` | All 3 = green | If <2: Critical error |
| **Peers Status** | `up{job=~"peer-org[1-3]"}` | All 3 = green | If <3: Degraded performance |
| **Backend API** | `up{job="backend-api"}` | 1 = green | If 0: Clients blocked |
| **Block Production** | `rate(ledger_blockchain_height[1m])` | >0 = healthy | If 0: Network stalled |
| **Throughput** | `rate(broadcast_processed_count{status="SUCCESS"}[1m])` | Expected TPS | If 0: Network failure |
| **Endorsement Latency** | `histogram_quantile(0.95, endorsement_duration_seconds)` | <2sec = green | If >5sec: Investigate chaincode |

### 2. API Metrics

Shows backend application performance:

| Panel | Metric | Target | Alert |
|-------|--------|--------|-------|
| **Error Rate** | 5xx errors / total | <1% | >5% = critical |
| **Request Rate** | HTTP per second by endpoint | Tracked | Peak hours: 100+ |
| **Response Time** | P95, P99 latency | <1sec | >2sec = investigate |
| **Document Throughput** | Documents anchored per hour | Tracked | Rate-limited by TPS |
| **Chaincode Duration** | P50, P95 execution time | <100ms | >5sec = slow chaincode |
| **HTTP Status Distribution** | 2xx / 4xx / 5xx count | Most 2xx | Alert if 5xx >10% |

### 3. System Resources

Shows Host/Container resource consumption:

| Gauge | Metric | Yellow | Red |
|-------|--------|--------|-----|
| **CPU** | `100 - avg(idle)` | 70% | 90% |
| **Memory** | `(Total - Available) / Total` | 70% | 90% |
| **Disk** | `1 - Available / Total` | 70% | 90% |

**Time Series**:
- CPU usage over last 6 hours
- Memory (Total vs Used) over 6 hours
- Network I/O (TX/RX) throughput

### 4. Chaincode Performance

Deep dive into chaincode execution metrics:

| Panel | Metric | Expected | Alert |
|-------|--------|----------|-------|
| **Invocation Rate** | Invocations per second | 10-50 | >100 = overload |
| **Latency P50/P95/P99** | Execution duration | P50<100ms | P99>5sec = problem |
| **Success Rate** | Success / (Success + Failure) | >99% | <99% = failures |

### 5. Active Alerts

Real-time alert display showing:
- Current firing alerts (severity, message, duration)
- Recently resolved alerts
- Alert details with links to runbooks

## Testing the Monitoring Stack

### Test 1: Verify Data Flow

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, state: .health}'

# Should see all 9 targets with "up" state
```

### Test 2: Trigger an Alert

```bash
# Get container ID
docker ps | grep orderer0

# Stop orderer0 (will trigger OrdererDown alert)
docker stop <container-id>

# Check Prometheus for alert state
curl http://localhost:9090/api/v1/query?query=ALERTS | jq

# Should see ALERTS{alertname="OrdererDown"} = 1

# Check Alertmanager
curl http://localhost:9093/api/v1/alerts | jq '.data[] | {alertname: .labels.alertname, status: .status}'

# Should see OrdererDown in "firing" status
```

### Test 3: View Dashboard Alerts

1. Open Grafana: http://localhost:3001
2. Click "Active Alerts" dashboard
3. Should see OrdererDown alert
4. Restart orderer0:
   ```bash
   docker start <container-id>
   ```
5. Wait 2 minutes - alert should resolve

### Test 4: Query Custom Metrics

In Prometheus UI (http://localhost:9090), try these queries:

```promql
# Current orderer status (1 = up, 0 = down)
up{job="orderer0"}

# Transactions per second
rate(broadcast_processed_count{status="SUCCESS"}[1m])

# P95 transaction latency
histogram_quantile(0.95, broadcast_enqueue_duration)

# Documents anchored today
increase(fabric_documents_anchored_total[24h])

# API error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# System CPU usage
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

## Troubleshooting

### Metrics not appearing in Prometheus

1. Check Prometheus targets: http://localhost:9090/targets
2. If status is "DOWN":
   - Verify orderer/peer is running: `docker ps | grep orderer`
   - Check metrics endpoint is accessible: `curl http://orderer0.example.com:17050/metrics`
   - Check Prometheus logs: `docker logs prometheus`

### Grafana not connecting to Prometheus

1. Go to Grafana Settings > Data Sources
2. Click Prometheus datasource
3. Check URL: should be `http://prometheus:9090`
4. Click "Test": should see "Data source is working"

### Alerts not firing

1. Check alert rules: http://localhost:9090/rules
2. If status is "Inactive": threshold not met
3. If status is "Pending": waiting for `for` duration to elapse
4. Check Alertmanager: http://localhost:9093
5. Verify webhook URLs are correct in alertmanager.yml

### No data from backend API

1. Verify backend is running: `curl http://localhost:5000/health`
2. Check metrics endpoint: `curl http://localhost:5000/metrics | head -20`
3. If empty: backend may not have prom-client configured
4. Check backend logs: `docker logs verifier-backend 2>&1 | grep metrics`

## Next Steps (Post-Week 2)

- Enable Slack/Email/PagerDuty notifications via environment variables
- Customize alert thresholds based on observed baseline
- Create runbooks for each critical alert
- Implement log aggregation (ELK stack) for error tracking
- Set up dashboard alerts for SLA monitoring

## Production Hardening (Week 3)

- Backup Prometheus data (2-week retention in production)
- Set storage limits for Prometheus TSDB
- Enable persistent volumes for Grafana dashboards
- Secure Grafana with LDAP/OAuth integration
- Configure SSL/TLS for metrics endpoints
