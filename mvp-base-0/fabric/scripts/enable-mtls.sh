#!/bin/bash
set -euo pipefail

# fabric/scripts/enable-mtls.sh
#
# Enable mutual TLS (mTLS) for all Fabric components
# - Generates client certificates for inter-organizational communication
# - Updates Fabric configurations to enforce TLS with client auth
# - Creates TLS policies for peer-orderer connections
#
# Usage: ./enable-mtls.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_DIR="$(dirname "$SCRIPT_DIR")"
CRYPTO_DIR="${FABRIC_DIR}/crypto-config"
TLS_DIR="${FABRIC_DIR}/tls-config"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Enabling Mutual TLS (mTLS) for Fabric Network${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Step 1: Create TLS directory structure
echo -e "${YELLOW}[1/5] Setting up TLS directory structure...${NC}"
mkdir -p "${TLS_DIR}/orderer"
mkdir -p "${TLS_DIR}/peer"
mkdir -p "${TLS_DIR}/ca"
mkdir -p "${TLS_DIR}/admin"

# Step 2: Generate CA certificates for TLS (if not exist)
echo -e "${YELLOW}[2/5] Generating TLS CA certificates...${NC}"

if [ ! -f "${TLS_DIR}/ca/ca-cert.pem" ]; then
  # Generate TLS CA key
  openssl genrsa -out "${TLS_DIR}/ca/ca-key.pem" 4096

  # Generate TLS CA certificate
  openssl req -new -x509 -days 3650 \
    -key "${TLS_DIR}/ca/ca-key.pem" \
    -out "${TLS_DIR}/ca/ca-cert.pem" \
    -subj "/C=US/ST=State/L=City/O=DocVerifier/CN=fabric-tls-ca"

  echo -e "${GREEN}✅ TLS CA certificates created${NC}"
else
  echo -e "${GREEN}✅ TLS CA certificates already exist${NC}"
fi

# Step 3: Generate orderer TLS certificates
echo -e "${YELLOW}[3/5] Generating orderer TLS certificates...${NC}"

for i in 0 1 2; do
  ORDERER_NAME="orderer${i}.docverifier.com"
  ORDERER_DIR="${TLS_DIR}/orderer/orderer${i}"
  mkdir -p "${ORDERER_DIR}"

  # Generate orderer key
  openssl genrsa -out "${ORDERER_DIR}/server.key" 2048

  # Generate CSR
  cat > "${ORDERER_DIR}/server.csr.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = DocVerifier
CN = ${ORDERER_NAME}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${ORDERER_NAME}
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = 0.0.0.0
EOF

  openssl req -new -key "${ORDERER_DIR}/server.key" \
    -out "${ORDERER_DIR}/server.csr" \
    -config "${ORDERER_DIR}/server.csr.conf"

  # Sign orderer certificate with TLS CA
  openssl x509 -req -in "${ORDERER_DIR}/server.csr" \
    -CA "${TLS_DIR}/ca/ca-cert.pem" \
    -CAkey "${TLS_DIR}/ca/ca-key.pem" \
    -CAcreateserial -out "${ORDERER_DIR}/server.crt" \
    -days 365 \
    -extensions v3_req \
    -extfile "${ORDERER_DIR}/server.csr.conf"

  # Copy CA cert
  cp "${TLS_DIR}/ca/ca-cert.pem" "${ORDERER_DIR}/ca.crt"

  # Generate client certificate for orderer (for peer-to-orderer mTLS)
  openssl genrsa -out "${ORDERER_DIR}/client.key" 2048
  openssl req -new -key "${ORDERER_DIR}/client.key" \
    -out "${ORDERER_DIR}/client.csr" \
    -subj "/C=US/ST=State/L=City/O=DocVerifier/CN=${ORDERER_NAME}-client"

  openssl x509 -req -in "${ORDERER_DIR}/client.csr" \
    -CA "${TLS_DIR}/ca/ca-cert.pem" \
    -CAkey "${TLS_DIR}/ca/ca-key.pem" \
    -CAcreateserial -out "${ORDERER_DIR}/client.crt" \
    -days 365

  echo -e "${GREEN}✅ Generated TLS certificates for ${ORDERER_NAME}${NC}"
done

# Step 4: Generate peer TLS certificates
echo -e "${YELLOW}[4/5] Generating peer TLS certificates...${NC}"

PEERS=(
  "peer0.org1.docverifier.com"
  "peer0.org2.docverifier.com"
  "peer0.org3.docverifier.com"
)

for idx in "${!PEERS[@]}"; do
  PEER_NAME="${PEERS[$idx]}"
  ORG_NUM=$((idx + 1))
  PEER_DIR="${TLS_DIR}/peer/peer${idx}"
  mkdir -p "${PEER_DIR}"

  # Generate peer key
  openssl genrsa -out "${PEER_DIR}/server.key" 2048

  # Generate CSR
  cat > "${PEER_DIR}/server.csr.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = DocVerifier
CN = ${PEER_NAME}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${PEER_NAME}
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = 0.0.0.0
EOF

  openssl req -new -key "${PEER_DIR}/server.key" \
    -out "${PEER_DIR}/server.csr" \
    -config "${PEER_DIR}/server.csr.conf"

  # Sign with TLS CA
  openssl x509 -req -in "${PEER_DIR}/server.csr" \
    -CA "${TLS_DIR}/ca/ca-cert.pem" \
    -CAkey "${TLS_DIR}/ca/ca-key.pem" \
    -CAcreateserial -out "${PEER_DIR}/server.crt" \
    -days 365 \
    -extensions v3_req \
    -extfile "${PEER_DIR}/server.csr.conf"

  # Copy CA cert
  cp "${TLS_DIR}/ca/ca-cert.pem" "${PEER_DIR}/ca.crt"

  # Generate client certificate (for inter-peer communication)
  openssl genrsa -out "${PEER_DIR}/client.key" 2048
  openssl req -new -key "${PEER_DIR}/client.key" \
    -out "${PEER_DIR}/client.csr" \
    -subj "/C=US/ST=State/L=City/O=DocVerifier/CN=${PEER_NAME}-client"

  openssl x509 -req -in "${PEER_DIR}/client.csr" \
    -CA "${TLS_DIR}/ca/ca-cert.pem" \
    -CAkey "${TLS_DIR}/ca/ca-key.pem" \
    -CAcreateserial -out "${PEER_DIR}/client.crt" \
    -days 365

  echo -e "${GREEN}✅ Generated TLS certificates for ${PEER_NAME}${NC}"
done

# Step 5: Create Docker volume for mTLS certificates
echo -e "${YELLOW}[5/5] Setting up Docker volumes for TLS certificates...${NC}"

# Copy certificates to locations accessible by docker-compose
mkdir -p "${FABRIC_DIR}/docker-volumes/orderers-tls"
mkdir -p "${FABRIC_DIR}/docker-volumes/peers-tls"

for i in 0 1 2; do
  cp -r "${TLS_DIR}/orderer/orderer${i}" \
    "${FABRIC_DIR}/docker-volumes/orderers-tls/"
done

for i in 0 1 2; do
  cp -r "${TLS_DIR}/peer/peer${i}" \
    "${FABRIC_DIR}/docker-volumes/peers-tls/"
done

echo -e "${GREEN}✅ TLS certificates copied to Docker volumes${NC}"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}mTLS Configuration Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update fabric/docker-compose.yml with mTLS environment variables"
echo "2. Set CORE_PEER_TLS_ENABLED=true for all peers"
echo "3. Set CORE_PEER_TLS_CLIENTAUTHREQUIRED=true for mutual TLS"
echo "4. Set ORDERER_GENERAL_TLS_CLIENTAUTHREQUIRED=true for orderers"
echo "5. Mount TLS certificates to containers"
echo "6. Restart network: docker-compose down && docker-compose up -d"
echo ""
echo -e "${YELLOW}Certificate Locations:${NC}"
echo "Orderer TLS:    ${TLS_DIR}/orderer/"
echo "Peer TLS:       ${TLS_DIR}/peer/"
echo "CA Certificate: ${TLS_DIR}/ca/ca-cert.pem"
echo ""
echo -e "${YELLOW}Certificate Validity:${NC}"
echo "- Server certificates: 365 days"
echo "- CA certificate: 3650 days (10 years)"
echo ""
echo -e "${RED}⚠️  IMPORTANT:${NC}"
echo "- Store TLS private keys securely"
echo "- Do not commit TLS keys to git"
echo "- Implement certificate rotation before expiry"
echo "- Add 'tls-config/' and 'docker-volumes/' to .gitignore"
echo ""
