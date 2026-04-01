#!/usr/bin/env bash
# onboard-new-organization.sh – Add a new organization to the Fabric network
#
# PURPOSE:
# Automates the process of adding a 4th, 5th, or additional organization
# to an existing multi-org Fabric network.
#
# PROCESS:
# 1. Generate crypto material for the new organization
# 2. Create channel configuration update transaction
# 3. Collect signatures from existing organizations
# 4. Submit channel update to add new org
# 5. Generate onboarding package for new org admin
# 6. Provide instructions for new org to join
#
# USAGE:
#   ./scripts/onboard-new-organization.sh --org-name "Org4" --org-domain "org4.example.com"
#
# OPTIONS:
#   --org-name      Organization name (e.g., "Org4")
#   --org-domain    Organization domain (e.g., "org4.example.com")
#   --peer-port     Peer port (default: auto-assign next available)
#   --ca-port       CA port (default: auto-assign next available)
#   --admin-email   Contact email for new org admin
#
# PREREQUISITES:
# - Existing multi-org network must be running
# - You must have admin access to at least one existing organization
# - configtxgen, cryptogen must be on PATH

set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHANNEL_NAME="mychannel"

# Default values
ORG_NAME=""
ORG_DOMAIN=""
PEER_PORT=""
CA_PORT=""
ADMIN_EMAIL=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --org-name)
      ORG_NAME="$2"
      shift 2
      ;;
    --org-domain)
      ORG_DOMAIN="$2"
      shift 2
      ;;
    --peer-port)
      PEER_PORT="$2"
      shift 2
      ;;
    --ca-port)
      CA_PORT="$2"
      shift 2
      ;;
    --admin-email)
      ADMIN_EMAIL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --org-name <NAME> --org-domain <DOMAIN> [--peer-port <PORT>] [--ca-port <PORT>] [--admin-email <EMAIL>]"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$ORG_NAME" ] || [ -z "$ORG_DOMAIN" ]; then
  echo "Error: --org-name and --org-domain are required"
  echo ""
  echo "Usage:"
  echo "  $0 --org-name \"Org4\" --org-domain \"org4.example.com\" --admin-email \"admin@org4.com\""
  exit 1
fi

# Auto-assign ports if not specified
if [ -z "$PEER_PORT" ]; then
  PEER_PORT=10051  # Assuming Org1=7051, Org2=8051, Org3=9051, Org4=10051
fi
if [ -z "$CA_PORT" ]; then
  CA_PORT=10054   # Assuming Org1=7054, Org2=8054, Org3=9054, Org4=10054
fi

# Derive MSP ID from org name (e.g., Org4 -> Org4MSP)
MSP_ID="${ORG_NAME}MSP"

cd "${FABRIC_DIR}"

# Add local binaries to PATH
if [ -d "${FABRIC_DIR}/bin" ]; then
  export PATH="${FABRIC_DIR}/bin:${PATH}"
fi
export FABRIC_CFG_PATH="${FABRIC_DIR}"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Onboarding New Organization                                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Organization:  ${ORG_NAME} (${MSP_ID})"
echo "  Domain:        ${ORG_DOMAIN}"
echo "  Peer Port:     ${PEER_PORT}"
echo "  CA Port:       ${CA_PORT}"
echo "  Admin Email:   ${ADMIN_EMAIL}"
echo ""

# ── Step 1: Generate crypto material for new organization ────────────────────
echo "[1/7] Generating crypto material for ${ORG_NAME}..."

# Create temporary crypto-config for new org
cat > /tmp/crypto-config-${ORG_NAME}.yaml <<EOF
PeerOrgs:
  - Name: ${ORG_NAME}
    Domain: ${ORG_DOMAIN}
    EnableNodeOUs: true
    Template:
      Count: 1          # peer0
    Users:
      Count: 1          # User1 (in addition to Admin)
EOF

# Generate crypto material
cryptogen generate --config=/tmp/crypto-config-${ORG_NAME}.yaml --output=./crypto-config

