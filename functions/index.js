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
const { CHANNELS, NEW_DEVICE_TYPE, pushData, newDeviceAlert } = require("./push_payload");
const { categoryOf, pushAllowed, deliveryChannels, WELCOME } = require("./notification_policy");
const { COMMODITY_ARCHIVED, archiveChange, commodityNotice } = require("./commodity_notice");

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
    // Photo URLs (Google account photos especially) can run well past 200.
    const maxLength = key === "photoUrl" ? 2000 : 200;
    if (typeof value === "string" && value.length <= maxLength) publicProfile[key] = value;
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
async function notifyUser(uid, { title, body, type, data, dedupeId, relatedId, channelId = CHANNELS.transactions }) {
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
    // ACCOUNT / ORDERS / MESSAGES / REVIEWS / SYSTEM (notification_policy.js).
    category: categoryOf(type),
    relatedId: relatedId || null,
    data: data || {},
    read: false,
    // How it goes out. The in-app copy is always saved; "push" is added
    // below once a push has actually been handed to a device.
    deliveryChannels: deliveryChannels(type, { pushed: false }),
    createdAt: FieldValue.serverTimestamp(),
  });

  // From here on it is push delivery only. The in-app record above is
  // already saved, and a push that cannot be sent must never fail the
  // trigger — the caller may still have another person to notify.
  try {
    const pushed = await pushToUser(uid, { title, body, type, data, channelId });
    if (pushed) {
      await itemRef.update({ deliveryChannels: deliveryChannels(type, { pushed: true }) });
    }
  } catch (err) {
    console.error(`notifyUser(${uid}, type=${type}): push failed —`, err.message);
  }
}

async function pushToUser(uid, { title, body, type, data, channelId }) {
  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.exists ? userSnap.data() : {};
  const tokens = user.fcmTokens || [];
  if (tokens.length === 0) {
    console.log(`notifyUser(${uid}, type=${type}): no fcmTokens on file — push skipped (in-app history still written).`);
    return false;
  }
  // The user's own Notification Preferences (Profile): a category, or all
  // pushes, switched off. The in-app record is unaffected.
  if (!pushAllowed(type, user.notificationPrefs)) {
    console.log(`notifyUser(${uid}, type=${type}): push is off in the user's preferences — push skipped (in-app history still written).`);
    return false;
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
      notification: { channelId },
    },
    // Strings only — see pushData.
    data: pushData(type, data),
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
  return response.successCount > 0;
}

// The one-time "Welcome to AgriTrade+!" notification. Its document id is
// fixed ("welcome"), so it can only ever exist once per user however many
// times this runs — never again on a later login or restart.
async function sendWelcome(uid, role) {
  await notifyUser(uid, {
    title: WELCOME.title,
    body: role === "farmer" ? WELCOME.farmer : WELCOME.buyer,
    type: "welcome",
    relatedId: uid,
    data: { role },
    dedupeId: "welcome",
  });
}

// ---------------------------------------------------------------
// A buyer's profile is created (registration finished: the email is
// verified by then, see AuthService.completeRegistration) -> welcome them.
// It is there in Notifications the first time they enter the app.
//
// A farmer is welcomed when their application is approved instead (see
// notifyFarmerApprovalStatusChange): that is when they can first enter.
// ---------------------------------------------------------------
exports.welcomeNewBuyer = onDocumentCreated("users/{uid}", async (event) => {
  const user = event.data.data() || {};
  if (user.role !== "buyer") return;
  await sendWelcome(event.params.uid, "buyer");
});

