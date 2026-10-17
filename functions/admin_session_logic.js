// The decisions behind the Admin Portal's single active session, kept
// free of Firestore so they can be tested on their own (see
// test/admin_session_logic.test.js). admin_session.js applies them.

// A session id is made by the browser that signs in: random, and nothing
// else. Anything that is not a plain token of a sensible length is refused.
const SESSION_ID = /^[A-Za-z0-9_-]{16,64}$/;

function isValidSessionId(value) {
  return typeof value === "string" && SESSION_ID.test(value);
}

/**
 * What starting session `sessionId` does to the session on record.
 *
 *   previousSessionId  the session this one takes over from, or null when
 *                      there is none (or it is this same browser again)
 *   replaced           that previous session was still active — it is the
 *                      one being signed out
 */
function planStart(current, sessionId) {
  const activeId = current && typeof current.activeSessionId === "string" ? current.activeSessionId : null;
  if (!activeId || activeId === sessionId) {
    return { previousSessionId: null, replaced: false };
  }
  return {
    previousSessionId: activeId,
    replaced: (current.sessionStatus || "active") === "active",
  };
}

/** "Chrome on Windows"; "Unknown device" when neither part is known. */
function deviceLabel({ browser, os }) {
  const known = (part) => part && part !== "Unknown";
  if (known(browser) && known(os)) return `${browser} on ${os}`;
  if (known(browser)) return browser;
  if (known(os)) return os;
  return "Unknown device";
}

// How recently the password must have been entered to revoke a session.
const REVOKE_RECENT_LOGIN_MS = 5 * 60 * 1000;

function millisOf(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Whether a token was signed in before the account's sessions were revoked.
 * `authTimeSeconds` is the token's auth_time claim; `validAfter` is
 * sessionsValidAfter on users/{uid} (a Timestamp), set when an Admin revokes
 * a session. firestore.rules (isAdmin) makes the same comparison.
 */
function signedInBeforeRevocation(authTimeSeconds, validAfter) {
  const after = millisOf(validAfter);
  if (after === null) return false;
  return Number(authTimeSeconds || 0) * 1000 < after;
}

/** The password was entered within `windowMs` of `nowMs`. */
function isRecentLogin(authTimeSeconds, nowMs, windowMs = REVOKE_RECENT_LOGIN_MS) {
  const at = Number(authTimeSeconds || 0) * 1000;
  return at > 0 && nowMs - at <= windowMs;
}

/**
 * Which sessions a revocation ends: `targetId`, or every session but the
 * caller's own when it is null. Only sessions still active are ended; the
 * caller's own session is never one of them.
 */
function sessionsToRevoke(history, targetId, currentId) {
  return history
    .filter((s) => s.id !== currentId && (s.status || "active") === "active")
    .filter((s) => targetId === null || s.id === targetId)
    .map((s) => s.id);
}

module.exports = {
  isValidSessionId,
  planStart,
  deviceLabel,
  REVOKE_RECENT_LOGIN_MS,
  signedInBeforeRevocation,
  isRecentLogin,
  sessionsToRevoke,
};
