# Deploy to Railway - Quick Start

## Prerequisites
- GitHub account
- Railway account (sign up at railway.app with GitHub)
- MongoDB Atlas account (free tier available)

## Step 1: Prepare MongoDB Atlas

1. Go to [MongoDB Atlas](https://www.mongodb.com/cloud/atlas/register)
2. Create free cluster (M0 Sandbox)
3. Create database user:
   - Username: `docverify_user`
   - Password: Generate strong password, save it
4. Whitelist all IPs: `0.0.0.0/0` (for Railway access)
5. Get connection string: Click "Connect" → "Connect your application"
   - Format: `mongodb+srv://docverify_user:PASSWORD@cluster0.xxxxx.mongodb.net/docverifier?retryWrites=true&w=majority`
   - Replace PASSWORD with your password

## Step 2: Deploy Backend to Railway

1. **Push code to GitHub** (ensure .env files are NOT committed)

2. **Create new Railway project**:
   - Go to [railway.app](https://railway.app)
   - Click "New Project" → "Deploy from GitHub repo"
   - Select your repository
   - Choose "Add service" → "GitHub Repo"

3. **Configure backend service**:
   - Root Directory: `verifier-backend`
   - Build Command: `npm install`
   - Start Command: `node server.js`

4. **Add environment variables**:
   Go to Variables tab and add:
   ```
   PORT=5000
   MONGO_URI=<your-mongodb-atlas-connection-string>
   JWT_SECRET=<generate-with-crypto-randomBytes-64-hex>
   ADMIN_PASSWORD=<your-secure-admin-password>
   CORS_ORIGINS=https://<frontend-url>.railway.app
   NODE_ENV=production
   ```

   Optional variables (leave empty for mock mode):
   ```
   AI_API_KEY=
   AI_PROVIDER=winstonai
   PINATA_API_KEY=
   PINATA_SECRET_KEY=
   ```

5. **Deploy**: Railway auto-deploys on variable changes

6. **Get backend URL**: Copy from Railway dashboard (e.g., `https://docverify-backend-production.up.railway.app`)

## Step 3: Deploy Frontend to Railway

1. **Add another service**: In same project, click "New Service" → "GitHub Repo"

2. **Configure frontend service**:
   - Root Directory: `verifier-client`
   - Build Command: `npm install && npm run build`
   - Start Command: `npx serve -s build -l $PORT`

3. **Add environment variables**:
   ```
   REACT_APP_API_URL=<your-backend-url-from-step2>
   REACT_APP_CONTRACT_ADDRESS=0x83ed6653dB8c25Bacebf6B3110e352bfE6F9196c
   ```

4. **Deploy**: Auto-deploys

5. **Get frontend URL**: This is your application URL

## Step 4: Update CORS

1. Go back to backend service variables
2. Update `CORS_ORIGINS` to include frontend URL:
   ```
   CORS_ORIGINS=https://<your-frontend-url>.railway.app
   ```
3. Redeploy backend (Railway auto-redeploys)

## Step 5: Verify Deployment

1. Visit your frontend URL
2. Check health endpoint: `<backend-url>/api/health`
3. Try uploading a document (will work in mock mode without AI keys)

## Custom Domain (Optional)

1. In Railway frontend service → Settings → Domain
2. Add custom domain
3. Update DNS records as instructed
4. Update backend CORS_ORIGINS to include custom domain

## Troubleshooting

**Deployment failed**: Check Railway logs for errors
**CORS errors**: Ensure frontend URL matches exactly in CORS_ORIGINS (include https://)
**MongoDB connection failed**: Verify connection string and IP whitelist
**Health check fails**: Check backend logs for startup errors