// ---------------------------------------------------------------
// New chat message -> notify the other participant.
// ---------------------------------------------------------------
exports.sendMessageNotification = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    const { conversationId } = event.params;

    // A receipt card is announced by the "Order Completed" notification
    // (notifyOrderStatusChange) — a second "New message" push for the same
    // event would just be noise.
    if (message.type === "receipt") return;

    const convSnap = await db.collection("conversations").doc(conversationId).get();
    if (!convSnap.exists) return;
    const conv = convSnap.data();

    const participants = conv.participants || [];
    const recipientId = participants.find((id) => id !== message.senderId);
    if (!recipientId) return;

    const senderProfile = await db.collection("users").doc(message.senderId).get();
    const senderData = senderProfile.exists ? senderProfile.data() : {};
    const senderName =
      senderData.name ||
      senderData.fullName ||
      (conv.participantNames && conv.participantNames[message.senderId]) ||
      "Someone";

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
    // No return here: this used to stop the function, so the status
    // change that happened to carry the clean-up never notified anyone.
    // The clean-up write re-fires this trigger with an unchanged status,
    // which ends at the check just below.
  }
  if (before.status === after.status) return;

  // Record when the order reached this stage, for the Order Timeline on the
  // details screen. The farmer's own write only carries status + updatedAt
  // (completedAt is already stamped by the client), so the stage time is
  // that same updatedAt. This second write doesn't change status, so the
  // triggers on this document return early when it re-fires them.
  const stageField = { confirmed: "confirmedAt", shipped: "shippedAt", rejected: "rejectedAt" }[after.status];
  if (stageField && after[stageField] == null) {
    await event.data.after.ref.update({
      [stageField]: after.updatedAt || FieldValue.serverTimestamp(),
    });
  }

  const statusLabels = {
    confirmed: "confirmed",
    shipped: "shipped",
    rejected: "declined",
    completed: "completed",
  };
  const label = statusLabels[after.status];
  if (!label) return;

  // Completion also tells the buyer their receipt is ready (issued by
  // issueOrderReceipt below from this same status change). Tapping it opens
  // the order's details, where View Receipt is.
  const completed = after.status === "completed";
  await notifyUser(after.buyerId, {
    title: completed ? "Order Completed" : `Order ${label}`,
    body: completed
      ? `Your ${after.productName || "product"} order has been completed. Your transaction receipt is now available.`
      : `Your order for ${after.productName || "a product"} was ${label}.`,
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
      ...(await marketSaleDemandFields(after)),
    },
    { merge: true }
  );
});

// What the Farmer Dashboard's Best-Selling Products / Top Buyer Locations
// need on top of the basics above (see market_demand_service.dart): the
// order type, the category, and the buyer's general area — municipality or
// city only, never the buyer's identity, barangay or address.
// (backfill_market_sales.js fills the same fields in for sales recorded
// before these existed — keep the two in step.)
async function marketSaleDemandFields(order) {
  let buyerArea = "";
  if (order.buyerId) {
    const buyerSnap = await db.collection("users").doc(order.buyerId).get();
    const municipality = buyerSnap.exists ? buyerSnap.data().municipality : null;
    if (typeof municipality === "string") buyerArea = municipality.trim();
  }
  return {
    pricingType: order.pricingType === "wholesale" ? "wholesale" : "retail",
    category: (order.category || "").toString().trim(),
    buyerArea,
    completedAt: order.completedAt || order.updatedAt || FieldValue.serverTimestamp(),
  };
}

// ---------------------------------------------------------------
// Order completed -> issue its Transaction Receipt.
//
// 1. receipts/{orderId}: a frozen copy of the transaction values, taken
//    from the order document (never from the product listing, whose price
//    and stock can change later). Clients can read it but never write it
//    (see firestore.rules), so neither side can edit an issued receipt.
//    The app renders the PDF from this record.
// 2. A 'receipt' message in the existing farmer–buyer conversation (created
//    only if the two have never chatted), so both can open the receipt from
//    Messages and the buyer gets Review Product.
//
// Idempotent: both documents have ids derived from the order id and are
// only ever created, so retries can't duplicate or overwrite them.
// ---------------------------------------------------------------

// Mirrors orderDisplayId / receiptNumberFor in lib/services/order_format.dart
// — the year is taken in Philippine time on both sides.
function orderCode(orderId, createdAt) {
  const code = orderId.replace(/[^A-Za-z0-9]/g, "").slice(0, 6).toUpperCase();
  const ms = createdAt && typeof createdAt.toMillis === "function" ? createdAt.toMillis() : Date.now();
  const year = new Date(ms + 8 * 60 * 60 * 1000).getUTCFullYear();
  return `${year}-${code}`;
}

function isAlreadyExists(err) {
  return err && (err.code === 6 || err.code === "already-exists");
}

