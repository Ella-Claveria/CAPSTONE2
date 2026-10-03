// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const otp = require("../otp_logic");

const uid = "user-1";
const email = "juan@example.com";
const now = 1_800_000_000_000;

// The record requestEmailOtp stores for `code`, issued `ageMs` ago.
function issued(code, ageMs = 0, extra = {}) {
  const salt = otp.newSalt();
  return {
    uid,
    email,
    otpHash: otp.hashOtp(code, salt, uid),
    otpSalt: salt,
    expiresAt: now - ageMs + otp.OTP_TTL_MS,
    attempts: 0,
    lastSentAt: now - ageMs,
    verified: false,
    sendWindowStart: now - ageMs,
    sendCount: 1,
    ...extra,
  };
}

test("codes are six digits and stored only as a hash", () => {
  for (let i = 0; i < 200; i++) assert.match(otp.generateOtp(), /^\d{6}$/);
  const record = issued("482731");
  assert.ok(!JSON.stringify(record).includes("482731"));
});

test("the correct code is accepted, a wrong one is not", () => {
  const record = issued("482731");
  assert.strictEqual(otp.checkCode(record, { uid, email, code: "482731", now }), "ok");
  assert.strictEqual(otp.checkCode(record, { uid, email, code: "482732", now }), "wrong");
});

test("a code cannot be used by another account or for another email", () => {
  const record = issued("482731");
  assert.strictEqual(otp.checkCode(record, { uid: "user-2", email, code: "482731", now }), "wrong");
  assert.strictEqual(
    otp.checkCode(record, { uid, email: "other@example.com", code: "482731", now }),
    "expired"
  );
});

test("an expired code is rejected even when correct", () => {
  const record = issued("482731", otp.OTP_TTL_MS + 1);
  assert.strictEqual(otp.checkCode(record, { uid, email, code: "482731", now }), "expired");
  assert.strictEqual(otp.checkCode(null, { uid, email, code: "482731", now }), "expired");
});

test("attempts run out and then even the correct code is blocked", () => {
  const last = issued("482731", 0, { attempts: otp.MAX_ATTEMPTS - 1 });
  assert.strictEqual(otp.checkCode(last, { uid, email, code: "000000", now }), "wrong-locked");
  const used = issued("482731", 0, { attempts: otp.MAX_ATTEMPTS });
  assert.strictEqual(otp.checkCode(used, { uid, email, code: "482731", now }), "locked");
});

test("a verified record has no code left to use", () => {
  const record = { uid, email, verified: true, attempts: 0 };
  assert.strictEqual(otp.checkCode(record, { uid, email, code: "482731", now }), "already");
  assert.strictEqual(otp.hasActiveCode(record, email, now), false);
});

test("first request sends", () => {
  const decision = otp.decideSend(null, { email, now, auto: true });
  assert.strictEqual(decision.action, "send");
  assert.strictEqual(decision.sendCount, 1);
});

test("the screen opening again does not send a second email", () => {
  const record = issued("482731", 20 * 1000);
  const decision = otp.decideSend(record, { email, now, auto: true });
  assert.strictEqual(decision.action, "skip");
  assert.strictEqual(decision.retryAfterSeconds, 40);
  // ...and still not after the cooldown, while the code is usable.
  const later = issued("482731", 5 * 60 * 1000);
  assert.strictEqual(otp.decideSend(later, { email, now, auto: true }).action, "skip");
});

test("the screen opening sends a new code once the old one is unusable", () => {
  const expired = issued("482731", otp.OTP_TTL_MS + 1);
  assert.strictEqual(otp.decideSend(expired, { email, now, auto: true }).action, "send");
});

test("resend is blocked inside the cooldown and allowed after it", () => {
  const early = issued("482731", 20 * 1000);
  const blocked = otp.decideSend(early, { email, now, auto: false });
  assert.strictEqual(blocked.action, "cooldown");
  assert.strictEqual(blocked.retryAfterSeconds, 40);

  const late = issued("482731", otp.RESEND_COOLDOWN_MS);
  const allowed = otp.decideSend(late, { email, now, auto: false });
  assert.strictEqual(allowed.action, "send");
  assert.strictEqual(allowed.sendCount, 2);
});

test("a resent code replaces the old one", () => {
  const replacement = issued("111111");
  assert.strictEqual(otp.checkCode(replacement, { uid, email, code: "482731", now }), "wrong");
  assert.strictEqual(otp.checkCode(replacement, { uid, email, code: "111111", now }), "ok");
});

test("no more than the hourly limit of codes", () => {
  const record = issued("482731", 2 * 60 * 1000, { sendCount: otp.MAX_SENDS_PER_WINDOW });
  assert.strictEqual(otp.decideSend(record, { email, now, auto: false }).action, "limit");

  const nextHour = issued("482731", 61 * 60 * 1000, { sendCount: otp.MAX_SENDS_PER_WINDOW });
  const decision = otp.decideSend(nextHour, { email, now, auto: false });
  assert.strictEqual(decision.action, "send");
  assert.strictEqual(decision.sendCount, 1);
});
