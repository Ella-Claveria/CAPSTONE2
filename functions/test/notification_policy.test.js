// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { categoryOf, pushAllowed, deliveryChannels, WELCOME } = require("../notification_policy");
const templates = require("../email_templates");

test("each notification type has its category", () => {
  assert.strictEqual(categoryOf("verification_status"), "account");
  assert.strictEqual(categoryOf("moderation_warning"), "account");
  assert.strictEqual(categoryOf("new_order"), "orders");
  assert.strictEqual(categoryOf("order_status"), "orders");
  assert.strictEqual(categoryOf("chat_message"), "messages");
  assert.strictEqual(categoryOf("welcome"), "system");
  assert.strictEqual(categoryOf("announcement"), "system");
  assert.strictEqual(categoryOf("something_new"), "system");
});

test("with no saved settings everything may be pushed", () => {
  for (const type of ["new_order", "chat_message", "verification_status", "welcome"]) {
    assert.ok(pushAllowed(type, undefined));
    assert.ok(pushAllowed(type, {}));
  }
});

test("a category switched off stops only that category's pushes", () => {
  const prefs = { orders: false };
  assert.ok(!pushAllowed("new_order", prefs));
  assert.ok(!pushAllowed("order_status", prefs));
  assert.ok(pushAllowed("chat_message", prefs));
  assert.ok(pushAllowed("announcement", prefs));
});

test("account notices cannot be muted by category", () => {
  assert.ok(pushAllowed("verification_status", { account: false }));
  assert.ok(pushAllowed("moderation_warning", { account: false }));
});

test("the master switch stops every push", () => {
  for (const type of ["new_order", "chat_message", "verification_status", "welcome"]) {
    assert.ok(!pushAllowed(type, { push: false }));
  }
});

test("the record says how it went out; the in-app copy is always there", () => {
  assert.deepStrictEqual(deliveryChannels("new_order", { pushed: false }), ["in_app"]);
  assert.deepStrictEqual(deliveryChannels("new_order", { pushed: true }), ["in_app", "push"]);
  // Account notices are emailed too — with or without a push.
  assert.deepStrictEqual(deliveryChannels("verification_status", { pushed: false }), ["in_app", "email"]);
  assert.deepStrictEqual(deliveryChannels("verification_status", { pushed: true }), ["in_app", "push", "email"]);
});

test("the welcome differs for buyers and farmers", () => {
  assert.strictEqual(WELCOME.title, "Welcome to AgriTrade+!");
  assert.ok(WELCOME.buyer.includes("Discover local agricultural and livestock products"));
  assert.ok(WELCOME.farmer.includes("manage your products"));
});

test("the approval email has its own subject", () => {
  assert.strictEqual(
    templates.farmerApprovedEmail({ name: "Juan" }).subject,
    "Your AgriTrade+ Farmer Application Has Been Approved"
  );
});

test("an account notice email carries the title, message and reason", () => {
  const mail = templates.accountNoticeEmail({
    name: "Juan",
    title: "Account Suspended",
    message: "Your AgriTrade+ account has been suspended until an Admin reactivates it.",
    reason: "Repeated no-shows.",
  });
  assert.strictEqual(mail.subject, "Account Suspended — AgriTrade+");
  for (const body of [mail.text, mail.html]) {
    assert.ok(body.includes("Hello Juan,"));
    assert.ok(body.includes("has been suspended"));
    assert.ok(body.includes("Repeated no-shows."));
  }
  assert.ok(!templates.accountNoticeEmail({ name: "", title: "T", message: "M", reason: "" }).text.includes("Reason"));
});
