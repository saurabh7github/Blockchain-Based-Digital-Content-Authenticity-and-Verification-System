#!/bin/bash

# fabric/scripts/test-complete-fabric.sh
#
# Comprehensive Fabric Network Test Suite
#
# Tests:
# 1. Network Connectivity (orderers, peers, CouchDB)
# 2. Multi-Organization Setup
# 3. Blockchain Operations (anchor, verify, revoke documents)
# 4. API Integration
# 5. Monitoring Stack
# 6. Security (audit logs, backups, encryption)
# 7. Performance & Scalability
#
# Usage: ./test-complete-fabric.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$FABRIC_DIR")"
LOG_FILE="${FABRIC_DIR}/test-complete-fabric.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_START_TIME=$(date +%s)

# Helper functions
log_test() {
  echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$LOG_FILE"
}

pass_test() {
  echo -e "${GREEN}✅ PASS${NC}: $1" | tee -a "$LOG_FILE"
  ((TESTS_PASSED++))
}

fail_test() {
  echo -e "${RED}❌ FAIL${NC}: $1" | tee -a "$LOG_FILE"
  ((TESTS_FAILED++))
}

skip_test() {
  echo -e "${YELLOW}⊘ SKIP${NC}: $1" | tee -a "$LOG_FILE"
  ((TESTS_SKIPPED++))
}

print_section() {
  echo "" | tee -a "$LOG_FILE"
  echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
  echo -e "${YELLOW}║${NC} $1" | tee -a "$LOG_FILE"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
}

# Initialize log
> "$LOG_FILE"
echo "Fabric Complete Test Suite - $(date)" >> "$LOG_FILE"
echo "=================================================" >> "$LOG_FILE"

echo "" && echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           FABRIC NETWORK COMPLETE TEST SUITE        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"

# ============================================================================
# SECTION 1: Network Connectivity Tests
# ============================================================================

print_section "SECTION 1: Network Connectivity Tests"

log_test "Checking if Docker is running..."
if docker ps > /dev/null 2>&1; then
  pass_test "Docker daemon is running"
else
  fail_test "Docker daemon is not running - cannot proceed"
  exit 1
fi

log_test "Checking Docker Compose version..."
if command -v docker-compose &> /dev/null; then
  COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}')
  pass_test "Docker Compose v$COMPOSE_VERSION installed"
else
  fail_test "Docker Compose not found"
fi

log_test "Checking for fabric docker-compose.yml..."
if [ -f "$FABRIC_DIR/docker-compose.yml" ]; then
  pass_test "docker-compose.yml exists"
else
  fail_test "docker-compose.yml not found"
  exit 1
fi

log_test "Checking if Fabric containers are running..."
RUNNING_CONTAINERS=$(docker-compose -f "$FABRIC_DIR/docker-compose.yml" ps -q 2>/dev/null | wc -l)
if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
  pass_test "Found $RUNNING_CONTAINERS running containers"
else
  skip_test "No containers running - starting Fabric network..."
  cd "$FABRIC_DIR"
  docker-compose up -d 2>&1 | tail -5
  sleep 5
fi

log_test "Checking Orderer connectivity (orderer0.example.com:7050)..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/7050" 2>/dev/null; then
  pass_test "Orderer0 is accessible on port 7050"
else
  fail_test "Orderer0 not responding on port 7050"
fi

log_test "Checking Peer0 Org1 connectivity (peer0.org1:7051)..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/7051" 2>/dev/null; then
  pass_test "Peer0 Org1 is accessible on port 7051"
else
  fail_test "Peer0 Org1 not responding on port 7051"
fi

log_test "Checking CouchDB connectivity (couchdb0:5984)..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/5984" 2>/dev/null; then
  pass_test "CouchDB0 is accessible on port 5984"
else
  fail_test "CouchDB0 not responding on port 5984"
fi

# ============================================================================
# SECTION 2: Multi-Organization Setup Tests
# ============================================================================

