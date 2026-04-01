'use strict';
/**
 * Integration tests for Fabric routes (verifier-backend/fabric/fabricRoutes.js)
 *
 * Strategy: Mock @hyperledger/fabric-gateway, mongoose, axios, pdf-parse
 * Use supertest to drive Express app in-process
 *
 * Tests cover:
 *   - POST /api/fabric/analyze (AI gate, chaincode, MongoDB)
 *   - GET  /api/fabric/document/:hash (chaincode + MongoDB)
 *   - POST /api/fabric/revoke (requires auth)
 *   - POST /api/fabric/pause (requires auth)
 *   - POST /api/fabric/unpause (requires auth)
 *   - GET  /api/fabric/status (network state)
 */

// ── Mock dependencies BEFORE requiring server ────────────────────────────────

// 1. Mock @hyperledger/fabric-gateway
const mockContract = {
  submitTransaction: jest.fn(),
  evaluateTransaction: jest.fn()
};

const mockNetwork = {
  getContract: jest.fn(() => mockContract)
};

const mockGateway = {
  getNetwork: jest.fn(() => mockNetwork),
  close: jest.fn()
};

jest.mock('@hyperledger/fabric-gateway', () => ({
  connect: jest.fn(() => mockGateway),
  signers: {
    newPrivateKeySigner: jest.fn(() => ({}))
  }
}));

//2. Mock mongoose (same as server.test.js)
jest.mock('mongoose', () => {
  const mockDoc = {
    fileName: 'test.png',
    aiScore: 5,
    aiProvider: 'mock',
    aiDetails: null,
    isAuthentic: true,
    ipfsCid: null,
    network: 'fabric',
    createdAt: new Date('2025-01-01')
  };

  const mockModel = {
    findOneAndUpdate: jest.fn().mockResolvedValue(mockDoc),
    findOne: jest.fn().mockResolvedValue(mockDoc)
  };

  const SchemaClass = class Schema {
    constructor() {}
    index() { return this; }
  };
  SchemaClass.Types = { Mixed: {} };

  return {
    connect: jest.fn().mockResolvedValue({}),
    Schema: SchemaClass,
    model: jest.fn().mockReturnValue(mockModel),
    models: {},
    connection: { readyState: 1, host: 'mock-host', name: 'docverifier' }
  };
});

// 3. Mock axios (AI and IPFS calls)
jest.mock('axios');
const axios = require('axios');

// 4. Mock pdf-parse
jest.mock('pdf-parse', () => jest.fn().mockResolvedValue({
  text: 'Sample PDF content for AI testing purposes.'
}));

// Set Fabric environment variable
process.env.FABRIC_ENABLED = 'true';
process.env.FABRIC_CHANNEL = 'mychannel';
process.env.FABRIC_CHAINCODE = 'docverifier';
process.env.FABRIC_PEER_ENDPOINT = 'localhost:7051';
process.env.JWT_SECRET = 'test-secret';
process.env.ADMIN_PASSWORD = 'test-password';

const request = require('supertest');
const app = require('../server');

// Helper: create fake file buffer
const PNG_HEADER = Buffer.from([0x89, 0x50, 0x4e, 0x47]);

// Helper: generate JWT token for authenticated requests
const jwt = require('jsonwebtoken');
function generateTestToken() {
  return jwt.sign({ username: 'admin' }, process.env.JWT_SECRET, { expiresIn: '1h' });
}

// ── Test Suite: POST /api/fabric/analyze ────────────────────────────────────