exports.issueOrderReceipt = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const order = event.data.after.data();
  if (before.status === "completed" || order.status !== "completed") return;
  if (!order.sellerId || !order.buyerId) return;

  const { orderId } = event.params;
  const code = orderCode(orderId, order.createdAt);
  const orderDisplayId = `AGR-${code}`;
  const receiptNumber = `RCT-${code}`;

  const subtotal = typeof order.subtotal === "number" ? order.subtotal : Number(order.total) || 0;
  const isDelivery = order.deliveryMethod === "delivery";
  const deliveryFee = isDelivery && typeof order.deliveryFee === "number" ? order.deliveryFee : null;
  // Unknown when the delivery fee was arranged outside the order.
  const total = isDelivery && deliveryFee == null
    ? null
    : (typeof order.grandTotal === "number" ? order.grandTotal : subtotal + (deliveryFee || 0));

  // General area only (barangay, municipality) — never an exact address.
  const sellerSnap = await db.collection("users").doc(order.sellerId).get();
  const seller = sellerSnap.exists ? sellerSnap.data() : {};
  const sellerArea = [seller.barangay, seller.municipality]
    .filter((v) => typeof v === "string" && v.trim())
    .join(", ");

  const pick = (key) => (order[key] === undefined ? null : order[key]);
  try {
    await db.collection("receipts").doc(orderId).create({
      receiptNumber,
      orderDisplayId,
      orderId,
      status: "completed",
      generatedAt: FieldValue.serverTimestamp(),
      sellerId: order.sellerId,
      sellerName: order.sellerName || "Farmer",
      sellerArea,
      buyerId: order.buyerId,
      buyerName: order.buyerName || "Buyer",
      productId: pick("productId"),
      productName: order.productName || "Product",
      pricingType: order.pricingType || "retail",
      quantity: pick("quantity"),
      unit: order.unit || "",
      quantityLabel: pick("quantityLabel"),
      pricePerUnit: order.pricePerUnit ?? order.unitPrice ?? null,
      subtotal,
      deliveryMethod: order.deliveryMethod || "",
      deliveryArrangement: pick("deliveryArrangement"),
      deliveryFee,
      grandTotal: total,
      createdAt: pick("createdAt"),
      confirmedAt: pick("confirmedAt"),
      shippedAt: pick("shippedAt"),
      completedAt: order.completedAt || order.updatedAt || FieldValue.serverTimestamp(),
    });
  } catch (err) {
    if (!isAlreadyExists(err)) throw err;
  }

  const conversationId = [order.sellerId, order.buyerId].sort().join("_");
  const convRef = db.collection("conversations").doc(conversationId);
  const msgRef = convRef.collection("messages").doc(`receipt_${orderId}`);
  try {
    await msgRef.create({
      senderId: order.sellerId,
      type: "receipt",
      orderId,
      orderDisplayId,
      receiptNumber,
      productId: pick("productId"),
      productName: order.productName || "Product",
      subtotal,
      total,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    if (isAlreadyExists(err)) return; // Already in the conversation.
    throw err;
  }

  const preview = {
    lastMessage: `Transaction receipt · Order #${orderDisplayId}`,
    lastMessageTime: FieldValue.serverTimestamp(),
    lastSenderId: order.sellerId,
    unreadCount: { [order.buyerId]: FieldValue.increment(1) },
    // Real content: this is what puts the thread in both Messages lists
    // (see MessageService.hasMessageActivity).
    hasMessages: true,
  };
  const convSnap = await convRef.get();
  if (convSnap.exists) {
    await convRef.set(preview, { merge: true });
  } else {
    await convRef.set({
      participants: [order.buyerId, order.sellerId],
      participantNames: {
        [order.buyerId]: order.buyerName || "Buyer",
        [order.sellerId]: order.sellerName || "Farmer",
      },
      farmerId: order.sellerId,
      farmerName: order.sellerName || "Farmer",
      productId: pick("productId"),
      productName: order.productName || "Product",
      productImageUrl: order.imageUrl || "",
      farmerImage: order.imageUrl || "",
      ...preview,
    });
  }
});

