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
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail, describeMailError } = require("./mailer");
const templates = require("./email_templates");
const { parseUserAgent } = require("./user_agent");
const { isValidSessionId, planStart, deviceLabel } = require("./admin_session_logic");

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
  return admin;
}

// One Audit Log entry, in the shape logAuditEvent writes, plus the session
// it is about.
function auditEntry(request, admin, { action, details, sessionId, device, ip }) {
  const email = request.auth.token.email || null;
  // The place the Admin's browser reported, as logAuditEvent records it.
  const place = request.data && typeof request.data.location === "string"
    ? request.data.location.trim().slice(0, 120)
    : "";
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
// address, and once per session however often the call is retried.
async function sendSignInAlert(uid, sessionId, admin, device) {
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
      deviceName: deviceLabel(device),
      browser: device.browser,
      platform: device.os,
      ipAddress: ip,
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
