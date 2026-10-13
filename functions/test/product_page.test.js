// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { isProductId, publicProductView, renderProductPage } = require("../product_page");

const product = {
  farmerId: "farmer1",
  farmerName: "Juan",
  name: "Native Tomato",
  category: "Vegetables",
  unit: "kg",
  price: 45,
  retailPrice: 45,
  wholesaleEnabled: true,
  wholesalePrice: 38,
  wholesaleMinimumQuantity: 20,
  quantity: 120,
  description: "Freshly harvested.",
  imageUrls: ["https://res.cloudinary.com/x/a.jpg", "https://res.cloudinary.com/x/b.jpg"],
  imageUrl: "https://res.cloudinary.com/x/a.jpg",
  deliveryAvailable: true,
  pickupOnly: false,
  rating: 4.5,
  reviewCount: 2,
  // Things that must never reach the page.
  priceFlag: { note: "internal moderation note" },
  deliveryCoverage: { barangays: ["Gulod"] },
  internalNote: "PRIVATE-PRODUCT-FIELD",
};

const farmer = {
  role: "farmer",
  approvalStatus: "approved",
  accountStatus: "active",
  name: "Juan Santos",
  barangay: "Gulod",
  municipality: "Laurel",
  province: "Batangas",
  // Private.
  email: "juan.private@gmail.com",
  mobileNumber: "+639171234567",
  phone: "09171234567",
  rsbaNumber: "RSBA123456789012",
  fcmTokens: ["TOKEN-SECRET"],
  recoveryEmail: "recover.private@gmail.com",
  address: "123 Private Street",
};

const reviews = [
  { rating: 5, comment: "Very fresh!", buyerId: "buyer-secret-id", buyerName: "Maria Buyer", orderId: "order-secret" },
  { rating: 4, comment: "", buyerId: "b2", buyerName: "Pedro Buyer" },
];

const active = () => publicProductView({ id: "p1", product, farmer, reviews });
const page = (view) => renderProductPage(view, { id: "p1", nonce: "n0nce" });

test("only real Firestore ids are accepted", () => {
  assert.ok(isProductId("abc123XYZ_-"));
  for (const bad of ["", "a/b", "../users", "a b", "x".repeat(65), null, 12]) {
    assert.strictEqual(isProductId(bad), false);
  }
});

test("an active listing shows its public details", () => {
  const view = active();
  assert.strictEqual(view.state, "active");
  const html = page(view);
  for (const expected of [
    "Native Tomato",
    "₱45.00",
    "₱38.00/kg",
    "20 kg",
    "120 kg available",
    "Freshly harvested.",
    "Juan Santos",
    "Gulod, Laurel, Batangas",
    "Delivery and pick-up",
    "4.5 out of 5",
    "Very fresh!",
    "Order Now",
    "Download the App to Order",
    "You can view product details here, but ordering is available only through the AgriTrade+ app.",
    "Maybe Later",
    "Download App",
  ]) {
    assert.ok(html.includes(expected), `missing: ${expected}`);
  }
});

test("nothing private about the farmer, the buyers or the listing is on the page", () => {
  const view = active();
  const everything = JSON.stringify(view) + page(view);
  for (const secret of [
    "juan.private@gmail.com",
    "+639171234567",
    "09171234567",
    "RSBA123456789012",
    "TOKEN-SECRET",
    "recover.private@gmail.com",
    "123 Private Street",
    "farmer1",
    "buyer-secret-id",
    "Maria Buyer",
    "Pedro Buyer",
    "order-secret",
    "internal moderation note",
    "PRIVATE-PRODUCT-FIELD",
  ]) {
    assert.ok(!everything.includes(secret), `leaked: ${secret}`);
  }
});

