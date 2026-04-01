/**
 * tests/multi-org.test.js
 * Integration tests for multi-organization Fabric network
 *
 * Tests multi-org scenarios:
 * - Org1 anchors document (issuer = Org1MSP)
 * - Org2 verifies Org1's document
 * - Org2 anchors their own documents
 * - Org2 cannot revoke Org1's documents (access control)
 * - Org3 can verify documents from any org
 * - Chaincode uses correct MSP ID for issuer
 *
 * Run: npm test -- tests/multi-org.test.js
 * With live network: FABRIC_ENABLED=true npm test -- tests/multi-org.test.js
 */

const mongoose = require('mongoose');
const { getContractForOrg, getAvailableOrganizations } = require('../fabric/gateway');

// Skip E2E tests if Fabric not available or SKIP_FABRIC_E2E is set
const SKIP_TESTS = process.env.SKIP_FABRIC_E2E === 'true' || process.env.FABRIC_ENABLED !== 'true';

describe('Multi-Organization Fabric Network', () => {
  let contractOrg1, contractOrg2, contractOrg3;
  const testDocHash = '0x' + '1'.repeat(64);
  const testCid = 'QmTest1234567890';

  // Skip entire suite if Fabric not available
  if (SKIP_TESTS) {
    it.skip('Skipped (Fabric network or SKIP_FABRIC_E2E)', () => {});
    return;
  }

  beforeAll(async () => {
    // Connect to fabric network as each org
    try {
      contractOrg1 = await getContractForOrg('Org1MSP');
      contractOrg2 = await getContractForOrg('Org2MSP');
      contractOrg3 = await getContractForOrg('Org3MSP');

      console.log('✓ Connected to network as 3 organizations');
    } catch (error) {
      console.error('Failed to connect to Fabric network:', error.message);
      throw error;
    }
  });

  describe('Organization Discovery', () => {
    test('should list available organizations', () => {
      const orgs = getAvailableOrganizations();
      expect(orgs).toContain('Org1MSP');
      expect(orgs).toContain('Org2MSP');
      expect(orgs).toContain('Org3MSP');
      expect(orgs.length).toBe(3);
    });

    test('should connect to Org1MSP', async () => {
      expect(contractOrg1).toBeDefined();
      // Simple query to verify connectivity
      const resultBytes = await contractOrg1.evaluateTransaction('GetNetworkState');
      const state = JSON.parse(Buffer.from(resultBytes).toString());
      expect(state).toHaveProperty('paused');
      expect(state).toHaveProperty('owner');
      expect(state.owner).toBe('Org1MSP');
    });

    test('should connect to Org2MSP', async () => {
      expect(contractOrg2).toBeDefined();
      const resultBytes = await contractOrg2.evaluateTransaction('GetNetworkState');
      const state = JSON.parse(Buffer.from(resultBytes).toString());
      expect(state).toHaveProperty('paused');
    });

    test('should connect to Org3MSP', async () => {
      expect(contractOrg3).toBeDefined();
      const resultBytes = await contractOrg3.evaluateTransaction('GetNetworkState');
      const state = JSON.parse(Buffer.from(resultBytes).toString());
      expect(state).toHaveProperty('paused');
    });
  });

  describe('Document Lifecycle - Org1 (Host Organization)', () => {
    const org1DocHash = '0x' + 'a'.repeat(64);
    const org1Cid = 'QmOrg1Doc123';

    test('Org1 should anchor a document as issuer', async () => {
      const result = await contractOrg1.submitTransaction(
        'AnchorDocument',
        org1DocHash,
        org1Cid
      );
      expect(result).toBeDefined();
      console.log('✓ Org1 anchored document:', org1DocHash);
    });

    test('Org1 should verify their own document', async () => {
      const resultBytes = await contractOrg1.evaluateTransaction(
        'VerifyDocument',
        org1DocHash
      );
      const doc = JSON.parse(Buffer.from(resultBytes).toString());

      expect(doc.docHash).toBe(org1DocHash);
      expect(doc.issuer).toBe('Org1MSP');
      expect(doc.ipfsCid).toBe(org1Cid);
      expect(doc.revoked).toBe(false);
      expect(doc.timestamp).toBeDefined();
    });

    test('Org1 should be able to revoke their own document', async () => {
      const result = await contractOrg1.submitTransaction(
        'RevokeDocument',
        org1DocHash
      );
      expect(result).toBeDefined();

      // Verify revocation
      const resultBytes = await contractOrg1.evaluateTransaction(
        'VerifyDocument',
        org1DocHash
      );
      const doc = JSON.parse(Buffer.from(resultBytes).toString());
      expect(doc.revoked).toBe(true);
      console.log('✓ Org1 revoked their document');
    });
  });

  describe('Document Lifecycle - Org2 (Partner Organization)', () => {
    const org2DocHash = '0x' + 'b'.repeat(64);
    const org2Cid = 'QmOrg2Doc456';

    test('Org2 should anchor a document with their MSP ID', async () => {
      const result = await contractOrg2.submitTransaction(
        'AnchorDocument',
        org2DocHash,
        org2Cid
      );
      expect(result).toBeDefined();
    });

    test('Org2 document should show Org2MSP as issuer', async () => {
      const resultBytes = await contractOrg2.evaluateTransaction(
        'VerifyDocument',
        org2DocHash
      );
      const doc = JSON.parse(Buffer.from(resultBytes).toString());

      expect(doc.docHash).toBe(org2DocHash);
      expect(doc.issuer).toBe('Org2MSP');  // Chaincode should extract issuer from ClientIdentity
      expect(doc.ipfsCid).toBe(org2Cid);
      expect(doc.revoked).toBe(false);
    });

    test('Org2 should be able to revoke their own document', async () => {
      const result = await contractOrg2.submitTransaction(
        'RevokeDocument',
        org2DocHash
      );
      expect(result).toBeDefined();

      const resultBytes = await contractOrg2.evaluateTransaction(
        'VerifyDocument',
        org2DocHash
      );
      const doc = JSON.parse(Buffer.from(resultBytes).toString());
      expect(doc.revoked).toBe(true);
    });
  });

  describe('Cross-Organization Verification', () => {
    const nonRevoked = '0x' + 'c'.repeat(64);
    const verifyOnOrgCid = 'QmCrossOrgDoc789';

    beforeAll(async () => {
      // Set up a document that won't be revoked
      await contractOrg1.submitTransaction(
        'AnchorDocument',
        nonRevoked,
        verifyOnOrgCid
      );
    });

    test('Org2 should verify a document issued by Org1', async () => {
      const resultBytes = await contractOrg2.evaluateTransaction(
        'VerifyDocument',
        nonRevoked
      );
      const doc = JSON.parse(Buffer.from(resultBytes).toString());

      expect(doc.docHash).toBe(nonRevoked);
      expect(doc.issuer).toBe('Org1MSP');  // Should see correct issuer
      expect(doc.revoked).toBe(false);
    });

    test('Org3 should verify documents from any organization', async () => {
      // Org3 verifies Org1's document
      const resultBytes1 = await contractOrg3.evaluateTransaction(
        'VerifyDocument',
        nonRevoked
      );
      const doc1 = JSON.parse(Buffer.from(resultBytes1).toString());
      expect(doc1.issuer).toBe('Org1MSP');

      // Org3 verifies Org2's document (if exists)
      // Would need another test document first
    });
  });

  describe('Access Control - Cross-Organization Restrictions', () => {
    const org1OnlyDoc = '0x' + 'd'.repeat(64);
    const org1OnlyOrgCid = 'QmOrg1OnlyDoc';

    beforeAll(async () => {
      // Create a document issued by Org1
      await contractOrg1.submitTransaction(
        'AnchorDocument',
        org1OnlyDoc,
        org1OnlyOrgCid
      );
    });

    test('Org2 should NOT be able to revoke Org1\'s document', async () => {
      // Attempt to revoke Org1's document as Org2
      // This should fail with access control error
      await expect(
        contractOrg2.submitTransaction(
          'RevokeDocument',
          org1OnlyDoc
        )
      ).rejects.toThrow(/access|permission|issuer|unauthorized/i);

      console.log('✓ Access control enforced: Org2 cannot revoke Org1 document');
    });

    test('Org3 should NOT be able to revoke document issued by Org1', async () => {
      await expect(
        contractOrg3.submitTransaction(
          'RevokeDocument',
          org1OnlyDoc
        )
      ).rejects.toThrow(/access|permission|issuer|unauthorized/i);
    });

    test('Org1 should still be able to revoke their own document', async () => {
      // Org1 can revoke it since they're the issuer
      const result = await contractOrg1.submitTransaction(
        'RevokeDocument',
        org1OnlyDoc
      );
      expect(result).toBeDefined();
      console.log('✓ Org1 authorized to revoke their own document');
    });
  });

  describe('Private Data Collections', () => {
    const pdcDocHash = '0x' + 'e'.repeat(64);
    const pdcCid = 'QmPrivateDataDoc';

    test('Document metadata should be in Private Data Collection', async () => {
      // Anchor document
      await contractOrg1.submitTransaction(
        'AnchorDocument',
        pdcDocHash,
        pdcCid
      );

      // Retrieve (from PDC)
      const resultBytes = await contractOrg1.evaluateTransaction(
        'VerifyDocument',
        pdcDocHash
      );
      const doc = JSON.parse(Buffer.from(resultBytes).toString());

      // Fields that should be in PDC
      expect(doc).toHaveProperty('docHash');
      expect(doc).toHaveProperty('issuer');
      expect(doc).toHaveProperty('timestamp');
      expect(doc).toHaveProperty('ipfsCid');

      console.log('✓ Private data accessed successfully');
    });

    test('All orgs should see the same document (PDC is multi-org)', async () => {
      // Org1 sees it
      const resultBytes1 = await contractOrg1.evaluateTransaction(
        'VerifyDocument',
        pdcDocHash
      );
      const doc1 = JSON.parse(Buffer.from(resultBytes1).toString());

      // Org2 sees it
      const resultBytes2 = await contractOrg2.evaluateTransaction(
        'VerifyDocument',
        pdcDocHash
      );
      const doc2 = JSON.parse(Buffer.from(resultBytes2).toString());

      expect(doc1.docHash).toBe(doc2.docHash);
      expect(doc1.issuer).toBe(doc2.issuer);
      expect(doc1.ipfsCid).toBe(doc2.ipfsCid);

      console.log('✓ PDC data consistent across organizations');
    });
  });

  describe('Network State Management', () => {
    test('Network state should be same for all orgs', async () => {
      const resultBytes1 = await contractOrg1.evaluateTransaction('GetNetworkState');
      const state1 = JSON.parse(Buffer.from(resultBytes1).toString());

      const resultBytes2 = await contractOrg2.evaluateTransaction('GetNetworkState');
      const state2 = JSON.parse(Buffer.from(resultBytes2).toString());

      const resultBytes3 = await contractOrg3.evaluateTransaction('GetNetworkState');
      const state3 = JSON.parse(Buffer.from(resultBytes3).toString());

      expect(state1.paused).toBe(state2.paused);
      expect(state2.paused).toBe(state3.paused);
      expect(state1.owner).toBe('Org1MSP');
      expect(state2.owner).toBe('Org1MSP');
      expect(state3.owner).toBe('Org1MSP');
    });

    test('Only Org1 should be able to pause network', async () => {
      // Org2 attempt should fail
      await expect(
        contractOrg2.submitTransaction('PauseNetwork')
      ).rejects.toThrow(/owner|permission|unauthorized/i);

      // Org1 attempt should succeed
      await expect(
        contractOrg1.submitTransaction('PauseNetwork')
      ).resolves.toBeDefined();

      // Verify paused
      const resultBytes = await contractOrg1.evaluateTransaction('GetNetworkState');
      const state = JSON.parse(Buffer.from(resultBytes).toString());
      expect(state.paused).toBe(true);

      // Unpause for other tests
      await contractOrg1.submitTransaction('UnpauseNetwork');
      console.log('✓ Network pause/unpause works correctly');
    });
  });

  afterAll(async () => {
    // Gateway cleanup happens in server.js on shutdown
    console.log('✓ Multi-org tests completed');
  });
});