// Account emails (verification, password reset, new-device alert) are sent
// through Gmail SMTP — see account_emails.js and mailer.js.
Object.assign(exports, require("./account_emails"));

// The Admin Portal's single active session and its sign-in alert: see
// admin_session.js.
Object.assign(exports, require("./admin_session"));

// "Is this email already registered?", asked before a second
// registration is started: see registration_status.js.
Object.assign(exports, require("./registration_status"));

// 6-digit email verification code for email/password sign-ups — see
// email_otp.js.
Object.assign(exports, require("./email_otp"));

// Failed-login cooldown (5 wrong passwords → 5 minute pause) — see
// login_throttle.js.
Object.assign(exports, require("./login_throttle"));

// The public page behind a shared product link (/product/<id> on Hosting).
Object.assign(exports, require("./public_product"));

// ---------------------------------------------------------------
// Order delay / reschedule (see OrderService.reportDelay and friends).
//
// A confirmed order the farmer cannot fulfil on time is not failed or
// re-created: the farmer reports a delay with a reason and a proposed new
// date, and the buyer accepts it or cancels. Same order id throughout; no
// penalty is recorded against either side for any reason given.
//
//   delay reported / updated  -> the buyer is told why, and the new date
//   buyer accepted the date   -> the farmer is told
//   buyer cancelled           -> the farmer is told, and the quantity the
//                                order had reserved goes back to the
//                                listing, exactly once (stockRestoredAt
//                                marks it; a buyer cannot write a
//                                product's stock, so it is done here)
//
// Nothing here runs on a date passing: a requested or proposed date is
// never a deadline that changes an order by itself.
// ---------------------------------------------------------------
const DELAY_REASON_TEXT = {
  weather: "weather conditions",
  transport: "a road or transportation issue",
  supply: "a harvest or supply delay",
  other: "an unexpected delay",
};

