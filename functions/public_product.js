/**
 * productPage — the public page a shared product link opens:
 *
 *   https://agritrade-bef87.web.app/product/<productId>
 *
 * Firebase Hosting sends /product/** here (see firebase.json) instead of
 * to the Admin web app. Anyone may open it, signed in or not, so:
 *
 *   - It only ever answers GET, for one product id at a time. There is no
 *     way to list or search products through it.
 *   - The page is built on the server from the handful of public fields
 *     picked out in product_page.js. The visitor's browser is given the
 *     finished HTML — it never talks to Firestore, and firestore.rules are
 *     unchanged (products stay readable only to signed-in marketplace
 *     users).
 *   - Being server-rendered also means link previews (Messenger,
 *     Facebook, …) get the product's name, price and photo.
 *
 * Read fresh on each request and cached only briefly, so a listing that is
 * archived, suspended or sold out stops showing as available within a
 * couple of minutes.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const crypto = require("crypto");
const { onRequest } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { isProductId, publicProductView, renderProductPage } = require("./product_page");

const db = getFirestore();

const REGION = "asia-southeast1";

exports.productPage = onRequest({ region: REGION, memory: "256MiB", maxInstances: 5 }, async (req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.set("Allow", "GET, HEAD").status(405).send("Method Not Allowed");
    return;
  }

  // /product/<id>, with or without a trailing slash; nothing after it.
  const match = /^\/product\/([^/]+)\/?$/.exec(req.path || "");
  const id = match ? match[1] : "";

  const nonce = crypto.randomBytes(16).toString("base64");
  res.set({
    "Content-Type": "text/html; charset=utf-8",
    "Content-Security-Policy": [
      "default-src 'none'",
      "img-src https: data:",
      `style-src 'nonce-${nonce}' https://fonts.googleapis.com`,
      "font-src https://fonts.gstatic.com",
      `script-src 'nonce-${nonce}'`,
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
    ].join("; "),
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin",
  });

  let view = { state: "not_found" };
  try {
    if (isProductId(id)) view = await loadView(id);
  } catch (err) {
    console.error("productPage: could not load the listing —", err.message);
    res.set("Cache-Control", "no-store").status(503);
    res.send(
      renderProductPage({ state: "not_found" }, { id, nonce }).replace(
        "This listing is no longer available.",
        "This page could not be loaded. Please try again in a moment."
      )
    );
    return;
  }

  // Short, so stock and availability stay current; a listing that cannot
  // be shown is not cached at all.
  res.set("Cache-Control", view.state === "active" ? "public, max-age=60, s-maxage=120" : "no-store");
  res.status(view.state === "not_found" ? 404 : 200).send(renderProductPage(view, { id, nonce }));
});

async function loadView(id) {
  const productSnap = await db.collection("products").doc(id).get();
  if (!productSnap.exists) return { state: "not_found" };
  const product = productSnap.data();

  const farmerId = typeof product.farmerId === "string" ? product.farmerId : "";
  const farmerSnap = farmerId ? await db.collection("users").doc(farmerId).get() : null;
  const farmer = farmerSnap && farmerSnap.exists ? farmerSnap.data() : null;

  const view = publicProductView({ id, product, farmer });
  if (view.state !== "active" || view.reviewCount === 0) return view;

  const reviews = await db.collection("productReviews").where("productId", "==", id).limit(30).get();
  return publicProductView({ id, product, farmer, reviews: reviews.docs.map((doc) => doc.data()) });
}
