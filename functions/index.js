/**
 * Cloud Functions for AgriTrade+ push notifications (FCM).
 *
 * Every trigger here reads the "users/{uid}.fcmTokens" array that the
 * client writes via MessageService.registerFcmToken() /
 * PushNotificationService.setupFCM(), and cleans up any token that FCM
 * reports as dead (uninstalled app, expired registration, etc).
 *
 * Deploy with: firebase deploy --only functions
 * Requires the Firebase project to be on the Blaze (pay-as-you-go) plan.
 */

const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();
const messaging = getMessaging();

/** Sends a push notification to every device registered for `uid` (pruning
 * any token FCM reports as no longer valid), AND writes a durable record to
 * notifications/{uid}/items so the in-app Notifications screen has history
 * even for events that happened while the app was closed.
 *
 * `dedupeId` must be stable across retries of the same underlying event
 * (each trigger below passes its Cloud Functions `event.id`, which Firestore
 * redelivers unchanged on retry) and unique per distinct event otherwise —
 * it becomes the notification's own document id, so a retried event
 * overwrites/no-ops the same doc rather than creating a duplicate. */
async function notifyUser(uid, { title, body, type, data, dedupeId }) {
  if (!uid || !dedupeId) return;

  const itemRef = db.collection("notifications").doc(uid).collection("items").doc(dedupeId);
  const existing = await itemRef.get();
  if (existing.exists) {
    // Already processed this exact event — a Cloud Functions retry of the
    // same delivery, not a new one. Skip both the Firestore write and the
    // push so retries can never produce duplicate notifications.
    return;
  }

  await itemRef.set({
    title,
    body,
    type,
    data: data || {},
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  const userSnap = await db.collection("users").doc(uid).get();
  const tokens = userSnap.exists ? userSnap.data().fcmTokens || [] : [];
  if (tokens.length === 0) {
    console.log(`notifyUser(${uid}, type=${type}): no fcmTokens on file — push skipped (in-app history still written).`);
    return;
  }

  const response = await messaging.sendEachForMulticast({
    notification: { title, body },
    // Only matters for background/terminated delivery — while the app is
    // foregrounded, PushNotificationService displays it itself via
    // flutter_local_notifications using this same channel id explicitly.
    // Without this, Android has no channel to post a background-delivered
    // notification to and silently drops or downgrades it on many devices
    // — which is exactly why this worked in-app but never outside it.
    android: {
      notification: { channelId: "agritrade_transactions" },
    },
    data: { type, ...(data || {}) },
    tokens,
  });
  console.log(
    `notifyUser(${uid}, type=${type}): sent to ${tokens.length} token(s), ` +
      `${response.successCount} succeeded, ${response.failureCount} failed.`
  );
  response.responses.forEach((res, i) => {
    if (!res.success) {
      console.log(`  token ${i} failed: ${res.error?.code} — ${res.error?.message}`);
    }
  });

  const staleTokens = [];
  response.responses.forEach((res, i) => {
    if (!res.success) {
      const code = res.error?.code;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        staleTokens.push(tokens[i]);
      }
    }
  });
  if (staleTokens.length > 0) {
    await db.collection("users").doc(uid).update({
      fcmTokens: FieldValue.arrayRemove(...staleTokens),
    });
  }
}

// ---------------------------------------------------------------
// New chat message -> notify the other participant.
// ---------------------------------------------------------------
exports.sendMessageNotification = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    const { conversationId } = event.params;

    const convSnap = await db.collection("conversations").doc(conversationId).get();
    if (!convSnap.exists) return;
    const conv = convSnap.data();

    const participants = conv.participants || [];
    const recipientId = participants.find((id) => id !== message.senderId);
    if (!recipientId) return;

    const senderName =
      (conv.participantNames && conv.participantNames[message.senderId]) || "Someone";

    let body;
    if (message.text && message.text.length > 120) {
      body = `${message.text.slice(0, 117)}...`;
    } else if (message.text) {
      body = message.text;
    } else if (message.type === "location") {
      body = "Shared their location";
    } else if (message.type === "pricingOptions") {
      body = "Sent pricing options";
    } else if (message.imageUrl) {
      body = "Sent a photo";
    } else {
      body = "Sent a message";
    }

    await notifyUser(recipientId, {
      title: senderName,
      body,
      type: "chat_message",
      data: {
        conversationId,
        senderId: message.senderId,
        senderName,
      },
      dedupeId: event.id,
    });
  }
);

