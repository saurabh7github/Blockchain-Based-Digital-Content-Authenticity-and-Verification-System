/**
 * middleware/orgAuth.js
 * Multi-organization authentication middleware for DocVerifier
 *
 * Authenticates requests using API keys and attaches organization context
 * to the request for use in downstream handlers.
 *
 * Usage in routes:
 *   const { requireOrgAuth } = require('../middleware/orgAuth');
 *   router.post('/api/fabric/analyze', requireOrgAuth, async (req, res) => {
 *     // req.organization - authenticated organization
 *     // req.organizationId - organization MSP ID
 *   });
 *
 * API Key Format:
 *   X-API-Key: doc_prod_<32_random_hex_chars>
 *   X-API-Secret: secret_<32_random_hex_chars>
 */

const Organization = require('../models/Organization');

/**
 * Authenticate organization via API key
 * Extracts and validates X-API-Key and X-API-Secret headers
 * Attaches organization context to req
 *
 * @param {Request} req
 * @param {Response} res
 * @param {Function} next
 */
async function requireOrgAuth(req, res, next) {
  try {
    const apiKey = req.headers['x-api-key'];
    const apiSecret = req.headers['x-api-secret'];

    // Both key and secret required
    if (!apiKey || !apiSecret) {
      return res.status(401).json({
        error: 'Missing credentials',
        details: 'Both X-API-Key and X-API-Secret headers required'
      });
    }

    // Find organization with matching API key hash
    const org = await Organization.findOne({
      'apiKeys.keyHash': require('crypto').createHash('sha256').update(apiKey).digest('hex'),
      status: 'active'
    });

    if (!org) {
      return res.status(401).json({
        error: 'Invalid API key',
        details: 'Organization not found or inactive'
      });
    }

    // Verify the secret matches
    const apiKeyEntry = org.verifyApiKey(apiKey, apiSecret);
    if (!apiKeyEntry) {
      return res.status(401).json({
        error: 'Invalid credentials',
        details: 'API key or secret mismatch'
      });
    }

    // Check if organization is active
    if (org.status !== 'active') {
      return res.status(403).json({
        error: 'Organization inactive',
        details: `Organization status is ${org.status}`
      });
    }

    // Attach organization to request
    req.organization = org;
    req.organizationId = org.mspId;
    req.apiKeyEntry = apiKeyEntry;

    // Update last used IP
    org.apiKeys.find(k => k.keyId === apiKeyEntry.keyId).lastUsedIp = req.ip;
    await org.save();

    next();
  } catch (error) {
    console.error('[OrgAuth] Error:', error.message);
    res.status(500).json({
      error: 'Authentication error',
      details: error.message
    });
  }
}

/**
 * Authenticate via JWT token using the same JWT_SECRET as auth.js
 * Validates tokens issued by /api/auth/login
 *
 * @param {Request} req
 * @param {Response} res
 * @param {Function} next
 */
async function requireJWT(req, res, next) {
  try {
    const authHeader = req.headers['authorization'];

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: 'Missing JWT token',
        details: 'Authorization header with Bearer token required'
      });
    }

    const token = authHeader.substring(7); // Remove "Bearer "
    const secret = process.env.JWT_SECRET;

    if (!secret) {
      return res.status(500).json({
        error: 'Server misconfiguration',
        details: 'JWT_SECRET is not set'
      });
    }

    // Verify JWT signature and expiration
    const jwt = require('jsonwebtoken');
    const payload = jwt.verify(token, secret);

    // Check for admin role
    if (payload.role !== 'admin') {
      return res.status(403).json({
        error: 'Insufficient permissions',
        details: 'Admin role required for this operation'
      });
    }

    // For JWT auth, use Org1MSP (host org)
    req.organization = { mspId: 'Org1MSP', name: 'Org1' };
    req.organizationId = 'Org1MSP';
    req.authMethod = 'jwt';
    req.admin = payload;

    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token expired',
        details: 'Please log in again'
      });
    }
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        error: 'Invalid JWT',
        details: 'Token verification failed'
      });
    }
    console.error('[JWTAuth] Error:', error.message);
    res.status(500).json({
      error: 'Authentication error',
      details: error.message
    });
  }
}

/**
 * Check if organization has permission for operation
 * @param {string} permission - 'anchor', 'verify', 'revoke', 'query', 'admin'
 * @returns {Function} Middleware function
 */
function requirePermission(permission) {
  return (req, res, next) => {
    if (!req.organization) {
      return res.status(401).json({ error: 'Organization not authenticated' });
    }

    if (!req.organization.hasPermission(permission)) {
      return res.status(403).json({
        error: 'Permission denied',
        details: `Organization does not have "${permission}" permission`,
        organizationId: req.organizationId
      });
    }

    next();
  };
}

/**
 * Rate limiting per organization
 * @param {string} limitType - 'requestsPerMinute', 'documentsPerDay'
 * @returns {Function} Middleware function
 */
function requireRateLimit(limitType = 'requestsPerMinute') {
  return async (req, res, next) => {
    if (!req.organization) {
      return res.status(401).json({ error: 'Organization not authenticated' });
    }

    const limit = req.organization.rateLimits[limitType];
    if (!limit) {
      return res.status(400).json({
        error: 'Invalid rate limit type',
        details: `Unknown limit type: ${limitType}`
      });
    }

    // Check current usage
    let currentCount = 0;
    if (limitType === 'requestsPerMinute') {
      // This would require Redis or in-memory store to track per-minute usage
      // For now, just log that we would check here
      console.log(`[RateLimit] Checking requests/minute for ${req.organizationId}`);
    } else if (limitType === 'documentsPerDay') {
      currentCount = req.organization.usage.documentsAnchoredToday || 0;
    }

    if (currentCount >= limit) {
      return res.status(429).json({
        error: 'Rate limit exceeded',
        details: `Organization has reached ${limitType} limit of ${limit}`,
        organizationId: req.organizationId,
        current: currentCount,
        limit
      });
    }

    next();
  };
}

/**
 * Optional: Allow either API key OR JWT auth
 * Tries API key first, falls back to JWT
 * @param {Request} req
 * @param {Response} res
 * @param {Function} next
 */
async function optionalOrgAuth(req, res, next) {
  try {
    const apiKey = req.headers['x-api-key'];

    if (apiKey) {
      // Try API key auth
      return requireOrgAuth(req, res, next);
    }

    const authHeader = req.headers['authorization'];
    if (authHeader && authHeader.startsWith('Bearer ')) {
      // Try JWT auth
      return requireJWT(req, res, next);
    }

    // If neither provided and policy allows, continue as anonymous
    // Set default org (Org1MSP - host org)
    if (process.env.FABRIC_ALLOW_ANONYMOUS === 'true') {
      req.organization = { mspId: 'Org1MSP', name: 'Org1' };
      req.organizationId = 'Org1MSP';
      req.authMethod = 'anonymous';
      return next();
    }

    res.status(401).json({
      error: 'Authentication required',
      details: 'Provide either X-API-Key header or Authorization Bearer token'
    });
  } catch (error) {
    console.error('[OptionalOrgAuth] Error:', error.message);
    res.status(500).json({
      error: 'Authentication error',
      details: error.message
    });
  }
}

module.exports = {
  requireOrgAuth,
  requireJWT,
  requirePermission,
  requireRateLimit,
  optionalOrgAuth
};
