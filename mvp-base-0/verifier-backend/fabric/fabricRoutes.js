'use strict';
/**
 * fabric/fabricRoutes.js
 * Express router for Fabric-backed routes with multi-organization support.
 *
 * Routes:
 *   POST /api/fabric/analyze        – AI-gate + AnchorDocument on Fabric + MongoDB
 *   GET  /api/fabric/document/:hash – VerifyDocument on Fabric + MongoDB metadata
 *   POST /api/fabric/revoke         – RevokeDocument on Fabric (org-authenticated)
 *   POST /api/fabric/pause          – PauseNetwork (admin only)
 *   POST /api/fabric/unpause        – UnpauseNetwork (admin only)
 *   GET  /api/fabric/status         – Get network state
 *
 * Authentication:
 * - Routes using orgAuth middleware require X-API-Key + X-API-Secret headers
 * - Admin routes (pause/unpause) require owner organization (Org1MSP)
 *
 * Mounted in server.js when FABRIC_ENABLED=true:
 *   app.use('/api/fabric', require('./fabric/fabricRoutes'));
 */

const express  = require('express');
const multer   = require('multer');
const crypto   = require('crypto');
const router   = express.Router();

const { getContract, getContractForOrg } = require('./gateway');
const { getThreshold, checkAuthenticity } = require('../lib/aiCheck');
const { pinToIPFS }                        = require('../lib/ipfs');
const DocModel                             = require('../models/Document');
const { requireAuth }                      = require('../middleware/auth');
const { requireOrgAuth, optionalOrgAuth }  = require('../middleware/orgAuth');

// 10 MB cap (same as main upload endpoint)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }
});