function formatManilaDate(timestamp) {
  if (!timestamp || typeof timestamp.toDate !== "function") return null;
  return timestamp.toDate().toLocaleDateString("en-US", {
    timeZone: "Asia/Manila",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

exports.handleOrderReschedule = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const orderId = event.params.orderId;
  const product = after.productName || "product";
  const delayBefore = before.delay || {};
  const delayAfter = after.delay || {};

  // ---- Buyer cancelled ----
  if (before.status !== "cancelled" && after.status === "cancelled") {
    const orderRef = event.data.after.ref;
    await db.runTransaction(async (tx) => {
      const order = (await tx.get(orderRef)).data();
      if (!order || order.status !== "cancelled" || order.stockRestoredAt) return;
      const quantity = typeof order.quantity === "number" ? order.quantity : Number(order.quantity) || 0;
      if (order.productId && quantity > 0) {
        const productRef = db.collection("products").doc(order.productId);
        const productSnap = await tx.get(productRef);
        if (productSnap.exists) {
          const current = Number(productSnap.data().quantity) || 0;
          tx.update(productRef, { quantity: current + quantity });
        }
      }
      tx.update(orderRef, { stockRestoredAt: FieldValue.serverTimestamp() });
    });

    if (after.sellerId) {
      await notifyUser(after.sellerId, {
        title: "Order Cancelled",
        body: `${after.buyerName || "The buyer"} cancelled the ${product} order after the delay. The quantity has been returned to your listing.`,
        type: "order_status",
        relatedId: orderId,
        data: { orderId, status: "cancelled" },
        dedupeId: `${event.id}-cancelled`,
      });
    }
    return;
  }

  if (after.status !== "confirmed") return;

  // ---- Farmer reported (or updated) a delay ----
  const reportedBefore = delayBefore.reportedAt ? delayBefore.reportedAt.toMillis() : 0;
  const reportedAfter = delayAfter.reportedAt ? delayAfter.reportedAt.toMillis() : 0;
  if (delayAfter.status === "proposed" && reportedAfter && reportedAfter !== reportedBefore) {
    const reason = DELAY_REASON_TEXT[delayAfter.reason] || DELAY_REASON_TEXT.other;
    const date = formatManilaDate(delayAfter.proposedDate);
    await notifyUser(after.buyerId, {
      title: "Order Delayed",
      body:
        `Your ${product} order has been delayed due to ${reason}. ` +
        `${after.sellerName || "The farmer"} proposed a new fulfillment date` +
        `${date ? `: ${date}` : ""}.`,
      type: "order_status",
      relatedId: orderId,
      data: { orderId, status: "delayed" },
      dedupeId: `${event.id}-delay`,
    });
    return;
  }

  // ---- Buyer accepted the proposed date ----
  if (delayBefore.status === "proposed" && delayAfter.status === "accepted" && after.sellerId) {
    const date = formatManilaDate(after.confirmedFulfillmentDate);
    await notifyUser(after.sellerId, {
      title: "New Date Accepted",
      body: `${after.buyerName || "The buyer"} accepted the new date${date ? ` (${date})` : ""} for the ${product} order.`,
      type: "order_status",
      relatedId: orderId,
      data: { orderId, status: "confirmed" },
      dedupeId: `${event.id}-accepted`,
    });
  }
});

// ---------------------------------------------------------------
// Completed sales per product: products/{productId}.completedOrderCount.
//
// A buyer cannot read other buyers' orders (firestore.rules), so the app
// cannot count a product's completed orders itself — this keeps that one
// number on the listing for Recommended Products and marketplace ranking
// (see product_recommendation_service.dart).
//
// Only orders whose status is 'completed' are counted: pending, confirmed,
// shipped and rejected orders never are. Counted afresh each time rather
// than incremented, so a redelivered event cannot inflate it, and an order
// that somehow left 'completed' would be dropped again. The field is not
// among those a farmer may write.
// ---------------------------------------------------------------
async function recountCompletedOrders(productId) {
  if (typeof productId !== "string" || !productId) return;
  const snap = await db.collection("orders")
    .where("productId", "==", productId)
    .where("status", "==", "completed")
    .count()
    .get();
  try {
    await db.collection("products").doc(productId).update({
      completedOrderCount: snap.data().count,
    });
  } catch (err) {
    // The listing itself was deleted — nothing to keep a count on.
    if (err.code !== 5) throw err;
  }
}

exports.syncProductCompletedOrders = onDocumentWritten("orders/{orderId}", async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const wasCompleted = !!before && before.status === "completed";
  const isCompleted = !!after && after.status === "completed";
  if (wasCompleted === isCompleted && (before && before.productId) === (after && after.productId)) return;

  const productIds = new Set([before && before.productId, after && after.productId].filter(Boolean));
  for (const productId of productIds) {
    await recountCompletedOrders(productId);
  }
});

// ---------------------------------------------------------------
// Trending Searches: anonymous per-day counts of what buyers search for.
//
// The Buyer Search screen logs each committed search to searchEvents
// (already normalized: lowercase, trimmed, single spaces). This folds every
// new event into searchTrends/{sha1(term)}:
//   { term, days: { 'YYYY-MM-DD': count }, updatedAt }
// which is what the app reads for Trending Searches (see
// lib/services/search_trends.dart). No buyer id is ever written there.
//
// One buyer counts once per term per day: searchTrendVotes holds a marker
// per (day, term, buyer), created before counting, so repeated searches —
// or a redelivered event — are not counted again. Clients have no access
// to those markers (see firestore.rules).
// ---------------------------------------------------------------
const TREND_DAYS_KEPT = 30;

