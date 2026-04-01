/**
 * middleware/auditLog.js
 *
 * Audit logging middleware that tracks all administrative operations and blockchain activities
 * for compliance, security, and troubleshooting purposes.
 *
 * Features:
 * - Logs all fabric transactions (anchor, verify, revoke)
 * - Tracks API key usage by organization
 * - Records user actions and changes
 * - Stores immutable audit trail in MongoDB
 * - Alerts on suspicious activities
 */

const AuditLog = require('../models/AuditLog');

/**
 * Comprehensive audit logging middleware
 * Captures request/response metadata and logs to persistent storage
 */
const auditLogger = async (req, res, next) => {
  const startTime = Date.now();

  // Capture original response.send for interception
  const originalSend = res.send;
  let responseBody = '';
  let responseSent = false;

  res.send = function(data) {
    responseBody = typeof data === 'string' ? data : JSON.stringify(data);
    responseSent = true;
    res.send = originalSend;
    return res.send(data);
  };

  // Continue to next middleware/handler
  res.on('finish', async () => {
    if (responseSent) {
      const duration = Date.now() - startTime;

      try {
        // Extract audit-relevant information
        const auditEntry = {
          timestamp: new Date(),
          path: req.path,
          method: req.method,
          statusCode: res.statusCode,
          duration: duration,

          // Identity information
          organizationId: req.organization?.mspId || 'anonymous',
          apiKeyUsed: req.headers['x-api-key']?.substring(0, 8) || null,
          userId: req.user?.id || null,
          ipAddress: req.ip || req.connection.remoteAddress,
          userAgent: req.headers['user-agent'],

          // Request details
          requestBody: sanitizeRequestBody(req.body),
          queryParams: req.query,

          // Response details
          responseStatus: res.statusCode < 400 ? 'success' : 'error',
          responseSize: responseBody.length,

          // Blockchain-specific information (Fabric)
          blockchain: {
            network: process.env.FABRIC_ENABLED === 'true' ? 'fabric' : 'ethereum',
            channel: process.env.FABRIC_CHANNEL || null,
            chaincode: 'docverifier',
            operation: extractBlockchainOperation(req.path, req.method)
          },

          // Categorization
          category: categorizeAction(req.path, req.method),
          severity: calculateSeverity(req.path, req.method, res.statusCode),

          // Additional context
          notes: extractNotesFromContext(req)
        };

        // Log to database
        await AuditLog.create(auditEntry);

        // Alert on critical actions
        if (auditEntry.severity === 'critical') {
          await alertOnCriticalAction(auditEntry);
        }

      } catch (error) {
        console.error('[AuditLog] Error logging operation:', error.message);
        // Don't fail the request if audit logging fails
      }
    }
  });

  next();
};

/**
 * Sanitize request body to remove sensitive information
 */
function sanitizeRequestBody(body) {
  if (!body) return null;

  const sanitized = JSON.parse(JSON.stringify(body)); // Deep copy

  // Remove sensitive fields
  const sensitiveFields = [
    'password',
    'secret',
    'key',
    'token',
    'pem',
    'privateKey',
    'apiSecret'
  ];

  function maskSensitiveData(obj) {
    if (obj && typeof obj === 'object') {
      for (const key in obj) {
        if (sensitiveFields.some(field => key.toLowerCase().includes(field.toLowerCase()))) {
          obj[key] = '[REDACTED]';
        } else if (typeof obj[key] === 'object') {
          maskSensitiveData(obj[key]);
        }
      }
    }
    return obj;
  }

  return maskSensitiveData(sanitized);
}

/**
 * Extract blockchain operation type from request
 */
function extractBlockchainOperation(path, method) {
  if (!path.includes('/fabric')) return null;

  if (path.includes('/analyze')) return 'anchor_document';
  if (path.includes('/verify')) return 'verify_document';
  if (path.includes('/revoke')) return 'revoke_document';
  if (path.includes('/document')) return 'query_document';
  if (path.includes('/pause')) return 'pause_network';
  if (path.includes('/unpause')) return 'unpause_network';

  return null;
}

/**
 * Categorize action for audit purposes
 */
function categorizeAction(path, method) {
  if (path.includes('/auth')) return 'authentication';
  if (path.includes('/fabric')) return 'blockchain_operation';
  if (path.includes('/analyze')) return 'document_analysis';
  if (path.includes('/document')) return 'document_query';
  if (method === 'DELETE') return 'data_deletion';
  if (method === 'POST') return 'data_modification';
  if (method === 'GET') return 'data_retrieval';
  return 'api_call';
}

