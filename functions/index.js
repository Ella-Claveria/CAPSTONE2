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

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
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
  if (tokens.length === 0) return;

  const response = await messaging.sendEachForMulticast({
    notification: { title, body },
    data: { type, ...(data || {}) },
    tokens,
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
      title: senderName,
      body:
        message.text?.length > 120
          ? `${message.text.slice(0, 117)}...`
          : message.text || "Sent a photo",
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
// New order -> notify the farmer/seller who needs to act on it.
// ---------------------------------------------------------------
exports.notifyNewOrder = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data.data();
  const productName = order.productName || "a product";
  const buyerName = order.buyerName || "A buyer";
  const qtyLabel = (order.quantityLabel || `${order.quantity ?? ""} ${order.unit ?? ""}`).trim();

  await notifyUser(order.sellerId, {
    title: "New order received",
    body: `${buyerName} ordered ${qtyLabel || "an item"} of ${productName}.`,
    type: "new_order",
    data: { orderId: event.params.orderId },
    dedupeId: event.id,
  });
});

// ---------------------------------------------------------------
// Order status changes (confirmed / rejected / completed) -> notify
// the buyer who placed it.
// ---------------------------------------------------------------
exports.notifyOrderStatusChange = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;

  const statusLabels = { confirmed: "confirmed", rejected: "declined", completed: "completed" };
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
// Farmer verification approved/rejected -> notify the applicant.
// ---------------------------------------------------------------
exports.notifyVerificationStatusChange = onDocumentUpdated(
  "verificationDocs/{uid}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (after.status !== "approved" && after.status !== "rejected") return;

    const uid = after.userId || event.params.uid;
    const approved = after.status === "approved";

    await notifyUser(uid, {
      title: approved ? "You're verified!" : "Verification update",
      body: approved
        ? "Your farmer account has been verified. You can now start listing products."
        : "Your verification application was not approved. Please review and resubmit your documents.",
      type: "verification_status",
      data: { status: after.status },
      dedupeId: event.id,
    });
  }
);
