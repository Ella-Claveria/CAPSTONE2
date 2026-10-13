// What the registration form is told about an email that is about to be
// registered — kept free of Firebase so it can be tested on its own (see
// test/registration_status_logic.test.js). registration_status.js applies it.

/** Trimmed and lowercased; null when it is not an email address. */
function normalizeEmail(value) {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  if (email.length < 3 || email.length > 254) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

/**
 * Where an email stands, from whether an account holds it and that
 * account's users/{uid} record:
 *
 *   none             no account — registration may go ahead
 *   farmer_pending   a farmer whose application is waiting for review
 *   farmer_approved  an approved farmer
 *   farmer_rejected  a farmer whose application was not approved
 *   registered       any other account (a buyer, or one whose
 *                    registration was started and not finished)
 */
function registrationStatus({ hasAccount, profile }) {
  if (!hasAccount) return "none";
  if (!profile || profile.role !== "farmer") return "registered";
  const approval = (profile.approvalStatus || "pending").toString().toLowerCase();
  if (approval === "approved") return "farmer_approved";
  if (approval === "rejected") return "farmer_rejected";
  return "farmer_pending";
}

module.exports = { normalizeEmail, registrationStatus };
