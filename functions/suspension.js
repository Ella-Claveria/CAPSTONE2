/**
 * Suspensions set for a time end by themselves.
 *
 *   liftExpiredSuspensions   every 15 minutes   — marks accounts whose
 *                                                 suspendedUntil has passed
 *                                                 active again
 *
 * Until it runs, the account is already treated as active: firestore.rules
 * (activeAccount) and the app's login check (AuthRoutingService) both read
 * suspendedUntil. A suspension with no suspendedUntil lasts until an Admin
 * reactivates the account.
 *
 * Loaded by index.js after the Admin app is initialized.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { suspensionExpired } = require("./suspension_logic");

const db = getFirestore();

const REGION = "asia-southeast1";

exports.liftExpiredSuspensions = onSchedule(
  { schedule: "every 15 minutes", region: REGION, timeZone: "Asia/Manila" },
  async () => {
    const now = new Date();
    // A range on one field needs no composite index; the status is checked
    // on each account below.
    const due = await db.collection("users")
      .where("suspendedUntil", "<=", Timestamp.fromDate(now))
      .limit(400)
      .get();
    const batch = db.batch();
    let lifted = 0;
    for (const doc of due.docs) {
      if (!suspensionExpired(doc.data(), now)) continue;
      batch.update(doc.ref, {
        accountStatus: "active",
        suspensionReason: FieldValue.delete(),
        suspendedUntil: FieldValue.delete(),
        suspensionEndedAt: FieldValue.serverTimestamp(),
      });
      lifted++;
    }
    if (lifted > 0) await batch.commit();
    console.log(`liftExpiredSuspensions: ${lifted} suspension(s) ended`);
  }
);
