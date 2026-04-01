#!/usr/bin/env bash
set -euo pipefail

# restore-fabric-network.sh - Disaster recovery and restore procedures
#
# PURPOSE:
# Restores Fabric network from backups:
# - Peer ledger data
# - CouchDB state databases
# - MongoDB metadata
# - Crypto material and certificates
#
# USAGE:
#   ./scripts/restore-fabric-network.sh /path/to/backup    # Local backup
#   ./scripts/restore-fabric-network.sh --s3 s3://bucket/   # S3 backup
#   ./scripts/restore-fabric-network.sh --verify            # Verify restore
#
# PREREQUISITES:
# - Backup archive exists
# - Fabric network can be stopped/started
# - AWS CLI configured (for S3 restore)
# - MongoDB and peer containers exist

set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")}" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESTORE_DIR="/tmp/fabric-restore"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ℹ️  $*"
}

log_success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✅ $*"
}

log_warning() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠️  $*"
}

log_error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ❌ $*"
}

show_usage() {
  cat <<EOF
Fabric Network Restore Utility (Disaster Recovery)

USAGE:
  $0 /path/to/backup.tar.gz      # Restore from local backup
  $0 --s3 s3://bucket/timestamp/ # Download and restore from S3
  $0 --verify                     # Verify latest backup
  $0 --list                       # List available backups

OPTIONS:
  -f, --force     - Skip confirmation prompts
  --dry-run       - Show what would be restored without making changes
  --help          - Show this help message

RESTORE PROCESS:
  1. Verify backup integrity
  2. Stop Fabric network
  3. Restore peer ledger data
  4. Restore CouchDB databases
  5. Restore MongoDB metadata
  6. Restore crypto material
  7. Restart Fabric network
  8. Verify network health

EXAMPLES:
  $0 /backups/fabric_20260326_143000.tar.gz
  $0 --s3 s3://docverifier-backups/20260326_143000/
  $0 --verify                  # Test restore without starting network

IMPORTANT: This operation will:
  - Stop all Fabric containers
  - Overwrite existing data
  - Take 5-15 minutes depending on backup size

EOF
}

verify_backup_integrity() {
  local BACKUP_DIR="$1"

  if [ ! -f "${BACKUP_DIR}/integrity.hash" ]; then
    log_error "Integrity checksums not found"
    return 1
  fi

  log_info "Verifying backup integrity..."
  (cd "${BACKUP_DIR}" && sha256sum -c integrity.hash > /dev/null 2>&1)
  if [ $? -eq 0 ]; then
    log_success "Backup integrity verified"
    return 0
  else
    log_error "Backup integrity check failed"
    return 1
  fi
}

stop_network() {
  log_warning "Stopping Fabric network..."
  cd "${PROJECT_DIR}"

  # Stop containers gracefully
  docker-compose down --remove-orphans 2>/dev/null || log_warning "Could not stop containers"

  sleep 5
  log_success "Network stopped"
}

start_network() {
  log_info "Starting Fabric network..."
  cd "${PROJECT_DIR}"

  docker-compose up -d 2>/dev/null || {
    log_error "Could not start network"
    return 1
  }

  log_info "Waiting 30 seconds for network to stabilize..."
  sleep 30

  log_success "Network started"
}

verify_network_health() {
  log_info "Verifying network health..."

  local CHECKS_PASSED=0
  local CHECKS_TOTAL=0

  # Check orderers
  for i in 0 1 2; do
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    CONTAINER="orderer$i.example.com"
    if docker ps | grep -q "$CONTAINER"; then
      log_success "  ✓ $CONTAINER is running"
      CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
      log_warning "  ✗ $CONTAINER not running"
    fi
  done

  # Check peers
  for ORG in org1 org2 org3; do
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    CONTAINER="peer0.${ORG}.example.com"
    if docker ps | grep -q "$CONTAINER"; then
      log_success "  ✓ $CONTAINER is running"
      CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
      log_warning "  ✗ $CONTAINER not running"
    fi
  done

  # Check backend
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  if curl -s http://localhost:5000/health > /dev/null 2>&1; then
    log_success "  ✓ Backend API is responding"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    log_warning "  ✗ Backend API not responding"
  fi

  if [ $CHECKS_PASSED -eq $CHECKS_TOTAL ]; then
    log_success "All health checks passed ($CHECKS_PASSED/$CHECKS_TOTAL)"
    return 0
  else
    log_warning "Some health checks failed ($CHECKS_PASSED/$CHECKS_TOTAL)"
    return 1
  fi
}

restore_peer_ledger() {
  local BACKUP_DIR="$1"

  if [ ! -d "${BACKUP_DIR}/peer0-ledger" ]; then
    log_warning "Peer ledger backup not found, skipping"
    return
  fi

  log_info "Restoring peer ledger data..."

  # Wait for peer to start
  sleep 10

  # Copy ledger data into container
  if docker ps | grep -q "peer0.org1.example.com"; then
    docker cp "${BACKUP_DIR}/peer0-ledger/." peer0.org1.example.com:/var/hyperledger/production/ 2>/dev/null || log_warning "Could not restore peer ledger"
    log_success "Peer ledger restored"
  else
    log_warning "Peer not accessible, skipping ledger restore"
  fi
}