function manilaDay(date) {
  return new Date(date.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

exports.aggregateSearchTrend = onDocumentCreated("searchEvents/{eventId}", async (event) => {
  const data = event.data.data() || {};
  const uid = typeof data.userId === "string" ? data.userId : "";
  const term = (typeof data.query === "string" ? data.query : "")
    .trim().toLowerCase().replace(/\s+/g, " ");
  // Too short to mean anything, or too long to be a real search term.
  if (!uid || term.length < 2 || term.length > 60) return;

  const termId = require("crypto").createHash("sha1").update(term).digest("hex");
  const now = new Date();
  const day = manilaDay(now);

  try {
    await db.collection("searchTrendVotes").doc(`${day}_${termId}_${uid}`).create({
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    if (err.code === 6) return; // This buyer already counted for this term today.
    throw err;
  }

  const oldestKept = manilaDay(new Date(now.getTime() - TREND_DAYS_KEPT * 24 * 60 * 60 * 1000));
  const trendRef = db.collection("searchTrends").doc(termId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(trendRef);
    const previous = (snap.exists && snap.data().days) || {};
    const days = {};
    for (const [key, count] of Object.entries(previous)) {
      if (key >= oldestKept) days[key] = count;
    }
    days[day] = (days[day] || 0) + 1;
    tx.set(trendRef, { term, days, updatedAt: FieldValue.serverTimestamp() });
  });
});

// ---------------------------------------------------------------
// Saved Products: how many buyers have bookmarked each listing.
//
// A buyer saving a product writes users/{uid}/savedProducts/{productId}
// (see saved_products_service.dart); removing it deletes that document.
// This mirrors each save to products/{productId}/saves/{uid} and stores
// the size of that subcollection as products/{productId}.saveCount — the
// only thing the farmer ever sees ("12 saves").
//
// Counted, not incremented: one document per buyer means the same buyer
// saving twice, or this event being delivered twice, cannot inflate the
// number. Who saved stays private — firestore.rules gives clients no
// access to the saves subcollection, and saveCount is not in the fields a
// farmer may write.
// ---------------------------------------------------------------
exports.syncProductSaveCount = onDocumentWritten(
  "users/{uid}/savedProducts/{productId}",
  async (event) => {
    const { uid, productId } = event.params;
    const productRef = db.collection("products").doc(productId);
    const saveRef = productRef.collection("saves").doc(uid);

    if (event.data.after.exists) {
      await saveRef.set({ savedAt: FieldValue.serverTimestamp() });
    } else {
      await saveRef.delete();
    }

    const count = (await productRef.collection("saves").count().get()).data().count;
    try {
      await productRef.update({ saveCount: count });
    } catch (err) {
      // The listing itself was deleted — nothing to count for.
      if (err.code !== 5) throw err;
    }
  }
);

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

    // The officer's reason for a rejection is kept with the application
    // (written in the same batch as the status), and goes in the notice.
    let reason = "";
    if (!approved) {
      const application = await db.collection("verificationDocs").doc(event.params.uid).get();
      reason = application.exists ? (application.get("rejectionReason") || "").toString().trim() : "";
    }

    // Saved in-app first, whether or not a push can be sent (see
    // notifyUser): a farmer who is signed out sees it at the next sign-in.
    // The email for the same decision is emailFarmerApprovalDecision
    // (account_emails.js).
    await notifyUser(event.params.uid, {
      title: approved ? "Farmer Account Approved" : "Farmer Application Update",
      body: approved
        ? "Your Farmer application has been approved. You can now start using AgriTrade+ as a Farmer."
        : "Your Farmer application was not approved. Please review the Admin's remarks." +
          (reason ? ` Reason: ${reason}` : ""),
      // Reuses the notification type the app's client already switches on
      // (NotificationNavigationService, NotificationsScreen icon lookup) —
      // introducing a differently-named type here would silently fall
      // through to their default case instead of routing/icon-matching.
      type: "verification_status",
      relatedId: event.params.uid,
      data: reason ? { status: after.approvalStatus, reason } : { status: after.approvalStatus },
      dedupeId: event.id,
    });

    // Approved: the farmer can now enter the app for the first time.
    if (approved) await sendWelcome(event.params.uid, "farmer");
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

  // The reported account (see reportedUserIdOf in the app): on a review
  // report farmerId is the farmer who filed it, not the one warned.
  const farmerId = after.reportedUserId || after.farmerId;
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
      ? `Your AgriTrade+ account has been suspended until an Admin reactivates it.${after.suspensionReason ? ` Reason: ${after.suspensionReason}` : ""}`
      : `Your AgriTrade+ account has been deactivated following an Admin review.${after.banReason ? ` Reason: ${after.banReason}` : ""}`,
    type: "moderation_warning",
    relatedId: event.params.uid,
    data: { accountStatus: after.accountStatus },
    dedupeId: event.id,
  });
});