describe('POST /api/fabric/analyze', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    // Default: AI returns low score (authenticated)
    axios.post = jest.fn().mockResolvedValue({
      data: { score: 5, provider: 'mock' }
    });

    // Default: chaincode submitTransaction succeeds
    mockContract.submitTransaction.mockResolvedValue(Buffer.from('{}'));
  });

  it('returns 400 when no file uploaded', async () => {
    const res = await request(app).post('/api/fabric/analyze');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/no file/i);
  });

  it('anchors document in mock mode successfully', async () => {
    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'test.png');

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.docHash).toMatch(/^0x[a-f0-9]{64}$/);
    expect(res.body.aiScore).toBe(5);
    expect(res.body.network).toBe('fabric');
  });

  it('calls AnchorDocument chaincode with correct parameters', async () => {
    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'test.png');

    expect(res.status).toBe(200);
    expect(mockContract.submitTransaction).toHaveBeenCalledWith(
      'AnchorDocument',
      expect.stringMatching(/^0x[a-f0-9]{64}$/),
      expect.any(String) // ipfsCid (empty in mock mode)
    );
  });

  it('blocks content above AI threshold', async () => {
    // Mock high AI score
    axios.post = jest.fn().mockResolvedValue({
      data: { score: 95, provider: 'mock' }
    });

    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'suspicious.png');

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/AI check failed/i);
    expect(res.body.aiScore).toBe(95);
    expect(mockContract.submitTransaction).not.toHaveBeenCalled();
  });

  it('stores metadata in MongoDB with network=fabric', async () => {
    const mongoose = require('mongoose');
    const DocModel = mongoose.model('Document');

    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'test.png');

    expect(res.status).toBe(200);
    expect(DocModel.findOneAndUpdate).toHaveBeenCalled();

    // Check that network='fabric' was passed
    const updateCall = DocModel.findOneAndUpdate.mock.calls[0];
    const updateData = updateCall[1];
    expect(updateData.network).toBe('fabric');
  });

  it('returns IPFS CID when pinning is configured', async () => {
    // Mock IPFS pinning
    axios.post = jest.fn()
      .mockResolvedValueOnce({ data: { score: 5, provider: 'mock' } }) // AI check
      .mockResolvedValueOnce({ data: { IpfsHash: 'QmTest123' } }); // IPFS pin

    process.env.PINATA_API_KEY = 'test-key';
    process.env.PINATA_SECRET_KEY = 'test-secret';

    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'test.png');

    expect(res.status).toBe(200);
    expect(res.body.ipfsCid).toMatch(/Qm/);

    // Cleanup
    delete process.env.PINATA_API_KEY;
    delete process.env.PINATA_SECRET_KEY;
  });

  it('handles chaincode errors gracefully', async () => {
    mockContract.submitTransaction.mockRejectedValue(
      new Error('Network is paused; new anchoring is disabled')
    );

    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'test.png');

    expect(res.status).toBe(500);
    expect(res.body.error).toMatch(/paused/i);
  });
});

// ── Test Suite: GET /api/fabric/document/:hash ───────────────────────────────

describe('GET /api/fabric/document/:hash', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns on-chain and off-chain data', async () => {
    const fabricDoc = {
      docHash: '0xabc123',
      issuer: 'Org1MSP',
      timestamp: '2026-03-25T10:00:00Z',
      ipfsCid: 'QmTest',
      revoked: false
    };

    mockContract.evaluateTransaction.mockResolvedValue(
      Buffer.from(JSON.stringify(fabricDoc))
    );

    const res = await request(app).get('/api/fabric/document/0xabc123');

    expect(res.status).toBe(200);
    expect(res.body.docHash).toBe('0xabc123');
    expect(res.body.issuer).toBe('Org1MSP');
    expect(res.body.network).toBe('fabric');
    expect(res.body.fileName).toBe('test.png'); // From MongoDB mock
  });

  it('returns 404 for non-existent document', async () => {
    mockContract.evaluateTransaction.mockRejectedValue(
      new Error('document not found: 0xnonexistent')
    );

    const res = await request(app).get('/api/fabric/document/0xnonexistent');

    expect(res.status).toBe(404);
    expect(res.body.error).toMatch(/not found/i);
  });

  it('handles chaincode errors gracefully', async () => {
    mockContract.evaluateTransaction.mockRejectedValue(
      new Error('Gateway connection failed')
    );

    const res = await request(app).get('/api/fabric/document/0xtest');

    expect(res.status).toBe(500);
    expect(res.body.error).toMatch(/Gateway connection failed/i);
  });

  it('merges on-chain and off-chain data correctly', async () => {
    const fabricDoc = {
      docHash: '0xmerge_test',
      issuer: 'Org2MSP',
      timestamp: '2026-03-25T12:00:00Z',
      ipfsCid: 'QmMerge',
      revoked: true
    };

    mockContract.evaluateTransaction.mockResolvedValue(
      Buffer.from(JSON.stringify(fabricDoc))
    );

    const res = await request(app).get('/api/fabric/document/0xmerge_test');

    expect(res.status).toBe(200);
    // On-chain fields (authoritative)
    expect(res.body.issuer).toBe('Org2MSP');
    expect(res.body.revoked).toBe(true);
    expect(res.body.ipfsCid).toBe('QmMerge');
    // Off-chain enrichment
    expect(res.body.fileName).toBe('test.png');
    expect(res.body.aiScore).toBe(5);
  });
});

// ── Test Suite: POST /api/fabric/revoke ─────────────────────────────────────