/**
 * Calculate severity level for action
 */
function calculateSeverity(path, method, statusCode) {
  // Error responses are concerning
  if (statusCode >= 500) return 'critical';
  if (statusCode >= 400) return 'warning';

  // Admin/destructive operations are critical
  if (path.includes('/pause') || path.includes('/unpause')) return 'critical';
  if (path.includes('/revoke')) return 'high';

  // Write operations are high severity
  if (method === 'DELETE') return 'high';
  if (method === 'POST') return 'medium';

  return 'low';
}

/**
 * Extract contextual notes from request
 */
function extractNotesFromContext(req) {
  const notes = [];

  if (req.file) {
    notes.push(`File upload: ${req.file.originalname} (${req.file.size} bytes)`);
  }

  if (req.body?.fileName) {
    notes.push(`Document: ${req.body.fileName}`);
  }

  if (req.body?.docHash) {
    notes.push(`Hash: ${req.body.docHash.substring(0, 16)}...`);
  }

  if (req.organization) {
    notes.push(`Organization: ${req.organization.name} (${req.organization.mspId})`);
  }

  return notes.join('; ');
}

/**
 * Alert on critical administrative actions
 */
async function alertOnCriticalAction(auditEntry) {
  const AlertTemplate = require('../models/AlertTemplate');

  const alert = await AlertTemplate.create({
    type: 'critical_action',
    severity: 'critical',
    organization: auditEntry.organizationId,
    action: auditEntry.blockchain?.operation || auditEntry.category,
    message: `Critical action: ${auditEntry.method} ${auditEntry.path} by ${auditEntry.organizationId}`,
    timestamp: auditEntry.timestamp,
    status: 'active'
  });

  // Log to console immediately for real-time visibility
  console.warn(`[AUDIT ALERT] ${alert.message}`);
}

/**
 * Middleware to require audit logging for specific operations
 */
const requireAuditLogging = (req, res, next) => {
  req.auditRequired = true;
  next();
};

/**
 * Generate audit report for compliance
 */
const generateAuditReport = async (req, res) => {
  try {
    const { from, to, organization, action } = req.query;

    const filters = {};
    if (from || to) {
      filters.timestamp = {};
      if (from) filters.timestamp.$gte = new Date(from);
      if (to) filters.timestamp.$lte = new Date(to);
    }
    if (organization) filters.organizationId = organization;
    if (action) filters.category = action;

    const logs = await AuditLog.find(filters)
      .sort({ timestamp: -1 })
      .limit(10000)
      .lean();

    // Generate statistics
    const stats = {
      totalActions: logs.length,
      actionsByType: {},
      actionsByOrganization: {},
      errorRate: 0,
      criticalActions: 0
    };

    logs.forEach(log => {
      stats.actionsByType[log.category] = (stats.actionsByType[log.category] || 0) + 1;
      stats.actionsByOrganization[log.organizationId] = (stats.actionsByOrganization[log.organizationId] || 0) + 1;
      if (log.responseStatus !== 'success') stats.errorRate++;
      if (log.severity === 'critical') stats.criticalActions++;
    });

    stats.errorRate = ((stats.errorRate / logs.length) * 100).toFixed(2) + '%';

    res.json({
      period: {
        from: from || 'beginning',
        to: to || 'now'
      },
      statistics: stats,
      logs: logs
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Query audit logs for forensics
 */
const queryAuditLogs = async (req, res) => {
  try {
    const { search, limit = 100, offset = 0 } = req.query;

    const query = {};
    if (search) {
      query.$or = [
        { organizationId: new RegExp(search, 'i') },
        { 'blockchain.operation': new RegExp(search, 'i') },
        { category: new RegExp(search, 'i') },
        { notes: new RegExp(search, 'i') }
      ];
    }

    const logs = await AuditLog.find(query)
      .sort({ timestamp: -1 })
      .skip(Number(offset))
      .limit(Number(limit))
      .lean();

    const total = await AuditLog.countDocuments(query);

    res.json({
      search: search || 'all',
      total: total,
      offset: Number(offset),
      limit: Number(limit),
      logs: logs
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

module.exports = {
  auditLogger,
  requireAuditLogging,
  generateAuditReport,
  queryAuditLogs
};
