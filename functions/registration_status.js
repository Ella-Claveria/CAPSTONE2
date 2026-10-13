// ---------------------------------------------------------------
// "Is this email already registered?" — asked by the app before it lets
// someone start a second registration for an account that already exists
// (Login → "Create one", and the registration form's own Create Account).
//
// A farmer who registered and is waiting for approval is signed out, so
// the app cannot look their account up itself: it has no session, and
// firestore.rules lets nobody read another person's users/{uid} record.
// This looks the email up with the Admin SDK and answers with one word —
// none / farmer_pending / farmer_approved / farmer_rejected / registered
// (see registration_status_logic.js). Nothing else about the account
// leaves the server: no uid, name, or any other field.
//
// It is not what prevents a duplicate account — Firebase Authentication
// already refuses a second account for the same email, and every profile
// is keyed by that one account's uid. This only lets the app say WHY, and
// send the person to Login, before they fill the form in again.
// ---------------------------------------------------------------

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { normalizeEmail, registrationStatus } = require("./registration_status_logic");

const db = getFirestore();

exports.registrationStatus = onCall({ region: "asia-southeast1" }, async (request) => {
  const email = normalizeEmail(request.data && request.data.email);
  if (!email) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }

  let authUser;
  try {
    authUser = await getAuth().getUserByEmail(email);
  } catch (err) {
    if (err && err.code === "auth/user-not-found") {
      return { status: "none" };
    }
    throw new HttpsError("unavailable", "Could not check this email. Please try again.");
  }

  const snap = await db.collection("users").doc(authUser.uid).get();
  return {
    status: registrationStatus({
      hasAccount: true,
      profile: snap.exists ? snap.data() : null,
    }),
  };
});