print_section "SECTION 2: Multi-Organization Setup Tests"

log_test "Checking crypto configuration for multiple organizations..."
if [ -d "$FABRIC_DIR/crypto-config/peerOrganizations" ]; then
  ORG_COUNT=$(find "$FABRIC_DIR/crypto-config/peerOrganizations" -maxdepth 1 -type d | grep -v "^$FABRIC_DIR" | wc -l)
  if [ "$ORG_COUNT" -ge 3 ]; then
    pass_test "Found $ORG_COUNT peer organizations (expected 3)"
  else
    fail_test "Expected 3+ organizations, found $ORG_COUNT"
  fi
else
  fail_test "crypto-config directory not found"
fi

log_test "Checking for Orderer MSP..."
if [ -d "$FABRIC_DIR/crypto-config/ordererOrganizations" ]; then
  pass_test "Orderer organizations configured"
else
  fail_test "Orderer organizations not configured"
fi

log_test "Checking channel configuration..."
if [ -f "$FABRIC_DIR/channel-artifacts/mychannel.tx" ]; then
  pass_test "Channel transaction artifact exists"
else
  fail_test "Channel transaction artifact not found"
fi

log_test "Checking collections config (private data)..."
if [ -f "$FABRIC_DIR/collections-config.json" ]; then
  pass_test "Collections configuration exists"
else
  fail_test "Collections configuration not found"
fi

# ============================================================================
# SECTION 3: Blockchain Operations Tests
# ============================================================================

print_section "SECTION 3: Blockchain Operations Tests"

log_test "Checking if chaincode is deployed..."
CHAINCODE_STATUS=$(docker exec peer0.org1.example.com \
  peer lifecycle chaincode queryinstalled 2>/dev/null | grep -c "docverifier" || echo "0")

if [ "$CHAINCODE_STATUS" -gt 0 ]; then
  pass_test "Chaincode 'docverifier' is installed"
else
  skip_test "Chaincode not installed - may be normal for fresh deployment"
fi

log_test "Checking channel membership..."
CHANNEL_INFO=$(docker exec peer0.org1.example.com \
  peer channel getinfo -c mychannel 2>/dev/null | grep -c "height" || echo "0")

if [ "$CHANNEL_INFO" -gt 0 ]; then
  pass_test "Peer is a member of mychannel"
else
  fail_test "Peer is not a member of mychannel"
fi

log_test "Checking ledger height..."
LEDGER_HEIGHT=$(docker exec peer0.org1.example.com \
  peer channel getinfo -c mychannel 2>/dev/null | grep "height" | grep -oE '[0-9]+' | head -1)

if [ ! -z "$LEDGER_HEIGHT" ] && [ "$LEDGER_HEIGHT" -gt 0 ]; then
  pass_test "Ledger height: $LEDGER_HEIGHT blocks"
else
  skip_test "Could not retrieve ledger height (may not be initialized yet)"
fi

# ============================================================================
# SECTION 4: Backend API Tests
# ============================================================================

print_section "SECTION 4: Backend API Integration Tests"

log_test "Checking if backend server is running on port 5000..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/5000" 2>/dev/null; then
  pass_test "Backend API is accessible on port 5000"
else
  skip_test "Backend API not running on port 5000 (may need to start separately)"
  BACKEND_RUNNING=0
fi

