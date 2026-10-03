/**
 * Account emails, sent through Gmail SMTP (see mailer.js):
 *
 *   sendVerificationEmail   callable, signed-in user   — email verification
 *   sendPasswordResetEmail  callable, no sign-in       — forgot password
 *   onNewTrustedDevice      Firestore trigger          — new-device alert
 *
 * Firebase Authentication still creates and validates the verification and
 * reset links (generateEmailVerificationLink / generatePasswordResetLink);
 * only the delivery of the email is ours.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const crypto = require("crypto");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail } = require("./mailer");
const templates = require("./email_templates");

const db = getFirestore();

const REGION = "asia-southeast1";

// Server-side floor between two emails of the same kind to the same
// account. The app's own resend button waits 60 seconds; this is slightly
// shorter so a resend tapped the moment the button unlocks is not refused.
const RESEND_WINDOW_MS = 50 * 1000;

// emailLog is written only here, through the Admin SDK; firestore.rules
// gives clients no access to it.
const emailLog = db.collection("emailLog");

function isAlreadyExists(err) {
  return err && (err.code === 6 || err.code === "already-exists");
}

/**
 * Claims the right to send one email under `key`. Returns false when one
 * was already sent (or is being sent) inside the resend window, so two
 * calls arriving together cannot both send.
 */
async function claimSend(key) {
  const ref = emailLog.doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const last = snap.exists ? snap.get("lastSentAt") : null;
    if (last && Date.now() - last.toMillis() < RESEND_WINDOW_MS) return false;
    tx.set(ref, { lastSentAt: Timestamp.now() });
    return true;
  });
}

// The email did not go out — let the user try again straight away.
async function releaseSend(key) {
  try {
    await emailLog.doc(key).delete();
  } catch (_) {
    // The window simply runs out on its own.
  }
}

async function profileName(uid, authUser) {
  const snap = await db.collection("users").doc(uid).get();
  const profile = snap.exists ? snap.data() : {};
  return (profile.name || profile.fullName || (authUser && authUser.displayName) || "").toString().trim();
}

// ---------------------------------------------------------------
// Email verification.
// ---------------------------------------------------------------
exports.sendVerificationEmail = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to verify your email.");
    }
    const uid = request.auth.uid;
    const authUser = await getAuth().getUser(uid);
    if (!authUser.email) {
      throw new HttpsError("failed-precondition", "This account has no email address.");
    }
    if (authUser.emailVerified) return { alreadyVerified: true };

    const key = `verify-${uid}`;
    if (!(await claimSend(key))) {
      throw new HttpsError("resource-exhausted", "A verification email was just sent. Please wait a minute.");
    }
    try {
      const link = await getAuth().generateEmailVerificationLink(authUser.email);
      const name = await profileName(uid, authUser);
      await sendMail(authUser.email, templates.verificationEmail({ name, link }));
    } catch (err) {
      await releaseSend(key);
      console.error(`sendVerificationEmail(${uid}) failed:`, err.message);
      throw new HttpsError("unavailable", "Could not send the verification email.");
    }
    return { sent: true };
  }
);

// ---------------------------------------------------------------
// Forgot password. Callable without signing in, so it never says whether
// an address belongs to an account: an unknown or disabled account gets
// the same answer as a real one, and no email.
// ---------------------------------------------------------------
exports.sendPasswordResetEmail = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const raw = request.data && request.data.email;
    const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
    if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Enter a valid email address.");
    }

    // Keyed by a hash so the log holds no list of typed-in addresses.
    const key = `reset-${crypto.createHash("sha256").update(email).digest("hex")}`;
    if (!(await claimSend(key))) {
      throw new HttpsError("resource-exhausted", "A reset email was just requested. Please wait a minute.");
    }

    let authUser;
    try {
      authUser = await getAuth().getUserByEmail(email);
    } catch (err) {
      if (err.code === "auth/user-not-found") return { ok: true };
      await releaseSend(key);
      throw new HttpsError("unavailable", "Could not send the reset email.");
    }
    if (authUser.disabled) return { ok: true };

    try {
      const link = await getAuth().generatePasswordResetLink(authUser.email);
      const name = await profileName(authUser.uid, authUser);
      await sendMail(authUser.email, templates.passwordResetEmail({ name, link }));
    } catch (err) {
      await releaseSend(key);
      console.error(`sendPasswordResetEmail(${authUser.uid}) failed:`, err.message);
      throw new HttpsError("unavailable", "Could not send the reset email.");
    }
    return { ok: true };
  }
);

// ---------------------------------------------------------------
// New Device Login Alert.
//
// The app records each installation an account signs in on under
// users/{uid}/trustedDevices/{deviceIdHash} (see device_trust_service.dart);
// a document only gets created there the first time that installation
// signs in to that account. That creation — which Firestore rules only
// allow from the account's own authenticated session — is the "new device"
// event, so reopening the app or logging in again on a known device never
// reaches this function.
//
// One alert per user and device: emailLog/new-device-<uid>-<deviceId> is
// created before sending and only ever created, so a redelivered event
// cannot send a second email.
//
// The account's very first recorded device is not alerted: there is no
// earlier device for it to be "new" relative to (a fresh registration, or
// an existing user's usual phone the first time this feature runs).
// ---------------------------------------------------------------
exports.onNewTrustedDevice = onDocumentCreated(
  { document: "users/{uid}/trustedDevices/{deviceId}", secrets: MAIL_SECRETS },
  async (event) => {
    const { uid, deviceId } = event.params;
    const device = event.data.data() || {};
    const deviceRef = event.data.ref;

    const known = await db.collection("users").doc(uid).collection("trustedDevices").limit(2).get();
    if (known.size <= 1) {
      await deviceRef.update({ alertStatus: "not-needed-first-device" });
      return;
    }

    let authUser;
    try {
      authUser = await getAuth().getUser(uid);
    } catch (err) {
      console.log(`onNewTrustedDevice(${uid}): no auth user — alert skipped.`);
      return;
    }
    // Only ever to the account's own verified address.
    if (!authUser.email || !authUser.emailVerified) {
      await deviceRef.update({ alertStatus: "skipped-no-verified-email" });
      return;
    }

    const logRef = emailLog.doc(`new-device-${uid}-${deviceId}`);
    try {
      await logRef.create({ status: "sending", createdAt: FieldValue.serverTimestamp() });
    } catch (err) {
      if (isAlreadyExists(err)) return; // Handled by an earlier delivery of this event.
      throw err;
    }

    const message = templates.newDeviceEmail({
      name: await profileName(uid, authUser),
      deviceName: (device.deviceName || "").toString().trim() || "Unknown device",
      platform: (device.platform || "").toString().trim() || "Unknown",
      when: new Date().toLocaleString("en-US", {
        timeZone: "Asia/Manila",
        dateStyle: "long",
        timeStyle: "short",
      }),
    });

    try {
      await sendMail(authUser.email, message);
    } catch (err) {
      console.error(`onNewTrustedDevice(${uid}) failed to send:`, err.message);
      await logRef.update({ status: "failed", failedAt: FieldValue.serverTimestamp() });
      await deviceRef.update({ alertStatus: "failed" });
      return;
    }
    await logRef.update({ status: "sent", sentAt: FieldValue.serverTimestamp() });
    await deviceRef.update({
      alertStatus: "sent",
      alertSentAt: FieldValue.serverTimestamp(),
    });
  }
);