test("link previews get the product, its price and its photo", () => {
  const html = page(active());
  assert.match(html, /<meta property="og:title" content="Native Tomato · AgriTrade\+">/);
  assert.match(html, /<meta property="og:image" content="https:\/\/res\.cloudinary\.com\/x\/a\.jpg">/);
  assert.match(html, /<meta property="og:url" content="https:\/\/agritrade-bef87\.web\.app\/product\/p1">/);
  assert.match(html, /og:description" content="₱45\.00\/kg · 120 kg available · Gulod, Laurel, Batangas"/);
});

test("an out-of-stock listing says so and cannot be ordered", () => {
  const view = publicProductView({ id: "p1", product: { ...product, quantity: 0 }, farmer });
  assert.strictEqual(view.outOfStock, true);
  const html = page(view);
  assert.match(html, /<button class="primary" id="order" type="button" disabled>Out of Stock<\/button>/);
});

test("an archived listing only says it is unavailable", () => {
  const view = publicProductView({ id: "p1", product: { ...product, isArchived: true }, farmer });
  assert.deepStrictEqual(view, { state: "unavailable" });
  const html = page(view);
  assert.ok(html.includes("This product is currently unavailable."));
  assert.ok(!html.includes("Native Tomato"));
  assert.ok(!html.includes("Order Now"));
});

test("hidden listings look exactly like ones that never existed", () => {
  const missing = page(publicProductView({ id: "p1", product: null, farmer: null }));
  assert.ok(missing.includes("Product Not Found"));
  const cases = [
    { product: { ...product, isSuspended: true }, farmer },
    { product, farmer: { ...farmer, accountStatus: "suspended" } },
    { product, farmer: { ...farmer, accountStatus: "banned" } },
    { product, farmer: { ...farmer, approvalStatus: "pending" } },
    { product, farmer: { ...farmer, approvalStatus: "rejected" } },
    { product, farmer: { ...farmer, role: "buyer" } },
    { product, farmer: null },
    // Suspended and archived: still says nothing.
    { product: { ...product, isSuspended: true, isArchived: true }, farmer },
  ];
  for (const input of cases) {
    const view = publicProductView({ id: "p1", ...input });
    assert.deepStrictEqual(view, { state: "not_found" });
    assert.strictEqual(page(view), missing);
  }
});

test("text from a listing cannot inject markup", () => {
  const view = publicProductView({
    id: "p1",
    product: {
      ...product,
      name: '<script>alert(1)</script>',
      description: '"><img src=x onerror=alert(1)>',
      unit: "kg<b>",
      imageUrls: ['https://x.test/a.jpg" onload="alert(1)', "javascript:alert(1)", "http://insecure.test/a.jpg"],
      imageUrl: "",
    },
    farmer: { ...farmer, name: "<i>Juan</i>" },
  });
  const html = page(view);
  assert.ok(!html.includes("<script>alert(1)</script>"));
  assert.ok(!html.includes("<img src=x"));
  assert.ok(!html.includes("<i>Juan</i>"));
  assert.ok(!html.includes("kg<b>"));
  assert.ok(!html.includes("javascript:alert"));
  assert.ok(!html.includes("insecure.test"));
  assert.ok(!html.includes('onload="alert'));
  assert.deepStrictEqual(view.images, []);
});

test("with no approved download link, the button never points anywhere made up", () => {
  const html = page(active());
  assert.match(html, /<button class="primary" id="download-soon" type="button">Download App<\/button>/);
  assert.ok(!html.includes("play.google.com"));
  const withLink = renderProductPage(active(), {
    id: "p1",
    nonce: "n",
    downloadUrl: "https://example.org/agritrade-app",
  });
  assert.match(withLink, /<a class="btn primary" id="download" href="https:\/\/example\.org\/agritrade-app"/);
});

test("the page offers to open the same product in the installed app", () => {
  assert.ok(page(active()).includes("intent://product/p1#Intent;scheme=agritrade;package=com.example.agritrade;"));
});

test("only this response's own style and script are allowed to run", () => {
  const html = page(active());
  assert.match(html, /<style nonce="n0nce">/);
  assert.match(html, /<script nonce="n0nce">/);
  assert.strictEqual((html.match(/<script/g) || []).length, 1);
});