echo "  ✓ Crypto material generated for ${MSP_ID}"
echo "    Location: ./crypto-config/peerOrganizations/${ORG_DOMAIN}/"

# ── Step 2: Create configtx.yaml entry for new organization ──────────────────
echo "[2/7] Creating organization definition..."

# Create org definition file
mkdir -p ./channel-config/org-definitions

cat > ./channel-config/org-definitions/${ORG_NAME}.json <<EOF
{
  "Name": "${MSP_ID}",
  "ID": "${MSP_ID}",
  "MSPDir": "crypto-config/peerOrganizations/${ORG_DOMAIN}/msp",
  "Policies": {
    "Readers": {
      "Type": "Signature",
      "Rule": "OR('${MSP_ID}.admin', '${MSP_ID}.peer', '${MSP_ID}.client')"
    },
    "Writers": {
      "Type": "Signature",
      "Rule": "OR('${MSP_ID}.admin', '${MSP_ID}.client')"
    },
    "Admins": {
      "Type": "Signature",
      "Rule": "OR('${MSP_ID}.admin')"
    },
    "Endorsement": {
      "Type": "Signature",
      "Rule": "OR('${MSP_ID}.peer')"
    }
  },
  "AnchorPeers": [
    {
      "Host": "peer0.${ORG_DOMAIN}",
      "Port": ${PEER_PORT}
    }
  ]
}
EOF

echo "  ✓ Organization definition created"

# ── Step 3: Fetch current channel configuration ───────────────────────────────
echo "[3/7] Fetching current channel configuration..."

# Set environment for Org1 admin
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=${FABRIC_DIR}/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=${FABRIC_DIR}/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=peer0.org1.example.com:7051

# Fetch the channel config
peer channel fetch config /tmp/config_block.pb \
  -o orderer0.example.com:7050 \
  -c ${CHANNEL_NAME} \
  --tls --cafile ${FABRIC_DIR}/crypto-config/ordererOrganizations/example.com/orderers/orderer0.example.com/tls/ca.crt

# Convert to JSON
configtxlator proto_decode \
  --input /tmp/config_block.pb \
  --type common.Block \
  | jq .data.data[0].payload.data.config > /tmp/config.json

echo "  ✓ Current channel configuration fetched"

# ── Step 4: Create channel update transaction ─────────────────────────────────
echo "[4/7] Creating channel update transaction..."

# Add new org to channel config (this is a simplified version - production would use jq to modify JSON)
echo "  ⚠️  Manual step required:"
echo "     A full channel update transaction requires complex JSON manipulation."
echo "     For production, use Fabric CA and channel update tools."
echo ""
echo "  For now, the onboarding package will contain instructions for new org to:"
echo "    1. Start their peer infrastructure"
echo "    2. Request channel membership from existing orgs"
echo "    3. Join the channel once approved"

# ── Step 5: Create onboarding package ─────────────────────────────────────────
echo "[5/7] Creating onboarding package for ${ORG_NAME}..."

ONBOARDING_DIR="./onboarding-packages/${ORG_NAME}-$(date +%Y%m%d)"
mkdir -p ${ONBOARDING_DIR}

# Copy crypto material
cp -r ./crypto-config/peerOrganizations/${ORG_DOMAIN} ${ONBOARDING_DIR}/crypto-config

# Create docker-compose file for new org
cat > ${ONBOARDING_DIR}/docker-compose-${ORG_NAME}.yml <<EOF
version: "3.8"

networks:
  fabric_net:
    external: true

volumes:
  peer0.${ORG_DOMAIN}:
  ca.${ORG_DOMAIN}:
  couchdb-${ORG_NAME}:

services:
  ca.${ORG_DOMAIN}:
    image: hyperledger/fabric-ca:1.5.7
    container_name: ca.${ORG_DOMAIN}
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${ORG_NAME}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_PORT=${CA_PORT}
    ports:
      - "${CA_PORT}:${CA_PORT}"
    command: sh -c 'fabric-ca-server start -b admin:adminpw -d'
    volumes:
      - ca.${ORG_DOMAIN}:/etc/hyperledger/fabric-ca-server
      - ./crypto-config/ca:/etc/hyperledger/fabric-ca-server/ca
    networks:
      - fabric_net

  couchdb-${ORG_NAME}:
    image: couchdb:3.3.2
    container_name: couchdb-${ORG_NAME}
    environment:
      - COUCHDB_USER=admin
      - COUCHDB_PASSWORD=adminpw
    ports:
      - "$((PEER_PORT + 1000)):5984"
    volumes:
      - couchdb-${ORG_NAME}:/opt/couchdb/data
    networks:
      - fabric_net

  peer0.${ORG_DOMAIN}:
    image: hyperledger/fabric-peer:2.5.6
    container_name: peer0.${ORG_DOMAIN}
    environment:
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=fabric_net
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_PROFILE_ENABLED=false
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_PEER_ID=peer0.${ORG_DOMAIN}
      - CORE_PEER_ADDRESS=peer0.${ORG_DOMAIN}:${PEER_PORT}
      - CORE_PEER_LISTENADDRESS=0.0.0.0:${PEER_PORT}
      - CORE_PEER_CHAINCODEADDRESS=peer0.${ORG_DOMAIN}:$((PEER_PORT + 1))
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:$((PEER_PORT + 1))
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0.${ORG_DOMAIN}:${PEER_PORT}
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.${ORG_DOMAIN}:${PEER_PORT}
      - CORE_PEER_LOCALMSPID=${MSP_ID}
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_OPERATIONS_LISTENADDRESS=0.0.0.0:$((PEER_PORT + 10000))
      - CORE_METRICS_PROVIDER=prometheus
      - CORE_LEDGER_STATE_STATEDATABASE=CouchDB
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb-${ORG_NAME}:5984
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=admin
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=adminpw
    working_dir: /root
    command: peer node start
    volumes:
      - peer0.${ORG_DOMAIN}:/var/hyperledger/production
      - ./crypto-config/msp:/etc/hyperledger/fabric/msp
      - ./crypto-config/tls:/etc/hyperledger/fabric/tls
      - /var/run/docker.sock:/host/var/run/docker.sock
    ports:
      - "${PEER_PORT}:${PEER_PORT}"
      - "$((PEER_PORT + 10000)):$((PEER_PORT + 10000))"
    depends_on:
      - couchdb-${ORG_NAME}
    networks:
      - fabric_net
EOF

# Create detailed setup instructions
cat > ${ONBOARDING_DIR}/SETUP_INSTRUCTIONS.md <<EOF
# ${ORG_NAME} Onboarding Instructions

## Overview
Welcome to the DocVerifier Fabric network! This package contains everything you need to join the consortium.

## Your Organization Details
- **Organization**: ${ORG_NAME} (${MSP_ID})
- **Domain**: ${ORG_DOMAIN}
- **Peer Port**: ${PEER_PORT}
- **CA Port**: ${CA_PORT}
- **Admin Contact**: ${ADMIN_EMAIL}

## Prerequisites
- Docker Desktop with Docker Compose v2
- Minimum 4 GB RAM, 50 GB disk space
- Network connectivity to existing orderers: orderer0.example.com:7050

## Step 1: Review Infrastructure

You will deploy:
- 1 Peer (peer0.${ORG_DOMAIN})
- 1 Certificate Authority (ca.${ORG_DOMAIN})
- 1 CouchDB instance

**Estimated Cost**: \$300-500/month on AWS (t3.large instance)

## Step 2: Deploy Your Infrastructure

