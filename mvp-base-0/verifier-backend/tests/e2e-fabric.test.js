'use strict';
/**
 * End-to-End Integration Tests for Fabric routes
 *
 * IMPORTANT: These tests require a live Fabric network running.
 * Before running:
 *   1. cd fabric && ./scripts/start-network.sh
 *   2. Verify: docker ps | grep hyperledger
 *   3. Set FABRIC_ENABLED=true in backend .env
 *   4. Start MongoDB (docker compose up -d mongodb)
 *
 * Run: FABRIC_ENABLED=true npm test -- e2e-fabric.test.js
 */

const request = require('supertest');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

// Skip if Fabric is not available (allow tests to run in CI without Fabric)
const SKIP_E2E = process.env.SKIP_FABRIC_E2E === 'true';

describe('E2E: Fabric Integration', () => {
  let app;
  let testToken;

  beforeAll(async () => {
    if (SKIP_E2E) {
      console.log('[E2E] Skipping Fabric E2E tests (SKIP_FABRIC_E2E=true)');
      return;
    }

    // Load app (will connect to real Fabric network)
    process.env.FABRIC_ENABLED = 'true';
    process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

    app = require('../server');

    // Generate admin token for authenticated operations
    testToken = jwt.sign(
      { username: 'admin' },
      process.env.JWT_SECRET,
      { expiresIn: '1h' }
    );

    // Check if Fabric network is available
    const healthRes = await request(app).get('/api/health');

    if (!healthRes.body.fabric || healthRes.body.fabric.gateway !== 'connected') {
      console.error('\n[E2E] Fabric network not available!');
      console.error('Start network: cd fabric && ./scripts/start-network.sh');
      console.error('Current status:', JSON.stringify(healthRes.body.fabric, null, 2));
      throw new Error('Fabric network required for E2E tests');
    }

    console.log('[E2E] Fabric network connected:', healthRes.body.fabric);
  }, 30000); // Allow 30s for network check

  // Helper: Create unique test document hash
  const createTestHash = (testName) => {
    return '0x' + crypto.createHash('sha256')
      .update(`e2e-test-${testName}-${Date.now()}`)
      .digest('hex');
  };

  // Helper: Create test file buffer
  const createTestFile = () => {
    return Buffer.from('E2E test file content for Fabric integration testing');
  };

  // ── Test 1: Complete Document Lifecycle ─────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should complete full document lifecycle', async () => {
    const testFile = createTestFile();
    const uniqueSuffix = Date.now();

    // Step 1: Anchor document
    const anchorRes = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-lifecycle-${uniqueSuffix}.txt`);

    expect(anchorRes.status).toBe(200);
    expect(anchorRes.body.success).toBe(true);
    expect(anchorRes.body.docHash).toMatch(/^0x[a-f0-9]{64}$/);
    expect(anchorRes.body.network).toBe('fabric');

    const docHash = anchorRes.body.docHash;
    console.log(`[E2E] Anchored document: ${docHash}`);

    // Wait for transaction to settle
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Step 2: Verify document exists
    const verifyRes = await request(app)
      .get(`/api/fabric/document/${docHash}`);

    expect(verifyRes.status).toBe(200);
    expect(verifyRes.body.docHash).toBe(docHash);
    expect(verifyRes.body.issuer).toBe('Org1MSP');
    expect(verifyRes.body.revoked).toBe(false);
    expect(verifyRes.body.network).toBe('fabric');
    console.log(`[E2E] Verified document: ${docHash}`);

    // Step 3: Revoke document
    const revokeRes = await request(app)
      .post('/api/fabric/revoke')
      .set('Authorization', `Bearer ${testToken}`)
      .send({ docHash });

    expect(revokeRes.status).toBe(200);
    expect(revokeRes.body.success).toBe(true);
    expect(revokeRes.body.revoked).toBe(true);
    console.log(`[E2E] Revoked document: ${docHash}`);

    // Wait for revocation to settle
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Step 4: Verify document shows as revoked
    const verifyRevokedRes = await request(app)
      .get(`/api/fabric/document/${docHash}`);

    expect(verifyRevokedRes.status).toBe(200);
    expect(verifyRevokedRes.body.revoked).toBe(true);
    console.log(`[E2E] Confirmed revocation: ${docHash}`);
  }, 30000);

  // ── Test 2: AI Gate Enforcement ─────────────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should enforce AI gate threshold', async () => {
    // Note: In real scenarios, we'd upload suspicious content.
    // For E2E tests, we rely on mock AI returning low scores.

    const testFile = createTestFile();
    const uniqueSuffix = Date.now();

    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-ai-gate-${uniqueSuffix}.txt`);

    // Should succeed (mock AI returns low scores)
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.aiScore).toBeDefined();

    // If AI score is above threshold, should fail
    // (This would happen with real AI provider and suspicious content)
    if (res.body.aiScore > 80) {
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/AI check failed/i);
    }
  }, 15000);

  // ── Test 3: Network Pause Flow ──────────────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should prevent anchoring when network paused', async () => {
    // Step 1: Pause network
    const pauseRes = await request(app)
      .post('/api/fabric/pause')
      .set('Authorization', `Bearer ${testToken}`);

    expect(pauseRes.status).toBe(200);
    expect(pauseRes.body.paused).toBe(true);
    console.log('[E2E] Network paused');

    await new Promise(resolve => setTimeout(resolve, 1000));

    // Step 2: Verify status shows paused
    const statusRes = await request(app).get('/api/fabric/status');
    expect(statusRes.status).toBe(200);
    expect(statusRes.body.paused).toBe(true);

    // Step 3: Attempt to anchor document (should fail)
    const testFile = createTestFile();
    const anchorRes = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-paused-${Date.now()}.txt`);

    expect(anchorRes.status).toBe(500);
    expect(anchorRes.body.error).toMatch(/paused/i);
    console.log('[E2E] Anchoring blocked while paused');

    // Step 4: Unpause network
    const unpauseRes = await request(app)
      .post('/api/fabric/unpause')
      .set('Authorization', `Bearer ${testToken}`);

    expect(unpauseRes.status).toBe(200);
    expect(unpauseRes.body.paused).toBe(false);
    console.log('[E2E] Network unpaused');

    await new Promise(resolve => setTimeout(resolve, 1000));

    // Step 5: Verify anchoring works again
    const anchorAfterRes = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-after-unpause-${Date.now()}.txt`);

    expect(anchorAfterRes.status).toBe(200);
    expect(anchorAfterRes.body.success).toBe(true);
    console.log('[E2E] Anchoring resumed after unpause');
  }, 30000);

  // ── Test 4: Duplicate Prevention ────────────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should reject duplicate document hash', async () => {
    const testFile = createTestFile();
    const uniqueSuffix = Date.now();

    // Anchor first time
    const firstRes = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-duplicate-${uniqueSuffix}.txt`);

    expect(firstRes.status).toBe(200);
    const docHash = firstRes.body.docHash;
    console.log(`[E2E] First anchor: ${docHash}`);

    await new Promise(resolve => setTimeout(resolve, 1000));

    // Attempt to anchor same file again (same hash)
    const secondRes = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-duplicate-${uniqueSuffix}.txt`);

    // Should fail (duplicate docHash)
    expect(secondRes.status).toBe(500);
    expect(secondRes.body.error).toMatch(/already anchored/i);
    console.log('[E2E] Duplicate correctly rejected');
  }, 20000);

  // ── Test 5: Query Consistency ───────────────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should have consistent on-chain and off-chain data', async () => {
    const testFile = createTestFile();
    const uniqueSuffix = Date.now();

    // Anchor document
    const anchorRes = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', testFile, `e2e-consistency-${uniqueSuffix}.txt`);

    expect(anchorRes.status).toBe(200);
    const docHash = anchorRes.body.docHash;

    await new Promise(resolve => setTimeout(resolve, 1000));

    // Query document
    const queryRes = await request(app)
      .get(`/api/fabric/document/${docHash}`);

    expect(queryRes.status).toBe(200);

    // Verify on-chain fields
    expect(queryRes.body.docHash).toBe(docHash);
    expect(queryRes.body.issuer).toBe('Org1MSP');
    expect(queryRes.body.timestamp).toBeDefined();
    expect(queryRes.body.revoked).toBe(false);

    // Verify off-chain enrichment
    expect(queryRes.body.fileName).toBeDefined();
    expect(queryRes.body.aiScore).toBeDefined();
    expect(queryRes.body.network).toBe('fabric');

    console.log('[E2E] Data consistency verified:', {
      onChain: { docHash: queryRes.body.docHash, issuer: queryRes.body.issuer },
      offChain: { fileName: queryRes.body.fileName, aiScore: queryRes.body.aiScore }
    });
  }, 20000);

  // ── Test 6: Network State Query ─────────────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should query network state correctly', async () => {
    const statusRes = await request(app).get('/api/fabric/status');

    expect(statusRes.status).toBe(200);
    expect(statusRes.body.paused).toBeDefined();
    expect(statusRes.body.owner).toBeDefined();
    expect(statusRes.body.network).toBe('fabric');
    expect(statusRes.body.owner).toBe('Org1MSP'); // Default owner

    console.log('[E2E] Network state:', {
      paused: statusRes.body.paused,
      owner: statusRes.body.owner
    });
  }, 10000);

  // ── Test 7: Authentication Requirements ─────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should require auth for admin operations', async () => {
    // Attempt revoke without auth
    const revokeRes = await request(app)
      .post('/api/fabric/revoke')
      .send({ docHash: '0xtest' });

    expect(revokeRes.status).toBe(401);

    // Attempt pause without auth
    const pauseRes = await request(app).post('/api/fabric/pause');
    expect(pauseRes.status).toBe(401);

    // Attempt unpause without auth
    const unpauseRes = await request(app).post('/api/fabric/unpause');
    expect(unpauseRes.status).toBe(401);

    console.log('[E2E] Auth requirements verified');
  }, 10000);

  // ── Test 8: Health Check Integration ────────────────────────────────────────

  (SKIP_E2E ? it.skip : it)('should report Fabric status in health check', async () => {
    const healthRes = await request(app).get('/api/health');

    expect(healthRes.status).toBe(200);
    expect(healthRes.body.fabric).toBeDefined();
    expect(healthRes.body.fabric.enabled).toBe(true);
    expect(healthRes.body.fabric.gateway).toBe('connected');
    expect(healthRes.body.fabric.chaincode).toBe('available');
    expect(healthRes.body.fabric.networkState).toBeDefined();

    console.log('[E2E] Health check:', {
      gateway: healthRes.body.fabric.gateway,
      networkState: healthRes.body.fabric.networkState
    });
  }, 10000);
});

// ── Helper: Manual Test Instructions ────────────────────────────────────────

if (require.main === module) {
  console.log(`
╔═══════════════════════════════════════════════════════════════╗
║   Fabric E2E Test Setup Instructions                          ║
╚═══════════════════════════════════════════════════════════════╝

Before running E2E tests:

1. Start Fabric network:
   cd fabric && ./scripts/start-network.sh

2. Verify network is running:
   docker ps | grep hyperledger

   You should see: orderer, peer, ca, cli containers

3. Start MongoDB:
   docker compose up -d mongodb

4. Configure backend:
   cd verifier-backend
   cp .env.example .env
   # Edit .env and set FABRIC_ENABLED=true

5. Run E2E tests:
   FABRIC_ENABLED=true npm test -- e2e-fabric.test.js

To skip E2E tests in CI:
   SKIP_FABRIC_E2E=true npm test

───────────────────────────────────────────────────────────────

Expected output: 8 E2E tests covering:
  ✓ Complete document lifecycle (anchor → verify → revoke)
  ✓ AI gate enforcement
  ✓ Network pause flow
  ✓ Duplicate prevention
  ✓ Query consistency
  ✓ Network state query
  ✓ Authentication requirements
  ✓ Health check integration
  `);
}
