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

// Keep marketplace-visible profile fields separate from private users/{uid}
// records. Admin SDK writes bypass client rules; clients cannot write this
// projection directly (see firestore.rules).
exports.syncPublicProfile = onDocumentWritten("users/{uid}", async (event) => {
  const profileRef = db.collection("publicProfiles").doc(event.params.uid);
  // Read current source state rather than replaying event.after, so a delayed
  // retry cannot overwrite a newer public profile with stale fields.
  const current = await db.collection("users").doc(event.params.uid).get();
  if (!current.exists) {
    await profileRef.delete().catch(() => {});
    return;
  }
  const data = current.data() || {};
  const publicProfile = {};
  for (const key of ["role", "name", "fullName", "photoUrl", "barangay", "municipality", "province", "approvalStatus", "rating", "reviewCount"]) {
    const value = data[key];
    if (typeof value === "string" && value.length <= 200) publicProfile[key] = value;
    else if ((key === "rating" || key === "reviewCount") && typeof value === "number" && Number.isFinite(value)) {
      publicProfile[key] = value;
    }
  }
  await profileRef.set(publicProfile);
});

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
async function notifyUser(uid, { title, body, type, data, dedupeId, relatedId }) {
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
    // recipientId duplicates the {uid} already in this doc's own path
    // (notifications/{uid}/items/{itemId}) — kept as an explicit field too
    // so a query/export never has to parse the path to know who a record
    // belongs to. relatedId is the one id most relevant to `type` (an
    // orderId, conversationId, reportId, or the acted-on user's own uid for
    // account-level events) — the full detail always still lives in `data`.
    recipientId: uid,
    title,
    body,
    type,
    relatedId: relatedId || null,
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

    await notifyUser(recipientId, {
      title: "New message",
      body: `A message was sent to you by ${senderName}.`,
      type: "chat_message",
      relatedId: conversationId,
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
    relatedId: event.params.orderId,
    data: { orderId: event.params.orderId },
    dedupeId: `${event.id}-seller`,
  });

  await notifyUser(order.buyerId, {
    title: "Order placed!",
    body: `Your order for ${qtyLabel || "an item"} of ${productName} was sent to ${sellerName}.`,
    type: "new_order",
    relatedId: event.params.orderId,
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

  // Older versions copied exact seller coordinates onto buyer-readable
  // orders. Remove that legacy snapshot and no longer create precise pins;
  // buyer-facing distance uses only the approximate barangay cluster.
  if (after.sellerLatitude != null || after.sellerLongitude != null || after.sellerLocationSnapshotAt != null) {
    await event.data.after.ref.update({
      sellerLatitude: FieldValue.delete(),
      sellerLongitude: FieldValue.delete(),
      sellerLocationSnapshotAt: FieldValue.delete(),
    });
    return;
  }
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
    relatedId: event.params.orderId,
    data: { orderId: event.params.orderId, status: after.status },
    dedupeId: event.id,
  });

  if (after.sellerId) {
    await notifyUser(after.sellerId, {
      title: `Order ${label}`,
      body: `The order for ${after.productName || "a product"} was ${label}.`,
      type: "order_status",
      relatedId: event.params.orderId,
      data: { orderId: event.params.orderId, status: after.status },
      dedupeId: `${event.id}-seller`,
    });
  }
});

// ---------------------------------------------------------------
// Buyer-facing marketplace map — barangay farmer-density clusters.
//
// The buyer map view must never read a farmer's exact coordinates
// directly (see users/{uid}/private/geo's Firestore rule — only that
// farmer or an admin can). This maintains a PII-free, pre-aggregated
// collection instead: one averaged point + a farmer count per barangay,
// never which specific farmers contribute to it. Recomputed whenever a
// farmer's exact location changes, or their role/barangay/approval/
// account status changes (any of which can move them into or out of a
// barangay's count).
// ---------------------------------------------------------------

