// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { completionReminderDue } = require("../order_reminder_logic");

// 9 AM Philippine time on a given October 2026 day.
const at9 = (day) => Date.UTC(2026, 9, day, 1, 0, 0);
const ts = (ms) => ({ toMillis: () => ms });

test("reminded the day after the order's date, not before", () => {
  const order = { status: "shipped", requestedFulfillmentDate: ts(at9(17)) };
  assert.strictEqual(completionReminderDue(order, at9(17)), false);
  assert.strictEqual(completionReminderDue(order, at9(18)), true);
});

test("an agreed new date wins over the requested one", () => {
  const order = {
    status: "shipped",
    requestedFulfillmentDate: ts(at9(15)),
    confirmedFulfillmentDate: ts(at9(20)),
  };
  assert.strictEqual(completionReminderDue(order, at9(18)), false);
  assert.strictEqual(completionReminderDue(order, at9(21)), true);
});

test("no date: counted from the day it was shipped", () => {
  const order = { status: "shipped", shippedAt: ts(at9(16)) };
  assert.strictEqual(completionReminderDue(order, at9(16)), false);
  assert.strictEqual(completionReminderDue(order, at9(17)), true);
});

test("only once, and only while shipped", () => {
  const due = { requestedFulfillmentDate: ts(at9(10)) };
  assert.strictEqual(
    completionReminderDue({ ...due, status: "shipped", completionReminderSentAt: ts(at9(11)) }, at9(18)),
    false
  );
  assert.strictEqual(completionReminderDue({ ...due, status: "completed" }, at9(18)), false);
  assert.strictEqual(completionReminderDue({ ...due, status: "confirmed" }, at9(18)), false);
});
