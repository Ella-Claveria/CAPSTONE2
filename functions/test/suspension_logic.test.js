// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { suspensionEnd, suspensionEndText, suspensionExpired } = require("../suspension_logic");

// A Firestore Timestamp, as the trigger hands it over.
const stamp = (date) => ({ toDate: () => date });

test("a suspension with no end lasts until an Admin reactivates it", () => {
  assert.strictEqual(suspensionEnd({ accountStatus: "suspended" }), null);
  assert.strictEqual(
    suspensionEndText({ accountStatus: "suspended" }),
    "until an Admin reactivates it",
  );
  assert.strictEqual(
    suspensionExpired({ accountStatus: "suspended" }, new Date()),
    false,
  );
});

test("a suspension for a set time says when it ends, in Philippine time", () => {
  // 02:51 UTC is 10:51 AM in Manila.
  const end = new Date("2026-10-17T02:51:00Z");
  const text = suspensionEndText({ suspendedUntil: stamp(end) });
  assert.match(text, /^until October 17, 2026/);
  assert.match(text, /10:51\s?AM/);
});

test("it is over once its time has passed, and only then", () => {
  const end = new Date("2026-10-17T02:51:00Z");
  const user = { accountStatus: "suspended", suspendedUntil: stamp(end) };
  assert.strictEqual(suspensionExpired(user, new Date("2026-10-17T02:50:59Z")), false);
  assert.strictEqual(suspensionExpired(user, end), true);
  assert.strictEqual(suspensionExpired(user, new Date("2026-10-18T00:00:00Z")), true);
  // A ban, or an account already active again, is not lifted.
  assert.strictEqual(
    suspensionExpired({ ...user, accountStatus: "banned" }, new Date("2026-10-18T00:00:00Z")),
    false,
  );
  assert.strictEqual(
    suspensionExpired({ ...user, accountStatus: "active" }, new Date("2026-10-18T00:00:00Z")),
    false,
  );
});