// ---------------------------------------------------------------
// New Device Sign-In alert (push + in-app record).
//
// The app records each installation an account signs in on under
// users/{uid}/trustedDevices/{deviceIdHash}; a record is only ever created
// the first time that installation signs in to that account (see
// DeviceTrustService in the app, and onNewTrustedDevice in
// account_emails.js, which sends the email for the same event).
//
// This is an alert about a sign-in that has already succeeded. It is not
// an approval step and gives no control over the session — tapping it
// opens the account's device list, where the password can be changed.
//
// It goes to every device the account receives notifications on. That can
// include the new device itself, which is harmless: it says nothing the
// person holding that device does not already know.
//
// Not sent for the account's very first device — there is no earlier one
// for it to be "new" relative to.
// ---------------------------------------------------------------
exports.notifyNewDeviceSignIn = onDocumentCreated(
  "users/{uid}/trustedDevices/{deviceId}",
  async (event) => {
    const { uid, deviceId } = event.params;
    const device = event.data.data() || {};

    const known = await db.collection("users").doc(uid).collection("trustedDevices").limit(2).get();
    if (known.size <= 1) return;

    const alert = newDeviceAlert({ deviceName: device.deviceName, platform: device.platform });
    await notifyUser(uid, {
      ...alert,
      type: NEW_DEVICE_TYPE,
      channelId: CHANNELS.security,
      relatedId: deviceId,
      // What the device list needs to point at the right row — the hashed
      // installation id, never a credential.
      data: {
        deviceId,
        deviceName: (device.deviceName || "").toString(),
        platform: (device.platform || "").toString(),
      },
      dedupeId: `new-device-${deviceId}`,
    });
  }
);

// ---------------------------------------------------------------
// Admin announcement -> notify its audience (in-app record + push).
//
// The Admin Portal creates announcements/{id} (title, body, kind,
// audience). Recipients are approved farmers, plus buyers when the
// audience is "all" (a maintenance notice always is). Banned accounts are
// left out. The title and body ride along in `data` so the app can show
// the whole message when the notification is tapped.
//
// A retry delivers nothing twice: each recipient's record is keyed by the
// announcement id (see notifyUser's dedupeId).
// ---------------------------------------------------------------
exports.sendAnnouncement = onDocumentCreated("announcements/{announcementId}", async (event) => {
  const { announcementId } = event.params;
  const announcement = event.data.data() || {};
  const title = String(announcement.title || "").trim();
  const body = String(announcement.body || "").trim();
  if (!title || !body) return;

  const kind = announcement.kind === "maintenance" ? "maintenance" : "announcement";
  const roles = announcement.audience === "all" ? ["farmer", "buyer"] : ["farmer"];
  const users = await db.collection("users").where("role", "in", roles).get();
  const recipients = users.docs.filter((doc) => {
    const user = doc.data();
    if (user.accountStatus === "banned") return false;
    return user.role !== "farmer" || user.approvalStatus === "approved";
  });

  let delivered = 0;
  for (const doc of recipients) {
    try {
      await notifyUser(doc.id, {
        title,
        body,
        type: "announcement",
        relatedId: announcementId,
        data: { announcementId, kind, title, body },
        dedupeId: `announcement_${announcementId}`,
      });
      delivered++;
    } catch (err) {
      console.error(`sendAnnouncement(${announcementId}): ${doc.id} failed —`, err.message);
    }
  }
  console.log(`sendAnnouncement(${announcementId}): delivered to ${delivered} of ${recipients.length} account(s).`);
  await event.data.ref.update({
    deliveredTo: delivered,
    deliveredAt: FieldValue.serverTimestamp(),
  });
});

