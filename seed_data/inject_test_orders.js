const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const FARMER_ID = '2LV2yHZ60zQo7AaPC7Rtgaelbb12';
const FARMER_NAME = 'Daniella';
const PRODUCT_ID = 'tsaOcGro4bbTcMg73VnP';
const PRODUCT_NAME = 'tomato';
const IMAGE_URL = 'https://res.cloudinary.com/gxir71bo/image/upload/v1790077759/agritrade/listings/u6xxdxyskxl7i9q9mdme.jpg';
const UNIT_PRICE = 45;

function daysAgo(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return admin.firestore.Timestamp.fromDate(d);
}

const testOrders = [
  { id: 'test_order_demo_1', quantity: 5, daysBack: 2 },
  { id: 'test_order_demo_2', quantity: 8, daysBack: 1 },
  { id: 'test_order_demo_3', quantity: 3, daysBack: 0 },
];

(async () => {
  const batch = db.batch();
  for (const o of testOrders) {
    const total = o.quantity * UNIT_PRICE;
    const ts = daysAgo(o.daysBack);
    const ref = db.collection('orders').doc(o.id);
    batch.set(ref, {
      sellerId: FARMER_ID,
      sellerName: FARMER_NAME,
      buyerId: 'test_buyer_demo',
      buyerName: 'Test Buyer',
      buyerContact: '09171234567',
      buyerAddress: 'Talisay, Batangas',
      productId: PRODUCT_ID,
      productName: PRODUCT_NAME,
      imageUrl: IMAGE_URL,
      quantity: o.quantity,
      unit: 'kg',
      quantityLabel: `${o.quantity} kg`,
      unitPrice: UNIT_PRICE,
      total,
      deliveryMethod: 'Pickup',
      status: 'completed',
      createdAt: ts,
      updatedAt: ts,
    });
    console.log(`Queued ${o.id}: ${o.quantity}kg = ₱${total}`);
  }
  await batch.commit();
  console.log('\nDone — 3 test completed orders written for farmer', FARMER_ID);
})().catch((e) => { console.error(e); process.exit(1); });
