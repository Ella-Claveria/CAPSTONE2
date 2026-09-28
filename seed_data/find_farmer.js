const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

(async () => {
  const usersSnap = await db.collection('users')
    .where('email', '==', 'ellaclaveria14@gmail.com')
    .get();
  if (usersSnap.empty) {
    console.log('No user found with that email.');
    process.exit(0);
  }
  const userDoc = usersSnap.docs[0];
  console.log('UID:', userDoc.id);
  console.log('User data:', JSON.stringify(userDoc.data(), null, 2));

  const productsSnap = await db.collection('products')
    .where('farmerId', '==', userDoc.id)
    .get();
  console.log('\nProducts owned by this farmer:', productsSnap.size);
  productsSnap.forEach((doc) => {
    console.log('---');
    console.log('Product ID:', doc.id);
    console.log(JSON.stringify(doc.data(), null, 2));
  });

  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
