// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DocVerifier {
    struct Document {
        address issuer;
        uint256 timestamp;
        string ipfsHash; // Optional: If you use IPFS later
    }

    // Maps the File Hash (SHA-256) to the Document Data
    mapping(bytes32 => Document) public documents;

    event DocumentAnchored(bytes32 indexed docHash, address indexed issuer);

    // 1. Anchoring Function
    function anchorDocument(bytes32 _docHash, string memory _ipfsHash) public {
        require(documents[_docHash].timestamp == 0, "Document already verified.");
        
        documents[_docHash] = Document({
            issuer: msg.sender,
            timestamp: block.timestamp,
            ipfsHash: _ipfsHash
        });

        emit DocumentAnchored(_docHash, msg.sender);
    }

    // 2. Verification Function
    function verifyDocument(bytes32 _docHash) public view returns (address, uint256, string memory) {
        require(documents[_docHash].timestamp != 0, "Document not found.");
        Document memory doc = documents[_docHash];
        return (doc.issuer, doc.timestamp, doc.ipfsHash);
    }
}