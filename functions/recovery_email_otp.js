/**
 * Verifying a Farmer's or Buyer's recovery email with a 6-digit code sent
 * to that address (Edit Profile > Recovery Email):
 *
 *   requestRecoveryEmailOtp   callable, signed-in user — save the address
 *                             as the (unverified) recovery email and email
 *                             it a code
 *   confirmRecoveryEmailOtp   callable, signed-in user — check the typed-in
 *                             code and mark the recovery email verified
 *
 * The recovery email is never the sign-in email (that address is
 * refused) and setting it never changes the sign-in email: this only
 * proves the person can read that second inbox. (The app used to call verifyBeforeUpdateEmail
 * for it, which would have replaced the account's LOGIN email once the
 * link was opened.)
 *
 * The code rules (length, expiry, attempts, resend cooldown, hourly limit)
 * are the sign-up code's, from otp_logic.js. Only the code's salted hash is
 * stored, in recoveryEmailVerifications/{uid}, which firestore.rules keeps
 * closed to clients — as it keeps users/{uid}.recoveryEmail and
 * recoveryEmailVerified, so only these functions can set them.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { MAIL_SECRETS, sendMail, describeMailError } = require("./mailer");
const templates = require("./email_templates");
const otp = require("./otp_logic");

const db = getFirestore();

const REGION = "asia-southeast1";

const verifications = db.collection("recoveryEmailVerifications");

const VALID_EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const EXPIRED_MESSAGE = "This verification code has expired. Please request a new code.";
const TOO_MANY_ATTEMPTS_MESSAGE = "Too many attempts. Please request a new code.";

function normalized(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

// A signed-in Farmer or Buyer whose account is not suspended or banned.
async function activeUser(request, fn) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please log in again.");
  }
  const uid = request.auth.uid;
  const snap = await db.collection("users").doc(uid).get();
  const profile = snap.exists ? snap.data() : {};
  if (!["farmer", "buyer"].includes(profile.role) ||
      (profile.accountStatus || "active") !== "active") {
    console.warn(`${fn}(${uid}): not an active farmer or buyer.`);
    throw new HttpsError("permission-denied", "Your account cannot change this right now.");
  }
  return uid;
}

// ---------------------------------------------------------------
// Save the address as the unverified recovery email and send it a code.
// The account's own (already verified) sign-in email needs no code.
// ---------------------------------------------------------------
exports.requestRecoveryEmailOtp = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const fn = "requestRecoveryEmailOtp";
    const uid = await activeUser(request, fn);
    const email = normalized(request.data && request.data.email);
    if (!VALID_EMAIL.test(email) || email.length > 254) {
      throw new HttpsError("invalid-argument", "Please enter a valid recovery email.");
    }

    let authUser;
    try {
      authUser = await getAuth().getUser(uid);
    } catch (err) {
      console.error(`${fn}(${uid}) auth lookup failed:`, err.code, err.message);
      throw new HttpsError("internal", "Could not check your account. Please try again.");
    }
    const userRef = db.collection("users").doc(uid);
    // A recovery email is a second address; the login email is not one.
    if (email === normalized(authUser.email)) {
      throw new HttpsError(
        "invalid-argument",
        "Use a different email from the one you log in with."
      );
    }

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
        // Saved now, shown as "Not verified" until the code is entered.
        tx.set(userRef, {
          recoveryEmail: email,
          recoveryEmailVerified: false,
          recoveryEmailVerifiedAt: FieldValue.delete(),
        }, { merge: true });
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
      await sendMail(email, templates.otpEmail({ code: outcome.code, purpose: "recovery-email" }));
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
    console.log(`${fn}(${uid}) code sent to the recovery email.`);
    return { sent: true, verified: false, resendAfterSeconds: otp.RESEND_COOLDOWN_MS / 1000 };
  }
);

// ---------------------------------------------------------------
// Check the typed-in code; when it is right, the recovery email it was
// sent to is marked verified. A correct code is used up in the same
// transaction that accepts it.
// ---------------------------------------------------------------
exports.confirmRecoveryEmailOtp = onCall({ region: REGION }, async (request) => {
  const fn = "confirmRecoveryEmailOtp";
  const uid = await activeUser(request, fn);

  const raw = request.data && request.data.code;
  const code = typeof raw === "string" ? raw.replace(/\s/g, "") : "";
  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Incorrect verification code.");
  }

  const ref = verifications.doc(uid);
  const userRef = db.collection("users").doc(uid);
  let result;
  try {
    result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const userSnap = await tx.get(userRef);
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
        // Only if the recovery email is still the one the code went to.
        const current = normalized(userSnap.exists ? userSnap.data().recoveryEmail : "");
        if (current === email) {
          tx.set(userRef, {
            recoveryEmailVerified: true,
            recoveryEmailVerifiedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
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
      return { verified: true, email: result.email };
    case "wrong":
      throw new HttpsError("invalid-argument", "Incorrect verification code.");
    case "locked":
    case "wrong-locked":
      throw new HttpsError("resource-exhausted", TOO_MANY_ATTEMPTS_MESSAGE);
    default:
      throw new HttpsError("failed-precondition", EXPIRED_MESSAGE);
  }
});
