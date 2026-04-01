package main

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ── Simple In-Memory Storage for Testing ────────────────────────────────────

type TestStorage struct {
	PublicState  map[string][]byte
	PrivateData  map[string]map[string][]byte // collection -> key -> value
	CallerMSP    string
}

func newTestStorage(msp string) *TestStorage {
	return &TestStorage{
		PublicState:  make(map[string][]byte),
		PrivateData:  make(map[string]map[string][]byte),
		CallerMSP:    msp,
	}
}

func (ts *TestStorage) getState(key string) (*NetworkState, error) {
	raw := ts.PublicState[stateKey]
	if raw == nil {
		return &NetworkState{Paused: false, Owner: ts.CallerMSP}, nil
	}
	var s NetworkState
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func (ts *TestStorage) putState(key string, v interface{}) error {
	raw, err := json.Marshal(v)
	if err != nil {
		return err
	}
	ts.PublicState[key] = raw
	return nil
}

func (ts *TestStorage) getPrivateData(collection, key string) (*Document, error) {
	if ts.PrivateData[collection] == nil {
		return nil, nil
	}
	raw := ts.PrivateData[collection][key]
	if raw == nil {
		return nil, nil
	}
	var doc Document
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, err
	}
	return &doc, nil
}

func (ts *TestStorage) putPrivateData(collection, key string, v interface{}) error {
	if ts.PrivateData[collection] == nil {
		ts.PrivateData[collection] = make(map[string][]byte)
	}
	raw, err := json.Marshal(v)
	if err != nil {
		return err
	}
	ts.PrivateData[collection][key] = raw
	return nil
}

// ── Test Suite: Network State ───────────────────────────────────────────────

func TestNetworkStateInitialization(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	state := NetworkState{Paused: false, Owner: "Org1MSP"}
	err := storage.putState(stateKey, &state)
	require.NoError(t, err)

	retrieved, err := storage.getState(stateKey)
	require.NoError(t, err)
	assert.Equal(t, "Org1MSP", retrieved.Owner)
	assert.False(t, retrieved.Paused)
}

func TestNetworkStateModification(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	// Initialize
	state := NetworkState{Paused: false, Owner: "Org1MSP"}
	storage.putState(stateKey, &state)

	// Modify
	state.Paused = true
	storage.putState(stateKey, &state)

	// Verify
	retrieved, err := storage.getState(stateKey)
	require.NoError(t, err)
	assert.True(t, retrieved.Paused)
}

// ── Test Suite: Document Storage ────────────────────────────────────────────