// ---------------------------------------------------------------
// New order -> notify both sides, each from their own point of view. Same
// `type: "new_order"` and `orderId` for both — the client's tap-navigation
// (NotificationNavigationService._openOrder) already branches on whether
// the *signed-in* user is the order's seller or buyer, so one shared type
// correctly opens the farmer's Orders tab for the seller and the buyer's
// Orders tab for the buyer without needing a second type. Two distinct
// dedupeIds (suffixed) so this counts as two separate notifications, not
// one overwriting the other.
// ---------------------------------------------------------------
exports.notifyNewOrder = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data.data();
  const productName = order.productName || "a product";
  const buyerName = order.buyerName || "A buyer";
  const sellerName = order.sellerName || "the farmer";
  const qtyLabel = (order.quantityLabel || `${order.quantity ?? ""} ${order.unit ?? ""}`).trim();

  await notifyUser(order.sellerId, {
    title: "New order received",
    body: `${buyerName} ordered ${qtyLabel || "an item"} of ${productName}.`,
    type: "new_order",
    data: { orderId: event.params.orderId },
    dedupeId: `${event.id}-seller`,
  });

  await notifyUser(order.buyerId, {
    title: "Order placed!",
    body: `Your order for ${qtyLabel || "an item"} of ${productName} was sent to ${sellerName}.`,
    type: "new_order",
    data: { orderId: event.params.orderId },
    dedupeId: `${event.id}-buyer`,
  });
});

// ---------------------------------------------------------------
// Order status changes (confirmed / shipped / rejected / completed) ->
// notify the buyer who placed it. All four are farmer-triggered (see
// OrderService.updateStatus/rejectOrder, only ever called from
// farmer_orders_tab.dart), so the buyer is always the correct — and only —
// recipient here.
// ---------------------------------------------------------------
exports.notifyOrderStatusChange = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;

  const statusLabels = {
    confirmed: "confirmed",
    shipped: "shipped",
    rejected: "declined",
    completed: "completed",
  };
  const label = statusLabels[after.status];
  if (!label) return;

  await notifyUser(after.buyerId, {
    title: `Order ${label}`,
    body: `Your order for ${after.productName || "a product"} was ${label}.`,
    type: "order_status",
    data: { orderId: event.params.orderId, status: after.status },
    dedupeId: event.id,
  });
});

// ---------------------------------------------------------------
// Order completed -> mirror a privacy-safe sale record for the Market
// tab's platform-wide "Market Objective" insights (current season's top
// product, last-30-day demand). Firestore rules only let a farmer read
// orders/{} where they're the buyer or seller, so the app can't query
// the whole `orders` collection directly for this — this copies just
// {productName, quantity, createdAt} into a public collection with no
// buyer/seller identity in it. Idempotent (doc id == orderId, merge:
// true), so re-fires (retries, or an unrelated field edit on an
// already-completed order) are harmless.
// ---------------------------------------------------------------
exports.recordMarketSale = onDocumentUpdated("orders/{orderId}", async (event) => {
  const after = event.data.after.data();
  if (after.status !== "completed") return;

  const productName = (after.productName || "").toString().trim();
  if (!productName) return;

  const quantity = typeof after.quantity === "number" ? after.quantity : Number(after.quantity) || 0;

  await db.collection("market_sales").doc(event.params.orderId).set(
    {
      productName,
      quantity,
      status: "completed",
      createdAt: after.updatedAt || FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
});

// ---------------------------------------------------------------
// Farmer verification approved/rejected -> notify the applicant.
//
// Triggers on users/{uid} (not verificationDocs/{uid}): that is the one
// document guaranteed to exist for every farmer (created at signup), and
// the field the Admin Dashboard's Approve/Reject actions and every login's
// role routing actually read. verificationDocs is a supplementary
// submission/audit record that a legacy or interrupted registration may
// not have — keying the notification off it would silently skip those
// farmers. See VerificationQueueView._setFarmerApproval, which writes both
// documents in the same action, keeping them in sync.
// ---------------------------------------------------------------
exports.notifyFarmerApprovalStatusChange = onDocumentUpdated(
  "users/{uid}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (after.role !== "farmer") return;
    if (before.approvalStatus === after.approvalStatus) return;
    if (after.approvalStatus !== "approved" && after.approvalStatus !== "rejected") return;

    const approved = after.approvalStatus === "approved";

    await notifyUser(event.params.uid, {
      title: approved ? "You're verified!" : "Verification update",
      body: approved
        ? "Your farmer account has been verified. You can now start listing products."
        : "Your verification application was not approved. Please review and resubmit your documents.",
      // Reuses the notification type the app's client already switches on
      // (NotificationNavigationService, NotificationsScreen icon lookup) —
      // introducing a differently-named type here would silently fall
      // through to their default case instead of routing/icon-matching.
      type: "verification_status",
      data: { status: after.approvalStatus },
      dedupeId: event.id,
    });
  }
);

// ---------------------------------------------------------------
// Admin Moderation Queue: a report just resolved with "warning" as its
// moderationAction -> notify the reported farmer. Reports document both a
// listing-targeted warning (productId present) and a farmer-account-targeted
// warning identically here; the client's notification-tap handler decides
// where to route based on `data.productId` being present or not.
// ---------------------------------------------------------------
exports.notifyModerationWarning = onDocumentUpdated("reports/{reportId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.moderationAction === after.moderationAction) return;
  if (after.moderationAction !== "warning") return;

  const farmerId = after.farmerId || after.reportedUserId;
  if (!farmerId) return;

  const productName = after.productName;
  const body = productName
    ? `Your listing for "${productName}" received a warning following an Admin review. Please review and correct the listing information.`
    : "An Admin has issued a warning regarding your account following a review. Please review your recent activity.";

  await notifyUser(farmerId, {
    title: productName ? "Listing Warning" : "Account Warning",
    body,
    type: "moderation_warning",
    data: {
      reportId: event.params.reportId,
      productId: after.productId || null,
    },
    dedupeId: event.id,
  });
});

