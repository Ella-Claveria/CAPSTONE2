// How a suspension set for a time is worded and when it is over. Pure, so
// it can be tested without Firestore (see test/suspension_logic.test.js).

// `suspendedUntil` on users/{uid} as a Date, or null for a suspension that
// lasts until an Admin reactivates the account.
function suspensionEnd(user) {
  const value = user && user.suspendedUntil;
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

// "until October 17, 2026 at 10:51 AM", in Philippine time, or "until an
// Admin reactivates it".
function suspensionEndText(user) {
  const end = suspensionEnd(user);
  if (!end) return "until an Admin reactivates it";
  return `until ${end.toLocaleString("en-US", {
    timeZone: "Asia/Manila",
    dateStyle: "long",
    timeStyle: "short",
  })}`;
}

// A suspension whose set time has passed.
function suspensionExpired(user, now) {
  if (!user || user.accountStatus !== "suspended") return false;
  const end = suspensionEnd(user);
  return end !== null && end.getTime() <= now.getTime();
}

module.exports = { suspensionEnd, suspensionEndText, suspensionExpired };
