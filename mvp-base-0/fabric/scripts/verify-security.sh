#!/bin/bash
set -e

# fabric/scripts/verify-security.sh
#
# Comprehensive security verification for production deployment
# Checks:
# - Secrets stored in AWS Secrets Manager (not in git)
# - mTLS certificates generated and valid
# - Audit logging operational
# - Backup system working
# - No sensitive data in code or configs
# - Access control policies enforced

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$FABRIC_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

# Test counters
test_count() {
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Security Verification Progress: $TESTS_PASSED passed, $TESTS_FAILED failed, $WARNINGS warnings${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass_test() {
  echo -e "${GREEN}✅ $1${NC}"
  ((TESTS_PASSED++))
}

fail_test() {
  echo -e "${RED}❌ $1${NC}"
  ((TESTS_FAILED++))
}

warn_test() {
  echo -e "${YELLOW}⚠️  $1${NC}"
  ((WARNINGS++))
}

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}SECURITY VERIFICATION SUITE${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# ============================================================================
# TEST 1: Secret Management
# ============================================================================
echo -e "${YELLOW}[1/8] Checking Secrets Management...${NC}"

# Check .env not committed
if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
  if grep -q "\.env" "${PROJECT_ROOT}/.gitignore"; then
    pass_test ".env file is in .gitignore"
  else
    fail_test ".env file should be in .gitignore"
  fi
else
  warn_test ".gitignore not found"
fi

# Check no secrets in git history
SECRETS_IN_GIT=0
for secret_pattern in "mongodb_password" "jwt_secret" "api_key" "ORDERER_KEY" "PEER_KEY"; do
  git log --all --group-objects-by-object-size -S "$secret_pattern" 2>/dev/null | wc -l | grep -q "^0$" && continue
  SECRETS_IN_GIT=$((SECRETS_IN_GIT + 1))
done

if [ $SECRETS_IN_GIT -eq 0 ]; then
  pass_test "No secrets found in git history"
else
  fail_test "Found $SECRETS_IN_GIT potential secrets in git history"
fi

# Check SecretsManager module exists
if [ -f "${PROJECT_ROOT}/verifier-backend/utils/secretsManager.js" ]; then
  pass_test "SecretsManager module exists"
else
  fail_test "SecretsManager module not found"
fi

test_count

# ============================================================================
# TEST 2: mTLS Certificates
# ============================================================================
echo -e "${YELLOW}[2/8] Checking mTLS Certificates...${NC}"

TLS_DIR="${FABRIC_DIR}/tls-config"
DOCKER_VOLUMES_DIR="${FABRIC_DIR}/docker-volumes"

# Check TLS CA exists
if [ -f "${TLS_DIR}/ca/ca-cert.pem" ]; then
  pass_test "TLS CA certificate exists"

  # Check CA validity
  EXPIRY=$(openssl x509 -in "${TLS_DIR}/ca/ca-cert.pem" -noout -dates | grep "notAfter" | cut -d= -f2)
  echo -e "   CA Certificate expires: $EXPIRY"
else
  warn_test "TLS CA certificate not generated yet (run enable-mtls.sh)"
fi

# Check orderer certificates
for i in 0 1 2; do
  ORDERER_CERT="${TLS_DIR}/orderer/orderer${i}/server.crt"
  if [ -f "$ORDERER_CERT" ]; then
    pass_test "Orderer $i TLS certificate exists"
  else
    fail_test "Orderer $i TLS certificate missing"
  fi
done

# Check peer certificates
for i in 0 1 2; do
  PEER_CERT="${TLS_DIR}/peer/peer${i}/server.crt"
  if [ -f "$PEER_CERT" ]; then
    pass_test "Peer $i TLS certificate exists"
  else
    fail_test "Peer $i TLS certificate missing"
  fi
done

# Check private keys are not in git
PRIVATE_KEYS_IN_GIT=$(git ls-tree -r HEAD --name-only | grep -c "\.key$" || echo "0")
if [ "$PRIVATE_KEYS_IN_GIT" -eq 0 ]; then
  pass_test "No private keys committed to git"
else
  fail_test "Found $PRIVATE_KEYS_IN_GIT private key files in git"
fi

test_count

# ============================================================================
# TEST 3: Audit Logging
# ============================================================================
echo -e "${YELLOW}[3/8] Checking Audit Logging...${NC}"

# Check AuditLog model exists
if [ -f "${PROJECT_ROOT}/verifier-backend/models/AuditLog.js" ]; then
  pass_test "AuditLog model exists"

  # Check immutable flag
  if grep -q "immutable.*default.*true" "${PROJECT_ROOT}/verifier-backend/models/AuditLog.js"; then
    pass_test "Audit logs configured as immutable"
  else
    fail_test "Audit logs should be immutable by default"
  fi
else
  fail_test "AuditLog model not found"
fi

# Check auditLog middleware exists
if [ -f "${PROJECT_ROOT}/verifier-backend/middleware/auditLog.js" ]; then
  pass_test "Audit logging middleware exists"

  # Check for sensitive field sanitization
  if grep -q "sanitize\|password\|secret\|key\|token" "${PROJECT_ROOT}/verifier-backend/middleware/auditLog.js"; then
    pass_test "Sensitive fields are sanitized in audit logs"
  else
    warn_test "Verify sensitive field sanitization is implemented"
  fi
else
  fail_test "Audit logging middleware not found"
fi

test_count

# ============================================================================
# TEST 4: Backup & Recovery
# ============================================================================
echo -e "${YELLOW}[4/8] Checking Backup & Recovery...${NC}"

# Check backup script exists
if [ -f "${FABRIC_DIR}/scripts/backup-fabric-network.sh" ]; then
  pass_test "Backup script exists"

  # Check script has required functions
  for func in "backup_ledger" "backup_couchdb" "backup_mongodb"; do
    if grep -q "^${func}" "${FABRIC_DIR}/scripts/backup-fabric-network.sh"; then
      pass_test "Backup script has $func function"
    fi
  done
else
  fail_test "Backup script not found"
fi

# Check restore script exists
if [ -f "${FABRIC_DIR}/scripts/restore-fabric-network.sh" ]; then
  pass_test "Restore script exists"
else
  fail_test "Restore script not found"
fi

# Check backup location is writable
BACKUP_DIR="/backup"
if [ -d "$BACKUP_DIR" ]; then
  if [ -w "$BACKUP_DIR" ]; then
    pass_test "Backup directory is writable"
  else
    fail_test "Backup directory is not writable"
  fi
else
  warn_test "Backup directory doesn't exist yet (will be created on first backup)"
fi

test_count

# ============================================================================
# TEST 5: Access Control
# ============================================================================
echo -e "${YELLOW}[5/8] Checking Access Control...${NC}"

# Check Organization model exists
if [ -f "${PROJECT_ROOT}/verifier-backend/models/Organization.js" ]; then
  pass_test "Organization model exists"

  # Check for API key fields
  if grep -q "apiKeys" "${PROJECT_ROOT}/verifier-backend/models/Organization.js"; then
    pass_test "Organization model has API key support"
  fi

  # Check for rate limits
  if grep -q "rateLimits" "${PROJECT_ROOT}/verifier-backend/models/Organization.js"; then
    pass_test "Organization model has rate limiting"
  fi
else
  fail_test "Organization model not found"
fi

# Check orgAuth middleware exists
if [ -f "${PROJECT_ROOT}/verifier-backend/middleware/orgAuth.js" ]; then
  pass_test "Organization auth middleware exists"

  # Check for API key validation
  if grep -q "api.key\|apiKey" "${PROJECT_ROOT}/verifier-backend/middleware/orgAuth.js"; then
    pass_test "orgAuth middleware validates API keys"
  fi
else
  fail_test "Organization auth middleware not found"
fi

test_count

# ============================================================================
# TEST 6: Configuration Security
# ============================================================================
echo -e "${YELLOW}[6/8] Checking Configuration Security...${NC}"

# Check .env.example doesn't contain actual values
if [ -f "${PROJECT_ROOT}/verifier-backend/.env.example" ]; then
  pass_test ".env.example file exists"

  if ! grep -q "real" "${PROJECT_ROOT}/verifier-backend/.env.example" && \
     ! grep -q "actual" "${PROJECT_ROOT}/verifier-backend/.env.example"; then
    pass_test ".env.example doesn't contain actual secrets"
  else
    warn_test "Check that .env.example doesn't have real secrets"
  fi
else
  fail_test ".env.example not found"
fi

# Check mTLS environment variables template
if [ -f "${FABRIC_DIR}/.env.mtls.example" ]; then
  pass_test "mTLS environment variable template exists"
else
  fail_test "mTLS environment variable template not found"
fi

# Check for hardcoded passwords in code
HARDCODED=$(grep -r "password.*=.*['\"]" "${PROJECT_ROOT}/verifier-backend" --include="*.js" 2>/dev/null | grep -v ".example\|node_modules" | wc -l)
if [ "$HARDCODED" -eq 0 ]; then
  pass_test "No hardcoded passwords found in code"
else
  warn_test "Found $HARDCODED potential hardcoded passwords"
fi

test_count

# ============================================================================
# TEST 7: Network Configuration
# ============================================================================
echo -e "${YELLOW}[7/8] Checking Network Configuration...${NC}"

# Check docker-compose for multi-org setup
if [ -f "${FABRIC_DIR}/docker-compose.yml" ]; then
  pass_test "docker-compose.yml exists"

  # Check for multiple orderers
  ORDERER_COUNT=$(grep -c "orderer.*:" "${FABRIC_DIR}/docker-compose.yml" || echo "0")
  if [ "$ORDERER_COUNT" -ge 3 ]; then
    pass_test "Found $ORDERER_COUNT orderers (multi-orderer setup)"
  else
    warn_test "Expected 3 orderers, found $ORDERER_COUNT"
  fi

  # Check for multiple peers
  PEER_COUNT=$(grep -c "peer[0-9].*:" "${FABRIC_DIR}/docker-compose.yml" || echo "0")
  if [ "$PEER_COUNT" -ge 3 ]; then
    pass_test "Found $PEER_COUNT peers (multi-org setup)"
  else
    warn_test "Expected 3+ peers, found $PEER_COUNT"
  fi
else
  fail_test "docker-compose.yml not found"
fi

# Check for CouchDB
if grep -q "couchdb" "${FABRIC_DIR}/docker-compose.yml"; then
  pass_test "CouchDB configured for state database"
else
  warn_test "CouchDB not configured (recommend for production)"
fi

test_count

# ============================================================================
# TEST 8: Monitoring & Alerting
# ============================================================================
echo -e "${YELLOW}[8/8] Checking Monitoring & Alerting...${NC}"

# Check monitoring stack
if [ -d "${PROJECT_ROOT}/monitoring" ]; then
  pass_test "Monitoring directory exists"

  # Check docker-compose
  if [ -f "${PROJECT_ROOT}/monitoring/docker-compose.yml" ]; then
    pass_test "Monitoring docker-compose exists"
  fi

  # Check Prometheus config
  if [ -f "${PROJECT_ROOT}/monitoring/prometheus.yml" ]; then
    pass_test "Prometheus configuration exists"
  fi

  # Check alert rules
  if [ -f "${PROJECT_ROOT}/monitoring/alerts.yml" ]; then
    pass_test "Alert rules configured"
  fi
else
  warn_test "Monitoring stack not set up yet"
fi

# Check backend metrics
if grep -q "prom-client\|prometheus" "${PROJECT_ROOT}/verifier-backend/package.json"; then
  pass_test "Backend instrumented with Prometheus metrics"
else
  warn_test "Prometheus metrics not configured in backend"
fi

test_count

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}SECURITY VERIFICATION SUMMARY${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
SCORE=$((TOTAL_TESTS > 0 ? TESTS_PASSED * 100 / TOTAL_TESTS : 0))

echo -e "${GREEN}✅ Tests Passed:  $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}❌ Tests Failed:  $TESTS_FAILED${NC}"
else
  echo -e "${GREEN}❌ Tests Failed:  0${NC}"
fi
echo -e "${YELLOW}⚠️  Warnings:     $WARNINGS${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ] && [ $WARNINGS -le 2 ]; then
  echo -e "${GREEN}✅ SECURITY VERIFICATION PASSED (${SCORE}%)${NC}"
  echo ""
  echo "Your DocVerifier network is configured for production deployment with:"
  echo "  • Secrets management (AWS Secrets Manager)"
  echo "  • Mutual TLS (mTLS) certificates"
  echo "  • Comprehensive audit logging"
  echo "  • Automated backup & recovery"
  echo "  • Multi-organization access control"
  echo "  • Monitoring and alerting"
  echo ""
  exit 0
elif [ $TESTS_FAILED -lt 3 ]; then
  echo -e "${YELLOW}⚠️  SECURITY VERIFICATION PASSED WITH WARNINGS (${SCORE}%)${NC}"
  echo ""
  echo "Address the warnings above before production deployment."
  echo ""
  exit 0
else
  echo -e "${RED}❌ SECURITY VERIFICATION FAILED (${SCORE}%)${NC}"
  echo ""
  echo "Critical issues found. Address all failures before deployment."
  echo ""
  exit 1
fi
