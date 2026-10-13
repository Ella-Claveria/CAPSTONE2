/**
 * The parts of a push notification that need no Firebase, so they can be
 * unit tested (see test/push_payload.test.js). Used by notifyUser and the
 * new-device alert in index.js.
 */

// Android notification channels. Each must exist in the app under the same
// id (see PushNotificationService in the Flutter app); a phone running an
// older build that lacks one falls back to the manifest's default channel.
const CHANNELS = {
  transactions: "agritrade_transactions",
  // Account security alerts, kept apart from orders and messages so they
  // can be told apart — and never muted along with them.
  security: "agritrade_security",
};

const NEW_DEVICE_TYPE = "security_new_device";

/**
 * FCM only accepts string values in `data`; one null or number makes the
 * whole send fail. Everything is turned into a string, and anything with
 * no value is left out.
 */
function pushData(type, data) {
  const out = { type: String(type || "") };
  for (const [key, value] of Object.entries(data || {})) {
    if (value === null || value === undefined) continue;
    out[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return out;
}

/**
 * The alert shown on an account's devices after it was signed in to on a
 * device it had no record of. It reports a sign-in that already happened;
 * it is not a request for approval and nothing depends on answering it.
 * Never carries credentials, tokens or the device's id.
 */
function newDeviceAlert({ deviceName, platform } = {}) {
  const device = [deviceName, platform]
    .map((part) => (part || "").toString().trim())
    .filter((part) => part && !part.toLowerCase().startsWith("unknown"))
    .join(", ");
  return {
    title: "New Device Login",
    body:
      `Your AgriTrade+ account was just logged in to on a new device${device ? ` (${device})` : ""}. ` +
      "If this wasn't you, change your password now.",
  };
}

module.exports = { CHANNELS, NEW_DEVICE_TYPE, pushData, newDeviceAlert };
