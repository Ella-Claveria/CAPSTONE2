// What kind of notification each `type` is, and whether a push may be
// sent for it — kept free of Firebase so it can be tested on its own (see
// test/notification_policy.test.js). notifyUser in index.js applies it.
//
// The in-app notification is ALWAYS saved, whatever the user's settings:
// preferences only decide whether the phone is also buzzed for it.

const CATEGORY = {
  account: "account",
  orders: "orders",
  messages: "messages",
  reviews: "reviews",
  system: "system",
};

const TYPE_CATEGORY = {
  // ACCOUNT: verification, warnings, suspension/ban, sign-in alerts.
  verification_status: CATEGORY.account,
  moderation_warning: CATEGORY.account,
  security_new_device: CATEGORY.account,
  // ORDERS
  new_order: CATEGORY.orders,
  order_status: CATEGORY.orders,
  receipt: CATEGORY.orders,
  // MESSAGES
  chat_message: CATEGORY.messages,
  // REVIEWS
  review: CATEGORY.reviews,
  // SYSTEM
  welcome: CATEGORY.system,
  announcement: CATEGORY.system,
};

/** The category a notification type belongs to; "system" if unknown. */
function categoryOf(type) {
  return TYPE_CATEGORY[type] || CATEGORY.system;
}

// Types that are also emailed (by the triggers in account_emails.js), so
// the person is reached even with push off or the phone signed out.
const EMAILED_TYPES = new Set(["verification_status", "moderation_warning", "security_new_device"]);

/**
 * Whether a push may be sent for `type`, given the user's saved
 * notificationPrefs (users/{uid}.notificationPrefs). A setting that was
 * never saved counts as on.
 *
 * Account notices are never muted: they are about the account's safety
 * and standing, not marketplace activity. They still stop with the master
 * "Push Notifications" switch, like everything else — and are emailed.
 */
function pushAllowed(type, prefs) {
  const saved = prefs && typeof prefs === "object" ? prefs : {};
  if (saved.push === false) return false;
  const category = categoryOf(type);
  if (category === CATEGORY.account) return true;
  return saved[category] !== false;
}

/** The channels a notification goes out on, for its record. */
function deliveryChannels(type, { pushed }) {
  const channels = ["in_app"];
  if (pushed) channels.push("push");
  if (EMAILED_TYPES.has(type)) channels.push("email");
  return channels;
}

const WELCOME = {
  title: "Welcome to AgriTrade+!",
  buyer:
    "Welcome to AgriTrade+! Discover local agricultural and livestock products, connect with farmers, and manage your orders in one place.",
  farmer:
    "Welcome to AgriTrade+! You can manage your products, communicate with buyers, track orders, and grow your local market presence.",
};

module.exports = { CATEGORY, categoryOf, pushAllowed, deliveryChannels, WELCOME };
