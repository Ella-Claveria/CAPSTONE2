// Read-only: prints every document in the `products` collection (the one
// the Buyer Explore screen reads) so test listings can be identified before
// anything is deleted. Changes nothing. Run from an authenticated
// environment with Firebase Admin ADC:
//   gcloud auth application-default login
//   node functions/list_products.js
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (!getApps().length) initializeApp({ projectId: "agritrade-bef87" });
const db = getFirestore();

async function main() {
  const snap = await db.collection("products").get();
  console.log(`products: ${snap.size} document(s)\n`);
  for (const doc of snap.docs) {
    const p = doc.data();
    const created = p.createdAt && p.createdAt.toDate ? p.createdAt.toDate().toISOString().slice(0, 10) : "-";
    // Shown on Explore unless archived or suspended.
    const visible = p.isArchived !== true && p.isSuspended !== true;
    console.log([
      `products/${doc.id}`,
      p.name || "(no name)",
      p.category || "-",
      `farmer: ${p.farmerName || "-"} (${p.farmerId || "-"})`,
      `created: ${created}`,
      visible ? "VISIBLE on Explore" : "hidden",
    ].join(" | "));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