// ---------------------------------------------------------------
// The Agricultural Office archived a commodity (Admin → Price Management:
// its selling is stopped for a reason, e.g. a livestock disease) or
// restored it.
//
// Archived:
//   * every listing of that commodity is hidden from the marketplace —
//     isSuspended, the flag buyers' screens, ordering and the farmer's own
//     listing already respect — and marked moderationStatus
//     "commodity_archived" with the office's reason, so it is known WHY it
//     is hidden and which listings to bring back;
//   * the farmers who sell it are told, with the reason.
// Restored:
//   * only the listings hidden by the archive come back (one an Admin hid
//     or removed for its own reasons stays as it is);
//   * the same farmers are told it is available again.
//
// The notice is an "announcement" to the app: tapping it shows its title
// and message, as any announcement from the office does.
// ---------------------------------------------------------------
exports.onCommodityArchiveChanged = onDocumentUpdated("market_prices/{commodityId}", async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};
  const change = archiveChange(before, after);
  if (!change) return;

  const { commodityId } = event.params;
  const name = String(after.name || commodityId).trim();
  const reason = String(after.archiveReason || "").trim();

  // The commodity's listings, by the commodity each one was posted under.
  const listings = await db.collection("products").where("commodity", "==", name).get();
  const affectedByFarmer = new Map();
  let batch = db.batch();
  let writes = 0;
  for (const doc of listings.docs) {
    const product = doc.data();
    if (change === "archived") {
      // Already hidden or removed by an Admin: left exactly as it is.
      if (product.isSuspended === true) continue;
      batch.update(doc.ref, {
        isSuspended: true,
        moderationStatus: COMMODITY_ARCHIVED,
        moderationReason: reason,
        moderatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      if (product.moderationStatus !== COMMODITY_ARCHIVED) continue;
      batch.update(doc.ref, {
        isSuspended: false,
        moderationStatus: FieldValue.delete(),
        moderationReason: FieldValue.delete(),
        moderatedAt: FieldValue.serverTimestamp(),
      });
    }
    const farmerId = String(product.farmerId || "");
    if (farmerId) affectedByFarmer.set(farmerId, (affectedByFarmer.get(farmerId) || 0) + 1);
    if (++writes % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (writes % 400 !== 0) await batch.commit();

  // Only the farmers who sell it: those with a listing hidden (or brought
  // back) just now. Nobody else is told.
  let delivered = 0;
  for (const [farmerId, count] of affectedByFarmer) {
    const notice = commodityNotice({ change, name, reason, listings: count });
    try {
      const farmer = await db.collection("users").doc(farmerId).get();
      if (!farmer.exists || farmer.data().accountStatus === "banned") continue;
      await notifyUser(farmerId, {
        title: notice.title,
        body: notice.body,
        type: "announcement",
        relatedId: commodityId,
        data: { kind: "commodity", commodityId, change, title: notice.title, body: notice.body },
        dedupeId: `commodity_${commodityId}_${event.id}`,
      });
      delivered++;
    } catch (err) {
      console.error(`onCommodityArchiveChanged(${commodityId}): ${farmerId} failed —`, err.message);
    }
  }
  console.log(
    `onCommodityArchiveChanged(${commodityId}): ${name} ${change}; ${writes} listing(s) updated, ` +
      `${delivered} farmer(s) notified.`
  );
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
  "REMOVE_REVIEW",
  "DISMISS_REPORT",
  "REACTIVATE_FARMER",
  "RESTORE_LISTING",
  "UPDATE_SUPPORT_REQUEST",
  "LOGIN_SUCCESS",
  "LOGOUT",
  // The browser whose Admin session was ended by a sign-in elsewhere logs
  // this on its way out. NEW_DEVICE_LOGIN and SESSION_REPLACED are written
  // by adminSession itself (admin_session.js), never by a client.
  "SESSION_FORCED_LOGOUT",
  // The report workflow, and account actions on any marketplace account.
  "START_REPORT_REVIEW",
  "RESOLVE_REPORT",
  "CONFIRM_VIOLATION",
  "SUSPEND_ACCOUNT",
  "BAN_ACCOUNT",
  "REACTIVATE_ACCOUNT",
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
  "SEND_ANNOUNCEMENT",
]);

// "Chrome on Windows" from a User-Agent header: see user_agent.js.
const { parseUserAgent } = require("./user_agent");

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
    throw new HttpsError("unauthenticated", "This action must be logged while logged in.");
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
    // The place the Admin's own browser reported (see AdminDeviceLocation
    // in the app) — a place name only. It is what the device says, not
    // something the server can check; nothing is guessed from the IP.
    location: clip(request.data && request.data.location, 120) || "Unknown",
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
