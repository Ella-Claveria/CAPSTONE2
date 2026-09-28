const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('market_sales').get();
  console.log('market_sales doc count:', snap.size);
  snap.forEach((doc) => console.log(doc.id, '->', JSON.stringify(doc.data())));
})().catch((e) => { console.error(e); process.exit(1); });