// ---------------------------------------------------------------
// Admin Moderation Queue: a farmer's account moderation status changed to
// suspended/banned -> notify them. Does NOT fire on approval/rejection
// (that's notifyFarmerApprovalStatusChange above) or on being cleared back
// to active (no notification needed for that today).
// ---------------------------------------------------------------
exports.notifyAccountModeration = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.accountStatus === after.accountStatus) return;
  if (after.accountStatus !== "suspended" && after.accountStatus !== "banned") return;

  const suspended = after.accountStatus === "suspended";

  await notifyUser(event.params.uid, {
    title: suspended ? "Account Suspended" : "Account Deactivated",
    body: suspended
      ? `Your AgriTrade+ account has been temporarily suspended following an Admin review.${after.suspensionReason ? ` Reason: ${after.suspensionReason}` : ""}`
      : `Your AgriTrade+ account has been deactivated following an Admin review.${after.banReason ? ` Reason: ${after.banReason}` : ""}`,
    type: "moderation_warning",
    data: { accountStatus: after.accountStatus },
    dedupeId: event.id,
  });
});

// ---------------------------------------------------------------
// One FCM token can only ever belong to one account at a time.
//
// Without this, a device token stays registered on whichever account(s)
// last saved it — logging out only ever cleans up the account that's
// ACTIVELY signing out (see AuthService.signOut/PushNotificationService.
// unregisterToken in the app). Any account that previously registered
// this same device (a shared/reused test device, an app crash or
// force-quit that skipped the normal logout flow, an old install) keeps
// a stale copy of the token, and messaging.sendEachForMulticast has no way
// to know that — it just sends to every token on file, including that
// stale one, so a message meant for one account's device visibly arrives
// on the wrong person's phone too.
//
// Fixing this here — the moment ANY account's fcmTokens gains a token —
// makes token ownership exclusive by construction, and self-heals every
// account already affected the very next time that device's token gets
// (re-)registered (which happens automatically on every app open, no user
// action needed). Removing a token here never triggers this function
// again for those docs (no *new* token was added), so there's no risk of
// looping.
// ---------------------------------------------------------------
exports.enforceExclusiveFcmToken = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data?.before?.exists ? event.data.before.data() : null;
  const after = event.data?.after?.exists ? event.data.after.data() : null;
  if (!after) return;

  const beforeTokens = new Set(before?.fcmTokens || []);
  const addedTokens = (after.fcmTokens || []).filter((t) => !beforeTokens.has(t));
  if (addedTokens.length === 0) return;

  const uid = event.params.uid;
  for (const token of addedTokens) {
    const holders = await db.collection("users").where("fcmTokens", "array-contains", token).get();
    const batch = db.batch();
    let hasWrites = false;
    holders.forEach((doc) => {
      if (doc.id !== uid) {
        batch.update(doc.ref, { fcmTokens: FieldValue.arrayRemove(token) });
        hasWrites = true;
      }
    });
    if (hasWrites) await batch.commit();
  }
});

// ---------------------------------------------------------------
// Admin Portal: Audit Log.
//
// Every audit entry — logged-in admin action or pre-auth login/password
// attempt — goes through this one callable instead of a client-side
// Firestore write, for two reasons: (1) a browser can never see its own
// public IP address, only a server can, and (2) trusting request.auth
// (verified server-side by the Callable SDK) instead of client-supplied
// fields means adminId/adminEmail on a log entry can never be spoofed.
// Firestore rules deny ALL client writes to audit_logs — this function,
// using the Admin SDK, is the only path in.
// ---------------------------------------------------------------

