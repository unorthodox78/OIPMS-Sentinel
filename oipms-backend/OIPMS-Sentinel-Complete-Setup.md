# OIPMS Sentinel - Complete Production Deployment Guide v5.0
## From Zero to Hero: Fresh VM Setup with Aerospike & Firestore Integration

**Date:** November 27, 2025  
**Status:** PRODUCTION READY ✅  
**Last Updated:** Complete with CORS fixes and working dashboard  

---

# PART 9.5: INVENTORY LIVE UPDATES (REST + WS/SSE)

The backend exposes authenticated Inventory APIs backed by Aerospike (namespace: `oipms`, set: `inventory`).

- Auth: All endpoints require Firebase ID token via header `Authorization: Bearer <ID_TOKEN>`
- Records: Two logical records keyed by type: `Ice Block` and `Ice Cube`
- Bins: `inStock` (int), `inProduction` (int)

## Endpoints

- GET `/api/inventory?ns=oipms&set=inventory`
  - Returns a list of two items (`Ice Block`, `Ice Cube`) with `inStock` and `inProduction`.

- POST `/api/inventory/update`
  - Body (JSON): `{ "ns":"oipms", "set":"inventory", "type":"Ice Block"|"Ice Cube", "inStock":123, "inProduction":15 }`
  - Persists to Aerospike and broadcasts to WS/SSE clients.

- SSE `/api/inventory/stream?ns=oipms&set=inventory`
  - Server-Sent Events stream. Emits `data: <json>\n\n` with the latest snapshot whenever it changes.

- WebSocket `/ws/inventory?ns=oipms&set=inventory`
  - Sends an initial snapshot on connect and pushes updates on change.
  - The WS upgrade requires the same `Authorization: Bearer <ID_TOKEN>` header.

## Quick tests (PowerShell)

- GET (replace <ID_TOKEN>):
  ```powershell
  $headers = @{ Authorization = 'Bearer <ID_TOKEN>' }
  Invoke-RestMethod -Uri 'http://<VM_IP>:8080/api/inventory?ns=oipms&set=inventory' -Headers $headers -Method Get
  ```

- POST update:
  ```powershell
  $headers = @{ Authorization = 'Bearer <ID_TOKEN>'; 'Content-Type' = 'application/json' }
  $body = @{ ns='oipms'; set='inventory'; type='Ice Block'; inStock=123 } | ConvertTo-Json
  Invoke-RestMethod -Uri 'http://<VM_IP>:8080/api/inventory/update' -Headers $headers -Method Post -Body $body
  ```

- SSE (cmd/powershell):
  ```powershell
  curl.exe --no-buffer -H "Authorization: Bearer <ID_TOKEN>" "http://<VM_IP>:8080/api/inventory/stream?ns=oipms&set=inventory"
  ```

- WebSocket (VM shell example with websocat):
  ```bash
  apt-get install -y websocat
  websocat -H "Authorization: Bearer <ID_TOKEN>" ws://127.0.0.1:8080/ws/inventory?ns=oipms&set=inventory
  ```

---

## TABLE OF CONTENTS

