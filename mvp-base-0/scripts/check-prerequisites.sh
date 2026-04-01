#!/usr/bin/env bash
# check-prerequisites.sh - Validate environment for DocVerifier Fabric implementation
#
# Checks all required tools, versions, ports, and resources before setup.
# Run from project root: ./scripts/check-prerequisites.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
CHECKMARK="${GREEN}✓${NC}"
CROSSMARK="${RED}✗${NC}"
WARNING="${YELLOW}⚠${NC}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# ── Helper functions ─────────────────────────────────────────────────────────

check_pass() {
  echo -e "${CHECKMARK} $1"
  PASSED=$((PASSED + 1))
}

check_fail() {
  echo -e "${CROSSMARK} $1"
  FAILED=$((FAILED + 1))
}

check_warn() {
  echo -e "${WARNING} $1"
  WARNINGS=$((WARNINGS + 1))
}

version_gte() {
  # Compare versions (returns 0 if $1 >= $2)
  printf '%s\n%s' "$2" "$1" | sort -V -C
}

check_port() {
  local port=$1
  if command -v lsof &> /dev/null; then
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
      return 1  # Port is in use
    fi
  elif command -v netstat &> /dev/null; then
    if netstat -an | grep -q ":$port.*LISTEN"; then
      return 1  # Port is in use
    fi
  else
    # Can't check, assume available
    return 0
  fi
  return 0  # Port is available
}

# ── ASCII Header ─────────────────────────────────────────────────────────────

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   DocVerifier Prerequisites Check                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ── 1. Docker checks ─────────────────────────────────────────────────────────

echo "[Docker]"

if command -v docker &> /dev/null; then
  DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if version_gte "$DOCKER_VERSION" "20.10.0"; then
    check_pass "Docker              : v$DOCKER_VERSION (OK)"
  else
    check_fail "Docker              : v$DOCKER_VERSION (need 20.10.0+)"
  fi
else
  check_fail "Docker              : Not found"
fi

if command -v docker &> /dev/null; then
  if docker info &> /dev/null; then
    check_pass "Docker Daemon       : Running"
  else
    check_fail "Docker Daemon       : Not running (start Docker Desktop)"
  fi
else
  check_fail "Docker Daemon       : Cannot check (Docker not found)"
fi

if docker compose version &> /dev/null 2>&1; then
  COMPOSE_VERSION=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  check_pass "Docker Compose      : v$COMPOSE_VERSION (v2 detected)"
elif command -v docker-compose &> /dev/null; then
  COMPOSE_VERSION=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  check_warn "Docker Compose      : v$COMPOSE_VERSION (v1 detected, v2 recommended)"
else
  check_fail "Docker Compose      : Not found"
fi

echo ""

# ── 2. Node.js and npm ───────────────────────────────────────────────────────

echo "[Node.js]"

if command -v node &> /dev/null; then
  NODE_VERSION=$(node --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 16 ]; then
    check_pass "Node.js             : v$NODE_VERSION (OK)"
  else
    check_fail "Node.js             : v$NODE_VERSION (need v16.0.0+)"
  fi
else
  check_fail "Node.js             : Not found"
fi

if command -v npm &> /dev/null; then
  NPM_VERSION=$(npm --version)
  check_pass "npm                 : v$NPM_VERSION (OK)"
else
  check_fail "npm                 : Not found"
fi

echo ""

# ── 3. Go (for chaincode tests) ──────────────────────────────────────────────

echo "[Go]"

if command -v go &> /dev/null; then
  GO_VERSION=$(go version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  GO_MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
  GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)

  if [ "$GO_MAJOR" -gt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -ge 21 ]); then
    check_pass "Go                  : v$GO_VERSION (OK)"
  else
    check_fail "Go                  : v$GO_VERSION (need v1.21.0+)"
  fi

  if [ -n "${GOPATH:-}" ]; then
    check_pass "GOPATH              : $GOPATH (set)"
  else
    check_warn "GOPATH              : Not set (Go will use default)"
  fi
else
  check_fail "Go                  : Not found (needed for chaincode tests)"
fi

echo ""

# ── 4. Python (for native dependencies) ──────────────────────────────────────

echo "[Python]"

