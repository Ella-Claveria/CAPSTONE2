// ---------------------------------------------------------------
// The Admin Portal's single active session.
//
// An Admin account may be signed in to the portal from one browser at a
// time. Firebase Authentication still does the signing in; this only
// records WHICH browser session is the active one:
//
//   adminSessions/{adminUid}                  the active session
//   adminSessions/{adminUid}/history/{id}     each session, when it
//                                             started and how it ended
//
// Signing in from a second browser makes that one the active session; the
// first sees its session id is no longer the active one and signs itself
// out (the portal watches the document — see AdminSessionService in the
// app). The account itself is never suspended or disabled by this.
//
// Everything is written here, through the Admin SDK: the browser's user
// agent and IP address can only be trusted when the server reads them, and
// firestore.rules gives the portal no way to write a session record
// except to say it is still open (lastActiveAt).
//
// Each sign-in also emails the Admin a "new sign-in" alert, through the
// same Gmail SMTP sender as the app's other account emails (mailer.js).
// ---------------------------------------------------------------

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail, describeMailError } = require("./mailer");
const templates = require("./email_templates");
const { parseUserAgent } = require("./user_agent");
const {
  isValidSessionId,
  planStart,
  deviceLabel,
  signedInBeforeRevocation,
  isRecentLogin,
  sessionsToRevoke,
} = require("./admin_session_logic");

const db = getFirestore();
const REGION = "asia-southeast1";
const emailLog = db.collection("emailLog");

function isAlreadyExists(err) {
  return err && (err.code === 6 || err.code === "already-exists");
}

// The same test logAuditEvent applies: a signed-in, active Admin.
async function requireActiveAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Log in first.");
  }
  const snap = await db.collection("users").doc(request.auth.uid).get();
  const admin = snap.exists ? snap.data() : {};
  const isUnverifiedAdminAccount = request.auth.token.email === "admin@agritrade.com";
  if ((request.auth.token.email_verified !== true && !isUnverifiedAdminAccount) ||
      admin.role !== "admin" ||
      (admin.accountStatus || "active") !== "active") {
    throw new HttpsError("permission-denied", "Only an active admin has an Admin session.");
  }
  // A browser signed out from Active Sessions keeps a token until it
  // expires; it is refused here as in firestore.rules (isAdmin).
  if (signedInBeforeRevocation(request.auth.token.auth_time, admin.sessionsValidAfter)) {
    throw new HttpsError("permission-denied", "This session was signed out. Please log in again.");
  }
  return admin;
}

// The location text the browser reported (AdminDeviceLocation in the app),
// trimmed as the Audit Log trims it.
function reportedPlace(request) {
  return request.data && typeof request.data.location === "string"
    ? request.data.location.trim().slice(0, 120)
    : "";
}

// One Audit Log entry, in the shape logAuditEvent writes, plus the session
// it is about.
function auditEntry(request, admin, { action, details, sessionId, device, ip }) {
  const email = request.auth.token.email || null;
  // The place the Admin's browser reported, as logAuditEvent records it.
  const place = reportedPlace(request);
  return {
    action,
    eventType: action,
    details,
    sessionId,
    device,
    ip,
    location: place || "Unknown",
    timestamp: FieldValue.serverTimestamp(),
    adminId: request.auth.uid,
    adminEmail: email,
    adminName: request.auth.token.name || admin.name || admin.fullName || email || "Admin",
    attemptedEmail: null,
  };
}

// The "new sign-in" email. Only ever to the account's own verified
// address, and once per session however often the call is retried. The
// Admin can turn it off (Manage Account > Two-Factor Authentication),
// which sets signInAlerts: false on their users/{uid}; it is on otherwise.
async function sendSignInAlert(uid, sessionId, admin, device) {
  if (admin && admin.signInAlerts === false) return "skipped-turned-off";
  let authUser;
  try {
    authUser = await getAuth().getUser(uid);
  } catch (err) {
    return "skipped-no-auth-user";
  }
  if (!authUser.email || !authUser.emailVerified) return "skipped-no-verified-email";

  const logRef = emailLog.doc(`admin-login-${uid}-${sessionId}`);
  try {
    await logRef.create({ status: "sending", createdAt: FieldValue.serverTimestamp() });
  } catch (err) {
    if (isAlreadyExists(err)) return "already-sent";
    throw err;
  }

  const message = templates.adminSignInEmail({
    browser: device.browser,
    platform: device.os,
    when: new Date().toLocaleString("en-US", {
      timeZone: "Asia/Manila",
      dateStyle: "long",
      timeStyle: "short",
    }),
  });
  try {
    await sendMail(authUser.email, message);
  } catch (err) {
    console.error(`adminSession(${uid}) login alert not sent:`, describeMailError(err));
    await logRef.update({ status: "failed", failedAt: FieldValue.serverTimestamp() });
    return "failed";
  }
  await logRef.update({ status: "sent", sentAt: FieldValue.serverTimestamp() });
  return "sent";
}