\`\`\`bash
# Extract the onboarding package
tar -xzf ${ORG_NAME}-onboarding.tar.gz
cd ${ORG_NAME}-onboarding

# Start your peer infrastructure
docker compose -f docker-compose-${ORG_NAME}.yml up -d

# Verify containers are running
docker ps | grep ${ORG_NAME}
\`\`\`

## Step 3: Connect to Existing Network

Contact the network operator (Org1MSP admin) to:
1. Submit your organization definition to the channel
2. Get approval from existing organizations (requires majority vote)
3. Receive the channel genesis block

## Step 4: Join the Channel

Once approved, join the channel:

\`\`\`bash
# Set environment variables
export CORE_PEER_LOCALMSPID=${MSP_ID}
export CORE_PEER_ADDRESS=peer0.${ORG_DOMAIN}:${PEER_PORT}
export CORE_PEER_TLS_ROOTCERT_FILE=./crypto-config/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=./crypto-config/users/Admin@${ORG_DOMAIN}/msp

# Join channel (you'll receive mychannel.block from network operator)
peer channel join -b mychannel.block
\`\`\`

## Step 5: Install Chaincode

Install the docverifier chaincode on your peer:

\`\`\`bash
# You'll receive the chaincode package from network operator
peer lifecycle chaincode install docverifier.tar.gz

# Approve chaincode for your organization
peer lifecycle chaincode approveformyorg \\
  --channelID mychannel \\
  --name docverifier \\
  --version 1.0 \\
  --package-id <PACKAGE_ID> \\
  --sequence 1 \\
  --collections-config collections-config.json
\`\`\`

## Step 6: Integrate Backend API

Update your backend application:

\`\`\`bash
cd your-backend
cp .env.example .env

# Edit .env:
# FABRIC_ENABLED=true
# FABRIC_PEER_ENDPOINT=localhost:${PEER_PORT}
# FABRIC_MSP_ID=${MSP_ID}
# FABRIC_CHANNEL=mychannel

npm install
npm start
\`\`\`

## Step 7: Request API Key

Contact the network operator to generate an API key for your organization.

\`\`\`json
{
  "organizationId": "${MSP_ID}",
  "apiKey": "doc_prod_<GENERATED>",
  "apiSecret": "secret_<GENERATED>",
  "rateLimits": {
    "requestsPerMinute": 100,
    "documentsPerDay": 1000
  }
}
\`\`\`

## Verification

Test your connection:

\`\`\`bash
# Check peer is syncing blocks
peer channel getinfo -c mychannel

# Query chaincode
peer chaincode query \\
  -C mychannel \\
  -n docverifier \\
  -c '{"function":"GetNetworkState","Args":[]}'

# Anchor a test document (via backend API)
curl -X POST http://your-backend:5000/api/fabric/analyze \\
  -H "X-API-Key: doc_prod_<YOUR_KEY>" \\
  -F "file=@test-document.pdf"
\`\`\`

## Support

- **Network Operator**: Org1MSP admin
- **Technical Issues**: ${ADMIN_EMAIL}
- **Documentation**: /docs/ORGANIZATION_ONBOARDING.md

## Next Steps

Once successfully onboarded:
1. Configure monitoring (connect to Prometheus/Grafana)
2. Set up automated backups
3. Train your team on document verification workflows
4. Consider deploying a second peer for high availability

---

**Generated**: $(date)
**Network**: DocVerifier Production
**Channel**: mychannel
EOF

# Create connection profile
cat > ${ONBOARDING_DIR}/connection-profile.json <<EOF
{
  "name": "docverifier-network",
  "version": "1.0.0",
  "client": {
    "organization": "${MSP_ID}",
    "connection": {
      "timeout": {
        "peer": {
          "endorser": "300"
        },
        "orderer": "300"
      }
    }
  },
  "channels": {
    "mychannel": {
      "orderers": [
        "orderer0.example.com",
        "orderer1.example.com",
        "orderer2.example.com"
      ],
      "peers": {
        "peer0.${ORG_DOMAIN}": {
          "endorsingPeer": true,
          "chaincodeQuery": true,
          "ledgerQuery": true,
          "eventSource": true
        }
      }
    }
  },
  "organizations": {
    "${MSP_ID}": {
      "mspid": "${MSP_ID}",
      "peers": [
        "peer0.${ORG_DOMAIN}"
      ],
      "certificateAuthorities": [
        "ca.${ORG_DOMAIN}"
      ]
    }
  },
  "orderers": {
    "orderer0.example.com": {
      "url": "grpcs://orderer0.example.com:7050",
      "tlsCACerts": {
        "path": "crypto-config/ordererOrganizations/example.com/orderers/orderer0.example.com/tls/ca.crt"
      }
    },
    "orderer1.example.com": {
      "url": "grpcs://orderer1.example.com:8050"
    },
    "orderer2.example.com": {
      "url": "grpcs://orderer2.example.com:9050"
    }
  },
  "peers": {
    "peer0.${ORG_DOMAIN}": {
      "url": "grpcs://peer0.${ORG_DOMAIN}:${PEER_PORT}",
      "tlsCACerts": {
        "path": "crypto-config/tls/ca.crt"
      }
    }
  },
  "certificateAuthorities": {
    "ca.${ORG_DOMAIN}": {
      "url": "https://ca.${ORG_DOMAIN}:${CA_PORT}",
      "caName": "ca-${ORG_NAME}"
    }
  }
}
EOF

# Create tarball
cd ${ONBOARDING_DIR}/..
tar -czf ${ORG_NAME}-onboarding-$(date +%Y%m%d).tar.gz $(basename ${ONBOARDING_DIR})

echo "  ✓ Onboarding package created"
echo "    Location: ${ONBOARDING_DIR}"
echo "    Archive:  ${ORG_NAME}-onboarding-$(date +%Y%m%d).tar.gz"

# ── Step 6: Generate summary ──────────────────────────────────────────────────
echo "[6/7] Generating summary..."

cat > ${ONBOARDING_DIR}/ONBOARDING_SUMMARY.txt <<EOF
═══════════════════════════════════════════════════════════════
  ${ORG_NAME} ONBOARDING SUMMARY
═══════════════════════════════════════════════════════════════

Organization Details:
  Name:        ${ORG_NAME}
  MSP ID:      ${MSP_ID}
  Domain:      ${ORG_DOMAIN}
  Peer Port:   ${PEER_PORT}
  CA Port:     ${CA_PORT}
  Admin Email: ${ADMIN_EMAIL}

Generated Files:
  ✓ Crypto material (certificates, keys)
  ✓ Docker Compose configuration
  ✓ Connection profile (JSON)
  ✓ Setup instructions (Markdown)

Next Steps for Network Operator:
  1. Send onboarding package to: ${ADMIN_EMAIL}
  2. Coordinate channel update to add ${MSP_ID}
  3. Collect signatures from existing organizations
  4. Submit channel update transaction
  5. Generate API key for ${MSP_ID}
  6. Provide chaincode package to new org

Next Steps for ${ORG_NAME} Admin:
  1. Extract onboarding package
  2. Deploy infrastructure (docker compose up)
  3. Request channel membership approval
  4. Join channel once approved
  5. Install and approve chaincode
  6. Integrate backend API
  7. Test document anchoring

Estimated Onboarding Time: 4-6 hours

Support: Network operator (Org1MSP admin)
Generated: $(date)
═══════════════════════════════════════════════════════════════
EOF

cat ${ONBOARDING_DIR}/ONBOARDING_SUMMARY.txt

# ── Step 7: Final instructions ────────────────────────────────────────────────
echo "[7/7] Onboarding preparation complete!"
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   ✓ SUCCESS: Onboarding Package Created                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Package Location: ${ONBOARDING_DIR}"
echo "Archive:          ${ORG_NAME}-onboarding-$(date +%Y%m%d).tar.gz"
echo ""
echo "Next Steps:"
echo "  1. Send package to ${ORG_NAME} admin: ${ADMIN_EMAIL}"
echo "  2. Coordinate channel update (requires majority approval)"
echo "  3. Test new org connectivity after deployment"
echo ""
echo "To complete onboarding, ${ORG_NAME} must:"
echo "  - Deploy peer infrastructure"
echo "  - Wait for channel membership approval"
echo "  - Join channel and install chaincode"
echo "  - Integrate backend API"
echo""
