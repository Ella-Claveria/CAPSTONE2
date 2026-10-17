/**
 * Changing an Admin's sign-in email with a 6-digit code sent to the NEW
 * address (Admin Portal > Manage Account > Change Email):
 *
 *   requestEmailChangeOtp   callable, signed-in Admin — check the new email
 *                           and email it a code
 *   confirmEmailChangeOtp   callable, signed-in Admin — check the typed-in
 *                           code and change the account's email
 *
 * The code rules (length, expiry, attempts, resend cooldown, hourly limit)
 * are the sign-up code's, from otp_logic.js. The code is generated here and
 * only its salted hash is stored, in emailChangeVerifications/{uid}, which
 * firestore.rules keeps closed to clients. The uid always comes from the
 * caller's own session; the new email is the one the code was sent to.
 *
 * The app re-authenticates with the current password before asking for a
 * code, and both calls refuse a sign-in older than RECENT_LOGIN_MS.
 *
 * Changing the email ends the account's other sessions (Firebase revokes
 * them), so the app logs the Admin out afterwards to log in again with the
 * new address.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail, describeMailError } = require("./mailer");
const templates = require("./email_templates");
const otp = require("./otp_logic");
const { signedInBeforeRevocation } = require("./admin_session_logic");

const db = getFirestore();

const REGION = "asia-southeast1";

const verifications = db.collection("emailChangeVerifications");

// How recently the Admin must have entered their password.
const RECENT_LOGIN_MS = 15 * 60 * 1000;

// The same rule as the Change Email form in the app.
const ALLOWED_EMAIL = /^[\w.-]+@(gmail\.com|laurelbatangas\.gov\.ph)$/i;

const INVALID_EMAIL_MESSAGE = "Please enter a valid email address.";
const IN_USE_MESSAGE = "That email is already used by another account.";
const EXPIRED_MESSAGE = "This verification code has expired. Please request a new code.";
const TOO_MANY_ATTEMPTS_MESSAGE = "Too many attempts. Please request a new code.";

// A signed-in, active Admin who entered their password recently.
async function recentAdmin(request, fn) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please log in again.");
  }
  const uid = request.auth.uid;
  const snap = await db.collection("users").doc(uid).get();
  const profile = snap.exists ? snap.data() : {};
  if (profile.role !== "admin" || (profile.accountStatus || "active") !== "active" ||
      // A browser signed out from Active Sessions (admin_session.js).
      signedInBeforeRevocation(request.auth.token.auth_time, profile.sessionsValidAfter)) {
    console.warn(`${fn}(${uid}): not an active admin.`);
    throw new HttpsError("permission-denied", "Only an active admin can change this email.");
  }
  const authTime = Number(request.auth.token.auth_time || 0) * 1000;
  if (Date.now() - authTime > RECENT_LOGIN_MS) {
    throw new HttpsError(
      "failed-precondition",
      "For your security, please enter your current password again.",
      { reason: "stale-login" }
    );
  }
  let authUser;
  try {
    authUser = await getAuth().getUser(uid);
  } catch (err) {
    console.error(`${fn}(${uid}) auth lookup failed:`, err.code, err.message);
    throw new HttpsError("internal", "Could not check your account. Please try again.");
  }
  return authUser;
}

// Whether another account already signs in with this email.
async function usedByAnother(email, uid) {
  try {
    const other = await getAuth().getUserByEmail(email);
    return other.uid !== uid;
  } catch (err) {
    if (err.code === "auth/user-not-found") return false;
    throw err;
  }
}

function normalized(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

// ---------------------------------------------------------------
// Check the new email and send it a code. A new code replaces the
// previous one (for this or another new email) and starts its attempts
// again from zero.
// ---------------------------------------------------------------
exports.requestEmailChangeOtp = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const fn = "requestEmailChangeOtp";
    const authUser = await recentAdmin(request, fn);
    const uid = authUser.uid;
    const newEmail = normalized(request.data && request.data.newEmail);

    if (!ALLOWED_EMAIL.test(newEmail)) {
      throw new HttpsError("invalid-argument", INVALID_EMAIL_MESSAGE);
    }
    if (newEmail === normalized(authUser.email)) {
      throw new HttpsError("invalid-argument", "That is already your current email.");
    }
    let taken;
    try {
      taken = await usedByAnother(newEmail, uid);
    } catch (err) {
      console.error(`${fn}(${uid}) email lookup failed:`, err.code, err.message);
      throw new HttpsError("internal", "Could not check that email. Please try again.");
    }
    if (taken) throw new HttpsError("already-exists", IN_USE_MESSAGE);

    const ref = verifications.doc(uid);
    let outcome;
    try {
      outcome = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const record = snap.exists ? snap.data() : null;
        const now = Date.now();
        const decision = otp.decideSend(record, { email: newEmail, now, auto: false });
        if (decision.action !== "send") return decision;

        const code = otp.generateOtp();
        const salt = otp.newSalt();
        tx.set(ref, {
          uid,
          email: newEmail,
          otpHash: otp.hashOtp(code, salt, uid),
          otpSalt: salt,
          expiresAt: Timestamp.fromMillis(now + otp.OTP_TTL_MS),
          attempts: 0,
          lastSentAt: Timestamp.fromMillis(now),
          verified: false,
          createdAt: (record && record.createdAt) || Timestamp.fromMillis(now),
          sendWindowStart: Timestamp.fromMillis(decision.sendWindowStart),
          sendCount: decision.sendCount,
        });
        return { action: "send", code };
      });
    } catch (err) {
      console.error(`${fn}(${uid}) Firestore write failed:`, err.code, err.message);
      throw new HttpsError("internal", "Could not prepare your verification code. Please try again.");
    }

    if (outcome.action !== "send") {
      const limited = outcome.action === "limit";
      throw new HttpsError(
        "resource-exhausted",
        limited
          ? "Too many codes requested. Please try again later."
          : "Please wait before requesting another code.",
        { retryAfterSeconds: outcome.retryAfterSeconds }
      );
    }

    try {
      await sendMail(newEmail, templates.otpEmail({ code: outcome.code, purpose: "email-change" }));
    } catch (err) {
      // Nothing was delivered — drop the code and let the Admin ask again.
      try {
        await ref.update({
          otpHash: FieldValue.delete(),
          otpSalt: FieldValue.delete(),
          lastSentAt: FieldValue.delete(),
          sendCount: FieldValue.increment(-1),
        });
      } catch (_) {
        // The code simply expires on its own.
      }
      console.error(`${fn}(${uid}) SMTP send failed:`, JSON.stringify(describeMailError(err)));
      throw new HttpsError("unavailable", "Could not send the verification code. Please try again.");
    }
    console.log(`${fn}(${uid}) code sent to the new email.`);
    return { sent: true, resendAfterSeconds: otp.RESEND_COOLDOWN_MS / 1000 };
  }
);

// ---------------------------------------------------------------
// Check the typed-in code; when it is right, the account's email becomes
// the one the code was sent to. A correct code is used up in the same
// transaction that accepts it.
// ---------------------------------------------------------------
exports.confirmEmailChangeOtp = onCall({ region: REGION }, async (request) => {
  const fn = "confirmEmailChangeOtp";
  const authUser = await recentAdmin(request, fn);
  const uid = authUser.uid;

  const raw = request.data && request.data.code;
  const code = typeof raw === "string" ? raw.replace(/\s/g, "") : "";
  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Incorrect verification code.");
  }

  const ref = verifications.doc(uid);
  let result;
  try {
    result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const record = snap.exists ? snap.data() : null;
      const email = record ? record.email : "";
      const outcome = otp.checkCode(record, { uid, email, code, now: Date.now() });
      if (outcome === "ok") {
        tx.update(ref, {
          verified: true,
          verifiedAt: FieldValue.serverTimestamp(),
          otpHash: FieldValue.delete(),
          otpSalt: FieldValue.delete(),
        });
      } else if (outcome === "wrong" || outcome === "wrong-locked") {
        tx.update(ref, { attempts: FieldValue.increment(1) });
      }
      return { outcome, email };
    });
  } catch (err) {
    console.error(`${fn}(${uid}) Firestore transaction failed:`, err.code, err.message);
    throw new HttpsError("internal", "Could not verify the code. Please try again.");
  }
  console.log(`${fn}(${uid}) result: ${result.outcome}`);

  switch (result.outcome) {
    case "ok":
    case "already":
      break;
    case "wrong":
      throw new HttpsError("invalid-argument", "Incorrect verification code.");
    case "locked":
    case "wrong-locked":
      throw new HttpsError("resource-exhausted", TOO_MANY_ATTEMPTS_MESSAGE);
    default:
      throw new HttpsError("failed-precondition", EXPIRED_MESSAGE);
  }

  const newEmail = result.email;
  if (normalized(authUser.email) === newEmail) return { changed: true, email: newEmail };
  try {
    // The code proved the Admin can read this inbox, so it is verified.
    await getAuth().updateUser(uid, { email: newEmail, emailVerified: true });
  } catch (err) {
    console.error(`${fn}(${uid}) could not update the account:`, err.code, err.message);
    if (err.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", IN_USE_MESSAGE);
    }
    throw new HttpsError("unavailable", "Could not change your email. Please try again.");
  }
  try {
    await db.collection("users").doc(uid).update({ email: newEmail });
  } catch (err) {
    // The app's syncProfileEmail copies it over on the next sign-in.
    console.error(`${fn}(${uid}) could not update users/${uid}.email:`, err.message);
  }
  return { changed: true, email: newEmail };
});