async function startSession(request, admin, sessionId, silent) {
  const uid = request.auth.uid;
  const device = parseUserAgent(request.rawRequest.get("user-agent") || "");
  // req.ip is Express's best-effort client IP (honors Cloud Run's
  // X-Forwarded-For) — the same source the Audit Log uses.
  const ip = request.rawRequest.ip || null;
  const sessionRef = db.collection("adminSessions").doc(uid);
  const history = sessionRef.collection("history");

  // A browser and platform this account has not signed in from before.
  // The account's very first session is not "new": there is nothing
  // earlier for it to be new against.
  const [seen, any] = await Promise.all([
    history.where("browser", "==", device.browser).where("platform", "==", device.os).limit(1).get(),
    history.limit(1).get(),
  ]);
  const newDevice = !any.empty && seen.empty;

  const plan = await db.runTransaction(async (tx) => {
    const current = await tx.get(sessionRef);
    const planned = planStart(current.exists ? current.data() : null, sessionId);
    tx.set(sessionRef, {
      activeSessionId: sessionId,
      loginAt: FieldValue.serverTimestamp(),
      lastActiveAt: FieldValue.serverTimestamp(),
      deviceName: deviceLabel(device),
      browser: device.browser,
      platform: device.os,
      ipAddress: ip,
      sessionStatus: "active",
    });
    tx.set(history.doc(sessionId), {
      sessionId,
      startedAt: FieldValue.serverTimestamp(),
      lastActiveAt: FieldValue.serverTimestamp(),
      deviceName: deviceLabel(device),
      browser: device.browser,
      platform: device.os,
      ipAddress: ip,
      // Approximate: the place the browser reported, when it did.
      location: reportedPlace(request) || null,
      status: "active",
      newDevice,
      // A session picked up again after an update or a cleared browser is
      // not a sign-in, and is not announced as one.
      announced: !silent,
    }, { merge: true });
    if (planned.previousSessionId) {
      tx.set(history.doc(planned.previousSessionId), {
        sessionId: planned.previousSessionId,
        status: "ended",
        endedAt: FieldValue.serverTimestamp(),
        endReason: planned.replaced ? "replaced" : "superseded",
      }, { merge: true });
    }
    return planned;
  });

  if (silent) return { ok: true, replaced: plan.replaced, newDevice: false, email: "not-needed" };

  const audit = db.collection("audit_logs");
  const writes = [];
  if (newDevice) {
    writes.push(audit.add(auditEntry(request, admin, {
      action: "NEW_DEVICE_LOGIN",
      details: `Logged in from a new browser or device (${deviceLabel(device)}).`,
      sessionId, device, ip,
    })));
  }
  if (plan.replaced) {
    writes.push(audit.add(auditEntry(request, admin, {
      action: "SESSION_REPLACED",
      details: "A new Admin session was started and the previous active session was ended.",
      sessionId, device, ip,
    })));
  }
  await Promise.all(writes);

  const email = await sendSignInAlert(uid, sessionId, admin, device);
  return { ok: true, replaced: plan.replaced, newDevice, email };
}

// Logout: the session is over, and the next sign-in has nothing to
// replace. Only the session that is still the active one can end it.
async function endSession(uid, sessionId) {
  const sessionRef = db.collection("adminSessions").doc(uid);
  await db.runTransaction(async (tx) => {
    const current = await tx.get(sessionRef);
    if (!current.exists || current.get("activeSessionId") !== sessionId) return;
    tx.update(sessionRef, { sessionStatus: "ended", endedAt: FieldValue.serverTimestamp() });
    tx.set(sessionRef.collection("history").doc(sessionId), {
      sessionId,
      status: "ended",
      endedAt: FieldValue.serverTimestamp(),
      endReason: "logout",
    }, { merge: true });
  });
  return { ok: true };
}

exports.adminSession = onCall({ region: REGION, secrets: MAIL_SECRETS }, async (request) => {
  const op = request.data && request.data.op;
  const sessionId = request.data && request.data.sessionId;
  if (op !== "start" && op !== "end") {
    throw new HttpsError("invalid-argument", "Unsupported session operation.");
  }
  if (!isValidSessionId(sessionId)) {
    throw new HttpsError("invalid-argument", "Invalid session id.");
  }
  const admin = await requireActiveAdmin(request);
  if (op === "end") return endSession(request.auth.uid, sessionId);
  return startSession(request, admin, sessionId, request.data.silent === true);
});

