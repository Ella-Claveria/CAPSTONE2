// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { normalizeEmail, registrationStatus } = require("../registration_status_logic");
const templates = require("../email_templates");

test("an email is trimmed and lowercased before it is looked up", () => {
  assert.strictEqual(normalizeEmail("  Juan.DelaCruz@Gmail.com "), "juan.delacruz@gmail.com");
  assert.strictEqual(normalizeEmail("not an email"), null);
  assert.strictEqual(normalizeEmail(""), null);
  assert.strictEqual(normalizeEmail(null), null);
});

test("no account: registration may go ahead", () => {
  assert.strictEqual(registrationStatus({ hasAccount: false, profile: null }), "none");
});

test("a farmer waiting for review", () => {
  assert.strictEqual(
    registrationStatus({ hasAccount: true, profile: { role: "farmer", approvalStatus: "pending" } }),
    "farmer_pending"
  );
  // A farmer record with no status yet is waiting too.
  assert.strictEqual(registrationStatus({ hasAccount: true, profile: { role: "farmer" } }), "farmer_pending");
});

test("an approved and a rejected farmer", () => {
  assert.strictEqual(
    registrationStatus({ hasAccount: true, profile: { role: "farmer", approvalStatus: "approved" } }),
    "farmer_approved"
  );
  assert.strictEqual(
    registrationStatus({ hasAccount: true, profile: { role: "farmer", approvalStatus: "rejected" } }),
    "farmer_rejected"
  );
});

test("any other account is simply already registered", () => {
  assert.strictEqual(registrationStatus({ hasAccount: true, profile: { role: "buyer" } }), "registered");
  // Registration started, email not verified yet: no profile.
  assert.strictEqual(registrationStatus({ hasAccount: true, profile: null }), "registered");
});

test("the approval email says the farmer can log in", () => {
  const mail = templates.farmerApprovedEmail({ name: "Bernadeth" });
  assert.strictEqual(mail.subject, "Your AgriTrade+ Farmer Application Has Been Approved");
  for (const body of [mail.text, mail.html]) {
    assert.ok(body.includes("Hello Bernadeth,"));
    assert.ok(body.includes("Your Farmer application has been approved."));
    assert.ok(body.includes("log in"));
  }
});

test("the rejection email gives the reason when there is one", () => {
  const withReason = templates.farmerRejectedEmail({ name: "", reason: "RSBA number not found." });
  assert.strictEqual(withReason.subject, "Farmer Application Update — AgriTrade+");
  for (const body of [withReason.text, withReason.html]) {
    assert.ok(body.includes("Your Farmer application was not approved."));
    assert.ok(body.includes("RSBA number not found."));
  }
  const without = templates.farmerRejectedEmail({ name: "", reason: "" });
  assert.ok(!without.text.includes("Reason"));
});