// Actions that make sense to log before the caller has signed in (a
// failed password attempt, or a password-reset request) — anything else
// requires request.auth to be populated. Keeping this list explicit (vs.
// "auth OR anything") is what keeps the unauthenticated path from being
// abused to write arbitrary log entries.
const PRE_AUTH_ACTIONS = new Set(["LOGIN_FAILED", "PASSWORD_RESET_REQUESTED"]);

const AUTHENTICATED_ACTIONS = new Set([
  "LOGIN_SUCCESS",
  "LOGOUT",
  "APPROVE_FARMER",
  "REJECT_FARMER",
  "UPDATE_BASELINE_PRICE",
  "DELETE_BASELINE_PRICE",
  "IMPORT_BASELINE_PRICES",
  "WARN_SELLER",
  "SUSPEND_LISTING",
  "REMOVE_LISTING",
  "SUSPEND_FARMER",
  "BAN_FARMER",
  "EXPORT_REPORT",
]);

// Minimal hand-rolled User-Agent parse — just enough to label "Chrome on
// Windows" / "Safari on macOS" for the audit table, not a full UA
// database. Falls back to "Unknown" for anything it doesn't recognize
// rather than guessing.
function parseUserAgent(ua) {
  if (!ua) return { browser: "Unknown", os: "Unknown" };

  let browser = "Unknown";
  if (/edg\//i.test(ua)) browser = "Edge";
  else if (/chrome\//i.test(ua) && !/chromium/i.test(ua)) browser = "Chrome";
  else if (/firefox\//i.test(ua)) browser = "Firefox";
  else if (/safari\//i.test(ua) && !/chrome\//i.test(ua)) browser = "Safari";
  else if (/opr\//i.test(ua)) browser = "Opera";

  let os = "Unknown";
  if (/windows/i.test(ua)) os = "Windows";
  else if (/mac os x/i.test(ua)) os = "macOS";
  else if (/android/i.test(ua)) os = "Android";
  else if (/iphone|ipad|ios/i.test(ua)) os = "iOS";
  else if (/linux/i.test(ua)) os = "Linux";

  return { browser, os };
}

// Firestore rejects fields over ~1 MiB, but the real reason to cap these
// is that the unauthenticated path (LOGIN_FAILED / PASSWORD_RESET_REQUESTED)
// takes client-supplied strings with no other validation — this keeps a
// malformed or malicious caller from writing oversized junk.
function clip(value, maxLen) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > maxLen ? trimmed.slice(0, maxLen) : trimmed;
}

exports.logAuditEvent = onCall({ region: "asia-southeast1" }, async (request) => {
  const action = clip(request.data && request.data.action, 60);
  const details = clip(request.data && request.data.details, 500);
  const isPreAuth = PRE_AUTH_ACTIONS.has(action);
  const isAuthenticated = AUTHENTICATED_ACTIONS.has(action);

  if (!isPreAuth && !isAuthenticated) {
    throw new HttpsError("invalid-argument", "Unsupported audit action.");
  }
  if (isAuthenticated && !request.auth) {
    throw new HttpsError("unauthenticated", "This action must be logged while signed in.");
  }

  const ua = request.rawRequest.get("user-agent") || "";
  const { browser, os } = parseUserAgent(ua);
  // req.ip is Express's best-effort client IP (honors Cloud Run's
  // X-Forwarded-For); there is no more authoritative source available to
  // a Cloud Function.
  const ip = request.rawRequest.ip || null;

  const entry = {
    action,
    details,
    device: { browser, os },
    ip,
    // City/province lookup was intentionally left out (see the Audit Log
    // plan) — no third-party geolocation dependency for now.
    location: "Unknown",
    timestamp: FieldValue.serverTimestamp(),
  };

  if (request.auth) {
    entry.adminId = request.auth.uid;
    entry.adminEmail = request.auth.token.email || null;
    let adminName = request.auth.token.name || null;
    if (!adminName) {
      const userSnap = await db.collection("users").doc(request.auth.uid).get();
      adminName = userSnap.exists ? userSnap.data().name || userSnap.data().fullName || null : null;
    }
    entry.adminName = adminName || entry.adminEmail || "Admin";
    entry.attemptedEmail = null;
  } else {
    entry.adminId = null;
    entry.adminName = null;
    entry.adminEmail = null;
    entry.attemptedEmail = clip(request.data && request.data.email, 200);
  }

  await db.collection("audit_logs").add(entry);
  return { ok: true };
});
