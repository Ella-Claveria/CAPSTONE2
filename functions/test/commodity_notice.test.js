// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { archiveChange, commodityNotice } = require("../commodity_notice");

test("only a change of isActive is an archive or a restore", () => {
  assert.strictEqual(archiveChange({ isActive: true }, { isActive: false }), "archived");
  // No isActive field means in use.
  assert.strictEqual(archiveChange({}, { isActive: false }), "archived");
  assert.strictEqual(archiveChange({ isActive: false }, { isActive: true }), "restored");
  assert.strictEqual(archiveChange({ isActive: false }, {}), "restored");
  // A price update, or an edit of an archived commodity, is neither.
  assert.strictEqual(archiveChange({ isActive: true }, { isActive: true }), null);
  assert.strictEqual(archiveChange({ isActive: false }, { isActive: false }), null);
  assert.strictEqual(archiveChange({}, {}), null);
});

test("a farmer with listings is told theirs are hidden, and why", () => {
  const notice = commodityNotice({
    change: "archived",
    name: "Swine",
    reason: "African Swine Fever outbreak.",
    role: "farmer",
    listings: 2,
  });
  assert.strictEqual(notice.title, "Swine is temporarily unavailable");
  assert.ok(notice.body.includes("Reason: African Swine Fever outbreak."));
  assert.ok(notice.body.includes("Your 2 listings of Swine are hidden"));
});

test("no reason leaves no dangling Reason", () => {
  const notice = commodityNotice({ change: "archived", name: "Swine", reason: "", listings: 1 });
  assert.ok(!notice.body.includes("Reason"));
  assert.ok(notice.body.includes("Your 1 listing of Swine is hidden"));
});

test("a restore says it is back", () => {
  const farmer = commodityNotice({ change: "restored", name: "Swine", listings: 1 });
  assert.strictEqual(farmer.title, "Swine is available again");
  assert.ok(farmer.body.includes("Your 1 listing of Swine is back on the marketplace."));
});
