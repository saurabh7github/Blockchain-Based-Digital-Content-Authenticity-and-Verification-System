# Environment Variables Reference

Complete guide to all environment variables in DocVerify.

## Backend (`verifier-backend`)

### Required

| Variable | Description | Example | Notes |
|----------|-------------|---------|-------|
| `MONGO_URI` | MongoDB connection string | `mongodb+srv://user:pass@cluster.mongodb.net/docverifier` | Get from MongoDB Atlas |
| `JWT_SECRET` | Secret for JWT signing | Generate 64-char hex | Use `crypto.randomBytes(64).toString('hex')` |
| `ADMIN_PASSWORD` | Admin dashboard password | Strong password | Min 16 characters |
| `CORS_ORIGINS` | Allowed frontend origins | `https://app.railway.app` | Comma-separated, no spaces |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `5000` |
| `NODE_ENV` | Environment | `development` |
| `JWT_EXPIRES_IN` | Token lifetime | `8h` |
| `ADMIN_USERNAME` | Admin username | `admin` |

### AI Services (Optional)

| Variable | Description | Required |
|----------|-------------|----------|
| `AI_ENGINE` | Engine: `eden_ai` or `reality_defender` | No (mock mode) |
| `AI_API_KEY` | Eden AI key | Only if `AI_ENGINE=eden_ai` |
| `REALITY_DEFENDER_API_KEY` | Reality Defender key | Only if `AI_ENGINE=reality_defender` |
| `AI_PROVIDER` | Sub-provider (winstonai, hive, etc.) | No (default: winstonai) |
| `AI_BLOCK_THRESHOLD` | Rejection threshold 0-100 | No (default: 80) |

### IPFS (Optional)

| Variable | Description |
|----------|-------------|
| `PINATA_API_KEY` | Pinata API key for IPFS |
| `PINATA_SECRET_KEY` | Pinata secret |

## Frontend (`verifier-client`)

| Variable | Description | Example |
|----------|-------------|---------|
| `REACT_APP_API_URL` | Backend URL (no trailing slash) | `https://api.railway.app` |
| `REACT_APP_CONTRACT_ADDRESS` | Ethereum contract | `0x83ed6653dB8c25Bacebf6B3110e352bfE6F9196c` |

**Note**: React requires `REACT_APP_` prefix. Set these as build-time environment variables.

## Security Best Practices

1. **Never commit .env files**
2. **Rotate secrets if exposed**
3. **Use strong passwords**: Minimum 16 characters
4. **Generate JWT_SECRET properly**: 64-byte hex from crypto
5. **CORS_ORIGINS**: Only include trusted domains
6. **MongoDB URI**: Use Atlas with authentication, not localhost in production

## Generating Secrets

```bash
# JWT Secret (64-byte hex)
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"

# Random password
openssl rand -base64 24
```

## Platform-Specific Notes

### Railway
- Set in: Dashboard → Service → Variables
- Automatic redeployment on changes
- Can use Railway's database addons

### Render
- Set in: Dashboard → Service → Environment
- Organized in key-value pairs
- Redeployment may need manual trigger
