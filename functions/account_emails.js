/**
 * Account emails, sent through Gmail SMTP (see mailer.js):
 *
 *   sendVerificationEmail   callable, signed-in user   — email verification
 *   sendPasswordResetEmail  callable, no sign-in       — forgot password
 *   onNewTrustedDevice      Firestore trigger          — new-device alert
 *   notifySignIn            callable, signed-in user   — login alert
 *
 * Firebase Authentication still creates and validates the verification and
 * reset links (generateEmailVerificationLink / generatePasswordResetLink);
 * only the delivery of the email is ours.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const crypto = require("crypto");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail } = require("./mailer");
const templates = require("./email_templates");
const { resetPageLink } = require("./reset_link");
const { suspensionEndText } = require("./suspension_logic");
const { isValidDeviceId, signInAlertDecision, cleanDeviceText } = require("./sign_in_alert_logic");

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
      throw new HttpsError("unauthenticated", "Log in to verify your email.");
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

    // An account that only signs in with Google has no password to reset,
    // and a reset link would quietly add one. It gets a short note saying
    // how to log in instead. Same answer to the caller as every other case.
    const hasPassword = authUser.providerData.some((p) => p.providerId === "password");
    if (!hasPassword) {
      try {
        const name = await profileName(authUser.uid, authUser);
        await sendMail(authUser.email, templates.googleSignInEmail({ name }));
      } catch (err) {
        await releaseSend(key);
        console.error(`sendPasswordResetEmail(${authUser.uid}) login note failed:`, err.message);
        throw new HttpsError("unavailable", "Could not send the reset email.");
      }
      return { ok: true };
    }

    try {
      // Firebase makes the one-time code; the link opens the AgriTrade+
      // reset page instead of Firebase's own (see reset_link.js).
      // Farmers and buyers log in from the mobile app, so only an admin's
      // link asks the page to offer the Admin web login afterwards.
      const profile = (await db.collection("users").doc(authUser.uid).get()).data() || {};
      const link = resetPageLink(await getAuth().generatePasswordResetLink(authUser.email), {
        admin: profile.role === "admin",
      });
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

// ---------------------------------------------------------------
// Login Alert — "You logged in to AgriTrade+".
//
// The mobile app calls this once a farmer or buyer has logged in and is
// in the app (SignInAlertService in the app) — not when an already
// signed-in app is reopened. Sent to the account's own verified email, so
// after a Change Email it goes to the new address.
//
// A login from a new device is already emailed by onNewTrustedDevice, so
// this sends nothing for it (sign_in_alert_logic.js decides). Admins get
// their own alert from the Admin Portal (adminSession).
//
//   data: { deviceId: <trusted-device hash>, deviceName, platform }
//
// Best effort: it never fails the login, and one per account per resend
// window, so a double tap or a retry does not send two.
// ---------------------------------------------------------------
exports.notifySignIn = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Log in first.");
    }
    const uid = request.auth.uid;
    const data = request.data || {};
    const deviceId = isValidDeviceId(data.deviceId) ? data.deviceId : null;

    const [authUser, profileSnap, deviceSnap, devices] = await Promise.all([
      getAuth().getUser(uid),
      db.collection("users").doc(uid).get(),
      deviceId
        ? db.collection("users").doc(uid).collection("trustedDevices").doc(deviceId).get()
        : Promise.resolve(null),
      db.collection("users").doc(uid).collection("trustedDevices").limit(3).get(),
    ]);
    const profile = profileSnap.exists ? profileSnap.data() : {};
    const firstSeen = deviceSnap && deviceSnap.exists ? deviceSnap.get("firstSeenAt") : null;

    const decision = signInAlertDecision({
      role: profile.role,
      signInAlerts: profile.signInAlerts,
      email: authUser.email,
      emailVerified: authUser.emailVerified,
      deviceKnown: deviceId != null,
      deviceFirstSeenMs: firstSeen && firstSeen.toMillis ? firstSeen.toMillis() : null,
      otherDevices: devices.docs.filter((d) => d.id !== deviceId).length,
    });
    if (decision !== "send") return { sent: false, reason: decision };

    const key = `sign-in-${uid}`;
    if (!(await claimSend(key))) return { sent: false, reason: "recently-sent" };

    const message = templates.signInEmail({
      name: await profileName(uid, authUser),
      deviceName: cleanDeviceText(data.deviceName, "Unknown"),
      platform: cleanDeviceText(data.platform, "Unknown"),
      when: new Date().toLocaleString("en-US", {
        timeZone: "Asia/Manila",
        dateStyle: "long",
        timeStyle: "short",
      }),
    });
    try {
      await sendMail(authUser.email, message);
    } catch (err) {
      await releaseSend(key);
      console.error(`notifySignIn(${uid}) failed to send:`, err.message);
      return { sent: false, reason: "failed" };
    }
    return { sent: true };
  }
);

// ---------------------------------------------------------------
// A farmer's application was approved or rejected -> email them.
//
// The in-app notification and the push for the same change are sent by
// notifyFarmerApprovalStatusChange (index.js). A farmer waiting for
// approval has usually gone "Back to login", which signs them out and
// takes this phone off the account's push list — so the push has nowhere
// to go and the in-app notice is only seen after the next sign-in. The
// email is what reaches them in the meantime.
//
// Once per decision: emailLog/farmer-approval-<uid>-<eventId> is created
// before sending and only ever created, so a redelivered event cannot
// send a second email.
// ---------------------------------------------------------------
exports.emailFarmerApprovalDecision = onDocumentUpdated(
  { document: "users/{uid}", secrets: MAIL_SECRETS },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (after.role !== "farmer") return;
    if (before.approvalStatus === after.approvalStatus) return;
    if (after.approvalStatus !== "approved" && after.approvalStatus !== "rejected") return;
    const { uid } = event.params;

    let authUser;
    try {
      authUser = await getAuth().getUser(uid);
    } catch (err) {
      console.log(`emailFarmerApprovalDecision(${uid}): no auth user — email skipped.`);
      return;
    }
    // Only ever to the account's own verified address.
    if (!authUser.email || !authUser.emailVerified) {
      console.log(`emailFarmerApprovalDecision(${uid}): no verified email — email skipped.`);
      return;
    }

    const logRef = emailLog.doc(`farmer-approval-${uid}-${event.id}`);
    try {
      await logRef.create({ status: "sending", createdAt: FieldValue.serverTimestamp() });
    } catch (err) {
      if (isAlreadyExists(err)) return; // Handled by an earlier delivery of this event.
      throw err;
    }

    const name = (after.fullName || after.name || authUser.displayName || "").toString().trim();
    let message;
    if (after.approvalStatus === "approved") {
      message = templates.farmerApprovedEmail({ name });
    } else {
      // The officer's reason is kept with the application.
      const application = await db.collection("verificationDocs").doc(uid).get();
      message = templates.farmerRejectedEmail({
        name,
        reason: application.exists ? application.get("rejectionReason") : "",
      });
    }

    try {
      await sendMail(authUser.email, message);
    } catch (err) {
      console.error(`emailFarmerApprovalDecision(${uid}) failed to send:`, err.message);
      await logRef.update({ status: "failed", failedAt: FieldValue.serverTimestamp() });
      return;
    }
    await logRef.update({ status: "sent", sentAt: FieldValue.serverTimestamp() });
  }
);

// One account notice by email, once per event, to the account's own
// verified address. Shared by the two triggers below.
async function sendAccountNotice(uid, eventId, { title, message, reason }) {
  let authUser;
  try {
    authUser = await getAuth().getUser(uid);
  } catch (err) {
    return;
  }
  if (!authUser.email || !authUser.emailVerified) return;

  const logRef = emailLog.doc(`account-notice-${uid}-${eventId}`);
  try {
    await logRef.create({ status: "sending", createdAt: FieldValue.serverTimestamp() });
  } catch (err) {
    if (isAlreadyExists(err)) return;
    throw err;
  }
  try {
    await sendMail(authUser.email, templates.accountNoticeEmail({
      name: await profileName(uid, authUser),
      title,
      message,
      reason,
    }));
  } catch (err) {
    console.error(`sendAccountNotice(${uid}) failed to send:`, err.message);
    await logRef.update({ status: "failed", failedAt: FieldValue.serverTimestamp() });
    return;
  }
  await logRef.update({ status: "sent", sentAt: FieldValue.serverTimestamp() });
}

// ---------------------------------------------------------------
// An account was suspended or deactivated -> email its owner. The in-app
// notice and push for the same change are notifyAccountModeration
// (index.js); a suspended account cannot sign in to read those, so the
// email is the one that is sure to be seen.
// ---------------------------------------------------------------
exports.emailAccountModeration = onDocumentUpdated(
  { document: "users/{uid}", secrets: MAIL_SECRETS },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (before.accountStatus === after.accountStatus) return;
    if (after.accountStatus !== "suspended" && after.accountStatus !== "banned") return;
    const suspended = after.accountStatus === "suspended";
    await sendAccountNotice(event.params.uid, event.id, {
      title: suspended ? "Account Suspended" : "Account Deactivated",
      message: suspended
        ? `Your AgriTrade+ account has been suspended ${suspensionEndText(after)}.`
        : "Your AgriTrade+ account has been deactivated following an Admin review.",
      reason: suspended ? after.suspensionReason : after.banReason,
    });
  }
);

// ---------------------------------------------------------------
// An Admin issued a warning on a report -> email the reported user. The
// in-app notice and push are notifyModerationWarning (index.js).
// ---------------------------------------------------------------
exports.emailModerationWarning = onDocumentUpdated(
  { document: "reports/{reportId}", secrets: MAIL_SECRETS },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (before.moderationAction === after.moderationAction) return;
    if (after.moderationAction !== "warning") return;
    // The reported account; on a review report farmerId is the reporter.
    const uid = after.reportedUserId || after.farmerId;
    if (!uid) return;
    const productName = (after.productName || "").toString().trim();
    await sendAccountNotice(uid, event.id, {
      title: productName ? "Listing Warning" : "Account Warning",
      message: productName
        ? `An Admin has issued a warning regarding your listing "${productName}" following a review.`
        : "An Admin has issued a warning regarding your account following a review. Please review your recent activity.",
      reason: "",
    });
  }
);
