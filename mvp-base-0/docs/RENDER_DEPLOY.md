# Deploy to Render - Quick Start

## Prerequisites
- GitHub account
- Render account (sign up at render.com with GitHub)
- MongoDB Atlas account (see MongoDB Atlas Setup guide)

## Step 1: Prepare MongoDB Atlas

Follow Step 1 from `MONGODB_ATLAS_SETUP.md`

## Step 2: Deploy Backend

1. **Push code to GitHub**

2. **Create Web Service**:
   - Go to [Render Dashboard](https://dashboard.render.com/)
   - Click "New +" → "Web Service"
   - Connect your GitHub repository
   - Configure:
     - Name: `docverify-backend`
     - Region: Choose closest to you
     - Root Directory: `verifier-backend`
     - Environment: `Node`
     - Build Command: `npm install`
     - Start Command: `node server.js`
     - Instance Type: Free

3. **Add Environment Variables**:
   Click "Advanced" → Add environment variables:
   ```
   PORT=5000
   MONGO_URI=<mongodb-atlas-connection-string>
   JWT_SECRET=<generate-64-hex-string>
   ADMIN_PASSWORD=<secure-password>
   CORS_ORIGINS=https://<your-frontend>.onrender.com
   NODE_ENV=production
   ```

4. **Deploy**: Click "Create Web Service"

5. **Note backend URL**: e.g., `https://docverify-backend.onrender.com`

## Step 3: Deploy Frontend

1. **Create Static Site**:
   - Click "New +" → "Static Site"
   - Select same repository
   - Configure:
     - Name: `docverify-frontend`
     - Root Directory: `verifier-client`
     - Build Command: `npm install && npm run build`
     - Publish Directory: `build`

2. **Add Environment Variables**:
   ```
   REACT_APP_API_URL=<backend-url-from-step2>
   REACT_APP_CONTRACT_ADDRESS=0x83ed6653dB8c25Bacebf6B3110e352bfE6F9196c
   ```

3. **Deploy**: Click "Create Static Site"

## Step 4: Update CORS

1. Go to backend service → Environment
2. Edit `CORS_ORIGINS` to include frontend URL
3. Save (triggers redeploy)

## Step 5: Verify

Visit your frontend URL and test the application

## Important Notes

- **Free tier sleep**: Render free services sleep after 15 min inactivity (30-60s cold start)
- **Build time**: Frontend build takes 2-5 minutes
- **Custom domain**: Available in Settings → Custom Domain