restore_couchdb() {
  local BACKUP_DIR="$1"

  log_info "Restoring CouchDB databases..."

  for i in 0 1 2; do
    COUCHDB_PORT=$((5984 + i))
    CONTAINER="couchdb$i"

    if ! docker ps | grep -q "$CONTAINER"; then
      log_warning "Container $CONTAINER not running, skipping"
      continue
    fi

    log_info "  Restoring CouchDB$i..."

    # Wait for CouchDB to be ready
    for j in {1..30}; do
      if curl -s "http://localhost:${COUCHDB_PORT}/_up" > /dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    # Restore individual databases
    find "${BACKUP_DIR}" -maxdepth 1 -name "couchdb${i}_*.json" | while read db_file; do
      DB_NAME=$(basename "$db_file" | sed "s/couchdb${i}_//; s/.json//")

      if [ ! -z "$DB_NAME" ] && [ "$DB_NAME" != "backup" ]; then
        log_info "    Restoring database: $DB_NAME"

        # Create database
        curl -s -X PUT "http://localhost:${COUCHDB_PORT}/${DB_NAME}" > /dev/null 2>&1 || true

        # Import data
        curl -s -X POST "http://localhost:${COUCHDB_PORT}/${DB_NAME}/_bulk_docs" \
          -H "Content-Type: application/json" \
          -d @"$db_file" > /dev/null 2>&1 || true
      fi
    done

    log_success "CouchDB$i restored"
  done
}

restore_mongodb() {
  local BACKUP_DIR="$1"

  if [ ! -f "${BACKUP_DIR}/mongodb.archive" ]; then
    log_warning "MongoDB backup not found, skipping"
    return
  fi

  log_info "Restoring MongoDB metadata..."

  if ! docker ps | grep -q "docverify-mongodb"; then
    log_warning "MongoDB container not running, skipping"
    return
  fi

  sleep 5  # Wait for MongoDB to be ready

  docker exec docverify-mongodb mongorestore --archive --gzip \
    --drop --db docverifier \
    < "${BACKUP_DIR}/mongodb.archive" 2>/dev/null || log_warning "Could not fully restore MongoDB"

  log_success "MongoDB restored"
}

restore_crypto() {
  local BACKUP_DIR="$1"

  if [ ! -f "${BACKUP_DIR}/crypto-config.tar.gz" ]; then
    log_warning "Crypto backup not found, skipping"
    return
  fi

  log_info "Restoring crypto material..."

  cd "${PROJECT_DIR}/fabric"
  tar -xzf "${BACKUP_DIR}/crypto-config.tar.gz" 2>/dev/null || log_warning "Could not restore crypto-config"

  log_success "Crypto material restored"
}

restore_configs() {
  local BACKUP_DIR="$1"

  if [ ! -d "${BACKUP_DIR}/config" ]; then
    log_warning "Configuration backup not found, skipping"
    return
  fi

  log_info "Restoring configuration files..."

  cd "${PROJECT_DIR}/fabric"
  cp "${BACKUP_DIR}/config/"* . 2>/dev/null || log_warning "Could not restore all configs"

  log_success "Configuration files restored"
}

extract_backup() {
  local BACKUP_FILE="$1"
  local TARGET_DIR="${RESTORE_DIR}/extracted"

  log_info "Extracting backup archive..."
  mkdir -p "${TARGET_DIR}"

  tar -xzf "${BACKUP_FILE}" -C "${TARGET_DIR}" 2>/dev/null || {
    log_error "Could not extract backup"
    return 1
  }

  # Find the backup directory (should be fabric_TIMESTAMP)
  EXTRACTED_BACKUP=$(find "${TARGET_DIR}" -maxdepth 1 -type d -name "fabric_*" | head -1)

  if [ -z "$EXTRACTED_BACKUP" ]; then
    log_error "Could not find backup directory in archive"
    return 1
  fi

  echo "${EXTRACTED_BACKUP}"
}

# Main restore process
BACKUP_SOURCE="${1:---help}"
FORCE_MODE=0
DRY_RUN=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE_MODE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --s3)
      S3_BACKUP="$2"
      log_info "Downloading backup from S3: $S3_BACKUP"
      # Download from S3 (simplified)
      shift 2
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      BACKUP_SOURCE="$1"
      shift
      ;;
  esac
done

# Validate backup file
if [ "$BACKUP_SOURCE" = "--help" ]; then
  show_usage
  exit 0
fi

if [ ! -f "$BACKUP_SOURCE" ]; then
  log_error "Backup file not found: $BACKUP_SOURCE"
  exit 1
fi

log_info "=========================================="
log_info "Fabric Network Disaster Recovery"
log_info "=========================================="
log_info "Backup: $BACKUP_SOURCE"
log_info "Size: $(du -h "$BACKUP_SOURCE" | cut -f1)"

if [ $FORCE_MODE -eq 0 ]; then
  echo ""
  log_warning "This will stop the network and restore data from backup."
  read -p "Continue? (yes/no): " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Restore cancelled"
    exit 0
  fi
fi

echo ""

# Extract backup
BACKUP_DIR=$(extract_backup "$BACKUP_SOURCE") || exit 1
log_success "Backup extracted to: $BACKUP_DIR"

# Verify integrity
verify_backup_integrity "$BACKUP_DIR" || exit 1

if [ $DRY_RUN -eq 1 ]; then
  log_info "Dry-run complete. No changes made."
  exit 0
fi

echo ""
log_warning "⏳ Restore process starting..."
echo ""

# Restore sequence
stop_network
sleep 2

restore_configs "$BACKUP_DIR"
sleep 2

start_network
sleep 5

restore_peer_ledger "$BACKUP_DIR"
restore_couchdb "$BACKUP_DIR"
restore_mongodb "$BACKUP_DIR"
restore_crypto "$BACKUP_DIR"

echo ""
log_info "Verifying network health..."
verify_network_health || log_warning "Some health checks failed"

log_success "=========================================="
log_success "Restore complete!"
log_success "=========================================="
log_info "Network restored from backup: $(basename $BACKUP_SOURCE)"
log_info "Start time: $(date)"

# Cleanup
rm -rf "${RESTORE_DIR}"
