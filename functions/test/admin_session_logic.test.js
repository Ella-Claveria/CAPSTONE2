// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { isValidSessionId, planStart, deviceLabel } = require("../admin_session_logic");
const templates = require("../email_templates");

test("a session id is a plain random token of a sensible length", () => {
  assert.ok(isValidSessionId("aB3_-xYz0123456789abcdef"));
  assert.ok(!isValidSessionId("short"));
  assert.ok(!isValidSessionId("has spaces in it, not a token"));
  assert.ok(!isValidSessionId("a".repeat(65)));
  assert.ok(!isValidSessionId(null));
  assert.ok(!isValidSessionId(12345678901234567890));
});

test("the first session has nothing to replace", () => {
  assert.deepStrictEqual(planStart(null, "session-b-0123456789"), {
    previousSessionId: null,
    replaced: false,
  });
});

test("the same browser logging in again replaces nothing", () => {
  const current = { activeSessionId: "session-a-0123456789", sessionStatus: "active" };
  assert.deepStrictEqual(planStart(current, "session-a-0123456789"), {
    previousSessionId: null,
    replaced: false,
  });
});

test("a second browser ends the active session of the first", () => {
  const current = { activeSessionId: "session-a-0123456789", sessionStatus: "active" };
  assert.deepStrictEqual(planStart(current, "session-b-0123456789"), {
    previousSessionId: "session-a-0123456789",
    replaced: true,
  });
});

test("a session already ended by logout is followed, not replaced", () => {
  const current = { activeSessionId: "session-a-0123456789", sessionStatus: "ended" };
  assert.deepStrictEqual(planStart(current, "session-b-0123456789"), {
    previousSessionId: "session-a-0123456789",
    replaced: false,
  });
});

test("a device is named by its browser and platform", () => {
  assert.strictEqual(deviceLabel({ browser: "Chrome", os: "Windows" }), "Chrome on Windows");
  assert.strictEqual(deviceLabel({ browser: "Chrome", os: "Unknown" }), "Chrome");
  assert.strictEqual(deviceLabel({ browser: "Unknown", os: "Unknown" }), "Unknown device");
});

test("the Admin login alert gives the details and nothing sensitive", () => {
  const mail = templates.adminSignInEmail({
    browser: "Chrome",
    platform: "Windows",
    when: "October 11, 2026 at 9:15 PM",
  });
  assert.strictEqual(mail.subject, "New login to your AgriTrade+ Admin account");
  assert.ok(mail.text.startsWith("Hello Admin,"));
  for (const body of [mail.text, mail.html]) {
    assert.ok(body.includes("Chrome"));
    assert.ok(body.includes("Windows"));
    assert.ok(body.includes("October 11, 2026 at 9:15 PM"));
    assert.ok(body.includes("If this was you, no action is required."));
    assert.ok(body.includes("change your password immediately"));
    assert.ok(!/token|session id|latitude|longitude/i.test(body));
  }
});