if command -v python3 &> /dev/null; then
  PYTHON_VERSION=$(python3 --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  check_pass "Python              : v$PYTHON_VERSION (OK)"
elif command -v python &> /dev/null; then
  PYTHON_VERSION=$(python --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  check_pass "Python              : v$PYTHON_VERSION (OK)"
else
  check_warn "Python              : Not found (may affect native npm modules)"
fi

echo ""

# ── 5. Hyperledger Fabric binaries ───────────────────────────────────────────

echo "[Hyperledger Fabric Binaries]"

FABRIC_BIN_DIR="./fabric/bin"
FOUND_IN_PATH=false
FOUND_IN_LOCAL=false

# Check if binaries are in PATH
if command -v cryptogen &> /dev/null; then
  FOUND_IN_PATH=true
fi

# Check if binaries are in fabric/bin/
if [ -f "$FABRIC_BIN_DIR/cryptogen" ]; then
  FOUND_IN_LOCAL=true
fi

if $FOUND_IN_PATH; then
  CRYPTOGEN_VERSION=$(cryptogen version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  check_pass "cryptogen           : $CRYPTOGEN_VERSION (found in PATH)"

  if command -v configtxgen &> /dev/null; then
    check_pass "configtxgen         : Found in PATH"
  else
    check_fail "configtxgen         : Not found"
  fi

  if command -v peer &> /dev/null; then
    check_pass "peer                : Found in PATH"
  else
    check_fail "peer                : Not found"
  fi

  if command -v osnadmin &> /dev/null; then
    check_pass "osnadmin            : Found in PATH"
  else
    check_fail "osnadmin            : Not found (Fabric 2.5+ required)"
  fi

elif $FOUND_IN_LOCAL; then
  check_pass "Fabric binaries     : Found in $FABRIC_BIN_DIR"
  check_warn "Fabric binaries     : Not in PATH (start-network.sh will use local bin/)"
else
  check_fail "Fabric binaries     : Not found (install with bootstrap script)"
  echo ""
  echo "  Download via:"
  echo "  cd fabric && curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh | bash -s -- binary 2.5.6"
fi

echo ""

# ── 6. Port availability ─────────────────────────────────────────────────────

echo "[Port Availability]"

PORTS=(7050 7051 7053 7054 5000 3000 27017)
PORT_NAMES=("Orderer" "Peer" "Peer Events" "CA" "Backend API" "Frontend" "MongoDB")

for i in "${!PORTS[@]}"; do
  PORT=${PORTS[$i]}
  NAME=${PORT_NAMES[$i]}

  if check_port $PORT; then
    check_pass "Port $PORT          : Available ($NAME)"
  else
    check_warn "Port $PORT          : In use ($NAME may conflict)"
  fi
done

echo ""

# ── 7. System resources ──────────────────────────────────────────────────────

echo "[System Resources]"

# RAM check (platform-specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
  TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
else
  # Windows or other
  TOTAL_RAM_GB=0
fi

if [ "$TOTAL_RAM_GB" -ge 4 ]; then
  check_pass "RAM                 : ${TOTAL_RAM_GB}GB available (OK)"
elif [ "$TOTAL_RAM_GB" -gt 0 ]; then
  check_warn "RAM                 : ${TOTAL_RAM_GB}GB available (4GB recommended)"
else
  check_warn "RAM                 : Cannot determine (ensure 4GB+ available)"
fi

# Disk space check
if command -v df &> /dev/null; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    DISK_AVAIL_GB=$(df -g . | tail -1 | awk '{print $4}')
  else
    DISK_AVAIL_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
  fi

  if [ "$DISK_AVAIL_GB" -ge 10 ]; then
    check_pass "Disk Space          : ${DISK_AVAIL_GB}GB available (OK)"
  else
    check_warn "Disk Space          : ${DISK_AVAIL_GB}GB available (10GB recommended)"
  fi
else
  check_warn "Disk Space          : Cannot check"
fi

echo ""

# ── 8. MongoDB (optional check) ──────────────────────────────────────────────

echo "[MongoDB]"

if command -v mongod &> /dev/null; then
  check_pass "MongoDB             : Installed locally"
elif docker ps --filter "name=mongodb" --filter "status=running" &> /dev/null 2>&1; then
  if docker ps --filter "name=mongodb" --filter "status=running" | grep -q mongodb; then
    check_pass "MongoDB             : Running in Docker"
  else
    check_warn "MongoDB             : Docker container exists but not running"
  fi
else
  check_warn "MongoDB             : Not detected (use Atlas or start container)"
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Summary                                                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${RED}Failed:${NC}   $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}✓ All critical prerequisites met. Ready to proceed!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Install Node dependencies:"
  echo "     cd verifier-backend && npm install"
  echo "     cd ../verifier-client && npm install"
  echo ""
  echo "  2. Start Fabric network:"
  echo "     cd fabric && ./scripts/start-network.sh"
  echo ""
  echo "  3. Configure environment:"
  echo "     cp verifier-backend/.env.example verifier-backend/.env"
  echo "     # Edit .env with your values"
  echo ""
  echo "  4. Start backend:"
  echo "     cd verifier-backend && npm run dev"
  echo ""
  echo "  5. Start frontend:"
  echo "     cd verifier-client && npm start"
  echo ""

  if ! $FOUND_IN_PATH && ! $FOUND_IN_LOCAL; then
    echo "  Optional: Install Fabric binaries:"
    echo "     cd fabric"
    echo "     curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh | bash -s -- binary 2.5.6"
    echo ""
  fi

  exit 0
else
  echo -e "${RED}✗ Some prerequisites are missing. Please address the failed checks above.${NC}"
  echo ""
  echo "Common fixes:"
  echo "  - Docker: Install Docker Desktop from https://www.docker.com/products/docker-desktop"
  echo "  - Node.js: Install from https://nodejs.org/ (LTS version)"
  echo "  - Go: Install from https://go.dev/dl/"
  echo "  - Fabric binaries: Run bootstrap script in fabric/ directory"
  echo ""
  exit 1
fi
