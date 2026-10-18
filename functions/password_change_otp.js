/**
 * Changing a signed-in user's password with a 6-digit code sent to the
 * account's own sign-in email (Manage Account › Change Password, and the
 * Admin Portal's Change Password):
 *
 *   requestPasswordChangeOtp   callable — email the code; the app has just
 *                              re-entered the current password
 *   confirmPasswordChangeOtp   callable — check the code and the new
 *                              password, change it, sign the account out
 *                              everywhere else and email a notice
 *
 * So someone left signed in on another phone, or who learned the password,
 * still cannot change it without the owner's inbox.
 *
 * Code rules (length, expiry, attempts, resend cooldown, hourly limit) are
 * the sign-up code's (otp_logic.js); only its salted hash is stored, in
 * passwordChangeVerifications/{uid}, closed to clients by firestore.rules.
 * Both calls refuse a sign-in older than RECENT_LOGIN_MS.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail, describeMailError } = require("./mailer");
const templates = require("./email_templates");
const otp = require("./otp_logic");
const { passwordProblem } = require("./password_policy");

const db = getFirestore();

const REGION = "asia-southeast1";

const verifications = db.collection("passwordChangeVerifications");

// How recently the current password must have been entered.
const RECENT_LOGIN_MS = 15 * 60 * 1000;

const EXPIRED_MESSAGE = "This verification code has expired. Please request a new code.";
const TOO_MANY_ATTEMPTS_MESSAGE = "Too many attempts. Please request a new code.";

// A signed-in, active account that entered its password recently.
async function recentUser(request, fn) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please log in again.");
  }
  const uid = request.auth.uid;
  const snap = await db.collection("users").doc(uid).get();
  const profile = snap.exists ? snap.data() : {};
  if ((profile.accountStatus || "active") !== "active") {
    console.warn(`${fn}(${uid}): account not active.`);
    throw new HttpsError("permission-denied", "Your account cannot change this right now.");
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
  if (!authUser.email) {
    throw new HttpsError("failed-precondition", "This account has no email to send a code to.");
  }
  return { authUser, profile };
}

// ---------------------------------------------------------------
// Email a code to the account's own email. A new code replaces the
// previous one and starts its attempts again from zero.
// ---------------------------------------------------------------
exports.requestPasswordChangeOtp = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const fn = "requestPasswordChangeOtp";
    const { authUser } = await recentUser(request, fn);
    const uid = authUser.uid;
    const email = authUser.email.trim().toLowerCase();

    const ref = verifications.doc(uid);
    let outcome;
    try {
      outcome = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const record = snap.exists ? snap.data() : null;
        const now = Date.now();
        const decision = otp.decideSend(record, { email, now, auto: false });
        if (decision.action !== "send") return decision;

        const code = otp.generateOtp();
        const salt = otp.newSalt();
        tx.set(ref, {
          uid,
          email,
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
      await sendMail(email, templates.otpEmail({ code: outcome.code, purpose: "password-change" }));
    } catch (err) {
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
    console.log(`${fn}(${uid}) code sent.`);
    return { sent: true, resendAfterSeconds: otp.RESEND_COOLDOWN_MS / 1000 };
  }
);

// ---------------------------------------------------------------
// Check the code and the new password; then change it, end the account's
// other sessions and email a notice. A correct code is used up in the same
// transaction that accepts it.
// ---------------------------------------------------------------
exports.confirmPasswordChangeOtp = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const fn = "confirmPasswordChangeOtp";
    const { authUser, profile } = await recentUser(request, fn);
    const uid = authUser.uid;

    const raw = request.data && request.data.code;
    const code = typeof raw === "string" ? raw.replace(/\s/g, "") : "";
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Incorrect verification code.");
    }
    const newPassword = request.data && request.data.newPassword;
    const problem = passwordProblem(newPassword);
    if (problem) throw new HttpsError("invalid-argument", problem);

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
        return outcome;
      });
    } catch (err) {
      console.error(`${fn}(${uid}) Firestore transaction failed:`, err.code, err.message);
      throw new HttpsError("internal", "Could not verify the code. Please try again.");
    }
    console.log(`${fn}(${uid}) result: ${result}`);
    switch (result) {
      case "ok":
        break;
      case "wrong":
        throw new HttpsError("invalid-argument", "Incorrect verification code.");
      case "locked":
      case "wrong-locked":
        throw new HttpsError("resource-exhausted", TOO_MANY_ATTEMPTS_MESSAGE);
      default:
        throw new HttpsError("failed-precondition", EXPIRED_MESSAGE);
    }

    try {
      await getAuth().updateUser(uid, { password: newPassword });
    } catch (err) {
      console.error(`${fn}(${uid}) could not change the password:`, err.code, err.message);
      throw new HttpsError("unavailable", "Could not change your password. Please try again.");
    }
    // Every other device must log in again with the new password; the app
    // signs this one straight back in.
    try {
      await getAuth().revokeRefreshTokens(uid);
    } catch (err) {
      console.error(`${fn}(${uid}) could not end other sessions:`, err.message);
    }
    try {
      const when = new Date().toLocaleString("en-PH", {
        timeZone: "Asia/Manila",
        dateStyle: "medium",
        timeStyle: "short",
      });
      await sendMail(authUser.email, templates.passwordChangedEmail({
        name: profile.name || profile.fullName || authUser.displayName,
        when,
      }));
    } catch (err) {
      console.error(`${fn}(${uid}) notice email failed:`, JSON.stringify(describeMailError(err)));
    }
    return { changed: true };
  }
);
