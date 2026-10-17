// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const {
  NEW_DEVICE_WINDOW_MS,
  isValidDeviceId,
  signInAlertDecision,
  cleanDeviceText,
} = require("../sign_in_alert_logic");

const now = Date.UTC(2026, 9, 16, 2, 0);
const buyer = { role: "buyer", email: "ana@gmail.com", emailVerified: true, nowMs: now };
const longAgo = now - 30 * 24 * 60 * 60 * 1000;

test("a login on a known device is emailed", () => {
  assert.strictEqual(
    signInAlertDecision({ ...buyer, deviceFirstSeenMs: longAgo, otherDevices: 2 }),
    "send",
  );
  assert.strictEqual(
    signInAlertDecision({ ...buyer, role: "farmer", deviceFirstSeenMs: longAgo }),
    "send",
  );
});

test("a new device gets the new-device alert instead, not two emails", () => {
  const fresh = now - 10 * 1000;
  assert.strictEqual(
    signInAlertDecision({ ...buyer, deviceFirstSeenMs: fresh, otherDevices: 1 }),
    "skipped-new-device",
  );
  // Its record not written yet: the same.
  assert.strictEqual(
    signInAlertDecision({ ...buyer, deviceFirstSeenMs: null, otherDevices: 1 }),
    "skipped-new-device",
  );
  // Older than the window: an ordinary login on that device.
  assert.strictEqual(
    signInAlertDecision({ ...buyer, deviceFirstSeenMs: now - NEW_DEVICE_WINDOW_MS - 1, otherDevices: 1 }),
    "send",
  );
});

test("the account's first device — no new-device alert — is emailed here", () => {
  assert.strictEqual(
    signInAlertDecision({ ...buyer, deviceFirstSeenMs: now - 1000, otherDevices: 0 }),
    "send",
  );
  assert.strictEqual(signInAlertDecision({ ...buyer, deviceFirstSeenMs: null }), "send");
});

test("only to a verified email, never for admins, and not when turned off", () => {
  assert.strictEqual(signInAlertDecision({ ...buyer, emailVerified: false }), "skipped-no-verified-email");
  assert.strictEqual(signInAlertDecision({ ...buyer, email: "" }), "skipped-no-verified-email");
  assert.strictEqual(signInAlertDecision({ ...buyer, role: "admin" }), "skipped-admin");
  assert.strictEqual(signInAlertDecision({ ...buyer, signInAlerts: false }), "skipped-turned-off");
});

test("device ids are trusted-device hashes; device text is trimmed", () => {
  assert.ok(isValidDeviceId("a".repeat(64)));
  assert.ok(!isValidDeviceId("../users/x"));
  assert.ok(!isValidDeviceId(undefined));
  assert.strictEqual(cleanDeviceText("  samsung SM-A166P ", "Unknown"), "samsung SM-A166P");
  assert.strictEqual(cleanDeviceText(42, "Unknown"), "Unknown");
  assert.strictEqual(cleanDeviceText("x".repeat(200), "Unknown").length, 80);
});
