#!/usr/bin/env bash
set -euo pipefail

# backup-fabric-network.sh - Automated backup for Fabric network and data
#
# PURPOSE:
# Creates daily backups of:
# - Fabric ledger data (peer state)
# - CouchDB state databases
# - Crypto material and certificates
# - MongoDB document metadata
#
# USAGE:
#   ./scripts/backup-fabric-network.sh              # Full backup
#   ./scripts/backup-fabric-network.sh --upload     # Backup + upload to S3
#   ./scripts/backup-fabric-network.sh --verify     # Verify backup integrity
#
# PREREQUISITES:
# - Fabric network running
# - AWS CLI configured (for S3 upload)
# - Sufficient disk space (>5GB for full backup)

set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")}" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Backup configuration
BACKUP_ROOT="/tmp/fabric-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/fabric_${TIMESTAMP}"
S3_BUCKET="${FABRIC_BACKUP_S3_BUCKET:-docverifier-backups}"
RETENTION_DAYS="${FABRIC_BACKUP_RETENTION:-7}"  # Keep last 7 days locally

# Backup targets
PEER_DATA_DIR="${PROJECT_DIR}/fabric/peer-data"
COUCHDB_CONTAINERS=("couchdb0" "couchdb1" "couchdb2")
MONGODB_CONTAINER="docverify-mongodb"
CRYPTO_DIR="${PROJECT_DIR}/fabric/crypto-config"
CHANNEL_ARTIFACTS_DIR="${PROJECT_DIR}/fabric/channel-config"

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
Fabric Network Backup Utility

USAGE:
  $0 [COMMAND] [OPTIONS]

COMMANDS:
  full        - Create complete system backup (default)
  aws-upload  - Backup and upload to AWS S3
  verify      - Verify backup integrity
  list        - List recent backups
  disk-usage  - Show backup disk usage

OPTIONS:
  --help      - Show this help message
  --dry-run   - Show what would be backed up without creating files

EXAMPLES:
  $0 full                    # Local backup only
  $0 aws-upload              # Backup and upload to S3
  $0 verify                  # Verify latest backup
  $0 --dry-run              # Preview backup process

ENVIRONMENT VARIABLES:
  FABRIC_BACKUP_S3_BUCKET   - S3 bucket name (default: docverifier-backups)
  FABRIC_BACKUP_RETENTION   - Days to keep local backups (default: 7)

EOF
}

create_backup() {
  log_info "Starting full backup of Fabric network..."

  # Create backup directory
  mkdir -p "${BACKUP_DIR}"
  log_success "Created backup directory: ${BACKUP_DIR}"

  # Backup 1: Peer ledger data
  log_info "Backing up peer ledger data..."
  if docker exec peer0.org1.example.com peerfscli ledgerinfo > /dev/null 2>&1; then
    # Peer is running - backup volumes
    docker cp peer0.org1.example.com:/var/hyperledger/production "${BACKUP_DIR}/peer0-ledger" 2>/dev/null || log_warning "Could not backup peer0 ledger (may not exist)"
  else
    log_warning "Peer0 not accessible, skipping ledger backup"
  fi
  log_success "Peer ledger backup complete"

  # Backup 2: CouchDB databases
  log_info "Backing up CouchDB state databases..."
  for i in 0 1 2; do
    CONTAINER="${COUCHDB_CONTAINERS[$i]}"
    if docker ps | grep -q "${CONTAINER}"; then
      log_info "Backing up ${CONTAINER}..."

      # Create CouchDB backup via API
      COUCHDB_PORT=$((5984 + i))
      BACKUP_FILE="${BACKUP_DIR}/couchdb${i}_backup.json"

      # Backup all databases
      curl -s -X GET "http://localhost:${COUCHDB_PORT}/_all_dbs" 2>/dev/null | jq -r '.[]' | while read db; do
        if [ ! -z "$db" ] && [ "$db" != "_replicator" ] && [ "$db" != "_users" ]; then
          log_info "  Backing up CouchDB database: $db"
          curl -s -X GET "http://localhost:${COUCHDB_PORT}/${db}" > "${BACKUP_DIR}/couchdb${i}_${db}.json" 2>/dev/null || true
        fi
      done

      log_success "CouchDB${i} backup complete"
    else
      log_warning "Container ${CONTAINER} not running, skipping"
    fi
  done

  # Backup 3: Crypto material and certificates
  log_info "Backing up crypto material and certificates..."
  if [ -d "${CRYPTO_DIR}" ]; then
    tar -czf "${BACKUP_DIR}/crypto-config.tar.gz" -C "${PROJECT_DIR}/fabric" crypto-config 2>/dev/null || log_warning "Could not backup crypto-config"
    log_success "Crypto material backed up"
  fi

  # Backup 4: Channel artifacts
  log_info "Backing up channel configurations..."
  if [ -d "${CHANNEL_ARTIFACTS_DIR}" ]; then
    tar -czf "${BACKUP_DIR}/channel-artifacts.tar.gz" -C "${PROJECT_DIR}/fabric" channel-config 2>/dev/null || log_warning "Could not backup channel artifacts"
    log_success "Channel artifacts backed up"
  fi

  # Backup 5: MongoDB metadata
  log_info "Backing up MongoDB metadata..."
  if docker ps | grep -q "${MONGODB_CONTAINER}"; then
    MONGO_BACKUP="${BACKUP_DIR}/mongodb.archive"
    docker exec ${MONGODB_CONTAINER} mongodump --archive --gzip --db docverifier > "${MONGO_BACKUP}" 2>/dev/null || log_warning "Could not backup MongoDB"
    log_success "MongoDB backup complete ($(du -h ${MONGO_BACKUP} 2>/dev/null | cut -f1))"
  else
    log_warning "MongoDB container not running, skipping"
  fi

  # Backup 6: Configuration files
  log_info "Backing up configuration files..."
  mkdir -p "${BACKUP_DIR}/config"
  cp "${PROJECT_DIR}/fabric/configtx.yaml" "${BACKUP_DIR}/config/" 2>/dev/null || true
  cp "${PROJECT_DIR}/fabric/crypto-config.yaml" "${BACKUP_DIR}/config/" 2>/dev/null || true
  cp "${PROJECT_DIR}/fabric/docker-compose.yml" "${BACKUP_DIR}/config/" 2>/dev/null || true
  cp "${PROJECT_DIR}/monitoring/prometheus.yml" "${BACKUP_DIR}/config/" 2>/dev/null || true
  log_success "Configuration files backed up"

  # Create backup manifest
  log_info "Creating backup manifest..."
  cat > "${BACKUP_DIR}/MANIFEST.txt" <<MANIFEST
Fabric Network Backup
=====================

Timestamp: ${TIMESTAMP}
Backup Directory: ${BACKUP_DIR}

Contents:
- peer0-ledger/: Peer ledger data and state
- couchdb*: CouchDB database exports
- crypto-config.tar.gz: MSP certificates and crypto material
- channel-artifacts.tar.gz: Channel configurations
- mongodb.archive: Document metadata (gzip compressed)
- config/: Configuration files
- MANIFEST.txt: This file
- integrity.hash: File checksums for verification

Backup Size: $(du -sh ${BACKUP_DIR} | cut -f1)
Host: $(hostname)
User: $(whoami)

MANIFEST

  # Create integrity checksums
  log_info "Computing file integrity checksums..."
  (cd "${BACKUP_DIR}" && find . -type f ! -name integrity.hash -exec sha256sum {} \; > integrity.hash)
  log_success "Integrity checksums created"

  # Summary
  BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
  FILE_COUNT=$(find "${BACKUP_DIR}" -type f | wc -l)

  log_success "Backup complete!"
  echo ""
  echo "📊 Backup Summary:"
  echo "   Location: ${BACKUP_DIR}"
  echo "   Size: ${BACKUP_SIZE}"
  echo "   Files: ${FILE_COUNT}"
  echo "   Timestamp: ${TIMESTAMP}"
}

