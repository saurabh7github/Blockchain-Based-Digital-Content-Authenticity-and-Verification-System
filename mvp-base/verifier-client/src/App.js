import React, { useState } from "react";
import { ethers } from "ethers";
import axios from "axios";

// PASTE YOUR CONTRACT ABI HERE
const ABI = [
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "_docHash",
				"type": "bytes32"
			},
			{
				"internalType": "string",
				"name": "_ipfsHash",
				"type": "string"
			}
		],
		"name": "anchorDocument",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "bytes32",
				"name": "docHash",
				"type": "bytes32"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "issuer",
				"type": "address"
			}
		],
		"name": "DocumentAnchored",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "documents",
		"outputs": [
			{
				"internalType": "address",
				"name": "issuer",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "timestamp",
				"type": "uint256"
			},
			{
				"internalType": "string",
				"name": "ipfsHash",
				"type": "string"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "_docHash",
				"type": "bytes32"
			}
		],
		"name": "verifyDocument",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			},
			{
				"internalType": "string",
				"name": "",
				"type": "string"
			}
		],
		"stateMutability": "view",
		"type": "function"
	}
]; 
const CONTRACT_ADDRESS = "0x80C223EeF4b50c76DeE2b62532A7AaEd9Eed5cB1";

function App() {
  const [file, setFile] = useState(null);
  const [status, setStatus] = useState("");

  const handleUpload = async () => {
    if (!file) return;
    setStatus("Analyzing with AI...");

    // 1. Send to Backend for AI Check & Hashing
    const formData = new FormData();
    formData.append("file", file);

    try {
      const res = await axios.post("http://localhost:5000/api/analyze", formData);
      const { docHash, aiScore } = res.data;
      
      setStatus(`AI Passed (Score: ${Math.floor(aiScore)}%). Anchoring to Blockchain...`);

      // 2. Anchor to Blockchain (The "Web3" part)
      if (window.ethereum) {
        const provider = new ethers.BrowserProvider(window.ethereum);
        const signer = await provider.getSigner();
        const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);

        // Call the smart contract
        const tx = await contract.anchorDocument(docHash, "ipfs_placeholder");
        setStatus("Waiting for transaction confirmation...");
        await tx.wait();
        
        setStatus(`Success! Document Anchored. Hash: ${docHash}`);
      } else {
        alert("Please install MetaMask!");
      }

    } catch (error) {
      console.error(error);
      setStatus("Error: " + (error.response?.data?.error || error.message));
    }
  };

  return (
    <div style={{ padding: "50px" }}>
      <h1>Blockchain Document Verifier</h1>
      <input type="file" onChange={(e) => setFile(e.target.files[0])} />
      <button onClick={handleUpload} style={{ marginLeft: "10px" }}>
        Upload & Verify
      </button>
      <p>Status: {status}</p>
    </div>
  );
}

export default App;