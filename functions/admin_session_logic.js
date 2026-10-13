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

module.exports = { isValidSessionId, planStart, deviceLabel };
