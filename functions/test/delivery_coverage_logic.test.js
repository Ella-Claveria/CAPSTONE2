// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const c = require("../delivery_coverage_logic");

const laurel = { originMunicipality: "Laurel", originProvince: "Batangas", originBarangay: "Bugaan East" };

test("place names compare however they are spelled, like the app", () => {
  assert.strictEqual(c.normalizePlace("City of Tanauan"), "tanauan");
  assert.strictEqual(c.normalizePlace("Tanauan City"), "tanauan");
  assert.strictEqual(c.normalizeBarangay("Brgy. 1"), "1");
  assert.strictEqual(c.normalizeBarangay("Barangay 1 (Pob.)"), "1");
  assert.strictEqual(c.normalizeProvince("National Capital Region (NCR)"), "metromanila");
});

test("each coverage type reaches only its own areas", () => {
  const within = { deliveryCoverage: { ...laurel, type: "municipality" } };
  assert.ok(c.deliveryCovers(within, { city: "Laurel", province: "Batangas" }));
  assert.ok(!c.deliveryCovers(within, { city: "Malvar", province: "Batangas" }));

  const nearby = { deliveryCoverage: { ...laurel, type: "nearby" } };
  assert.ok(c.deliveryCovers(nearby, { city: "Tanauan City", province: "Batangas" }));
  assert.ok(!c.deliveryCovers(nearby, { city: "Malvar", province: "Batangas" }));

  const same = { deliveryCoverage: { ...laurel, type: "sameBarangay" } };
  assert.ok(c.deliveryCovers(same, { barangay: "Bugaan East", city: "Laurel", province: "Batangas" }));
  assert.ok(!c.deliveryCovers(same, { barangay: "Ticub", city: "Laurel", province: "Batangas" }));

  const custom = { deliveryCoverage: { ...laurel, type: "custom", areas: [{ name: "Malvar", province: "Batangas" }] } };
  assert.ok(c.deliveryCovers(custom, { city: "Malvar", province: "Batangas" }));
  assert.ok(!c.deliveryCovers(custom, { city: "Laurel", province: "Batangas" }));

  // Saved before coverage existed: the farm's own town.
  assert.ok(c.deliveryCovers({}, { city: "Laurel", province: "Batangas" }));
  // No town known: never covered.
  assert.ok(!c.deliveryCovers(within, { city: "" }));
});

test("only an uncovered delivery order is turned away", () => {
  const product = { deliveryCoverage: { ...laurel, type: "municipality" } };
  const order = { deliveryMethod: "delivery", buyerMunicipality: "Laurel", buyerProvince: "Batangas" };
  assert.strictEqual(c.outsideCoverage(order, product), false);
  assert.strictEqual(c.outsideCoverage({ ...order, buyerMunicipality: "Malvar" }, product), true);
  assert.strictEqual(c.outsideCoverage({ ...order, deliveryArrangement: "longDistance" }, product), true);
  assert.strictEqual(c.outsideCoverage({ deliveryMethod: "pickup" }, product), false);
});
