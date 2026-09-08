/**
 * One-time loader for AgriTrade+ sample historical data.
 *
 * Usage:
 *   npm install
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json node import.js
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json node import.js --delete
 *
 * See README.md for how to get a service account key. This script only
 * touches documents whose IDs appear in these JSON files (all prefixed
 * "seed_", plus five fixed commodity IDs in market_prices.json) — it never
 * wipes a whole collection, so it's safe to run alongside real data.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const COLLECTIONS = [
  'users',
  'products',
  'orders',
  'verificationDocs',
  'market_prices',
  'reports',
  'searchEvents',
];

const isDelete = process.argv.includes('--delete');

function loadServiceAccount() {
  const localKeyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (fs.existsSync(localKeyPath)) {
    return require(localKeyPath);
  }
  // Falls back to GOOGLE_APPLICATION_CREDENTIALS env var if no local file.
  return null;
}

const serviceAccount = loadServiceAccount();
admin.initializeApp(
  serviceAccount ? { credential: admin.credential.cert(serviceAccount) } : {}
);

const db = admin.firestore();

// Any field named like "...At" (createdAt, updatedAt, submittedAt,
// archivedAt) gets its ISO-8601 string converted to a Firestore Timestamp.
function toFirestoreValue(key, value) {
  if (typeof value === 'string' && key.endsWith('At') && !isNaN(Date.parse(value))) {
    return admin.firestore.Timestamp.fromDate(new Date(value));
  }
  return value;
}

function convertRecord(record) {
  const { _id, ...fields } = record;
  const converted = {};
  for (const [key, value] of Object.entries(fields)) {
    converted[key] = toFirestoreValue(key, value);
  }
  return { id: _id, data: converted };
}

async function run() {
  for (const collectionName of COLLECTIONS) {
    const filePath = path.join(__dirname, `${collectionName}.json`);
    if (!fs.existsSync(filePath)) continue;

    const records = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const batch = db.batch();

    for (const record of records) {
      const { id, data } = convertRecord(record);
      const ref = id ? db.collection(collectionName).doc(id) : db.collection(collectionName).doc();
      if (isDelete) {
        batch.delete(ref);
      } else {
        batch.set(ref, data, { merge: true });
      }
    }

    await batch.commit();
    console.log(
      `${isDelete ? 'Deleted' : 'Wrote'} ${records.length} doc(s) in "${collectionName}".`
    );
  }

  console.log(isDelete ? '\nSeed data removed.' : '\nSeed data loaded.');
  process.exit(0);
}

run().catch((err) => {
  console.error('Import failed:', err);
  process.exit(1);
});
