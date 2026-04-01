'use strict';
/**
 * models/AuditLog.js
 *
 * Immutable audit log for tracking all administrative operations,
 * blockchain activities, and security events.
 *
 * Purpose:
 * - Compliance and forensics (SOC2, GDPR audit trails)
 * - Security incident investigation
 * - API usage analytics
 * - Access control validation
 */

const mongoose = require('mongoose');

const AuditLogSchema = new mongoose.Schema({
  // Timestamp and sequencing
  timestamp: { type: Date, default: Date.now, index: true },
  sequence: { type: Number }  // For ordering if timestamps collide

  // Request metadata
  method: { type: String, required: true, index: true },  // GET, POST, PUT, DELETE
  path: { type: String, required: true, index: true },
  statusCode: { type: Number, index: true },
  duration: { type: Number },  // milliseconds

  // Identity information
  organizationId: { type: String, index: true },  // Org1MSP, Org2MSP, etc.
  apiKeyUsed: { type: String },  // First 8 chars for identification
  userId: { type: String },
  ipAddress: { type: String, index: true },
  userAgent: { type: String },

  // Action categorization
  category: {
    type: String,
    enum: [
      'authentication',
      'blockchain_operation',
      'document_analysis',
      'document_query',
      'data_modification',
      'data_deletion',
      'data_retrieval',
      'api_call'
    ],
    index: true
  },
  severity: {
    type: String,
    enum: ['low', 'medium', 'high', 'critical'],
    default: 'low',
    index: true
  },

  // Request details
  requestBody: { type: mongoose.Schema.Types.Mixed },
  queryParams: { type: mongoose.Schema.Types.Mixed },

  // Response details
  responseStatus: { type: String, enum: ['success', 'error'] },
  responseSize: { type: Number },

  // Blockchain-specific information
  blockchain: {
    network: { type: String, enum: ['fabric', 'ethereum'] },
    channel: String,
    chaincode: String,
    operation: {
      type: String,
      enum: [
        'anchor_document',
        'verify_document',
        'revoke_document',
        'query_document',
        'pause_network',
        'unpause_network',
        null
      ]
    },
    transactionId: String,
    blockNumber: Number
  },

  // Contextual information
  notes: { type: String },
  relatedDocuments: [String],  // Document hashes related to this action

  // Compliance fields
  immutable: { type: Boolean, default: true },  // Mark as immutable
  archived: { type: Boolean, default: false }
});

// Indexes for common queries
AuditLogSchema.index({ organizationId: 1, timestamp: -1 });  // Org activity timeline
AuditLogSchema.index({ ipAddress: 1, timestamp: -1 });  // IP activity timeline
AuditLogSchema.index({ 'blockchain.operation': 1, timestamp: -1 });  // Operation timeline
AuditLogSchema.index({ severity: 1, timestamp: -1 });  // Critical actions first
AuditLogSchema.index({ category: 1, organizationId: 1, timestamp: -1 });  // Org action timeline

// Compound index for compliance queries
AuditLogSchema.index({ organizationId: 1, category: 1, timestamp: -1 });

// TTL Index (optional: keep logs for 2 years in production)
// In development, logs are kept indefinitely
if (process.env.NODE_ENV === 'production') {
  AuditLogSchema.index(
    { timestamp: 1 },
    { expireAfterSeconds: 63072000 }  // 2 years
  );
}

// Prevent modification of existing logs
AuditLogSchema.pre('updateOne', function(next) {
  if (this.immutable) {
    return next(new Error('Audit logs are immutable and cannot be modified'));
  }
  next();
});

AuditLogSchema.pre('findByIdAndUpdate', function(next) {
  if (this.immutable) {
    return next(new Error('Audit logs are immutable and cannot be modified'));
  }
  next();
});

// Instance method: Check if action is suspicious
AuditLogSchema.methods.isSuspicious = function() {
  const suspiciousPatterns = [
    // Multiple failures in short time
    this.statusCode >= 400,
    // Unusual IP
    this.ipAddress && !isKnownIP(this.ipAddress),
    // Critical action
    this.severity === 'critical',
    // Unusual time (3am-5am)
    [3, 4, 5].includes(new Date(this.timestamp).getHours())
  ];

  return suspiciousPatterns.filter(Boolean).length >= 2;
};

// Static method: Get organization activity summary
AuditLogSchema.statics.getOrgActivitySummary = async function(orgId, days = 7) {
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - days);

  const logs = await this.find({
    organizationId: orgId,
    timestamp: { $gte: startDate }
  });

  return {
    organization: orgId,
    period: `${days} days`,
    totalActions: logs.length,
    actionsByType: groupBy(logs, 'category'),
    successRate: ((logs.filter(l => l.responseStatus === 'success').length / logs.length) * 100).toFixed(2) + '%',
    criticalActions: logs.filter(l => l.severity === 'critical').length,
    uniqueIPs: [...new Set(logs.map(l => l.ipAddress))].length
  };
};

// Static method: Audit trail for security incident investigation
AuditLogSchema.statics.getSecurityIncidentReport = async function(filters = {}) {
  const {
    organizationId,
    startDate,
    endDate,
    severity = 'high',
    includeErrors = true
  } = filters;

  const query = {};
  if (organizationId) query.organizationId = organizationId;
  if (startDate || endDate) {
    query.timestamp = {};
    if (startDate) query.timestamp.$gte = new Date(startDate);
    if (endDate) query.timestamp.$lte = new Date(endDate);
  }
  if (severity) {
    const severityLevels = ['low', 'medium', 'high', 'critical'];
    const index = severityLevels.indexOf(severity);
    query.severity = { $in: severityLevels.slice(index) };
  }
  if (includeErrors) {
    query.$or = [{ responseStatus: 'error' }, { isSuspicious: true }];
  }

  const logs = await this.find(query)
    .sort({ timestamp: -1 })
    .lean();

  return {
    incidentTimeframe: {
      start: startDate || 'beginning',
      end: endDate || 'now'
    },
    riskSummary: {
      criticalEvents: logs.filter(l => l.severity === 'critical').length,
      errorEvents: logs.filter(l => l.responseStatus === 'error').length,
      suspiciousPatterns: logs.filter(l => l.isSuspicious?.()).length
    },
    events: logs
  };
};

// Helper function: Group array by property
function groupBy(array, property) {
  return array.reduce((groups, item) => {
    const key = item[property];
    groups[key] = (groups[key] || 0) + 1;
    return groups;
  }, {});
}

// Helper function: Check if IP is known/trusted
function isKnownIP(ip) {
  const knownIPs = [
    '127.0.0.1',
    '::1',
    process.env.TRUSTED_IP_RANGE
  ].filter(Boolean);

  return knownIPs.some(known => ip.includes(known));
}

module.exports = mongoose.models.AuditLog || mongoose.model('AuditLog', AuditLogSchema);
