/**
 * models/Organization.js
 * MongoDB schema for organizations in the DocVerifier network
 *
 * Stores:
 * - Organization metadata (name, MSP ID, domain)
 * - API keys for programmatic access (hashed for security)
 * - Rate limits per organization
 * - Status (active/suspended)
 */

const mongoose = require('mongoose');
const crypto = require('crypto');

const OrganizationSchema = new mongoose.Schema({
  // ── Organization Identity ──────────────────────────────────────────────────
  mspId: {
    type: String,
    required: true,
    unique: true,
    enum: ['Org1MSP', 'Org2MSP', 'Org3MSP', 'Org4MSP', 'Org5MSP'],
    description: 'Fabric MSP ID (e.g., Org2MSP)'
  },

  name: {
    type: String,
    required: true,
    description: 'Organization display name (e.g., "Partner University")'
  },

  domain: {
    type: String,
    required: true,
    description: 'Organization domain (e.g., org2.example.com)'
  },

  // ── Contact Information ────────────────────────────────────────────────────
  adminEmail: {
    type: String,
    description: 'Primary admin email for the organization'
  },

  // ── API Keys ───────────────────────────────────────────────────────────────
  apiKeys: [{
    // Public key handle (for identification)
    keyId: {
      type: String,
      required: true,
      unique: true,
      description: 'Key ID for reference (e.g., "doc_prod_aB3xYz...")'
    },

    // Hashed for security (never store plain)
    keyHash: {
      type: String,
      required: true,
      description: 'SHA-256 hash of the actual API key'
    },

    secretHash: {
      type: String,
      required: true,
      description: 'SHA-256 hash of the API secret'
    },

    // Metadata
    description: {
      type: String,
      default: '',
      description: 'Description of this API key (e.g., "Production backend")'
    },

    enabled: {
      type: Boolean,
      default: true,
      description: 'Whether this key is active'
    },

    createdAt: {
      type: Date,
      default: Date.now,
      description: 'When the key was created'
    },

    createdBy: {
      type: String,
      description: 'Admin who created this key'
    },

    revokedAt: {
      type: Date,
      description: 'When the key was revoked (if applicable)'
    },

    revokedBy: {
      type: String,
      description: 'Admin who revoked this key'
    },

    // Usage tracking
    lastUsedAt: {
      type: Date,
      description: 'Last time this key was used'
    },

    lastUsedIp: {
      type: String,
      description: 'IP address of last usage'
    },

    requestCount: {
      type: Number,
      default: 0,
      description: 'Total API requests using this key'
    }
  }],

  // ── Rate Limiting ──────────────────────────────────────────────────────────
  rateLimits: {
    requestsPerMinute: {
      type: Number,
      default: 100,
      description: 'Max API requests per minute'
    },

    documentsPerDay: {
      type: Number,
      default: 1000,
      description: 'Max documents that can be anchored per day'
    },

    documentsPerMonth: {
      type: Number,
      default: 10000,
      description: 'Max documents per month'
    }
  },

  // ── Usage Metrics (for monitoring) ─────────────────────────────────────────
  usage: {
    documentsAnchoredToday: {
      type: Number,
      default: 0,
      description: 'Documents anchored in current day'
    },

    documentsAnchoredThisMonth: {
      type: Number,
      default: 0,
      description: 'Documents anchored in current month'
    },

    lastAnchorAt: {
      type: Date,
      description: 'Timestamp of last document anchor'
    },

    totalDocumentsAnchored: {
      type: Number,
      default: 0,
      description: 'Lifetime documents anchored by this org'
    },

    totalApiRequests: {
      type: Number,
      default: 0,
      description: 'Lifetime API requests from this org'
    }
  },

  // ── Status & Permissions ───────────────────────────────────────────────────
  status: {
    type: String,
    enum: ['active', 'suspended', 'onboarding'],
    default: 'onboarding',
    description: "Organization's current status"
  },

  permissions: [{
    type: String,
    enum: ['anchor', 'verify', 'revoke', 'query', 'admin'],
    default: ['anchor', 'verify', 'query'],
    description: 'Permitted operations for this organization'
  }],

  // ── Blockchain Configuration ───────────────────────────────────────────────
  peerEndpoint: {
    type: String,
    description: 'Fabric peer endpoint for this org (e.g., localhost:8051)'
  },

  // ── Timestamps ─────────────────────────────────────────────────────────────
  createdAt: {
    type: Date,
    default: Date.now,
    description: 'When the organization was onboarded'
  },

  updatedAt: {
    type: Date,
    default: Date.now,
    description: 'Last update timestamp'
  },

  onboardedBy: {
    type: String,
    description: 'Admin who onboarded this organization'
  }
});