// ── POST /api/fabric/analyze ─────────────────────────────────────────────────
// Multi-org: Any org can anchor documents
// 1. Compute SHA-256 hash
// 2. AI check (same gate as Ethereum route)
// 3. IPFS upload (optional)
// 4. AnchorDocument on Fabric (Private Data Collection) under org's MSP ID
// 5. Persist metadata to MongoDB with issuer tracking
router.post('/analyze', optionalOrgAuth, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded.' });

    const fileBuffer = req.file.buffer;
    const fileName   = req.file.originalname;
    const mimeType   = req.file.mimetype;
    const organizationId = req.organizationId || 'Org1MSP';  // Default to Org1

    // A. Hash
    const docHash  = '0x' + crypto.createHash('sha256').update(fileBuffer).digest('hex');
    const threshold = getThreshold(mimeType);

    // B. AI gate
    const aiResult = await checkAuthenticity(fileBuffer, fileName, mimeType);
    if (aiResult.score > threshold) {
      return res.status(400).json({
        error:      'AI check failed: content appears synthetic or forged.',
        aiScore:    aiResult.score,
        aiProvider: aiResult.provider,
        threshold
      });
    }

    // C. IPFS
    let ipfsCid = null;
    try {
      ipfsCid = await pinToIPFS(fileBuffer, fileName);
      if (ipfsCid) console.log(`[Fabric] [${organizationId}] [IPFS] Pinned: ${ipfsCid}`);
    } catch (pinErr) {
      console.warn(`[Fabric] [${organizationId}] [IPFS] Pinata upload failed (non-fatal):`, pinErr.message);
    }

    // D. Anchor on Fabric (using organization's peer via their MSP ID)
    const contract = await getContractForOrg(organizationId);
    // AnchorDocument(docHash, ipfsCid) – chaincode will use chaincode.ClientIdentity to get issuer MSP
    await contract.submitTransaction('AnchorDocument', docHash, ipfsCid ?? '');
    console.log(`[Fabric] [${organizationId}] Anchored: ${docHash}`);

    // E. Persist to MongoDB with issuer tracking
    const isAuthentic = aiResult.score <= threshold;
    await DocModel.findOneAndUpdate(
      { docHash },
      {
        docHash,
        fileName,
        issuer: organizationId,  // Track which org anchored this
        aiScore:    aiResult.score,
        aiProvider: aiResult.provider,
        aiDetails:  aiResult.details,
        isAuthentic,
        ipfsCid,
        network:    'fabric',
        anchoredAt: new Date(),
        anchoredBy: organizationId
      },
      { upsert: true, new: true }
    );

    // F. Update organization usage stats (skip for anonymous)
    if (req.organization && typeof req.organization.recordUsage === 'function') {
      req.organization.recordUsage({ documentsAnchored: 1 });
      await req.organization.save();
    }

    res.json({
      success:    true,
      docHash,
      aiScore:    aiResult.score,
      aiProvider: aiResult.provider,
      ipfsCid,
      network:    'fabric',
      issuer:     organizationId
    });

  } catch (err) {
    console.error('[Fabric] /api/fabric/analyze error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/fabric/document/:hash ───────────────────────────────────────────
// Queries both Fabric (on-chain truth) and MongoDB (off-chain metadata).
// No auth required – documents are public once issued
router.get('/document/:hash', async (req, res) => {
  try {
    const docHash  = req.params.hash;
    const organizationId = req.organizationId || 'Org1MSP';

    // On-chain data (from Private Data Collection)
    let fabricDoc;
    try {
      const contract = await getContractForOrg(organizationId);
      const resultBytes = await contract.evaluateTransaction('VerifyDocument', docHash);
      fabricDoc = JSON.parse(Buffer.from(resultBytes).toString());
    } catch (ccErr) {
      // Chaincode throws "document not found" – treat as 404
      if (ccErr.message?.includes('not found')) {
        return res.status(404).json({ error: 'Document not found on Fabric ledger.' });
      }
      throw ccErr;
    }

    // Off-chain metadata (may not exist if anchored from another node)
    const dbDoc = await DocModel.findOne({ docHash });

    res.json({
      // On-chain fields (authoritative)
      docHash:   fabricDoc.docHash,
      issuer:    fabricDoc.issuer,
      timestamp: fabricDoc.timestamp,
      ipfsCid:   fabricDoc.ipfsCid || null,
      revoked:   fabricDoc.revoked,
      network:   'fabric',
      // Off-chain enrichment (may be null)
      fileName:    dbDoc?.fileName    ?? null,
      issuer:      dbDoc?.issuer      ?? fabricDoc.issuer,  // Fall back to on-chain
      aiScore:     dbDoc?.aiScore     ?? null,
      aiProvider:  dbDoc?.aiProvider  ?? null,
      aiDetails:   dbDoc?.aiDetails   ?? null,
      isAuthentic: dbDoc?.isAuthentic ?? null,
      createdAt:   dbDoc?.createdAt   ?? null,
      anchoredBy:  dbDoc?.anchoredBy   ?? fabricDoc.issuer
    });

  } catch (err) {
    console.error('[Fabric] /api/fabric/document error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/fabric/revoke ──────────────────────────────────────────────────
// Multi-org: Only issuer or owner can revoke
// Requires API key authentication OR JWT admin token
router.post('/revoke', optionalOrgAuth, express.json(), async (req, res) => {
  try {
    const { docHash } = req.body;
    if (!docHash) return res.status(400).json({ error: 'docHash is required.' });

    const organizationId = req.organizationId || 'Org1MSP';

    // Get document to check permissions
    const dbDoc = await DocModel.findOne({ docHash });
    if (!dbDoc) {
      return res.status(404).json({ error: 'Document not found in system.' });
    }

    // Check if org is issuer or owner
    if (dbDoc.issuer !== organizationId && organizationId !== 'Org1MSP') {
      return res.status(403).json({
        error: 'Permission denied',
        details: `Only the issuer (${dbDoc.issuer}) or network owner can revoke this document`,
        issuedBy: dbDoc.issuer,
        requestedBy: organizationId
      });
    }

    const contract = await getContractForOrg(organizationId);
    await contract.submitTransaction('RevokeDocument', docHash);
    console.log(`[Fabric] [${organizationId}] Revoked: ${docHash}`);

    // Update MongoDB
    dbDoc.revoked = true;
    dbDoc.revokedBy = organizationId;
    dbDoc.revokedAt = new Date();
    await dbDoc.save();

    res.json({
      success: true,
      docHash,
      revoked: true,
      network: 'fabric',
      revokedBy: organizationId
    });

  } catch (err) {
    console.error('[Fabric] /api/fabric/revoke error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/fabric/pause  /  POST /api/fabric/unpause ─────────────────────
// Admin only: Network owner (Org1MSP) can pause/unpause
router.post('/pause', requireAuth, express.json(), async (_req, res) => {
  try {
    const contract = await getContractForOrg('Org1MSP');  // Only owner can pause
    await contract.submitTransaction('PauseNetwork');
    console.log('[Fabric] Network paused');
    res.json({ success: true, paused: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/unpause', requireAuth, express.json(), async (_req, res) => {
  try {
    const contract = await getContractForOrg('Org1MSP');  // Only owner can unpause
    await contract.submitTransaction('UnpauseNetwork');
    console.log('[Fabric] Network unpaused');
    res.json({ success: true, paused: false });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/fabric/status ───────────────────────────────────────────────────
// Returns current Fabric network state (paused, owner).
// Public endpoint – no auth required
router.get('/status', async (_req, res) => {
  try {
    const contract    = await getContract();  // Use default org
    const resultBytes = await contract.evaluateTransaction('GetNetworkState');
    const state       = JSON.parse(Buffer.from(resultBytes).toString());
    res.json({ ...state, network: 'fabric' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
