/**
 * Email ownership check for email/password sign-ups: a 6-digit code sent to
 * the account's address (see mailer.js) and typed into the app.
 *
 *   requestEmailOtp   callable, signed-in user — issue and email a code
 *   verifyEmailOtp    callable, signed-in user — check the typed-in code
 *
 * Firebase Authentication still owns sign-up and login. A correct code sets
 * the account's own emailVerified flag (which firestore.rules and the app's
 * routing already check) and stamps emailOtpVerified on users/{uid}.
 *
 * The code is generated here, never in the app, and only its salted hash is
 * stored, in emailVerifications/{uid}. That collection is written only
 * through the Admin SDK; firestore.rules gives clients no access to it. The
 * uid and the email always come from the caller's own Firebase session,
 * never from the request, so one account cannot verify another's address.
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

const verifications = db.collection("emailVerifications");

const EXPIRED_MESSAGE = "This verification code has expired. Please request a new code.";
const TOO_MANY_ATTEMPTS_MESSAGE = "Too many attempts. Please request a new code.";

// Every failure carries a `reason` in the error details so the app (and
// whoever reads its debug log) can tell which step failed:
//   unauthenticated   no signed-in user on the call
//   auth-lookup       could not read the account from Firebase Auth
//   firestore-write   could not store the verification record
//   smtp-auth         Gmail refused the username / App Password
//   smtp-connection   could not reach smtp.gmail.com:587
//   smtp-send         Gmail refused or failed the message itself
//   cooldown / rate-limit   resend asked for too soon / too often
// The real server error is always logged first; the message sent to the
// app never contains it.
function fail(code, reason, message, extra) {
  return new HttpsError(code, message, { reason, ...(extra || {}) });
}

function smtpReason(err) {
  const code = err && err.code;
  if (code === "EAUTH") return "smtp-auth";
  if (["ESOCKET", "ETIMEDOUT", "ECONNECTION", "ECONNREFUSED", "EDNS", "ETLS"].includes(code)) {
    return "smtp-connection";
  }
  return "smtp-send";
}

const SMTP_MESSAGES = {
  "smtp-auth": "The email service could not log in. Please contact AgriTrade+ support.",
  "smtp-connection": "The email service could not be reached. Please try again in a moment.",
  "smtp-send": "Could not send the verification code. Please try again.",
};

async function signedInUser(request, fn) {
  if (!request.auth) {
    console.warn(`${fn}: called without a signed-in user.`);
    throw fail("unauthenticated", "unauthenticated", "Please log in again.");
  }
  let authUser;
  try {
    authUser = await getAuth().getUser(request.auth.uid);
  } catch (err) {
    console.error(`${fn}(${request.auth.uid}) auth lookup failed:`, err.code, err.message);
    throw fail("internal", "auth-lookup", "Could not check your account. Please try again.");
  }
  if (!authUser.email) {
    throw new HttpsError("failed-precondition", "This account has no email address.");
  }
  return authUser;
}

// The code was correct: record that on the account itself. Safe to repeat.
async function markAccountVerified(uid) {
  await getAuth().updateUser(uid, { emailVerified: true });
  // The profile is only created by the app after verification (see
  // AuthService.completeRegistration), so there may be nothing to stamp yet.
  const userRef = db.collection("users").doc(uid);
  if ((await userRef.get()).exists) {
    await userRef.update({
      emailOtpVerified: true,
      emailOtpVerifiedAt: FieldValue.serverTimestamp(),
    });
  }
}

// ---------------------------------------------------------------
// Issue a code and email it. `auto: true` is the Verify Email screen
// opening; anything else is the user tapping "Resend Code". A new code
// replaces the previous one and starts its attempts again from zero.
// ---------------------------------------------------------------
exports.requestEmailOtp = onCall(
  { region: REGION, secrets: MAIL_SECRETS },
  async (request) => {
    const fn = "requestEmailOtp";
    const authUser = await signedInUser(request, fn);
    const uid = authUser.uid;
    const auto = !!(request.data && request.data.auto === true);
    console.log(`${fn}(${uid}) step 1/3 authenticated; auto=${auto}, emailVerified=${authUser.emailVerified}`);
    if (authUser.emailVerified) return { alreadyVerified: true };

    const email = authUser.email.trim().toLowerCase();
    const ref = verifications.doc(uid);

    let outcome;
    try {
      outcome = await issueCode(ref, { uid, email, auto });
    } catch (err) {
      console.error(`${fn}(${uid}) step 2/3 Firestore write failed:`, err.code, err.message);
      throw fail("internal", "firestore-write", "Could not prepare your verification code. Please try again.");
    }
    console.log(`${fn}(${uid}) step 2/3 verification record: ${outcome.action}`);

    if (outcome.action === "verified") {
      // An earlier verifyEmailOtp consumed the code but did not finish.
      try {
        await markAccountVerified(uid);
      } catch (err) {
        console.error(`${fn}(${uid}) could not update the account:`, err.code, err.message);
        throw fail("internal", "auth-lookup", "Could not check your account. Please try again.");
      }
      return { alreadyVerified: true };
    }
    if (outcome.action !== "send") {
      if (auto) return { sent: false, resendAfterSeconds: outcome.retryAfterSeconds };
      const limited = outcome.action === "limit";
      throw fail(
        "resource-exhausted",
        limited ? "rate-limit" : "cooldown",
        limited
          ? "Too many codes requested. Please try again later."
          : "Please wait before requesting another code.",
        { retryAfterSeconds: outcome.retryAfterSeconds }
      );
    }

    try {
      const info = await sendMail(authUser.email, templates.otpEmail({ code: outcome.code }));
      console.log(`${fn}(${uid}) step 3/3 email accepted by Gmail:`, (info && info.response) || "ok");
    } catch (err) {
      // Nothing was delivered — drop the code and let the user ask again.
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
      const reason = smtpReason(err);
      console.error(`${fn}(${uid}) step 3/3 SMTP send failed (${reason}):`, JSON.stringify(describeMailError(err)));
      throw fail("unavailable", reason, SMTP_MESSAGES[reason]);
    }
    return { sent: true, resendAfterSeconds: otp.RESEND_COOLDOWN_MS / 1000 };
  }
);

// Decides whether a code may be issued and, if so, stores its hash — one
// transaction, so two calls arriving together cannot both issue one.
function issueCode(ref, { uid, email, auto }) {
  return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const record = snap.exists ? snap.data() : null;
      if (record && record.verified === true && record.email === email) {
        return { action: "verified" };
      }

      const now = Date.now();
      const decision = otp.decideSend(record, { email, now, auto });
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
}

// ---------------------------------------------------------------
// Check the typed-in code. A correct code is used up in the same
// transaction that accepts it, so it can never be accepted twice.
// ---------------------------------------------------------------
exports.verifyEmailOtp = onCall({ region: REGION }, async (request) => {
  const authUser = await signedInUser(request, "verifyEmailOtp");
  const uid = authUser.uid;
  const email = authUser.email.trim().toLowerCase();

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
    console.error(`verifyEmailOtp(${uid}) Firestore transaction failed:`, err.code, err.message);
    throw fail("internal", "firestore-write", "Could not verify the code. Please try again.");
  }
  console.log(`verifyEmailOtp(${uid}) result: ${result}`);

  switch (result) {
    case "ok":
    case "already":
      try {
        await markAccountVerified(uid);
      } catch (err) {
        console.error(`verifyEmailOtp(${uid}) could not update the account:`, err.message);
        throw new HttpsError("unavailable", "Could not finish verification. Please try again.");
      }
      return { verified: true };
    case "wrong":
      throw new HttpsError("invalid-argument", "Incorrect verification code.");
    case "locked":
    case "wrong-locked":
      throw new HttpsError("resource-exhausted", TOO_MANY_ATTEMPTS_MESSAGE);
    default:
      throw new HttpsError("failed-precondition", EXPIRED_MESSAGE);
  }
});
