// OIPMS Sentinel - Flexible Database Management Backend
// Supports both Aerospike (NoSQL) and Firestore (Cloud) with dynamic table operations

const Aerospike = require('aerospike');
const admin = require('firebase-admin');
const express = require('express');
const path = require('path');
const http = require('http');
const { WebSocketServer } = require('ws');
const url = require('url');
const app = express();
const crypto = require('crypto');
const multer = require('multer');
// SendGrid only; no nodemailer/SMTP
// Load environment variables from .env
require('dotenv').config();

// Middleware
app.use(express.json());

// Aerospike namespace (configurable). Defaults to 'oipms'.
const AERO_NS = process.env.AEROSPIKE_NAMESPACE || 'oipms';

// ===================== CRITICAL FIX: ADD CORS HEADERS =====================
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

// Upload helpers (defined BEFORE routes that use them)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
});

async function verifyIdToken(req, res, next) {
  try {
    const h = req.headers['authorization'] || '';
    const m = /^Bearer\s+(.+)$/i.exec(h);
    if (!m) return res.status(401).json({ error: 'missing_token' });
    const decoded = await admin.auth().verifyIdToken(m[1]);
    req.uid = decoded.uid;
    next();
  } catch (e) {
    return res.status(401).json({ error: 'invalid_token' });
  }
}

// ===================== AVATAR UPLOAD (AEROSPIKE) =====================
app.post('/upload-avatar', verifyIdToken, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'file_required' });

    let contentType = req.file.mimetype || 'application/octet-stream';
    const name = (req.file.originalname || '').toLowerCase();
    const byExt = name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.webp');
    const looksImage = /^image\//i.test(contentType);
    if (!looksImage && !byExt) {
      return res.status(400).json({ error: 'invalid_type' });
    }
    // Coerce a sensible content type when client didn't send one
    if (!looksImage && byExt) {
      if (name.endsWith('.png')) contentType = 'image/png';
      else if (name.endsWith('.webp')) contentType = 'image/webp';
      else contentType = 'image/jpeg';
    }

    const id = `${req.uid}:${crypto.randomUUID()}`;
    const key = new Aerospike.Key(AERO_NS, 'profileImages', id);
    const bins = { bytes: req.file.buffer, contentType, createdAt: Date.now() };
    await aerospikeClient.put(key, bins, { ttl: 0 });

    const baseUrl = process.env.PUBLIC_BASE_URL || `http://139.162.46.103:${process.env.PORT || 8080}`;
    const url = `${baseUrl}/img/${encodeURIComponent(id)}`;
    return res.json({ id, url });
  } catch (e) {
    return res.status(500).json({ error: e.toString() });
  }
});

// ===================== TABLE STATS (FIRESTORE + AEROSPIKE) =====================
app.get('/api/tables/stats', async (req, res) => {
  try {
    const stats = [];

    // Firestore: read metadata from 'tables' collection if present
    try {
      const snap = await firestore.collection('tables').get();
      snap.forEach(doc => {
        const d = doc.data() || {};
        stats.push({
          database: 'firestore',
          name: d.name || doc.id,
          totalRecords: d.recordCount || 0,
        });
      });
    } catch (_) {}

    // Aerospike: parse 'sets' info, include objects count when available
    try {
      const setsInfo = String(await aerospikeInfo('sets'));
      // Example line fragment: ns=oipms:set=inventory:objects=123:... (format varies by version)
      const lines = setsInfo.split(/\n+/);
      for (const line of lines) {
        if (!line) continue;
        const nsMatch = /ns=([^;:]+)[;:]/.exec(line);
        const setMatch = /set=([^;:]+)[;:]/.exec(line);
        if (!nsMatch || !setMatch) continue;
        const ns = nsMatch[1];
        const setName = setMatch[1];
        if (ns !== AERO_NS) continue;
        const objMatch = /objects=(\d+)/.exec(line);
        const count = objMatch ? parseInt(objMatch[1], 10) : 0;
        stats.push({ database: 'aerospike', name: setName, totalRecords: isNaN(count) ? 0 : count });
      }
    } catch (_) {}

    res.json({ success: true, stats });
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

app.get('/img/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const key = new Aerospike.Key(AERO_NS, 'profileImages', id);
    const rec = await aerospikeClient.get(key);
    const bins = rec.bins || {};
    const body = bins.bytes;
    const ct = bins.contentType || 'application/octet-stream';
    if (!body) return res.status(404).end();
    res.setHeader('Content-Type', ct);
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    return res.end(body);
  } catch (e) {
    if (e.code === Aerospike.status.AEROSPIKE_ERR_RECORD_NOT_FOUND) return res.status(404).end();
    return res.status(500).json({ error: e.toString() });
  }
});

// Serve static assets from this folder (so /database-manager.html works)
app.use(express.static(__dirname));

async function sendMail(to, subject, text) {
  const from = process.env.MAIL_FROM;
  const sgKey = process.env.SENDGRID_API_KEY;
  if (!from || !sgKey) {
    throw new Error('SendGrid not configured');
  }
  console.log('sendMail: using SendGrid', { from, to });
  const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sgKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: from },
      subject,
      content: [{ type: 'text/plain', value: text }]
    })
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`SendGrid API error: ${res.status} ${body}`);
  }
}

