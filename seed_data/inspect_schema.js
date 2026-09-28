const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  console.log('=== market_prices ===');
  const prices = await db.collection('market_prices').get();
  prices.forEach((d) => console.log(d.id, JSON.stringify(d.data())));

  console.log('\n=== products: distinct categories ===');
  const products = await db.collection('products').get();
  const cats = new Set();
  products.forEach((d) => cats.add(d.data().category));
  console.log([...cats]);
  console.log('total products:', products.size);

  console.log('\n=== orders: sample doc fields (first 3) ===');
  const orders = await db.collection('orders').limit(3).get();
  orders.forEach((d) => console.log(d.id, Object.keys(d.data()).sort()));
  console.log('total orders:', (await db.collection('orders').get()).size);

  console.log('\n=== orders: completed count ===');
  const completed = await db.collection('orders').where('status', '==', 'completed').get();
  console.log('completed orders:', completed.size);
  completed.forEach((d) => {
    const data = d.data();
    console.log(d.id, '| productName:', data.productName, '| category:', data.category, '| total:', data.total, '| createdAt:', data.createdAt?.toDate?.());
  });

  console.log('\n=== users: role/approvalStatus breakdown ===');
  const users = await db.collection('users').get();
  const roleCounts = {};
  users.forEach((d) => {
    const r = d.data().role || 'unknown';
    const a = d.data().approvalStatus || 'n/a';
    const key = `${r}:${a}`;
    roleCounts[key] = (roleCounts[key] || 0) + 1;
  });
  console.log(roleCounts);

  console.log('\n=== reports: sample fields ===');
  const reports = await db.collection('reports').limit(2).get();
  reports.forEach((d) => console.log(d.id, Object.keys(d.data()).sort()));
  console.log('total reports:', (await db.collection('reports').get()).size);

  console.log('\n=== verificationDocs: sample fields ===');
  const verif = await db.collection('verificationDocs').limit(2).get();
  verif.forEach((d) => console.log(d.id, Object.keys(d.data()).sort()));

  console.log('\n=== searchEvents: sample fields ===');
  const search = await db.collection('searchEvents').limit(2).get();
  search.forEach((d) => console.log(d.id, Object.keys(d.data()).sort()));

  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
