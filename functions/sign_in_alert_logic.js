// When a farmer's or buyer's login to the mobile app is emailed to them
// (notifySignIn in account_emails.js). Pure, so it can be tested.

// A device record this new was created by this very login.
const NEW_DEVICE_WINDOW_MS = 5 * 60 * 1000;

// Trusted-device ids are SHA-256 hashes (device_trust_service.dart).
function isValidDeviceId(id) {
  return typeof id === "string" && /^[0-9a-f]{64}$/.test(id);
}

/**
 * "send", or why not:
 *   skipped-admin              the Admin Portal sends its own (adminSession)
 *   skipped-turned-off         signInAlerts: false on users/{uid}
 *   skipped-no-verified-email  only ever to the account's own verified email
 *   skipped-new-device         onNewTrustedDevice sends the new-device alert
 *                              for this login instead — one email, not two
 *
 * deviceFirstSeenMs: when this device's record was created (null when there
 * is none yet — the app writes it at the same moment); otherDevices: how
 * many other devices the account has. The account's first device gets no
 * new-device alert, so its login is emailed here.
 */
function signInAlertDecision({
  role,
  signInAlerts,
  email,
  emailVerified,
  deviceKnown = true,
  deviceFirstSeenMs = null,
  otherDevices = 0,
  nowMs = Date.now(),
}) {
  if (role === "admin") return "skipped-admin";
  if (signInAlerts === false) return "skipped-turned-off";
  if (!email || emailVerified !== true) return "skipped-no-verified-email";
  if (deviceKnown) {
    const isNew = deviceFirstSeenMs == null || nowMs - deviceFirstSeenMs < NEW_DEVICE_WINDOW_MS;
    if (isNew && otherDevices > 0) return "skipped-new-device";
  }
  return "send";
}

// What the app reports about the device, trimmed for the email.
function cleanDeviceText(value, fallback) {
  const text = typeof value === "string" ? value.trim().slice(0, 80) : "";
  return text || fallback;
}

module.exports = { NEW_DEVICE_WINDOW_MS, isValidDeviceId, signInAlertDecision, cleanDeviceText };