async function recomputeBarangayCluster(barangay) {
  if (!barangay) return;
  const clusterRef = db.collection("barangayClusters").doc(barangay);
  const usersSnap = await db.collection("users").where("role", "==", "farmer").get();

  const points = [];
  for (const doc of usersSnap.docs) {
    const data = doc.data();
    if (data.barangay !== barangay) continue;
    if ((data.approvalStatus || "pending") !== "approved") continue;
    if ((data.accountStatus || "active") !== "active") continue;
    const geoSnap = await db.collection("users").doc(doc.id).collection("private").doc("geo").get();
    const geo = geoSnap.data();
    if (geo && typeof geo.latitude === "number" && typeof geo.longitude === "number") {
      points.push(geo);
    }
  }

  if (points.length === 0) {
    await clusterRef.delete();
    return;
  }

  const avgLat = points.reduce((sum, p) => sum + p.latitude, 0) / points.length;
  const avgLng = points.reduce((sum, p) => sum + p.longitude, 0) / points.length;
  await clusterRef.set({
    barangay,
    lat: avgLat,
    lng: avgLng,
    farmerCount: points.length,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

exports.onFarmerGeoChanged = onDocumentWritten("users/{uid}/private/{subDocId}", async (event) => {
  if (event.params.subDocId !== "geo") return;
  const userSnap = await db.collection("users").doc(event.params.uid).get();
  const user = userSnap.data();
  if (!user || user.role !== "farmer" || !user.barangay) return;
  await recomputeBarangayCluster(user.barangay);
});

exports.onFarmerEligibilityChanged = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();

  // Only role/barangay/approvalStatus/accountStatus affect cluster
  // membership — skip the (far more frequent) writes to unrelated fields
  // like fcmTokens or lastActiveAt so this doesn't re-scan every farmer
  // on every unrelated profile write.
  const relevantFields = (d) => (d ? [d.role, d.barangay, d.approvalStatus, d.accountStatus] : null);
  if (JSON.stringify(relevantFields(before)) === JSON.stringify(relevantFields(after))) return;

  const barangays = new Set();
  if (before && before.role === "farmer" && before.barangay) barangays.add(before.barangay);
  if (after && after.role === "farmer" && after.barangay) barangays.add(after.barangay);
  for (const barangay of barangays) {
    await recomputeBarangayCluster(barangay);
  }
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
      unit: (after.unit || "").toString().trim(),
      status: "completed",
      createdAt: after.updatedAt || FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
});

async function validCompletedReview(reviewDoc) {
  const review = reviewDoc.data();
  if (
    reviewDoc.id !== review.orderId ||
    review.moderationStatus === "removed" ||
    typeof review.rating !== "number" ||
    !Number.isFinite(review.rating) ||
    review.rating < 0.5 ||
    review.rating > 5
    || review.rating * 2 !== Math.round(review.rating * 2)
  ) {
    return null;
  }

  const orderSnap = await db.collection("orders").doc(review.orderId).get();
  if (!orderSnap.exists) return null;
  const order = orderSnap.data();
  if (
    order.status !== "completed" ||
    order.buyerId !== review.buyerId ||
    order.productId !== review.productId ||
    order.sellerId !== review.sellerId
  ) {
    return null;
  }
  return review;
}

// Product and farmer ratings are derived from reviews whose source order is
// still completed and whose buyer/product/seller IDs match that order.
exports.recomputeProductReviewStats = onDocumentWritten(
  "productReviews/{reviewId}",
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    const productIds = new Set(
      [before?.productId, after?.productId].filter((id) => typeof id === "string" && id.length > 0)
    );

    const sellerIds = new Set(
      [before?.sellerId, after?.sellerId].filter((id) => typeof id === "string" && id.length > 0)
    );
    const buyerIds = new Set(
      [before?.buyerId, after?.buyerId].filter((id) => typeof id === "string" && id.length > 0)
    );

    async function ratingSummary(reviewDocs) {
      const validReviews = (await Promise.all(reviewDocs.map(validCompletedReview))).filter(Boolean);
      const count = validReviews.length;
      const average = count === 0
        ? 0
        : validReviews.reduce((sum, review) => sum + review.rating, 0) / count;
      return { rating: average, reviewCount: count };
    }

    for (const productId of productIds) {
      const productRef = db.collection("products").doc(productId);
      const product = await productRef.get();
      if (!product.exists) continue;

      const reviews = await db.collection("productReviews").where("productId", "==", productId).get();
      await productRef.update(await ratingSummary(reviews.docs));
    }

    for (const sellerId of sellerIds) {
      const reviews = await db.collection("productReviews").where("sellerId", "==", sellerId).get();
      await db.collection("users").doc(sellerId).set(
        await ratingSummary(reviews.docs),
        { merge: true }
      );
    }

    for (const buyerId of buyerIds) {
      const reviews = await db.collection("productReviews").where("buyerId", "==", buyerId).get();
      const validReviews = (await Promise.all(reviews.docs.map(validCompletedReview))).filter(Boolean);
      const count = validReviews.length;
      await db.collection("users").doc(buyerId).set({
        trustedBuyerReviewCount: count,
        trustedBuyer: count >= 3,
      }, { merge: true });
    }
  }
);

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
      relatedId: event.params.uid,
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
    relatedId: event.params.reportId,
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
    relatedId: event.params.uid,
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
  if (isAuthenticated) {
    const adminRef = db.collection("users").doc(request.auth.uid);
    const adminSnap = await adminRef.get();
    const admin = adminSnap.exists ? adminSnap.data() : {};
    const isUnverifiedAdminAccount =
      request.auth.token.email === "admin@agritrade.com";
    if ((request.auth.token.email_verified !== true && !isUnverifiedAdminAccount) ||
        admin.role !== "admin" ||
        (admin.accountStatus || "active") !== "active") {
      throw new HttpsError("permission-denied", "Only an active admin can log this action.");
    }
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