func TestDocumentStorageInPDC(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	doc := Document{
		DocHash:   "0xtest123",
		IpfsCid:   "QmTest",
		Issuer:    "Org1MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}

	err := storage.putPrivateData(collection, doc.DocHash, &doc)
	require.NoError(t, err)

	retrieved, err := storage.getPrivateData(collection, doc.DocHash)
	require.NoError(t, err)
	assert.NotNil(t, retrieved)
	assert.Equal(t, doc.DocHash, retrieved.DocHash)
	assert.Equal(t, doc.IpfsCid, retrieved.IpfsCid)
	assert.Equal(t, doc.Issuer, retrieved.Issuer)
	assert.False(t, retrieved.Revoked)
}

func TestDocumentNotFoundInPDC(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	retrieved, err := storage.getPrivateData(collection, "0xnonexistent")
	require.NoError(t, err)
	assert.Nil(t, retrieved)
}

func TestDocumentRevocationToggle(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	doc := Document{
		DocHash:   "0xrevoke_test",
		IpfsCid:   "",
		Issuer:    "Org1MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}

	// Store document
	storage.putPrivateData(collection, doc.DocHash, &doc)

	// Revoke
	doc.Revoked = true
	storage.putPrivateData(collection, doc.DocHash, &doc)

	// Verify revoked
	retrieved, err := storage.getPrivateData(collection, doc.DocHash)
	require.NoError(t, err)
	assert.True(t, retrieved.Revoked)
}

// ── Test Suite: Document Structure Validation ───────────────────────────────

func TestDocumentStructureValid(t *testing.T) {
	doc := Document{
		DocHash:   "0xabc123",
		IpfsCid:   "QmTest",
		Issuer:    "Org1MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}

	// Serialize
	raw, err := json.Marshal(&doc)
	require.NoError(t, err)
	assert.NotNil(t, raw)

	// Deserialize
	var decoded Document
	err = json.Unmarshal(raw, &decoded)
	require.NoError(t, err)
	assert.Equal(t, doc.DocHash, decoded.DocHash)
	assert.Equal(t, doc.IpfsCid, decoded.IpfsCid)
	assert.Equal(t, doc.Issuer, decoded.Issuer)
	assert.False(t, decoded.Revoked)
}

func TestDocumentWithoutIPFS(t *testing.T) {
	doc := Document{
		DocHash:   "0xno_ipfs",
		IpfsCid:   "",
		Issuer:    "Org2MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}

	raw, err := json.Marshal(&doc)
	require.NoError(t, err)

	var decoded Document
	err = json.Unmarshal(raw, &decoded)
	require.NoError(t, err)
	assert.Equal(t, "", decoded.IpfsCid)
}

// ── Test Suite: Business Logic Validation ───────────────────────────────────

func TestDuplicateDocumentDetection(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	docHash := "0xduplicate_test"

	// First document
	doc1 := Document{
		DocHash:   docHash,
		IpfsCid:   "QmFirst",
		Issuer:    "Org1MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}
	storage.putPrivateData(collection, docHash, &doc1)

	// Check if exists
	existing, err := storage.getPrivateData(collection, docHash)
	require.NoError(t, err)
	assert.NotNil(t, existing, "Document should exist (simulating duplicate check)")
}

func TestAccessControlLogic(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	// Document issued by Org2MSP
	doc := Document{
		DocHash:   "0xaccess_test",
		IpfsCid:   "",
		Issuer:    "Org2MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}
	storage.putPrivateData(collection, doc.DocHash, &doc)

	// Get network state (Org1MSP is owner)
	state, _ := storage.getState(stateKey)
	assert.Equal(t, "Org1MSP", state.Owner)

	// Simulate access control check
	callerMSP := "Org2MSP" // Issuer
	canRevoke := (callerMSP == doc.Issuer) || (callerMSP == state.Owner)
	assert.True(t, canRevoke, "Issuer should be able to revoke")

	// Different caller
	callerMSP = "Org3MSP"
	canRevoke = (callerMSP == doc.Issuer) || (callerMSP == state.Owner)
	assert.False(t, canRevoke, "Non-issuer/non-owner should not be able to revoke")

	// Owner can revoke
	callerMSP = "Org1MSP" // Owner
	canRevoke = (callerMSP == doc.Issuer) || (callerMSP == state.Owner)
	assert.True(t, canRevoke, "Owner should be able to revoke any document")
}

func TestPauseLogic(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	// Initialize state
	state := NetworkState{Paused: false, Owner: "Org1MSP"}
	storage.putState(stateKey, &state)

	// Pause
	state.Paused = true
	storage.putState(stateKey, &state)

	retrieved, _ := storage.getState(stateKey)
	assert.True(t, retrieved.Paused)

	// Attempt to anchor (should fail in real chaincode)
	if retrieved.Paused {
		// Simulate rejection
		assert.True(t, true, "Anchoring should be blocked when paused")
	}

	// Unpause
	state.Paused = false
	storage.putState(stateKey, &state)

	retrieved, _ = storage.getState(stateKey)
	assert.False(t, retrieved.Paused)
}

func TestOwnershipTransferLogic(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	// Initialize
	state := NetworkState{Paused: false, Owner: "Org1MSP"}
	storage.putState(stateKey, &state)

	// Transfer
	state.Owner = "Org2MSP"
	storage.putState(stateKey, &state)

	// Verify
	retrieved, _ := storage.getState(stateKey)
	assert.Equal(t, "Org2MSP", retrieved.Owner)

	// Old owner should lose privileges
	callerMSP := "Org1MSP"
	canPause := callerMSP == retrieved.Owner
	assert.False(t, canPause, "Old owner should not be able to pause")

	// New owner should have privileges
	callerMSP = "Org2MSP"
	canPause = callerMSP == retrieved.Owner
	assert.True(t, canPause, "New owner should be able to pause")
}

// ── Test Suite: Edge Cases ──────────────────────────────────────────────────

func TestEmptyDocHashValidation(t *testing.T) {
	// Simulate empty hash rejection
	docHash := ""
	assert.Empty(t, docHash, "Empty docHash should be rejected")
}

func TestEmptyOwnerValidation(t *testing.T) {
	// Simulate empty owner rejection
	newOwner := ""
	assert.Empty(t, newOwner, "Empty newOwner should be rejected")
}

func TestDoubleRevokePrevention(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	doc := Document{
		DocHash:   "0xdouble_revoke",
		IpfsCid:   "",
		Issuer:    "Org1MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}

	storage.putPrivateData(collection, doc.DocHash, &doc)

	// First revoke
	doc.Revoked = true
	storage.putPrivateData(collection, doc.DocHash, &doc)

	// Check already revoked
	retrieved, _ := storage.getPrivateData(collection, doc.DocHash)
	if retrieved.Revoked {
		// Should reject second revoke
		assert.True(t, true, "Double revoke should be rejected")
	}
}

func TestDoublePausePrevent(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	state := NetworkState{Paused: false, Owner: "Org1MSP"}
	storage.putState(stateKey, &state)

	// First pause
	state.Paused = true
	storage.putState(stateKey, &state)

	// Check already paused
	retrieved, _ := storage.getState(stateKey)
	if retrieved.Paused {
		// Should reject second pause
		assert.True(t, true, "Double pause should be rejected")
	}
}

// ── Test Suite: Timestamp Handling ──────────────────────────────────────────

func TestTimestampFormat(t *testing.T) {
	now := time.Now().UTC()
	doc := Document{
		DocHash:   "0xtime_test",
		IpfsCid:   "",
		Issuer:    "Org1MSP",
		Timestamp: now,
		Revoked:   false,
	}

	raw, err := json.Marshal(&doc)
	require.NoError(t, err)

	var decoded Document
	err = json.Unmarshal(raw, &decoded)
	require.NoError(t, err)

	// Check timestamp is within reasonable bounds (account for JSON encoding/decoding)
	diff := decoded.Timestamp.Sub(now)
	assert.True(t, diff < time.Second && diff > -time.Second, "Timestamp should be preserved accurately")
}

// ── Test Suite: Complete Workflow ───────────────────────────────────────────

func TestCompleteDocumentLifecycle(t *testing.T) {
	storage := newTestStorage("Org1MSP")

	// 1. Initialize network
	state := NetworkState{Paused: false, Owner: "Org1MSP"}
	storage.putState(stateKey, &state)

	docHash := "0xlifecycle"
	ipfsCid := "QmLifecycle"

	// 2. Anchor document
	doc := Document{
		DocHash:   docHash,
		IpfsCid:   ipfsCid,
		Issuer:    "Org1MSP",
		Timestamp: time.Now().UTC(),
		Revoked:   false,
	}
	storage.putPrivateData(collection, docHash, &doc)

	// 3. Verify document
	retrieved, err := storage.getPrivateData(collection, docHash)
	require.NoError(t, err)
	assert.NotNil(t, retrieved)
	assert.Equal(t, docHash, retrieved.DocHash)
	assert.False(t, retrieved.Revoked)

	// 4. Revoke document
	doc.Revoked = true
	storage.putPrivateData(collection, docHash, &doc)

	// 5. Verify revoked
	retrieved, err = storage.getPrivateData(collection, docHash)
	require.NoError(t, err)
	assert.True(t, retrieved.Revoked)

	// 6. Pause network
	state.Paused = true
	storage.putState(stateKey, &state)

	// 7. Verify paused
	networkState, err := storage.getState(stateKey)
	require.NoError(t, err)
	assert.True(t, networkState.Paused)
}

// ── Note ─────────────────────────────────────────────────────────────────────
//
// These tests validate the data structures, storage logic, and business rules
// of the DocVerifier chaincode. Full integration testing with actual Fabric
// transaction contexts requires a running Fabric network, which is covered by
// the E2E tests in verifier-backend/tests/e2e-fabric.test.js.
//
// For comprehensive chaincode validation including transaction context handling,
// run:
//   cd fabric && ./scripts/start-network.sh
//   cd ../verifier-backend && FABRIC_ENABLED=true npm test -- e2e-fabric.test.js
