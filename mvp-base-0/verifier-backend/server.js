require('dotenv').config();
const express   = require('express');
const mongoose  = require('mongoose');
const cors      = require('cors');
const multer    = require('multer');
const crypto    = require('crypto');
const rateLimit = require('express-rate-limit');

const { getThreshold, checkAuthenticity } = require('./lib/aiCheck');
const { pinToIPFS }                       = require('./lib/ipfs');
const DocModel                            = require('./models/Document');
const { requireAuth, loginHandler }       = require('./middleware/auth');

const app = express();

// --- CORS Configuration ------------------------------------------------------
const corsOptions = {
  origin: ['http://localhost:3000', 'http://localhost:3001'],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
};
app.use(cors(corsOptions));

app.use(express.json());

// --- Rate Limiters -----------------------------------------------------------
// General API: 200 req / 15 min per IP
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests – please try again later.' }
});

// AI analysis routes: expensive – 20 req / 15 min per IP
const analyzeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'AI analysis rate limit exceeded – please wait before submitting another file.' }
});

app.use('/api', generalLimiter);

// --- MongoDB Setup -----------------------------------------------------------
mongoose.connect(process.env.MONGO_URI)
  .then(() => console.log('MongoDB connected'))
  .catch((err) => { console.error('MongoDB connection error:', err.message); process.exit(1); });

// --- Fabric routes (optional – only loaded when FABRIC_ENABLED=true) ---------
if (process.env.FABRIC_ENABLED === 'true') {
  try {
    const fabricRoutes = require('./fabric/fabricRoutes');
    app.use('/api/fabric/analyze', analyzeLimiter);   // extra cap on Fabric AI route
    app.use('/api/fabric', fabricRoutes);
    console.log('[Fabric] Routes mounted at /api/fabric');
  } catch (err) {
    console.warn('[Fabric] Failed to load fabric routes:', err.message);
  }
}

// Multer -- 10 MB file size cap
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }
});

// --- POST /api/analyze -------------------------------------------------------
app.post('/api/analyze', analyzeLimiter, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded.' });

    const fileBuffer = req.file.buffer;
    const fileName   = req.file.originalname;
    const mimeType   = req.file.mimetype;

    // A. SHA-256 hash
    const docHash = '0x' + crypto.createHash('sha256').update(fileBuffer).digest('hex');

    // B. AI check with per-type threshold
    const threshold = getThreshold(mimeType);
    const aiResult  = await checkAuthenticity(fileBuffer, fileName, mimeType);

    if (aiResult.score > threshold) {
      return res.status(400).json({
        error:      'AI check failed: content appears synthetic or forged.',
        aiScore:    aiResult.score,
        aiProvider: aiResult.provider,
        threshold
      });
    }

    // C. isAuthentic reflects actual gate outcome (no longer hardcoded true)
    const isAuthentic = aiResult.score <= threshold;

    // D. IPFS via Pinata (gracefully skipped when keys not configured)
    let ipfsCid = null;
    try {
      ipfsCid = await pinToIPFS(fileBuffer, fileName);
      if (ipfsCid) console.log(`[IPFS] Pinned: ${ipfsCid}`);
    } catch (pinErr) {
      console.warn('[IPFS] Pinata upload failed (non-fatal):', pinErr.message);
    }

    // E. Persist to MongoDB
    await DocModel.findOneAndUpdate(
      { docHash },
      { docHash, fileName, aiScore: aiResult.score, aiProvider: aiResult.provider,
        aiDetails: aiResult.details, isAuthentic, ipfsCid },
      { upsert: true, new: true }
    );

    res.json({ success: true, docHash, aiScore: aiResult.score, aiProvider: aiResult.provider, ipfsCid });

  } catch (err) {
    console.error('/api/analyze error:', err);
    res.status(500).json({ error: err.message });
  }
});

// --- POST /api/auth/login ----------------------------------------------------
app.post('/api/auth/login', loginHandler);

// --- GET /api/health ---------------------------------------------------------
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    mongo:  mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
    uptime: Math.floor(process.uptime())
  });
});

// --- GET /api/document/:hash -------------------------------------------------
app.get('/api/document/:hash', async (req, res) => {
  try {
    const doc = await DocModel.findOne({ docHash: req.params.hash });
    if (!doc) return res.status(404).json({ error: 'No off-chain record found for this hash.' });
    res.json({
      fileName:    doc.fileName,
      aiScore:     doc.aiScore,
      aiProvider:  doc.aiProvider,
      aiDetails:   doc.aiDetails,
      isAuthentic: doc.isAuthentic,
      ipfsCid:     doc.ipfsCid,
      createdAt:   doc.createdAt
    });
  } catch (err) {
    console.error('/api/document error:', err);
    res.status(500).json({ error: err.message });
  }
});

// --- Server startup ----------------------------------------------------------
// Guard prevents the port from being bound when Jest imports this module.
const PORT = process.env.PORT || 5000;
if (require.main === module) {
  app.listen(PORT, () => {
    const engine = process.env.AI_ENGINE || 'eden_ai';
    const hasKey = engine === 'eden_ai' ? !!process.env.AI_API_KEY : !!process.env.REALITY_DEFENDER_API_KEY;
    console.log(`\nServer running on port ${PORT}`);
    console.log(`  MongoDB   : ${process.env.MONGO_URI ? 'configured' : 'MISSING'}`);
    console.log(`  AI Engine : ${engine} -- ${hasKey ? 'key loaded' : 'no key -- mock mode'}`);
    console.log(`  Thresholds: image=${process.env.AI_THRESHOLD_IMAGE || '-'} video=${process.env.AI_THRESHOLD_VIDEO || '-'} text=${process.env.AI_THRESHOLD_TEXT || '-'} default=${process.env.AI_BLOCK_THRESHOLD || 80}`);
    console.log(`  Pinata    : ${process.env.PINATA_API_KEY ? 'configured' : 'no key -- IPFS disabled'}\n`);
  });
}

// Export for integration tests (Jest imports this without triggering listen)
module.exports = app;

