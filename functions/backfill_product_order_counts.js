// One-time: fills in products/{id}.completedOrderCount for listings whose
// orders were completed before syncProductCompletedOrders existed (that
// function only runs when an order changes). Counts each product's orders
// with status 'completed' and writes just that one number — nothing else on
// the product is touched. Safe to run again. Run from an authenticated
// environment with Firebase Admin ADC:
//   gcloud auth application-default login
//   node functions/backfill_product_order_counts.js
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (!getApps().length) initializeApp({ projectId: "agritrade-bef87" });
const db = getFirestore();

async function main() {
  const products = await db.collection("products").get();
  let updated = 0;
  for (const product of products.docs) {
    const count = (await db.collection("orders")
      .where("productId", "==", product.id)
      .where("status", "==", "completed")
      .count()
      .get()).data().count;
    if (product.data().completedOrderCount !== count) {
      await product.ref.update({ completedOrderCount: count });
      updated += 1;
    }
    console.log(`${product.id} | ${product.data().name || "(no name)"} | completed orders: ${count}`);
  }
  console.log(`\n${products.size} product(s) checked, ${updated} updated.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