// ── Indexes ────────────────────────────────────────────────────────────────
OrganizationSchema.index({ mspId: 1 });
OrganizationSchema.index({ 'apiKeys.keyHash': 1 });
OrganizationSchema.index({ status: 1 });
OrganizationSchema.index({ createdAt: -1 });

// ── Methods ────────────────────────────────────────────────────────────────

/**
 * Hash an API key for secure storage
 * @param {string} apiKey - Plain API key
 * @returns {string} SHA-256 hash
 */
function hashApiKey(apiKey) {
  return crypto.createHash('sha256').update(apiKey).digest('hex');
}

/**
 * Generate a new API key pair for this organization
 * @param {string} description - Description of the key
 * @param {string} createdBy - Admin email who created it
 * @returns {object} { keyId, plainKey, plainSecret, keyHash, secretHash }
 */
OrganizationSchema.methods.generateApiKey = function(description, createdBy) {
  // Generate random key and secret
  const plainKey = 'doc_prod_' + crypto.randomBytes(24).toString('hex');
  const plainSecret = 'secret_' + crypto.randomBytes(24).toString('hex');

  // Hash for storage
  const keyHash = hashApiKey(plainKey);
  const secretHash = hashApiKey(plainSecret);

  // Create key ID (public reference)
  const keyId = plainKey.substring(0, 24) + '...';

  // Add to apiKeys array
  this.apiKeys.push({
    keyId,
    keyHash,
    secretHash,
    description: description || '',
    createdAt: new Date(),
    createdBy: createdBy || 'system',
    enabled: true
  });

  return {
    keyId: `${plainKey}`,  // Return full key (only shown once!)
    secret: `${plainSecret}`,
    publicKeyId: keyId,
    keyHash,
    secretHash
  };
};

/**
 * Verify an API key + secret combination
 * @param {string} plainKey - API key to verify
 * @param {string} plainSecret - Secret to verify
 * @returns {object|null} Valid API key object or null if invalid
 */
OrganizationSchema.methods.verifyApiKey = function(plainKey, plainSecret) {
  const keyHash = hashApiKey(plainKey);
  const secretHash = hashApiKey(plainSecret);

  const apiKey = this.apiKeys.find(
    k => k.keyHash === keyHash && k.secretHash === secretHash && k.enabled
  );

  if (!apiKey) return null;

  // Update usage
  apiKey.lastUsedAt = new Date();
  apiKey.requestCount = (apiKey.requestCount || 0) + 1;

  // Return public info (never return hashes!)
  return {
    keyId: apiKey.keyId,
    createdAt: apiKey.createdAt,
    lastUsedAt: apiKey.lastUsedAt,
    requestCount: apiKey.requestCount
  };
};

/**
 * Revoke an API key
 * @param {string} revokedBy - Admin email
 * @param {string} keyId - Public key ID
 * @returns {boolean} Success
 */
OrganizationSchema.methods.revokeApiKey = function(revokedBy, keyId) {
  const apiKey = this.apiKeys.find(k => k.keyId === keyId);
  if (!apiKey) return false;

  apiKey.enabled = false;
  apiKey.revokedAt = new Date();
  apiKey.revokedBy = revokedBy;
  return true;
};

/**
 * Check if organization can perform a permission
 * @param {string} permission - e.g., 'anchor', 'verify', 'revoke'
 * @returns {boolean}
 */
OrganizationSchema.methods.hasPermission = function(permission) {
  return this.permissions.includes(permission) && this.status === 'active';
};

/**
 * Check if rate limit exceeded
 * @param {string} limitType - 'requestsPerMinute', 'documentsPerDay'
 * @param {number} currentCount - Current count in time window
 * @returns {boolean}
 */
OrganizationSchema.methods.isRateLimited = function(limitType, currentCount) {
  return currentCount >= this.rateLimits[limitType];
};

/**
 * Record usage
 * @param {object} options - { documentsAnchored, requestsMade, ipAddress }
 */
OrganizationSchema.methods.recordUsage = function(options = {}) {
  if (options.documentsAnchored) {
    this.usage.documentsAnchoredToday = (this.usage.documentsAnchoredToday || 0) + options.documentsAnchored;
    this.usage.documentsAnchoredThisMonth = (this.usage.documentsAnchoredThisMonth || 0) + options.documentsAnchored;
    this.usage.totalDocumentsAnchored = (this.usage.totalDocumentsAnchored || 0) + options.documentsAnchored;
    this.usage.lastAnchorAt = new Date();
  }

  if (options.requestsMade) {
    this.usage.totalApiRequests = (this.usage.totalApiRequests || 0) + options.requestsMade;
  }
};

module.exports = mongoose.model('Organization', OrganizationSchema);
