require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const multer = require('multer'); // File handling
const crypto = require('crypto'); // Hashing
const axios = require('axios');   // For AI API calls

const app = express();
app.use(cors());
app.use(express.json());

// 1. MongoDB Setup (Use a free MongoDB Atlas connection string)
mongoose.connect(process.env.MONGO_URI)
  .then(() => console.log("MongoDB Connected"));

// Schema for Off-Chain Metadata
const DocSchema = new mongoose.Schema({
    docHash: String,
    fileName: String,
    aiScore: Number, // 0-100 (Deepfake probability)
    isAuthentic: Boolean
});
const DocModel = mongoose.model('Document', DocSchema);

// Multer Storage (Memory is fine for MVP)
const upload = multer({ storage: multer.memoryStorage() });

// 2. The Core Endpoint: Upload & Analyze
app.post('/api/analyze', upload.single('file'), async (req, res) => {
    try {
        const fileBuffer = req.file.buffer;
        
        // A. Calculate SHA-256 Hash
        const hashSum = crypto.createHash('sha256');
        hashSum.update(fileBuffer);
        const docHash = "0x" + hashSum.digest('hex');

        // B. AI Check (Mocking Eden AI/Deepware for MVP)
        // In production, you would call: await axios.post('https://api.edenai.run/...')
        const mockAiScore = Math.random() * 20; // Simulating a low fake score (0-20%)
        
        if (mockAiScore > 80) {
            return res.status(400).json({ error: "Deepfake Detected! Threshold exceeded." });
        }

        // C. Save Metadata to MongoDB
        const newDoc = new DocModel({
            docHash: docHash,
            fileName: req.file.originalname,
            aiScore: mockAiScore,
            isAuthentic: true
        });
        await newDoc.save();

        // Return the Hash to frontend so it can anchor it on-chain
        res.json({ success: true, docHash: docHash, aiScore: mockAiScore });

    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(5000, () => console.log("Server running on port 5000"));