// ---------------------------------------------------------------
// Active Sessions > Revoke Session.
//
// Firebase Authentication cannot sign out one device on its own: refresh
// tokens are revoked for the whole account (revokeRefreshTokens), and an
// ID token already handed out stays valid for up to an hour. So revoking
// does both of these, for every session but the caller's:
//
//   1. revokeRefreshTokens — no other browser can renew its sign-in;
//   2. sessionsValidAfter on users/{uid}, set to when the caller last
//      entered their password — firestore.rules (isAdmin) and the Admin
//      functions (requireActiveAdmin, logAuditEvent) refuse any token
//      signed in before it, so the revoked browser loses access at once.
//
// The caller has just re-entered their password (checked here: within
// five minutes), so their own token is newer and keeps working; they sign
// in again with it right after this returns to get a new refresh token
// (AdminSessionService.revoke in the app). The caller's own session is
// never revoked here — Logout ends that one.
//
//   data: { sessionId: <the session to revoke> | null (every other one),
//           currentSessionId: <the caller's own session> | null }
// ---------------------------------------------------------------
exports.revokeAdminSession = onCall({ region: REGION }, async (request) => {
  const admin = await requireActiveAdmin(request);
  const uid = request.auth.uid;
  const data = request.data || {};
  const targetId = data.sessionId == null ? null : data.sessionId;
  const currentId = data.currentSessionId == null ? null : data.currentSessionId;
  if (targetId !== null && !isValidSessionId(targetId)) {
    throw new HttpsError("invalid-argument", "Invalid session id.");
  }
  if (currentId !== null && !isValidSessionId(currentId)) {
    throw new HttpsError("invalid-argument", "Invalid session id.");
  }
  if (targetId !== null && targetId === currentId) {
    throw new HttpsError(
      "failed-precondition",
      "This is the session you are using now. Use Logout to end it.",
    );
  }
  const authTime = Number(request.auth.token.auth_time || 0);
  if (!isRecentLogin(authTime, Date.now())) {
    throw new HttpsError(
      "failed-precondition",
      "For your security, please enter your password again.",
      { reason: "stale-login" },
    );
  }

  const sessionRef = db.collection("adminSessions").doc(uid);
  const history = sessionRef.collection("history");
  const active = await history.where("status", "==", "active").get();
  const ids = sessionsToRevoke(
    active.docs.map((d) => ({ id: d.id, status: d.get("status") })),
    null,
    currentId,
  );
  if (targetId !== null && !ids.includes(targetId)) {
    throw new HttpsError("not-found", "That session has already ended.");
  }

  // 1. No other browser can renew its sign-in.
  await getAuth().revokeRefreshTokens(uid);

  // 2. Tokens from before the caller's password entry are refused.
  const validAfter = Timestamp.fromMillis(authTime * 1000);
  await db.runTransaction(async (tx) => {
    const record = await tx.get(sessionRef);
    tx.set(db.collection("users").doc(uid), { sessionsValidAfter: validAfter }, { merge: true });
    for (const id of ids) {
      tx.set(history.doc(id), {
        sessionId: id,
        status: "ended",
        endReason: "revoked",
        endedAt: FieldValue.serverTimestamp(),
        revokedAt: FieldValue.serverTimestamp(),
        revokedFromSessionId: currentId,
      }, { merge: true });
    }
    // The revoked one was the active session on record: it is over.
    if (record.exists && ids.includes(record.get("activeSessionId"))) {
      tx.update(sessionRef, {
        sessionStatus: "revoked",
        endedAt: FieldValue.serverTimestamp(),
      });
    }
  });

  const device = parseUserAgent(request.rawRequest.get("user-agent") || "");
  const ip = request.rawRequest.ip || null;
  const names = active.docs
    .filter((d) => ids.includes(d.id))
    .map((d) => `${d.get("deviceName") || "Unknown device"} (session ${d.id.slice(0, 8)}…)`);
  await db.collection("audit_logs").add({
    ...auditEntry(request, admin, {
      action: "SESSION_REVOKED",
      details: ids.length === 0
        ? "Signed out every other device (no other session was active)."
        : `Signed out ${names.join(", ")} from Active Sessions.`,
      sessionId: currentId,
      device,
      ip,
    }),
    // Which sessions were revoked, for the record.
    revokedSessionIds: ids,
    targetSessionId: targetId,
  });

  return { ok: true, revoked: ids };
});
