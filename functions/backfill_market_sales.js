// One-time migration for completed orders recorded in market_sales before
// recordMarketSale stored the order type, category and buyer area that the
// Farmer Dashboard's Best-Selling Products / Top Buyer Locations use. Run
// from an authenticated environment with Firebase Admin ADC:
//   node functions/backfill_market_sales.js
// Reads completed orders and their buyers' municipality; writes only the
// same anonymized fields recordMarketSale does (see marketSaleDemandFields
// in index.js) — never who the buyer or seller was. Safe to run again.
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (!getApps().length) initializeApp();
const db = getFirestore();

async function main() {
  const municipalityByBuyer = new Map();
  async function buyerArea(buyerId) {
    if (!buyerId) return "";
    if (!municipalityByBuyer.has(buyerId)) {
      const snap = await db.collection("users").doc(buyerId).get();
      const municipality = snap.exists ? snap.data().municipality : null;
      municipalityByBuyer.set(buyerId, typeof municipality === "string" ? municipality.trim() : "");
    }
    return municipalityByBuyer.get(buyerId);
  }

  let cursor = null;
  let total = 0;
  while (true) {
    let query = db.collection("orders").where("status", "==", "completed").orderBy("__name__").limit(300);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      const order = doc.data();
      const productName = (order.productName || "").toString().trim();
      if (!productName) continue;
      const completedAt = order.completedAt || order.updatedAt || order.createdAt;
      batch.set(
        db.collection("market_sales").doc(doc.id),
        {
          productName,
          quantity: typeof order.quantity === "number" ? order.quantity : Number(order.quantity) || 0,
          unit: (order.unit || "").toString().trim(),
          status: "completed",
          pricingType: order.pricingType === "wholesale" ? "wholesale" : "retail",
          category: (order.category || "").toString().trim(),
          buyerArea: await buyerArea(order.buyerId),
          ...(completedAt ? { completedAt } : {}),
        },
        { merge: true }
      );
      total += 1;
    }
    await batch.commit();
    cursor = page.docs[page.docs.length - 1];
  }
  process.stdout.write(`Updated ${total} market sale record(s).\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
