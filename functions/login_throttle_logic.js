/**
 * The rules of the failed-login cooldown, with no Firebase in them so they
 * can be unit tested (see test/login_throttle_logic.test.js).
 * login_throttle.js applies these inside Firestore transactions.
 */

const crypto = require("crypto");

// Consecutive wrong passwords that pause password login.
const MAX_FAILED_ATTEMPTS = 5;
// How long the pause lasts. It is never extended while it is running.
const LOCK_MS = 5 * 60 * 1000;
// Failures older than this no longer count as "consecutive".
const STALE_MS = 30 * 60 * 1000;

// Firestore Timestamp, or plain milliseconds in tests.
function millis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : 0;
}

function seconds(ms) {
  return Math.max(0, Math.ceil(ms / 1000));
}

function normalizeEmail(raw) {
  const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return "";
  return email;
}

// The record is keyed by a hash, so the collection holds no list of
// typed-in addresses and says nothing about which ones are registered.
function keyFor(email) {
  return crypto.createHash("sha256").update(`login:${email}`).digest("hex");
}

// Failures that still count right now: none once a pause has run out, and
// none once the last one is stale.
function activeFailures(record, now) {
  if (!record) return 0;
  const lockedUntil = millis(record.lockedUntil);
  if (lockedUntil && lockedUntil <= now) return 0;
  if (now - millis(record.lastFailedAt) > STALE_MS) return 0;
  return record.failedCount || 0;
}

/** Whether password login is paused right now, and for how much longer. */
function status(record, now) {
  const lockedUntil = record ? millis(record.lockedUntil) : 0;
  if (lockedUntil > now) {
    return { locked: true, retryAfterSeconds: seconds(lockedUntil - now), attemptsRemaining: 0 };
  }
  return {
    locked: false,
    retryAfterSeconds: 0,
    attemptsRemaining: MAX_FAILED_ATTEMPTS - activeFailures(record, now),
  };
}

/**
 * One more wrong password. Returns the record to store (`next`, or null to
 * leave it untouched) and what to tell the app (`result`).
 *
 * A failure reported while a pause is already running changes nothing, so
 * repeated attempts can never stretch a pause past its five minutes.
 */
function recordFailure(record, now) {
  const current = status(record, now);
  if (current.locked) return { next: null, result: current };

  const failedCount = activeFailures(record, now) + 1;
  if (failedCount >= MAX_FAILED_ATTEMPTS) {
    return {
      next: { failedCount, lastFailedAt: now, lockedUntil: now + LOCK_MS },
      result: { locked: true, retryAfterSeconds: seconds(LOCK_MS), attemptsRemaining: 0 },
    };
  }
  return {
    next: { failedCount, lastFailedAt: now, lockedUntil: null },
    result: {
      locked: false,
      retryAfterSeconds: 0,
      attemptsRemaining: MAX_FAILED_ATTEMPTS - failedCount,
    },
  };
}

module.exports = {
  MAX_FAILED_ATTEMPTS,
  LOCK_MS,
  STALE_MS,
  normalizeEmail,
  keyFor,
  status,
  recordFailure,
};