describe('POST /api/fabric/revoke', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockContract.submitTransaction.mockResolvedValue(Buffer.from('{}'));
  });

  it('requires JWT authentication', async () => {
    const res = await request(app)
      .post('/api/fabric/revoke')
      .send({ docHash: '0xtest' });

    expect(res.status).toBe(401);
    expect(res.body.error).toMatch(/authentication|token/i);
  });

  it('returns 400 when docHash is missing', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/revoke')
      .set('Authorization', `Bearer ${token}`)
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/docHash/i);
  });

  it('calls RevokeDocument chaincode function', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/revoke')
      .set('Authorization', `Bearer ${token}`)
      .send({ docHash: '0xrevoke_test' });

    expect(res.status).toBe(200);
    expect(mockContract.submitTransaction).toHaveBeenCalledWith(
      'RevokeDocument',
      '0xrevoke_test'
    );
  });

  it('returns success response with revoked=true', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/revoke')
      .set('Authorization', `Bearer ${token}`)
      .send({ docHash: '0xsuccess_test' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.revoked).toBe(true);
    expect(res.body.network).toBe('fabric');
  });

  it('handles chaincode access control errors', async () => {
    mockContract.submitTransaction.mockRejectedValue(
      new Error('only the issuer or owner may revoke a document')
    );

    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/revoke')
      .set('Authorization', `Bearer ${token}`)
      .send({ docHash: '0xaccess_denied' });

    expect(res.status).toBe(500);
    expect(res.body.error).toMatch(/issuer or owner/i);
  });
});

// ── Test Suite: POST /api/fabric/pause ───────────────────────────────────────

describe('POST /api/fabric/pause', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockContract.submitTransaction.mockResolvedValue(Buffer.from('{}'));
  });

  it('requires authentication', async () => {
    const res = await request(app).post('/api/fabric/pause');

    expect(res.status).toBe(401);
  });

  it('calls PauseNetwork chaincode function', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/pause')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(mockContract.submitTransaction).toHaveBeenCalledWith('PauseNetwork');
  });

  it('returns paused=true', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/pause')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.paused).toBe(true);
  });
});

// ── Test Suite: POST /api/fabric/unpause ─────────────────────────────────────

describe('POST /api/fabric/unpause', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockContract.submitTransaction.mockResolvedValue(Buffer.from('{}'));
  });

  it('requires authentication', async () => {
    const res = await request(app).post('/api/fabric/unpause');

    expect(res.status).toBe(401);
  });

  it('calls UnpauseNetwork chaincode function', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/unpause')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(mockContract.submitTransaction).toHaveBeenCalledWith('UnpauseNetwork');
  });

  it('returns paused=false', async () => {
    const token = generateTestToken();

    const res = await request(app)
      .post('/api/fabric/unpause')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.paused).toBe(false);
  });
});

// ── Test Suite: GET /api/fabric/status ───────────────────────────────────────

describe('GET /api/fabric/status', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('calls GetNetworkState chaincode function', async () => {
    const networkState = {
      paused: false,
      owner: 'Org1MSP'
    };

    mockContract.evaluateTransaction.mockResolvedValue(
      Buffer.from(JSON.stringify(networkState))
    );

    const res = await request(app).get('/api/fabric/status');

    expect(res.status).toBe(200);
    expect(mockContract.evaluateTransaction).toHaveBeenCalledWith('GetNetworkState');
  });

  it('returns paused and owner fields', async () => {
    const networkState = {
      paused: true,
      owner: 'Org2MSP'
    };

    mockContract.evaluateTransaction.mockResolvedValue(
      Buffer.from(JSON.stringify(networkState))
    );

    const res = await request(app).get('/api/fabric/status');

    expect(res.status).toBe(200);
    expect(res.body.paused).toBe(true);
    expect(res.body.owner).toBe('Org2MSP');
    expect(res.body.network).toBe('fabric');
  });

  it('handles chaincode errors gracefully', async () => {
    mockContract.evaluateTransaction.mockRejectedValue(
      new Error('Failed to read network state')
    );

    const res = await request(app).get('/api/fabric/status');

    expect(res.status).toBe(500);
    expect(res.body.error).toMatch(/network state/i);
  });
});

// ── Test Suite: Gateway Connection Handling ──────────────────────────────────

describe('Gateway connection resilience', () => {
  it('handles gateway connection failures', async () => {
    const fabricGateway = require('@hyperledger/fabric-gateway');
    fabricGateway.connect.mockRejectedValueOnce(
      new Error('Failed to connect to peer')
    );

    const res = await request(app)
      .post('/api/fabric/analyze')
      .attach('file', PNG_HEADER, 'test.png');

    expect(res.status).toBe(500);
    expect(res.body.error).toMatch(/connect/i);
  });
});