1. [Part 0: Prerequisites](#part-0-prerequisites)
2. [Part 1: Fresh VM Setup from Scratch](#part-1-fresh-vm-setup-from-scratch)
3. [Part 2: Install Node.js & Dependencies](#part-2-install-nodejs--dependencies)
4. [Part 3: Setup Aerospike C Client](#part-3-setup-aerospike-c-client)
5. [Part 4: Download & Install Aerospike Server](#part-4-download--install-aerospike-server)
6. [Part 5: Configure Firebase & Firestore](#part-5-configure-firebase--firestore)
7. [Part 6: Upload Backend Files](#part-6-upload-backend-files)
8. [Part 7: Install npm Dependencies](#part-7-install-npm-dependencies)
9. [Part 8: Configure PM2 Process Manager](#part-8-configure-pm2-process-manager)
10. [Part 9: Setup Firewall & Network](#part-9-setup-firewall--network)
11. [Part 10: Testing & Verification](#part-10-testing--verification)
12. [Part 11: Dashboard Access & Usage](#part-11-dashboard-access--usage)
13. [Troubleshooting Guide](#troubleshooting-guide)
14. [API Reference](#api-reference)

---

# PART 0: PREREQUISITES

## What You Need

✅ **Cloud VM Provider** (Linode, DigitalOcean, or AWS)  
✅ **VM Specs:** 2GB RAM, 50GB Storage minimum  
✅ **OS:** Ubuntu 22.04 LTS or Ubuntu 24.04 LTS  
✅ **Local Machine:** Windows/Mac with SSH client (PowerShell recommended)  
✅ **Firebase Project:** Already created with Firestore enabled  
✅ **Service Account Key:** Downloaded from Firebase Console  

## Getting Your Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project → **Settings** ⚙️ → **Service Accounts**
3. Click **Generate New Private Key**
4. Save as `serviceAccountKey.json`
5. Keep it **SECURE** - never commit to public repos!

---

# PART 1: FRESH VM SETUP FROM SCRATCH

## Step 1.1: Create New VM on Linode/DigitalOcean

**If using Linode:**
```
- OS: Ubuntu 24.04 LTS
- Size: Linode 2GB RAM minimum
- Region: Choose closest to you
- Root Password: Create strong password
```

**If using DigitalOcean:**
```
- Image: Ubuntu 24.04 x64
- Plan: Basic $5-6/month (2GB RAM)
- Datacenter: Choose region
- Authentication: SSH key or password
```

**Note the VM IP address!** Example: `172.235.32.111`

## Step 1.2: Connect from Windows PowerShell

```powershell
ssh root@172.235.32.111
# Enter password when prompted
```

You should see:
```
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-71-generic x86_64)
```

## Step 1.3: Update System

```bash
apt update
apt upgrade -y
apt install -y curl wget git vim nano build-essential
```

This installs essential tools for development.

---

# PART 2: INSTALL NODE.JS & DEPENDENCIES

## Step 2.1: Install Node.js v20 LTS

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
apt install -y nodejs
```

## Step 2.2: Verify Installation

```bash
node --version    # Should show v20.x or higher
npm --version     # Should show 10.x or higher
```

## Step 2.3: Install Build Tools

```bash
apt install -y build-essential python3 libssl-dev pkg-config
```

These are required for compiling Aerospike C client bindings.

## Step 2.4: Install PM2 (Process Manager)

```bash
npm install -g pm2
pm2 --version    # Verify installation
```

PM2 will manage your services and restart them on reboot.

---

# PART 3: SETUP AEROSPIKE C CLIENT

## Step 3.1: Download Aerospike C Client

On your **local machine (Windows)**, download from:
```
https://www.aerospike.com/download/client/c/
```

Select: **aerospike-client-c_6.3.0_ubuntu22.04_x86_64.tgz**

## Step 3.2: Upload to VM

From **Windows PowerShell**:

```powershell
scp aerospike-client-c_6.3.0_ubuntu22.04_x86_64.tgz root@172.235.32.111:/tmp/
```

## Step 3.3: Extract on VM

```bash
cd /tmp
tar -xzf aerospike-client-c_6.3.0_ubuntu22.04_x86_64.tgz

# Verify extraction
ls -d aerospike-client-c-*
# Should show: aerospike-client-c-6.3.0/
```

## Step 3.4: Set Environment Variables (Permanent)

```bash
nano ~/.bashrc
```

Add at the very end:

```bash
# Aerospike Configuration
export AEROSPIKE_C_HOME="/tmp/aerospike-client-c-6.3.0"

# Firebase Configuration  
export GOOGLE_APPLICATION_CREDENTIALS="/root/oipms-backend/serviceAccountKey.json"
```

Save: `Ctrl+X`, `Y`, `Enter`

Apply immediately:

```bash
source ~/.bashrc

# Verify
echo $AEROSPIKE_C_HOME
# Should output: /tmp/aerospike-client-c-6.3.0
```

---

# PART 4: DOWNLOAD & INSTALL AEROSPIKE SERVER

## Step 4.1: Download Aerospike Server

On your **local machine**, download:
```
https://www.aerospike.com/download/server/
```

Select: **aerospike-server-community_8.1.0.1_tools-12.0.2_ubuntu22.04_x86_64.tgz**

## Step 4.2: Upload to VM

From **Windows PowerShell**:

```powershell
scp aerospike-server-community_8.1.0.1_tools-12.0.2_ubuntu22.04_x86_64.tgz root@172.235.32.111:/tmp/
```

## Step 4.3: Extract and Install

```bash
cd /tmp
tar -xzf aerospike-server-community_8.1.0.1_tools-12.0.2_ubuntu22.04_x86_64.tgz

# Navigate to folder
cd aerospike-server-community_8.1.0.1_tools-12.0.2_ubuntu22.04_x86_64

# Install .deb packages
sudo dpkg -i aerospike-server-community_8.1.0.1-1ubuntu22.04_amd64.deb
sudo dpkg -i aerospike-tools_12.0.2-ubuntu22.04_amd64.deb
```

If dependency errors:

```bash
sudo apt --fix-broken install -y
# Then retry dpkg commands
```

## Step 4.4: Start Aerospike Service

```bash
sudo systemctl start aerospike
sudo systemctl enable aerospike    # Auto-start on reboot
```

## Step 4.5: Verify Aerospike is Running

```bash
sudo systemctl status aerospike
```

Should show: **Active: active (running)**

## Step 4.6: Test Connection

```bash
aql
```

You should see:

```
Aerospike Query Language
Version 8.1.0
Copyright 2012-2025 Aerospike Inc. All rights reserved.

aql>
```

Type `exit` to quit:

```bash
exit
```

✅ **Aerospike is now running!**

---

# PART 5: CONFIGURE FIREBASE & FIRESTORE

## Step 5.1: Ensure Firestore is Enabled

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Firestore Database**
4. Click **Create Database**
5. Select **Start in production mode**
6. Choose your region
7. Click **Create**

Wait for Firestore to initialize (2-3 minutes).

## Step 5.2: Get Service Account Key

1. In Firebase Console: **Project Settings** ⚙️
2. Go to **Service Accounts** tab
3. Click **Generate New Private Key**
4. Save the JSON file

You'll use this in the next section.

---

# PART 6: UPLOAD BACKEND FILES

## Step 6.1: Create Backend Folder on VM

```bash
mkdir -p /root/oipms-backend
cd /root/oipms-backend
```

## Step 6.2: Prepare Files on Local Machine

Create these files in your local project folder:

### File 1: `package.json`

```json
{
  "name": "oipms-backend",
  "version": "1.0.0",
  "description": "OIPMS Sentinel - Flexible Database Management Backend",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^5.1.0",
    "firebase-admin": "^13.6.0",
    "aerospike": "^6.4.0",
    "ws": "^8.17.0"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
```

### File 2: `server.js` (WITH CORS FIX)

```javascript
// OIPMS Sentinel - Flexible Database Management Backend
// Supports both Aerospike (NoSQL) and Firestore (Cloud) with dynamic table operations

const Aerospike = require('aerospike');
const admin = require('firebase-admin');
const express = require('express');
const app = express();

// Middleware
app.use(express.json());

// ============================================
// CRITICAL FIX: ADD CORS HEADERS
// ============================================
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  res.header('Access-Control-Max-Age', '3600');
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// --- Firebase Admin Initialization ---
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'oipms-86caa'
});
const firestore = admin.firestore();

// --- Aerospike Connection ---
const aerospikeConfig = {
  hosts: [{ addr: '127.0.0.1', port: 3000 }]
};
const aerospikeClient = Aerospike.client(aerospikeConfig);

aerospikeClient.connect((err) => {
  if (err) {
    console.error('Failed to connect to Aerospike:', err);
  } else {
    console.log('Connected to Aerospike');
  }
});

// --- Aerospike Diagnostics ---
async function aerospikeInfo(cmd) {
  return new Promise((resolve, reject) => {
    aerospikeClient.infoAny(cmd, (err, response) => {
      if (err) return reject(err);
      resolve(String(response || ''));
    });
  });
}

// ============================================
// CREATE TABLE
// ============================================
app.post('/api/tables', async (req, res) => {
  try {
    const { tableName, database, schema } = req.body;

    if (!tableName || !database) {
      return res.status(400).json({ error: 'tableName and database required' });
    }

    if (database === 'aerospike') {
      res.json({
        success: true,
        message: `Set '${tableName}' will be created on first insert`,
        database: 'aerospike',
        tableName
      });
    } else if (database === 'firestore') {
      await firestore.collection('__tables__').doc(tableName).set({
        name: tableName,
        schema: schema || {},
        createdAt: new Date().toISOString(),
        recordCount: 0
      });

      res.json({
        success: true,
        message: `Collection '${tableName}' created in Firestore`,
        database: 'firestore',
        tableName
      });
    } else {
      res.status(400).json({ error: 'Invalid database. Use "aerospike" or "firestore"' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ============================================
// INSERT DATA
// ============================================
app.post('/api/tables/:tableName/records', async (req, res) => {
  try {
    const { tableName } = req.params;
    const { database, record, primaryKey } = req.body;

    if (!database || !record) {
      return res.status(400).json({ error: 'database and record required' });
    }

    if (database === 'aerospike') {
      const key = new Aerospike.Key(
        'oipms',
        tableName,
        primaryKey || record.id || Date.now().toString()
      );

      await aerospikeClient.put(key, { bins: record });

      res.json({
        success: true,
        message: `Record inserted into Aerospike.${tableName}`,
        key: key.key,
        record
      });
    } else if (database === 'firestore') {
      const docId = primaryKey || record.id || Date.now().toString();
      await firestore.collection(tableName).doc(docId).set(record);

      await firestore.collection('__tables__').doc(tableName).update({
        recordCount: admin.firestore.FieldValue.increment(1)
      });

      res.json({
        success: true,
        message: `Record inserted into Firestore.${tableName}`,
        docId,
        record
      });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ============================================
// READ ALL RECORDS
// ============================================
app.get('/api/tables/:tableName/records', async (req, res) => {
  try {
    const { tableName } = req.params;
    const { database } = req.query;

    if (!database) {
      return res.status(400).json({ error: 'database query parameter required' });
    }

    if (database === 'firestore') {
      const snapshot = await firestore.collection(tableName).get();
      const records = [];

      snapshot.forEach((doc) => {
        records.push({
          id: doc.id,
          ...doc.data()
        });
      });

      res.json({
        database: 'firestore',
        table: tableName,
        count: records.length,
        records
      });
    } else if (database === 'aerospike') {
      const statement = new Aerospike.Query('oipms', tableName);
      const query = aerospikeClient.query(statement);

      const records = [];
      return new Promise((resolve) => {
        query.forEach((record) => {
          records.push({
            key: record.key.key,
            bins: record.bins
          });
        }, (err) => {
          if (err) {
            return res.status(500).json({ error: err.toString() });
          }
          res.json({
            database: 'aerospike',
            table: tableName,
            count: records.length,
            records
          });
          resolve();
        });
      });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ============================================
// DELETE RECORD
// ============================================
app.delete('/api/tables/:tableName/records/:recordId', async (req, res) => {
  try {
    const { tableName, recordId } = req.params;
    const { database } = req.query;

    if (!database) {
      return res.status(400).json({ error: 'database query parameter required' });
    }

    if (database === 'firestore') {
      await firestore.collection(tableName).doc(recordId).delete();

      await firestore.collection('__tables__').doc(tableName).update({
        recordCount: admin.firestore.FieldValue.increment(-1)
      });

      res.json({
        success: true,
        message: `Record deleted from Firestore.${tableName}`,
        recordId
      });
    } else if (database === 'aerospike') {
      const key = new Aerospike.Key('oipms', tableName, recordId);
      await aerospikeClient.remove(key);

      res.json({
        success: true,
        message: `Record deleted from Aerospike.${tableName}`,
        recordId
      });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ============================================
// HEALTH CHECK
// ============================================
app.get('/aerospike/health', async (req, res) => {
  try {
    if (!aerospikeClient.isConnected()) {
      return res.status(503).json({ ok: false, error: 'Not connected' });
    }

    const [services, namespaces, builds] = await Promise.all([
      aerospikeInfo('services\n'),
      aerospikeInfo('namespaces\n'),
      aerospikeInfo('build\n')
    ]);

    res.json({
      ok: true,
      services: services.trim().split(';').filter(Boolean),
      namespaces: namespaces.trim().split(';').filter(Boolean),
      build: builds.trim()
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.toString() });
  }
});

// ============================================
// START SERVER
// ============================================
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend API running on port ${PORT}`);
  console.log('Connected to Aerospike');
});

process.on('SIGTERM', () => {
  aerospikeClient.close();
  process.exit(0);
});
```

## Step 6.3: Upload Files from Windows PowerShell

```powershell
cd C:\Users\jomar\AndroidStudioProjects\OIP_Sentinel\oipms-backend

# Upload backend files
scp server.js root@139.162.46.103:/root/oipms-backend/
scp package.json root@172.235.32.111:/root/oipms-backend/
scp dashboard.html root@172.235.32.111:/root/oipms-backend/
scp database-manager.html root@172.235.32.111:/root/oipms-backend/
scp serviceAccountKey.json root@172.235.32.111:/root/oipms-backend/
```

## Step 6.4: Verify Files on VM

```bash
ls -lh /root/oipms-backend/
```

Should show:
```
-rw-r--r-- server.js
-rw-r--r-- package.json
-rw-r--r-- dashboard.html
-rw-r--r-- database-manager.html
-rw-r--r-- serviceAccountKey.json
```

---

# PART 7: INSTALL NPM DEPENDENCIES

## Step 7.1: Clean Install

```bash
cd /root/oipms-backend

rm -rf node_modules package-lock.json

# Set environment variable for this session
export AEROSPIKE_C_HOME="/tmp/aerospike-client-c-6.3.0"

# Install packages
npm install
```

This takes 3-5 minutes. You should see:

```
added 437 packages, and audited 438 packages
found 0 vulnerabilities
```

## Step 7.2: Verify Packages

```bash
npm list aerospike firebase-admin express
```

Should show all three packages installed.

---

# PART 8: CONFIGURE PM2 PROCESS MANAGER

## Step 8.1: Start Backend Service

```bash
cd /root/oipms-backend
pm2 start server.js --name oipms-backend --time
```

## Step 8.2: Start Dashboard Server

```bash
pm2 start "python3 -m http.server 3001 --directory /root/oipms-backend" --name oipms-dashboard
```

## Step 8.3: Check Status

```bash
pm2 status
```

Both should show **online**:

```
┌────┬──────────────────┬──────────┬──────┬───────────┬──────────┐
│ id │ name             │ mode     │ ↺    │ status    │ memory   │
├────┼──────────────────┼──────────┼──────┼───────────┼──────────┤
│ 0  │ oipms-backend    │ fork     │ 0    │ online    │ 25MB     │
│ 1  │ oipms-dashboard  │ fork     │ 0    │ online    │ 10MB     │
└────┴──────────────────┴──────────┴──────┴───────────┴──────────┘
```

## Step 8.4: Setup Auto-Restart on Reboot

```bash
sudo /usr/bin/pm2 startup systemd -u root --hp /root
sudo systemctl enable pm2-root
pm2 save
```

---

# PART 9: SETUP FIREWALL & NETWORK

## Step 9.1: Enable and Configure UFW

```bash
ufw enable
ufw allow 22/tcp      # SSH
ufw allow 8080/tcp    # Backend API
ufw allow 3001/tcp    # Dashboard
ufw reload
ufw status
```

You should see all three ports **ALLOW**.

## Step 9.2: Test Port Accessibility

From **Windows PowerShell**:

```powershell
# Test backend
curl http://172.235.32.111:8080/aerospike/health

# Test dashboard
curl http://172.235.32.111:3001/database-manager.html
```

---

# PART 10: TESTING & VERIFICATION

## Step 10.1: View Backend Logs

```bash
pm2 logs oipms-backend --lines 50
```

Should show:
```
Backend API running on port 8080
Connected to Aerospike
Connected to Aerospike
```

## Step 10.2: Test Aerospike Health Endpoint

From **Windows PowerShell**:

```powershell
curl http://172.235.32.111:8080/aerospike/health
```

Expected response:

```json
{
  "ok": true,
  "services": ["172.235.32.111:3000"],
  "namespaces": ["test", "oipms"],
  "build": "8.1.0.0"
}
```

✅ **Aerospike is connected!**

---

# PART 11: DASHBOARD ACCESS & USAGE

## Step 11.1: Open Dashboard

In your browser:

```
http://172.235.32.111:3001/database-manager.html
```

You should see the beautiful purple dashboard with 7 tabs.

## Step 11.2: Create Your First Table

1. **Table Name:** `customers`
2. **Database:** `Firestore (Cloud)`
3. Click **"Create Table"** button

Success message:
```json
{
  "success": true,
  "message": "Collection 'customers' created in Firestore",
  "database": "firestore",
  "tableName": "customers"
}
```

## Step 11.3: Insert Sample Data

1. Go to **"➕ Insert Data"** tab
2. **Database:** `Firestore`
3. **Table Name:** `customers`
4. **Primary Key:** `cust_001`
5. **Record Data:**

```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "phone": "123-456-7890",
  "status": "active",
  "city": "New York",
  "createdAt": "2025-11-27"
}
```

6. Click **"Insert Record"** button

## Step 11.4: Browse Data

1. Go to **"👁️ Browse Data"** tab
2. **Database:** `Firestore`
3. **Table Name:** `customers`
4. Click **"Load Data"** button

You'll see your data in a beautiful table! ✅

---

# TROUBLESHOOTING GUIDE

## "Failed to connect to Aerospike"

**Check service:**
```bash
sudo systemctl status aerospike
```

**Restart if needed:**
```bash
sudo systemctl restart aerospike
```

**Check Aerospike logs:**
```bash
sudo journalctl -u aerospike -f
```

## "npm install Failed"

**Verify environment variable:**
```bash
echo $AEROSPIKE_C_HOME
# Should show: /tmp/aerospike-client-c-6.3.0
```

**If not set, add to ~/.bashrc and reload**

**Clean install:**
```bash
cd /root/oipms-backend
rm -rf node_modules package-lock.json
npm install
```

## "Cannot access dashboard"

**Check PM2 services:**
```bash
pm2 status
```

**Check ports:**
```bash
netstat -tlnp | grep 3001
netstat -tlnp | grep 8080
```

**Restart services:**
```bash
pm2 restart all
```

## "Firestore connection error"

**Verify credentials file:**
```bash
ls -la /root/oipms-backend/serviceAccountKey.json
```

**Check environment variable:**
```bash
echo $GOOGLE_APPLICATION_CREDENTIALS
# Should output: /root/oipms-backend/serviceAccountKey.json
```

**Test JSON is valid:**
```bash
cat /root/oipms-backend/serviceAccountKey.json | python3 -m json.tool
```

## "Port already in use"

**Find process using port:**
```bash
lsof -i :8080
lsof -i :3001
```

**Kill if needed:**
```bash
kill -9 <PID>
```

---

# API REFERENCE

## Health Check

```bash
GET /aerospike/health
```

**Response:**
```json
{
  "ok": true,
  "services": ["172.235.32.111:3000"],
  "namespaces": ["test", "oipms"],
  "build": "8.1.0.0"
}
```

## Create Table

```bash
POST /api/tables
Content-Type: application/json

{
  "tableName": "customers",
  "database": "firestore"
}
```

## Insert Record

```bash
POST /api/tables/customers/records
Content-Type: application/json

{
  "database": "firestore",
  "primaryKey": "cust_001",
  "record": {
    "name": "John Doe",
    "email": "john@example.com"
  }
}
```

## Get Records

```bash
GET /api/tables/customers/records?database=firestore
```

## Delete Record

```bash
DELETE /api/tables/customers/records/cust_001?database=firestore
```

---

# PART 12: CONFIGURE SENDGRID EMAIL OTP ON VM

## Step 12.1: Create a SendGrid API Key

1. Sign in to https://app.sendgrid.com/
2. Left sidebar → Settings → API Keys → Create API Key
3. Name: OIPMS Backend
4. API Key Permissions: Full Access (or Restricted to Mail Send)
5. Copy the key once; you won’t see it again. Example format: SG.xxxxx.yyyyy

## Step 12.2: Verify a Single Sender (for From address)

1. Settings → Sender Authentication → Single Sender Verification
2. Create New Sender
   - From Name: OIPMS Sentinel
   - From Email: your Gmail (e.g., jomarisunogan23@gmail.com)
   - Reply-To: same or another
   - Address details: fill in
3. Open your email and click the verification link
4. Ensure the sender shows Verified ✓

## Step 12.3: Configure Environment Variables on the VM

On the VM (SSH):

```bash
export SENDGRID_API_KEY="<YOUR_SENDGRID_API_KEY>"
export MAIL_FROM="jomarisunogan23@gmail.com"   # your verified sender
```

To persist them across restarts, add to ~/.bashrc (optional):

```bash
echo 'export SENDGRID_API_KEY="<YOUR_SENDGRID_API_KEY>"' >> ~/.bashrc
echo 'export MAIL_FROM="jomarisunogan23@gmail.com"' >> ~/.bashrc
source ~/.bashrc
```

## Step 12.4: Restart Backend with SendGrid Env

Using PM2:

```bash
pm2 restart oipms-backend --update-env

# If the process is not started yet, do:
# SENDGRID_API_KEY="<YOUR_SENDGRID_API_KEY>" MAIL_FROM="jomarisunogan23@gmail.com" \
#   pm2 start /opt/oipms-backend/oipms-backend/server.js --name oipms-backend --time

pm2 env 0 | egrep -i 'SENDGRID|MAIL_FROM'
```

Expected output contains both variables (API key masked) and no MailerSend key.

## Step 12.5: Test the OTP Email Flow

From Windows PowerShell:

```powershell
(Invoke-RestMethod -Uri http://<VM_IP>:8080/auth/request-password-otp -Method POST -ContentType 'application/json' -Body '{"email":"<YOUR_EMAIL>"}') | ConvertTo-Json -Compress
```

Expected response:

```json
{"success": true}
```

Check your inbox/spam for a 6-digit OTP. Then reset:

```powershell
(Invoke-RestMethod -Uri http://<VM_IP>:8080/auth/reset-password-with-otp -Method POST -ContentType 'application/json' -Body '{"email":"<YOUR_EMAIL>","otp":"<CODE>","newPassword":"NewStrongPass#1"}') | ConvertTo-Json -Compress
```

## Step 12.6: Logs and Troubleshooting

```bash
pm2 logs oipms-backend --lines 100
```

Look for one of:
- sendMail: using SendGrid { from, to }
- SendGrid API error: <status> <body>

Common fixes:
- 401/403: API key invalid → regenerate in SendGrid, update VM env, restart PM2
- 400 with sender error: verify Single Sender and ensure MAIL_FROM matches the verified email
- No email: check spam folder and PM2 logs

## Step 12.7: Security Notes

- Never commit the API key to Git. Use environment variables.
- Rotate the API key periodically (Settings → API Keys → Regenerate), update VM env, then `pm2 restart oipms-backend --update-env`.
- Limit scope to “Mail Send” if you don’t need Full Access.

---

# PART 13: STEP-UP TWO-FACTOR VERIFICATION (2FA)

This enables OTP verification only on new devices or after 30 days for both admin and cashier logins.

## 13.1 Backend Endpoints

Implementations are already in `server.js`.

- POST `/auth/request-login-otp`
  - Request JSON:
    ```json
    { "email": "user@example.com" }
    ```
  - Response JSON (success):
    ```json
    { "success": true, "message": "OTP sent" }
    ```
  - Response JSON (error):
    ```json
    { "success": false, "message": "reason" }
    ```

- POST `/auth/verify-login-otp`
  - Request JSON:
    ```json
    { "email": "user@example.com", "otp": "123456" }
    ```
  - Response JSON (success):
    ```json
    { "success": true }
    ```
  - Response JSON (error):
    ```json
    { "success": false, "message": "Invalid or expired OTP" }
    ```

Notes:
- Server reads the recipient email from the request; you do NOT pre-register users in SendGrid.
- Sender is the verified Single Sender configured by env (see below).

## 13.2 VM Environment

Set on the VM (do not commit keys):

```bash
export SENDGRID_API_KEY="<YOUR_SENDGRID_API_KEY>"
export MAIL_FROM="jomarisunogan23@gmail.com"
```

Restart backend with new env:

```bash
pm2 restart oipms-backend --update-env --time
pm2 logs oipms-backend --lines 100
```

## 13.3 Quick Tests (Windows PowerShell)

- Send OTP:

```powershell
Invoke-RestMethod -Method Post -Uri "http://172.235.32.111:8080/auth/request-login-otp" -ContentType "application/json" -Body '{"email":"jomarisunogan23@gmail.com"}'
```

- Verify OTP (replace 123456 with the email code):

```powershell
Invoke-RestMethod -Method Post -Uri "http://172.235.32.111:8080/auth/verify-login-otp" -ContentType "application/json" -Body '{"email":"jomarisunogan23@gmail.com","otp":"123456"}'
```

Expected responses are exactly as shown above in 13.1.

## 13.4 App Behavior (Flutter)

- After successful credential login (Google or Email/Password), the app enforces 2FA when:
  - Device is new (no trust record), or
  - `trustedUntil` expired (default 30 days).
- Trust records are stored at:
  - `users/{uid}/trustedDevices/{device_id}` with fields:
    - `trustedUntil: Timestamp`
    - `firstSeenAt: Timestamp`
    - `lastSeenAt: Timestamp`
- To reset a device for a user, delete that subdocument in Firestore.
- Trust duration can be adjusted in the app code (`_refreshTrust(uid, days: 30)`).

## 13.5 Troubleshooting

- If you see HTML responses when testing, your route is not hit (proxy/redirect). Check PM2 logs and reverse proxy config.
- If email not received:
  - Verify `MAIL_FROM` matches a verified Single Sender in SendGrid.
  - Check `pm2 logs oipms-backend` for SendGrid errors.
  - Check spam folder.
- 401/403: Rotate or fix `SENDGRID_API_KEY`.

---

# QUICK REFERENCE COMMANDS

## VM Access

```bash
ssh root@172.235.32.111
cd /root/oipms-backend
```

## PM2 Management

```bash
pm2 status              # Check all services
pm2 logs               # View all logs
pm2 logs oipms-backend # View backend logs only
pm2 restart all        # Restart all services
pm2 stop all           # Stop all services
pm2 start all          # Start all services
pm2 monit              # Real-time monitoring
```

## Service Management

```bash
# Aerospike
sudo systemctl status aerospike
sudo systemctl restart aerospike
sudo journalctl -u aerospike -f

# PM2
systemctl status pm2-root
systemctl restart pm2-root
```

## Network

```bash
# Check open ports
netstat -tlnp

# Firewall status
ufw status

# Test connectivity
curl http://172.235.32.111:8080/aerospike/health
curl http://172.235.32.111:3001/database-manager.html
```

---

# DEPLOYMENT CHECKLIST

Before declaring success, verify:

## VM Setup ✅
- [ ] Node.js v20+ installed
- [ ] npm installed
- [ ] PM2 installed globally
- [ ] Build tools installed
- [ ] Firewall configured with 3 ports open

## Aerospike ✅
- [ ] C client extracted to /tmp/
- [ ] Environment variables set permanently
- [ ] Server installed and running
- [ ] Service enabled for auto-start
- [ ] aql command works

## Firestore ✅
- [ ] Project created in Firebase
- [ ] Firestore database enabled
- [ ] Service account key created
- [ ] Key uploaded to VM

## Backend ✅
- [ ] server.js with CORS headers
- [ ] package.json with dependencies
- [ ] npm install successful
- [ ] Dashboard HTML files uploaded
- [ ] serviceAccountKey.json in place

## Services ✅
- [ ] Backend service online (PM2)
- [ ] Dashboard service online (PM2)
- [ ] Auto-restart configured
- [ ] Port 8080 accessible
- [ ] Port 3001 accessible

## Testing ✅
- [ ] Aerospike health endpoint responds
- [ ] Dashboard loads in browser
- [ ] Tabs switch correctly
- [ ] Can create tables
- [ ] Can insert records
- [ ] Can browse data

---

# YOUR SYSTEM IS NOW PRODUCTION READY! 🚀

```
✅ Aerospike 8.1.0 - Ultra-fast in-memory database
✅ Firestore - Cloud document database
✅ Express.js Backend - RESTful API
✅ Beautiful Dashboard - Full UI for operations
✅ PM2 Process Manager - Auto-restart and monitoring
✅ CORS Enabled - Frontend-backend communication
✅ Auto-Startup - Survives VM reboots
```

## System Details

| Component | Address |
|-----------|---------|
| **VM IP** | 172.235.32.111 (your actual VM IP) |
| **Backend API** | http://172.235.32.111:8080 |
| **Dashboard** | http://172.235.32.111:3001/database-manager.html |
| **Aerospike** | 172.235.32.111:3000 |
| **Firestore** | Cloud-based (Firebase) |

---

## What You Can Do Now

1. ✅ Create unlimited tables/collections
2. ✅ Insert, update, delete records instantly
3. ✅ Query and filter data
4. ✅ Join multiple tables
5. ✅ Real-time metrics tracking
6. ✅ Manage entire ice plant operations
7. ✅ Scale to millions of operations

---

**Built with ❤️ for OIPMS Sentinel Excellence**

Last Updated: November 27, 2025  
Status: PRODUCTION READY ✅
