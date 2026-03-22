# MongoDB Atlas Setup Guide

Complete guide to setting up MongoDB Atlas for DocVerify.

## Step 1: Create Account

1. Go to [MongoDB Atlas](https://www.mongodb.com/cloud/atlas/register)
2. Sign up with Google or email
3. Verify email if needed

## Step 2: Create Cluster

1. Click "Build a Database"
2. Choose **FREE** tier (M0 Sandbox)
3. Choose region (select closest to your app deployment)
4. Cluster Name: `docverify` or leave default
5. Click "Create"

Wait 1-3 minutes for provisioning.

## Step 3: Create Database User

1. Security → Database Access → Add New Database User
2. Authentication Method: Password
3. Username: `docverify_user`
4. Generate password or create strong one
5. **SAVE PASSWORD SECURELY** - you'll need it
6. Database User Privileges: "Read and write to any database"
7. Add User

## Step 4: Configure Network Access

1. Security → Network Access → Add IP Address
2. Choose: "Allow Access from Anywhere"
3. IP Address: `0.0.0.0/0`
4. Comment: "Railway/Render access"
5. Confirm

**Why 0.0.0.0/0**: Cloud platforms use dynamic IPs. In production, restrict to known IPs if possible.

## Step 5: Get Connection String

1. Click "Connect" on your cluster
2. Choose "Connect your application"
3. Driver: Node.js, Version: 5.5 or later
4. Copy connection string:
   ```
   mongodb+srv://docverify_user:<password>@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```

5. **Modify the string**:
   - Replace `<password>` with your actual password
   - Add database name: `/docverifier` after `.net`
   - Final format:
     ```
     mongodb+srv://docverify_user:YOUR_PASSWORD@cluster0.xxxxx.mongodb.net/docverifier?retryWrites=true&w=majority
     ```

## Step 6: Test Connection (Optional)

Using mongosh locally:
```bash
mongosh "mongodb+srv://docverify_user:PASSWORD@cluster0.xxxxx.mongodb.net/docverifier"
```

## Use in Application

Set as `MONGO_URI` environment variable in Railway/Render.

## Free Tier Limits

- 512 MB storage
- Shared RAM
- No backups (manual export recommended)
- Sufficient for MVP/testing

## Upgrading

When you need more:
- Atlas → Cluster → Upgrade
- M2 tier: $9/month (2GB storage, automated backups)
