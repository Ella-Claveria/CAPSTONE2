/**
 * The rules of the email OTP, with no Firebase in them so they can be unit
 * tested (see test/otp_logic.test.js). email_otp.js applies these inside
 * Firestore transactions.
 */

const crypto = require("crypto");

const OTP_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;
// What the app counts down before "Resend Code" unlocks.
const RESEND_COOLDOWN_MS = 60 * 1000;
// The server refuses slightly earlier than that, so a resend tapped the
// moment the button unlocks is not turned away.
const RESEND_GRACE_MS = 5 * 1000;
// On top of the cooldown: no more than this many codes per hour.
const SEND_WINDOW_MS = 60 * 60 * 1000;
const MAX_SENDS_PER_WINDOW = 5;

function generateOtp() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, "0");
}

function newSalt() {
  return crypto.randomBytes(16).toString("hex");
}

function hashOtp(otp, salt, uid) {
  return crypto.createHmac("sha256", salt).update(`${uid}:${otp}`).digest("hex");
}

// Firestore Timestamp, or plain milliseconds in tests.
function millis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : 0;
}

function seconds(ms) {
  return Math.max(0, Math.ceil(ms / 1000));
}

/** A code the user could still type in successfully. */
function hasActiveCode(record, email, now) {
  return !!record &&
    record.verified !== true &&
    !!record.otpHash &&
    record.email === email &&
    millis(record.expiresAt) > now &&
    (record.attempts || 0) < MAX_ATTEMPTS;
}

/**
 * Whether a new code may be issued now.
 *
 * `auto` is the request the Verify Email screen makes by itself when it
 * opens: it only gets a new code if there is none to use, so a rebuild,
 * hot restart or reopening the app never sends a second email.
 *
 * Returns { action: "send", sendWindowStart, sendCount } or
 * { action: "skip" | "cooldown" | "limit", retryAfterSeconds }.
 */
function decideSend(record, { email, now, auto }) {
  const last = millis(record && record.lastSentAt);
  const cooldownLeft = last ? RESEND_COOLDOWN_MS - (now - last) : 0;

  if (auto && hasActiveCode(record, email, now)) {
    return { action: "skip", retryAfterSeconds: seconds(cooldownLeft) };
  }
  if (cooldownLeft > RESEND_GRACE_MS) {
    return { action: "cooldown", retryAfterSeconds: seconds(cooldownLeft) };
  }

  let windowStart = millis(record && record.sendWindowStart);
  let count = (record && record.sendCount) || 0;
  if (!windowStart || now - windowStart >= SEND_WINDOW_MS) {
    windowStart = now;
    count = 0;
  }
  if (count >= MAX_SENDS_PER_WINDOW) {
    return { action: "limit", retryAfterSeconds: seconds(windowStart + SEND_WINDOW_MS - now) };
  }
  return { action: "send", sendWindowStart: windowStart, sendCount: count + 1 };
}

/**
 * Checks a typed-in code against the stored record. Returns one of:
 *   "ok"            correct — the caller marks the record verified
 *   "already"       this record was verified before
 *   "expired"       no usable code (none issued, timed out, or other email)
 *   "locked"        attempts were already used up
 *   "wrong"         incorrect — the caller counts the attempt
 *   "wrong-locked"  incorrect, and that was the last attempt
 */
function checkCode(record, { uid, email, code, now }) {
  if (!record || record.email !== email) return "expired";
  if (record.verified === true) return "already";
  if (!record.otpHash || !record.otpSalt || millis(record.expiresAt) <= now) return "expired";
  const attempts = record.attempts || 0;
  if (attempts >= MAX_ATTEMPTS) return "locked";

  const expected = Buffer.from(record.otpHash, "hex");
  const given = Buffer.from(hashOtp(code, record.otpSalt, uid), "hex");
  if (expected.length === given.length && crypto.timingSafeEqual(expected, given)) return "ok";
  return attempts + 1 >= MAX_ATTEMPTS ? "wrong-locked" : "wrong";
}

module.exports = {
  OTP_TTL_MS,
  MAX_ATTEMPTS,
  RESEND_COOLDOWN_MS,
  MAX_SENDS_PER_WINDOW,
  generateOtp,
  newSalt,
  hashOtp,
  hasActiveCode,
  decideSend,
  checkCode,
};
