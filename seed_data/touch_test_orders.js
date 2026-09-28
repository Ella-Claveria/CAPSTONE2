const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const ORDER_IDS = ['test_order_demo_1', 'test_order_demo_2', 'test_order_demo_3'];

(async () => {
  const batch = db.batch();
  for (const id of ORDER_IDS) {
    batch.update(db.collection('orders').doc(id), {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log('Touched', ORDER_IDS.length, 'orders — recordMarketSale should fire now.');
})().catch((e) => { console.error(e); process.exit(1); });