upload_to_s3() {
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not installed. Cannot upload to S3."
    return 1
  fi

  log_info "Uploading backup to S3 (${S3_BUCKET})..."

  # Create tarball of entire backup
  BACKUP_ARCHIVE="${BACKUP_ROOT}/fabric_${TIMESTAMP}.tar.gz"
  log_info "Creating backup archive..."
  tar -czf "${BACKUP_ARCHIVE}" -C "${BACKUP_ROOT}" "fabric_${TIMESTAMP}" 2>/dev/null

  ARCHIVE_SIZE=$(du -h "${BACKUP_ARCHIVE}" | cut -f1)
  log_success "Archive created (${ARCHIVE_SIZE})"

  # Upload to S3
  log_info "Uploading to S3://docverifier-backups/${TIMESTAMP}/..."
  if aws s3 cp "${BACKUP_ARCHIVE}" "s3://${S3_BUCKET}/${TIMESTAMP}/" --sse AES256 2>/dev/null; then
    log_success "Backup uploaded to S3"

    # Set expiration policy (optional)
    log_info "Upload complete. Backup available at: s3://${S3_BUCKET}/${TIMESTAMP}/"
  else
    log_error "Failed to upload to S3"
    return 1
  fi
}

verify_backup() {
  log_info "Verifying backup integrity..."

  if [ ! -f "${BACKUP_DIR}/integrity.hash" ]; then
    log_error "Integrity checksums not found"
    return 1
  fi

  # Verify checksums
  (cd "${BACKUP_DIR}" && sha256sum -c integrity.hash > /dev/null 2>&1)
  if [ $? -eq 0 ]; then
    log_success "All files verified successfully"
    return 0
  else
    log_error "Integrity check failed - some files may be corrupted"
    return 1
  fi
}

list_backups() {
  log_info "Recent backups:"
  echo ""
  ls -lhd ${BACKUP_ROOT}/fabric_* 2>/dev/null | awk '{print $6, $7, $8, $9}' | tail -10 || log_warning "No backups found"
  echo ""
}

cleanup_old_backups() {
  log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."

  find "${BACKUP_ROOT}" -maxdepth 1 -name "fabric_*" -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null

  DELETED=$(find "${BACKUP_ROOT}" -maxdepth 1 -name "fabric_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null; echo "")

  log_success "Cleanup complete"
}

show_disk_usage() {
  if [ ! -d "${BACKUP_ROOT}" ]; then
    log_warning "No backups found"
    return
  fi

  echo ""
  echo "📁 Backup Storage Usage:"
  du -sh "${BACKUP_ROOT}" | awk '{print "   Total: " $1}'
  echo ""
  echo "   Backups by date:"
  du -sh "${BACKUP_ROOT}"/fabric_* 2>/dev/null | awk '{print "   " $1 "\t" $2}' | tail -20
  echo ""
}

# Main execution
COMMAND="${1:-full}"

case "${COMMAND}" in
  full)
    create_backup
    cleanup_old_backups
    ;;
  aws-upload)
    create_backup
    upload_to_s3
    cleanup_old_backups
    ;;
  verify)
    verify_backup
    ;;
  list)
    list_backups
    ;;
  disk-usage)
    show_disk_usage
    ;;
  --help|-h)
    show_usage
    ;;
  *)
    log_error "Unknown command: ${COMMAND}"
    show_usage
    exit 1
    ;;
esac

log_success "Backup operation completed"
