/**
 * Cloud Function: sends a push notification to the OTHER participant
 * whenever a new message document is created in a conversation.
 *
 * Deploy path: functions/index.js (or add this export to your existing file)
 *
 * Requires: firebase-functions v2, firebase-admin, and the "users/{uid}.fcmTokens"
 * array that MessageService.registerFcmToken() writes on the client.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();
const messaging = getMessaging();

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

    const userSnap = await db.collection("users").doc(recipientId).get();
    const tokens = userSnap.exists ? userSnap.data().fcmTokens || [] : [];
    if (tokens.length === 0) return;

    const payload = {
      notification: {
        title: senderName,
        body: message.text?.length > 120 ? `${message.text.slice(0, 117)}...` : message.text,
      },
      data: {
        type: "chat_message",
        conversationId,
        senderId: message.senderId,
      },
      tokens,
    };

    const response = await messaging.sendEachForMulticast(payload);

    // Clean up tokens that are no longer valid (uninstalled app, etc.)
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
      const { FieldValue } = require("firebase-admin/firestore");
      await db.collection("users").doc(recipientId).update({
        fcmTokens: FieldValue.arrayRemove(...staleTokens),
      });
    }
  }
);