// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { RESET_PAGE_URL, resetPageLink } = require("../reset_link");

const firebaseLink =
  "https://agritrade-bef87.firebaseapp.com/__/auth/action" +
  "?mode=resetPassword&oobCode=AbC-123_xyz&apiKey=test-key&lang=en";

test("a reset link is pointed at the AgriTrade+ page with its code intact", () => {
  const link = new URL(resetPageLink(firebaseLink));
  assert.strictEqual(link.origin + link.pathname, RESET_PAGE_URL);
  assert.strictEqual(link.searchParams.get("mode"), "resetPassword");
  assert.strictEqual(link.searchParams.get("oobCode"), "AbC-123_xyz");
  assert.strictEqual(link.searchParams.get("apiKey"), "test-key");
  assert.strictEqual(link.searchParams.get("lang"), "en");
});

test("only an admin account's link is marked for the Admin login", () => {
  assert.strictEqual(new URL(resetPageLink(firebaseLink)).searchParams.get("portal"), null);
  const admin = new URL(resetPageLink(firebaseLink, { admin: true }));
  assert.strictEqual(admin.searchParams.get("portal"), "admin");
  assert.strictEqual(admin.searchParams.get("oobCode"), "AbC-123_xyz");
});

test("anything that is not a reset link is left untouched", () => {
  const verify = firebaseLink.replace("resetPassword", "verifyEmail");
  assert.strictEqual(resetPageLink(verify), verify);
  const noCode = "https://agritrade-bef87.firebaseapp.com/__/auth/action?mode=resetPassword";
  assert.strictEqual(resetPageLink(noCode), noCode);
  assert.strictEqual(resetPageLink("not a url"), "not a url");
});