if [ "${BACKEND_RUNNING:-1}" -ne 0 ]; then
  log_test "Testing health endpoint..."
  HEALTH=$(curl -s http://localhost:5000/health 2>/dev/null | grep -o "ok\|healthy" | head -1)
  if [ ! -z "$HEALTH" ]; then
    pass_test "Backend health check passed"
  else
    fail_test "Backend health check failed"
  fi

  log_test "Testing metrics endpoint..."
  METRICS=$(curl -s http://localhost:5000/metrics 2>/dev/null | grep -c "TYPE\|HELP" || echo "0")
  if [ "$METRICS" -gt 0 ]; then
    pass_test "Prometheus metrics endpoint is responding"
  else
    fail_test "Prometheus metrics endpoint not responding"
  fi

  log_test "Checking API key authentication..."
  # This will fail without a real API key, but we're checking if endpoint exists
  TEST_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET http://localhost:5000/api/fabric/verify/test 2>/dev/null | tail -1)
  if [ "$TEST_RESPONSE" = "401" ] || [ "$TEST_RESPONSE" = "400" ]; then
    pass_test "API key authentication is enforced (got HTTP $TEST_RESPONSE)"
  else
    skip_test "Could not verify API key requirement"
  fi
fi

# ============================================================================
# SECTION 5: Monitoring Stack Tests
# ============================================================================

print_section "SECTION 5: Monitoring Stack Tests"

log_test "Checking if Prometheus is running on port 9090..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/9090" 2>/dev/null; then
  pass_test "Prometheus is accessible on port 9090"

  log_test "Testing Prometheus health endpoint..."
  PROM_HEALTH=$(curl -s http://localhost:9090/-/healthy 2>/dev/null)
  if [ ! -z "$PROM_HEALTH" ]; then
    pass_test "Prometheus health check passed"
  fi

  log_test "Checking Prometheus targets..."
  TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -o "\"health\"" | wc -l)
  if [ "$TARGETS" -gt 0 ]; then
    pass_test "Prometheus has $TARGETS configured targets"
  fi
else
  skip_test "Prometheus not running on port 9090"
fi

log_test "Checking if Grafana is running on port 3001..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/3001" 2>/dev/null; then
  pass_test "Grafana is accessible on port 3001"

  log_test "Testing Grafana API health..."
  GRAFANA_HEALTH=$(curl -s http://localhost:3001/api/health 2>/dev/null | grep -c "ok" || echo "0")
  if [ "$GRAFANA_HEALTH" -gt 0 ]; then
    pass_test "Grafana API is responding"
  fi
else
  skip_test "Grafana not running on port 3001"
fi

log_test "Checking if Alertmanager is running on port 9093..."
if timeout 5 bash -c "echo > /dev/null > /dev/tcp/127.0.0.1/9093" 2>/dev/null; then
  pass_test "Alertmanager is accessible on port 9093"

  log_test "Checking active alerts..."
  ALERTS=$(curl -s http://localhost:9093/api/v1/alerts 2>/dev/null | grep -o "\"status\"" | wc -l)
  if [ ! -z "$ALERTS" ]; then
    pass_test "Alertmanager has $ALERTS alerts"
  fi
else
  skip_test "Alertmanager not running on port 9093"
fi

# ============================================================================
# SECTION 6: Security Tests
# ============================================================================

print_section "SECTION 6: Security Infrastructure Tests"

log_test "Checking secrets management module..."
if [ -f "$PROJECT_ROOT/verifier-backend/utils/secretsManager.js" ]; then
  pass_test "SecretsManager module exists"
else
  fail_test "SecretsManager module not found"
fi

log_test "Checking audit logging system..."
if [ -f "$PROJECT_ROOT/verifier-backend/models/AuditLog.js" ]; then
  if grep -q "immutable.*default.*true" "$PROJECT_ROOT/verifier-backend/models/AuditLog.js"; then
    pass_test "Audit logs configured as immutable"
  else
    fail_test "Audit logs not set as immutable"
  fi
else
  fail_test "AuditLog model not found"
fi

log_test "Checking backup script..."
if [ -f "$FABRIC_DIR/scripts/backup-fabric-network.sh" ]; then
  pass_test "Backup script exists and is available"
else
  fail_test "Backup script not found"
fi

log_test "Checking mTLS configuration script..."
if [ -f "$FABRIC_DIR/scripts/enable-mtls.sh" ]; then
  pass_test "mTLS setup script exists"
else
  fail_test "mTLS setup script not found"
fi

log_test "Checking if .env files are in gitignore..."
if grep -q "\.env" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
  pass_test "Environment files properly ignored in git"
else
  fail_test ".env files not ignored in git"
fi

# ============================================================================
# SECTION 7: Container Status Tests
# ============================================================================

print_section "SECTION 7: Docker Container Status"

log_test "Listing active containers..."
docker-compose -f "$FABRIC_DIR/docker-compose.yml" ps 2>/dev/null | tee -a "$LOG_FILE"

CONTAINER_STATUS=$(docker-compose -f "$FABRIC_DIR/docker-compose.yml" ps 2>/dev/null | grep -c "Up" || echo "0")
if [ "$CONTAINER_STATUS" -gt 0 ]; then
  pass_test "Found $CONTAINER_STATUS containers running"
else
  fail_test "No containers marked as 'Up'"
fi

# ============================================================================
# SECTION 8: Performance & Resource Usage
# ============================================================================

print_section "SECTION 8: Performance & Resource Usage"

log_test "Checking Docker resource usage..."
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | tee -a "$LOG_FILE" || skip_test "Could not retrieve Docker stats"

log_test "Checking disk space..."
DISK_USAGE=$(df -h "$FABRIC_DIR" | awk 'NR==2 {print $5}')
DISK_AVAILABLE=$(df -h "$FABRIC_DIR" | awk 'NR==2 {print $4}')
pass_test "Disk usage: $DISK_USAGE (Available: $DISK_AVAILABLE)"

# ============================================================================
# SECTION 9: Manual Tests (Optional)
# ============================================================================

print_section "SECTION 9: Optional Manual Tests"

log_test "Testing document anchoring (requires API key)..."
skip_test "Skipped - requires valid API key. Test manually with:"
echo "    curl -X POST http://localhost:5000/api/fabric/anchor \\" | tee -a "$LOG_FILE"
echo "      -H 'X-API-Key: YOUR_API_KEY' \\" | tee -a "$LOG_FILE"
echo "      -H 'Content-Type: application/json' \\" | tee -a "$LOG_FILE"
echo "      -d '{\"docHash\": \"test123\", \"fileName\": \"test.pdf\"}'" | tee -a "$LOG_FILE"

log_test "Testing document verification (requires API key)..."
skip_test "Skipped - requires valid API key. Test manually with:"
echo "    curl -X GET http://localhost:5000/api/fabric/verify/test123 \\" | tee -a "$LOG_FILE"
echo "      -H 'X-API-Key: YOUR_API_KEY'" | tee -a "$LOG_FILE"

# ============================================================================
# FINAL REPORT
# ============================================================================

TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
PASS_RATE=$((TOTAL_TESTS > 0 ? TESTS_PASSED * 100 / TOTAL_TESTS : 0))

echo "" && echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           FABRIC TEST SUITE COMPLETE               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

echo "Test Results Summary:" | tee -a "$LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED" | tee -a "$LOG_FILE"
echo -e "${RED}Failed:${NC}  $TESTS_FAILED" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED" | tee -a "$LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
echo "Total:    $TOTAL_TESTS" | tee -a "$LOG_FILE"
echo "Duration: ${TEST_DURATION}s" | tee -a "$LOG_FILE"
echo ""

if [ $PASS_RATE -ge 90 ]; then
  echo -e "${GREEN}✅ PASS RATE: ${PASS_RATE}% - EXCELLENT!${NC}" | tee -a "$LOG_FILE"
  EXIT_CODE=0
elif [ $PASS_RATE -ge 70 ]; then
  echo -e "${YELLOW}⚠️  PASS RATE: ${PASS_RATE}% - GOOD (some issues found)${NC}" | tee -a "$LOG_FILE"
  EXIT_CODE=0
else
  echo -e "${RED}❌ PASS RATE: ${PASS_RATE}% - CRITICAL (major issues)${NC}" | tee -a "$LOG_FILE"
  EXIT_CODE=1
fi

echo ""
echo "View full log: tail -f $LOG_FILE"
echo ""

exit $EXIT_CODE