// Twilio SMS sender
async function sendSms(to, body) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_FROM;
  if (!sid || !token || !from) throw new Error('Twilio not configured');
  console.log('sendSms: using Twilio', { from, to });
  const url = `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`;
  const params = new URLSearchParams();
  params.append('To', to);
  params.append('From', from);
  params.append('Body', body);
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Basic ' + Buffer.from(`${sid}:${token}`).toString('base64')
    },
    body: params.toString()
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Twilio API error: ${res.status} ${t}`);
  }
}

// ===================== AEROSPIKE INFO (generic) =====================
app.get('/aerospike/info', async (req, res) => {
  try {
    const { cmd } = req.query;
    if (!cmd) return res.status(400).json({ error: 'cmd is required' });
    const out = await aerospikeInfo(String(cmd));
    res.json({ success: true, cmd, output: out });
  } catch (e) {
    res.status(500).json({ error: e.toString() });
  }
});

// ===================== LOGIN 2FA OTP (EMAIL) =====================
// POST /auth/request-login-otp
// Body: { email }
// Response: { success: true, message: 'OTP sent' } OR { success: false, message }
app.post('/auth/request-login-otp', async (req, res) => {
  try {
    const { email } = req.body || {};
    if (!email) return res.status(400).json({ success: false, message: 'email required' });

    let uid, authEmail;
    try {
      const user = await admin.auth().getUserByEmail(String(email).trim());
      uid = user.uid;
      authEmail = user.email;
    } catch (e) {
      // Avoid email enumeration: pretend success
      return res.json({ success: true, message: 'OTP sent' });
    }

    const otp = String(Math.floor(100000 + Math.random() * 900000));
    const hash = crypto.createHash('sha256').update(otp).digest('hex');
    const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000));
    const data = {
      hash,
      attempts: 0,
      maxAttempts: 5,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    };
    await firestore.collection('_loginOtps').doc(uid).set(data);

    await sendMail(authEmail, 'Your login verification code', `Your OTP is ${otp}. It will expire in 10 minutes.`);
    return res.json({ success: true, message: 'OTP sent' });
  } catch (e) {
    return res.status(500).json({ success: false, message: 'send failed' });
  }
});

// POST /auth/verify-login-otp
// Body: { email, otp }
// Response: { success: true } OR { success: false, message: 'Invalid or expired OTP' }
app.post('/auth/verify-login-otp', async (req, res) => {
  try {
    const { email, otp } = req.body || {};
    if (!email || !otp) return res.status(400).json({ success: false, message: 'email and otp required' });

    let uid;
    try {
      const user = await admin.auth().getUserByEmail(String(email).trim());
      uid = user.uid;
    } catch (e) {
      // Unknown email -> generic failure (avoid enumeration)
      return res.json({ success: false, message: 'Invalid or expired OTP' });
    }

    const ref = firestore.collection('_loginOtps').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) return res.json({ success: false, message: 'Invalid or expired OTP' });
    const d = snap.data() || {};

    const now = new Date();
    const exp = d.expiresAt && d.expiresAt.toDate ? d.expiresAt.toDate() : new Date(0);
    if (exp < now) {
      await ref.delete().catch(() => {});
      return res.json({ success: false, message: 'Invalid or expired OTP' });
    }

    const attempt = (d.attempts || 0) + 1;
    const maxAttempts = d.maxAttempts || 5;
    const inHash = crypto.createHash('sha256').update(String(otp)).digest('hex');
    if (inHash !== d.hash) {
      if (attempt >= maxAttempts) {
        await ref.delete().catch(() => {});
      } else {
        await ref.update({ attempts: attempt }).catch(() => {});
      }
      return res.json({ success: false, message: 'Invalid or expired OTP' });
    }

    await ref.delete().catch(() => {});
    return res.json({ success: true });
  } catch (e) {
    return res.status(500).json({ success: false, message: 'server_error' });
  }
});

// ===================== READ SINGLE RECORD =====================
app.get('/api/tables/:tableName/records/:recordId', async (req, res) => {
  try {
    const { tableName, recordId } = req.params;
    const { database } = req.query;

    if (!database) return res.status(400).json({ error: 'database query parameter required' });

    if (database === 'firestore') {
      const doc = await firestore.collection(tableName).doc(recordId).get();
      if (!doc.exists) return res.status(404).json({ error: 'Not found' });
      return res.json({ database: 'firestore', table: tableName, id: doc.id, record: doc.data() });
    } else if (database === 'aerospike') {
      const key = new Aerospike.Key(AERO_NS, tableName, recordId);
      try {
        const rec = await aerospikeClient.get(key);
        // Normalize legacy shape where a 'bins' bin was stored
        let bins = rec.bins || {};
        if (bins && typeof bins.bins === 'object') {
          bins = bins.bins;
        }
        return res.json({ database: 'aerospike', table: tableName, id: recordId, record: bins });
      } catch (e) {
        if (e.code === Aerospike.status.AEROSPIKE_ERR_RECORD_NOT_FOUND) {
          return res.status(404).json({ error: 'Not found' });
        }
        throw e;
      }
    } else {
      res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

app.post('/auth/request-password-otp', async (req, res) => {
  try {
    const { email, phone, channel } = req.body || {};
    const ch = (channel || 'email').toString().toLowerCase();
    if (ch === 'sms') {
      if (!phone) return res.status(400).json({ error: 'phone required for sms' });
      // Resolve uid by phone from Firestore users collection (phone stored as array)
      const snap = await firestore.collection('users').where('phone', 'array-contains', String(phone).trim()).limit(1).get();
      if (snap.empty) return res.json({ success: true }); // avoid enumeration
      const uid = snap.docs[0].id;

      const otp = String(Math.floor(100000 + Math.random() * 900000));
      const hash = crypto.createHash('sha256').update(otp).digest('hex');
      const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000));
      const data = { hash, attempts: 0, maxAttempts: 5, createdAt: admin.firestore.FieldValue.serverTimestamp(), expiresAt };
      await firestore.collection('_passwordOtps').doc(uid).set(data);

      await sendSms(String(phone).trim(), `Your OTP is ${otp}. It will expire in 10 minutes.`);
      return res.json({ success: true });
    } else {
      if (!email) return res.status(400).json({ error: 'email required' });
      const user = await admin.auth().getUserByEmail(String(email).trim());

      const otp = String(Math.floor(100000 + Math.random() * 900000));
      const hash = crypto.createHash('sha256').update(otp).digest('hex');
      const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000));
      const data = { hash, attempts: 0, maxAttempts: 5, createdAt: admin.firestore.FieldValue.serverTimestamp(), expiresAt };
      await firestore.collection('_passwordOtps').doc(user.uid).set(data);

      await sendMail(user.email, 'Your password reset code', `Your OTP is ${otp}. It will expire in 10 minutes.`);
      return res.json({ success: true });
    }
  } catch (e) {
    if (e.code === 'auth/user-not-found') return res.json({ success: true });
    return res.status(500).json({ error: e.toString() });
  }
});

app.post('/auth/reset-password-with-otp', async (req, res) => {
  try {
    const { email, phone, otp, newPassword } = req.body || {};
    if ((!email && !phone) || !otp || !newPassword) return res.status(400).json({ error: 'email_or_phone, otp, newPassword required' });

    let uid, authEmail;
    if (phone) {
      const snap = await firestore.collection('users').where('phone', 'array-contains', String(phone).trim()).limit(1).get();
      if (snap.empty) return res.status(400).json({ error: 'invalid_or_expired' });
      uid = snap.docs[0].id;
      authEmail = snap.docs[0].data().email;
    } else {
      const user = await admin.auth().getUserByEmail(String(email).trim());
      uid = user.uid;
      authEmail = user.email;
    }

    const ref = firestore.collection('_passwordOtps').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) return res.status(400).json({ error: 'invalid_or_expired' });
    const d = snap.data() || {};

    const now = new Date();
    const exp = d.expiresAt && d.expiresAt.toDate ? d.expiresAt.toDate() : new Date(0);
    if (exp < now) {
      await ref.delete().catch(() => {});
      return res.status(400).json({ error: 'invalid_or_expired' });
    }

    const attempt = (d.attempts || 0) + 1;
    const maxAttempts = d.maxAttempts || 5;
    const inHash = crypto.createHash('sha256').update(String(otp)).digest('hex');
    if (inHash !== d.hash) {
      if (attempt >= maxAttempts) {
        await ref.delete().catch(() => {});
      } else {
        await ref.update({ attempts: attempt }).catch(() => {});
      }
      return res.status(400).json({ error: 'invalid_or_expired' });
    }

    await admin.auth().updateUser(uid, { password: String(newPassword) });
    await ref.delete().catch(() => {});
    return res.json({ success: true });
  } catch (e) {
    if (e.code === 'auth/user-not-found') return res.status(400).json({ error: 'invalid_or_expired' });
    return res.status(500).json({ error: e.toString() });
  }
});

// ===================== SIMPLE QUERY API =====================
// Supported SQL (basic):
//   SELECT * FROM <table> [WHERE <field> = <value>] [LIMIT n]
// Notes:
// - WHERE supports only equality and a single condition. Value may be 'single-quoted' or "double-quoted" or bare for numbers/booleans.
app.post('/api/query', async (req, res) => {
  try {
    const { database, sql } = req.body || {};
    if (!database || !sql) return res.status(400).json({ error: 'database and sql are required' });

    // Parse: SELECT * FROM table [WHERE field = value] [LIMIT n]
    const m = /\s*select\s+\*\s+from\s+([a-zA-Z0-9_\-]+)(?:\s+where\s+([a-zA-Z0-9_\-]+)\s*=\s*(?:'([^']*)'|"([^"]*)"|([^\s;]+)))?(?:\s+limit\s+(\d+))?\s*;?\s*$/i.exec(sql);
    if (!m) return res.status(400).json({ error: 'Only SELECT * FROM <table> [WHERE field = value] [LIMIT n] is supported' });
    const tableName = m[1];
    const whereField = m[2];
    const whereValStr = m[3] ?? m[4] ?? m[5]; // quoted or bare
    const limit = m[6] ? parseInt(m[6], 10) : undefined;

    // Best-effort type coercion for bare values (number/boolean), else string
    const coerceValue = (v) => {
      if (v === undefined) return undefined;
      const low = String(v).toLowerCase();
      if (low === 'true') return true; if (low === 'false') return false;
      const n = Number(v); if (!isNaN(n) && String(n) === String(v)) return n;
      return v;
    };
    const whereValue = coerceValue(whereValStr);

    if (database === 'firestore') {
      let q = firestore.collection(tableName);
      if (whereField !== undefined) q = q.where(whereField, '==', whereValue);
      if (limit) q = q.limit(limit);
      const snapshot = await q.get();
      const records = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
      return res.json({ success: true, database: 'firestore', table: tableName, count: records.length, records });
    } else if (database === 'aerospike') {
      const records = [];
      const scan = aerospikeClient.scan(AERO_NS, tableName);
      const stream = scan.foreach();
      stream.on('data', (r) => {
        let bins = r.bins || {};
        if (bins && typeof bins.bins === 'object') bins = bins.bins;
        const obj = { id: r.key && r.key.key, ...bins };
        // Apply client-side filter if requested
        if (whereField !== undefined) {
          if (obj[whereField] === whereValue) {
            records.push(obj);
          }
        } else {
          records.push(obj);
        }
        if (limit && records.length >= limit) {
          stream.abort();
        }
      });
      stream.on('error', (err) => res.status(500).json({ error: err.toString() }));
      stream.on('end', () => res.json({ success: true, database: 'aerospike', table: tableName, count: records.length, records }));
    } else {
      return res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== AEROSPIKE FLUSH (truncate all sets) =====================
app.post('/aerospike/flush', async (req, res) => {
  try {
    const setsInfo = String(await aerospikeInfo('sets'));
    const re = /ns=([^;\s]+)[^\n]*?set=([^;\s]+)/g;
    const promises = [];
    let m;
    while ((m = re.exec(setsInfo)) !== null) {
      const ns = m[1];
      const setName = m[2];
      if (ns !== AERO_NS || !setName) continue;
      promises.push(new Promise((resolve, reject) => {
        aerospikeClient.truncate(ns, setName, new Date(), (err) => err ? reject(err) : resolve());
      }));
    }
    await Promise.all(promises);
    res.json({ success: true, message: `All sets in ${AERO_NS} truncated` });
  } catch (e) {
    res.status(500).json({ error: e.toString() });
  }
});

// ===================== DELETE TABLE (metadata + optional data) =====================
async function deleteFirestoreCollection(collectionName) {
  const batchSize = 300;
  while (true) {
    const snapshot = await firestore.collection(collectionName).limit(batchSize).get();
    if (snapshot.empty) break;
    const batch = firestore.batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    if (snapshot.size < batchSize) break;
  }
}

app.delete('/api/tables/:tableName', async (req, res) => {
  try {
    const { tableName } = req.params;
    const { database, dropData } = req.query; // dropData=true to remove all records

    if (!database) return res.status(400).json({ error: 'database query parameter required' });

    if (database === 'firestore') {
      if (dropData === 'true') {
        await deleteFirestoreCollection(tableName);
      }
      await firestore.collection('tables').doc(tableName).delete().catch(() => {});
      return res.json({ success: true, message: `Firestore collection ${tableName} deleted${dropData==='true'?' with data':''}` });
    } else if (database === 'aerospike') {
      // Aerospike sets cannot be dropped via client API; clear metadata only
      await firestore.collection('tables').doc(tableName).delete().catch(() => {});
      return res.json({ success: true, message: `Aerospike set ${tableName} metadata removed` });
    } else {
      return res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});
// ===================== Firebase Admin Initialization =====================
// Initialize using local service account to avoid ADC mismatch and project ID typos
let firestore;
try {
  const serviceAccount = require('./serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id
  });
  firestore = admin.firestore();
  console.log('Firebase initialized for project:', serviceAccount.project_id);
} catch (e) {
  console.error('Failed to load serviceAccountKey.json. Ensure the file exists and is valid.', e);
  throw e;
}

// ===================== Aerospike Connection =====================
const aerospikeConfig = {
  hosts: [{ addr: '139.162.46.103', port: 3000 }]
};

const aerospikeClient = Aerospike.client(aerospikeConfig);

aerospikeClient.connect((err) => {
  if (err) {
    console.error('Failed to connect to Aerospike:', err);
  } else {
    console.log('Connected to Aerospike at 139.162.46.103:3000');
    console.log('Using Aerospike namespace:', AERO_NS);
  }
});

// ===================== Aerospike Diagnostics =====================
async function aerospikeInfo(cmd) {
  return new Promise((resolve, reject) => {
    aerospikeClient.infoAny(cmd, (err, response) => {
      if (err) return reject(err);
      resolve(String(response));
    });
  });
}

// ===================== CREATE TABLE =====================
app.post('/api/tables', async (req, res) => {
  try {
    const { tableName, database, schema } = req.body;

    if (!tableName || !database) {
      return res.status(400).json({ error: 'tableName and database required' });
    }

    if (database === 'aerospike') {
      // Record metadata so UI can list Aerospike sets too
      await firestore.collection('tables').doc(tableName).set({
        name: tableName,
        schema: schema || {},
        database: 'aerospike',
        createdAt: new Date().toISOString(),
        recordCount: 0
      });

      res.json({
        success: true,
        message: 'Set ' + tableName + ' will be created on first insert',
        database: 'aerospike',
        tableName
      });
    } else if (database === 'firestore') {
      await firestore.collection('tables').doc(tableName).set({
        name: tableName,
        schema: schema || {},
        database: 'firestore',
        createdAt: new Date().toISOString(),
        recordCount: 0
      });

      res.json({
        success: true,
        message: 'Collection ' + tableName + ' created in Firestore',
        database: 'firestore',
        tableName
      });
    } else {
      res.status(400).json({ error: 'Invalid database. Use aerospike or firestore' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== LIST TABLES =====================
app.get('/api/tables', async (req, res) => {
  try {
    const { database } = req.query;
    const snapshot = await firestore.collection('tables').get();
    const tablesMap = new Map();

    // 1) Include metadata-defined tables (both firestore and aerospike)
    snapshot.forEach(doc => {
      const data = doc.data() || {};
      const name = data.name || doc.id;
      if (!name) return;
      tablesMap.set(name, {
        name,
        database: data.database || 'firestore',
        recordCount: data.recordCount || 0,
        schema: data.schema || {}
      });
    });

    // 2) For Firestore, also list actual root collections so existing ones like 'users' appear
    if (!database || database === 'firestore') {
      const collections = await firestore.listCollections();
      for (const col of collections) {
        const name = col.id;
        if (!name || name === 'tables' || name.startsWith('_')) continue; // skip metadata/system
        if (!tablesMap.has(name)) {
          tablesMap.set(name, {
            name,
            database: 'firestore',
            recordCount: 0,
            schema: {}
          });
        }
      }
    }

    // 3) For Aerospike, enumerate sets from the server and merge (namespace-agnostic)
    if (!database || database === 'aerospike') {
      try {
        const setsInfo = String(await aerospikeInfo('sets'));
        // Match any 'ns=<ns>;...;set=<set>' pair across the whole blob
        const re = /ns=([^;\s]+)[^\n]*?set=([^;\s]+)/g;
        let m;
        while ((m = re.exec(setsInfo)) !== null) {
          const ns = m[1];
          const setName = m[2];
          if (!setName) continue;
          if (ns !== AERO_NS) continue; // limit to the configured namespace
          const key = `${ns}:${setName}`;
          if (!tablesMap.has(key)) {
            tablesMap.set(key, {
              name: setName,
              namespace: ns,
              database: 'aerospike',
              recordCount: 0,
              schema: {}
            });
          }
        }

        // Fallback: if 'inventory' records exist but 'sets' didn't list it, add it
        const invKeyBlock = new Aerospike.Key(AERO_NS, 'inventory', 'Ice Block');
        const invKeyCube = new Aerospike.Key(AERO_NS, 'inventory', 'Ice Cube');
        let hasInventory = false;
        try { await aerospikeClient.get(invKeyBlock); hasInventory = true; } catch (_) {}
        if (!hasInventory) { try { await aerospikeClient.get(invKeyCube); hasInventory = true; } catch (_) {} }
        if (hasInventory) {
          const invKey = `${AERO_NS}:inventory`;
          if (!tablesMap.has(invKey)) {
            tablesMap.set(invKey, {
              name: 'inventory',
              namespace: AERO_NS,
              database: 'aerospike',
              recordCount: 0,
              schema: {}
            });
          }
        }
      } catch (e) {
        console.warn('Aerospike set enumeration failed:', e.toString());
      }
    }

    let tables = Array.from(tablesMap.values());
    if (database === 'firestore' || database === 'aerospike') {
      tables = tables.filter(t => t.database === database);
    }
    // Sort by name for stable UI
    tables.sort((a, b) => a.name.localeCompare(b.name));
    res.json({ success: true, tables });
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== INSERT DATA =====================
app.post('/api/tables/:tableName/records', async (req, res) => {
  try {
    const { tableName } = req.params;
    const { database, record, primaryKey } = req.body;

    if (!database || !record) {
      return res.status(400).json({ error: 'database and record required' });
    }

    if (database === 'aerospike') {
      const key = new Aerospike.Key(AERO_NS, tableName, primaryKey || record.id || Date.now().toString());
      await aerospikeClient.put(key, { bins: record });

      // If prices set changed, broadcast latest prices to SSE subscribers
      if (tableName === 'prices') {
        try {
          const snap = await readPricesSnapshot(AERO_NS);
          broadcastPrices(AERO_NS, snap);
        } catch (_) {}
      }
      // If sales_history set changed, broadcast latest sales snapshot to SSE subscribers
      if (tableName === 'sales_history') {
        try {
          const snap = await readSalesHistorySnapshot(AERO_NS);
          broadcastSalesHistory(AERO_NS, snap);
        } catch (_) {}
      }

      res.json({
        success: true,
        message: 'Record inserted into Aerospike.' + tableName,
        key: key.key,
        record
      });
    } else if (database === 'firestore') {
      const docId = primaryKey || record.id || Date.now().toString();
      await firestore.collection(tableName).doc(docId).set(record);

      await firestore.collection('tables').doc(tableName).update({
        recordCount: admin.firestore.FieldValue.increment(1)
      });

      res.json({
        success: true,
        message: 'Record inserted into Firestore.' + tableName,
        docId,
        record
      });
    } else {
      res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== READ ALL RECORDS =====================
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
      const records = [];
      try {
        const scan = aerospikeClient.scan(AERO_NS, tableName);
        const stream = scan.foreach();
        stream.on('data', (r) => {
          // Normalize to flat object: include 'id' and all bins at top-level
          let bins = r.bins || {};
          if (bins && typeof bins.bins === 'object') {
            bins = bins.bins; // legacy records where we mistakenly wrote { bins: {...} }
          }
          records.push({ id: r.key && r.key.key, ...bins });
        });
        stream.on('error', (err) => {
          return res.status(500).json({ error: err.toString() });
        });
        stream.on('end', () => {
          res.json({
            database: 'aerospike',
            table: tableName,
            count: records.length,
            records
          });
        });
      } catch (e) {
        return res.status(500).json({ error: e.toString() });
      }
    } else {
      res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== UPDATE RECORD =====================
app.put('/api/tables/:tableName/records/:recordId', async (req, res) => {
  try {
    const { tableName, recordId } = req.params;
    const { database, record } = req.body;

    if (!database || !record) {
      return res.status(400).json({ error: 'database and record required' });
    }

    if (database === 'firestore') {
      await firestore.collection(tableName).doc(recordId).update(record);

      res.json({
        success: true,
        message: 'Record updated in Firestore.' + tableName,
        recordId
      });
    } else if (database === 'aerospike') {
      const key = new Aerospike.Key(AERO_NS, tableName, recordId);
      await aerospikeClient.put(key, record);

      res.json({
        success: true,
        message: 'Record updated in Aerospike.' + tableName,
        recordId
      });
    } else {
      res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== DELETE RECORD =====================
app.delete('/api/tables/:tableName/records/:recordId', async (req, res) => {
  try {
    const { tableName, recordId } = req.params;
    const { database } = req.query;

    if (!database) {
      return res.status(400).json({ error: 'database query parameter required' });
    }

    if (database === 'firestore') {
      await firestore.collection(tableName).doc(recordId).delete();

      await firestore.collection('tables').doc(tableName).update({
        recordCount: admin.firestore.FieldValue.increment(-1)
      });

      res.json({
        success: true,
        message: 'Record deleted from Firestore.' + tableName,
        recordId
      });
    } else if (database === 'aerospike') {
      const key = new Aerospike.Key(AERO_NS, tableName, recordId);
      await aerospikeClient.remove(key);

      res.json({
        success: true,
        message: 'Record deleted from Aerospike.' + tableName,
        recordId
      });
    } else {
      res.status(400).json({ error: 'Invalid database' });
    }
  } catch (err) {
    res.status(500).json({ error: err.toString() });
  }
});

// ===================== HEALTH CHECK =====================
app.get('/aerospike-health', async (req, res) => {
  try {
    if (!aerospikeClient.isConnected()) {
      return res.status(503).json({
        ok: false,
        error: 'Not connected'
      });
    }

    const [services, namespaces, builds] = await Promise.all([
      aerospikeInfo('services'),
      aerospikeInfo('namespaces'),
      aerospikeInfo('build')
    ]);

    res.json({
      ok: true,
      services: services.trim().split('\n').filter(Boolean),
      namespaces: namespaces.trim().split('\n').filter(Boolean),
      build: builds.trim()
    });
  } catch (e) {
    res.status(500).json({
      ok: false,
      error: e.toString()
    });
  }
});

// ===================== DASHBOARD METRICS =====================
app.get('/dashboard-metrics', (req, res) => {
  res.json({
    currentSales: 5000,
    currentProduction: 2500,
    currentRevenue: 25000,
    dailySalesGoal: 10000,
    dailyProductionGoal: 5000,
    dailyRevenueGoal: 50000
  });
});

// Serve the database manager UI
app.get('/database-manager', (req, res) => {
  res.sendFile(path.join(__dirname, 'database-manager.html'));
});

// ===================== INVENTORY (OIPMS) =====================
// Helper to build Aerospike key for inventory items by type
function invKey(ns, type) {
  return new Aerospike.Key(ns, 'inventory', type);
}

async function readInventorySnapshot(ns) {
  const types = ['Ice Block', 'Ice Cube'];
  const items = [];
  for (const t of types) {
    try {
      const rec = await aerospikeClient.get(invKey(ns, t));
      const bins = rec.bins || {};
      items.push({
        type: t,
        inStock: Number(bins.inStock || 0),
        inProduction: Number(bins.inProduction || 0),
      });
    } catch (e) {
      if (e.code === Aerospike.status.AEROSPIKE_ERR_RECORD_NOT_FOUND) {
        items.push({ type: t, inStock: 0, inProduction: 0 });
      } else {
        throw e;
      }
    }
  }
  return items;
}

// Read all price records from Aerospike 'prices' set
async function readPricesSnapshot(ns) {
  const records = [];
  try {
    const scan = aerospikeClient.scan(ns, 'prices');
    const stream = scan.foreach();
    await new Promise((resolve, reject) => {
      stream.on('data', (r) => {
        let bins = r.bins || {};
        if (bins && typeof bins.bins === 'object') bins = bins.bins;
        records.push({ id: r.key && r.key.key, ...bins });
      });
      stream.on('error', (err) => reject(err));
      stream.on('end', () => resolve());
    });
  } catch (_) {}
  return records;
}

// Read all sales_history records from Aerospike 'sales_history' set
async function readSalesHistorySnapshot(ns) {
  const records = [];
  try {
    const scan = aerospikeClient.scan(ns, 'sales_history');
    const stream = scan.foreach();
    await new Promise((resolve, reject) => {
      stream.on('data', (r) => {
        let bins = r.bins || {};
        if (bins && typeof bins.bins === 'object') bins = bins.bins;
        records.push({ id: r.key && r.key.key, ...bins });
      });
      stream.on('error', (err) => reject(err));
      stream.on('end', () => resolve());
    });
  } catch (_) {}
  return records;
}

// GET /api/inventory?ns=oipms&set=inventory
app.get('/api/inventory', verifyIdToken, async (req, res) => {
  try {
    const ns = (req.query.ns || AERO_NS).toString();
    // set param reserved for future multiplexing; we always use 'inventory'
    const data = await readInventorySnapshot(ns);
    return res.json(data);
  } catch (e) {
    return res.status(500).json({ error: e.toString() });
  }
});

// POST /api/inventory/update { ns, set, type, inStock?, inProduction? }
app.post('/api/inventory/update', verifyIdToken, async (req, res) => {
  try {
    const { ns, set, type, inStock, inProduction } = req.body || {};
    const namespace = (ns || AERO_NS).toString();
    const t = (type || '').toString();
    if (!t) return res.status(400).json({ error: 'type required' });
    const bins = {};
    if (inStock !== undefined) bins.inStock = Number(inStock);
    if (inProduction !== undefined) bins.inProduction = Number(inProduction);
    if (Object.keys(bins).length === 0) {
      return res.status(400).json({ error: 'inStock or inProduction required' });
    }
    await aerospikeClient.put(invKey(namespace, t), bins, { ttl: 0 });
    const snap = await readInventorySnapshot(namespace);
    broadcastInventory(namespace, snap);
    return res.json({ success: true });
  } catch (e) {
    return res.status(500).json({ error: e.toString() });
  }
});

// ===================== SSE STREAM =====================
const sseClients = new Map(); // key: `${ns}:inventory` -> Set(res)

app.get('/api/inventory/stream', verifyIdToken, (req, res) => {
  const ns = (req.query.ns || AERO_NS).toString();
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders && res.flushHeaders();

  const key = `${ns}:inventory`;
  if (!sseClients.has(key)) sseClients.set(key, new Set());
  sseClients.get(key).add(res);

  req.on('close', () => {
    const set = sseClients.get(key);
    if (set) set.delete(res);
  });
});

function broadcastInventory(ns, data) {
  // WS
  const key = `${ns}:inventory`;
  const set = wsClients.get(key);
  if (set) {
    const msg = JSON.stringify(data);
    for (const ws of set) {
      try { ws.readyState === 1 && ws.send(msg); } catch (_) {}
    }
  }
  // SSE
  const sseSet = sseClients.get(key);
  if (sseSet) {
    const payload = `data: ${JSON.stringify(data)}\n\n`;
    for (const resp of sseSet) {
      try { resp.write(payload); } catch (_) {}
    }
  }
}

// SSE: prices
app.get('/api/prices/stream', verifyIdToken, async (req, res) => {
  const ns = (req.query.ns || AERO_NS).toString();
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders && res.flushHeaders();

  const key = `${ns}:prices`;
  if (!sseClients.has(key)) sseClients.set(key, new Set());
  sseClients.get(key).add(res);

  // Send initial snapshot
  try {
    const snap = await readPricesSnapshot(ns);
    const payload = `data: ${JSON.stringify(snap)}\n\n`;
    res.write(payload);
  } catch (_) {}

  req.on('close', () => {
    const set = sseClients.get(key);
    if (set) set.delete(res);
  });
});

function broadcastPrices(ns, data) {
  const key = `${ns}:prices`;
  const sseSet = sseClients.get(key);
  if (sseSet) {
    const payload = `data: ${JSON.stringify(data)}\n\n`;
    for (const resp of sseSet) {
      try { resp.write(payload); } catch (_) {}
    }
  }
}

// SSE: sales history
app.get('/api/sales_history/stream', verifyIdToken, async (req, res) => {
  const ns = (req.query.ns || AERO_NS).toString();
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders && res.flushHeaders();

  const key = `${ns}:sales_history`;
  if (!sseClients.has(key)) sseClients.set(key, new Set());
  sseClients.get(key).add(res);

  try {
    const snap = await readSalesHistorySnapshot(ns);
    const payload = `data: ${JSON.stringify(snap)}\n\n`;
    res.write(payload);
  } catch (_) {}

  req.on('close', () => {
    const set = sseClients.get(key);
    if (set) set.delete(res);
  });
});

function broadcastSalesHistory(ns, data) {
  const key = `${ns}:sales_history`;
  const sseSet = sseClients.get(key);
  if (sseSet) {
    const payload = `data: ${JSON.stringify(data)}\n\n`;
    for (const resp of sseSet) {
      try { resp.write(payload); } catch (_) {}
    }
  }
}

// ===================== START SERVER WITH WS =====================
const PORT = process.env.PORT || 8080;
const server = http.createServer(app);

// WS server for inventory
const wss = new WebSocketServer({ noServer: true });
const wsClients = new Map(); // key: `${ns}:inventory` -> Set(ws)

server.on('upgrade', async (request, socket, head) => {
  const pathname = url.parse(request.url).pathname;
  if (pathname === '/ws/inventory') {
    // Auth check for WS using Authorization: Bearer <token>
    try {
      const h = request.headers['authorization'] || '';
      const m = /^Bearer\s+(.+)$/i.exec(h);
      if (!m) return socket.destroy();
      await admin.auth().verifyIdToken(m[1]);
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    } catch (e) {
      return socket.destroy();
    }
  } else {
    socket.destroy();
  }
});

wss.on('connection', async (ws, request) => {
  const q = url.parse(request.url, true).query || {};
  const ns = (q.ns || AERO_NS).toString();
  const key = `${ns}:inventory`;
  if (!wsClients.has(key)) wsClients.set(key, new Set());
  wsClients.get(key).add(ws);

  ws.on('close', () => {
    const set = wsClients.get(key);
    if (set) set.delete(ws);
  });

  // Send initial snapshot
  try {
    const snap = await readInventorySnapshot(ns);
    ws.send(JSON.stringify(snap));
  } catch (_) {}
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend API running on port ${PORT}`);
  console.log('Aerospike target host: 139.162.46.103:3000');
});

// Graceful shutdown
process.on('SIGTERM', () => {
  aerospikeClient.close();
  process.exit(0);
});
