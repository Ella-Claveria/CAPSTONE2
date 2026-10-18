/**
 * When to remind a farmer to mark a shipped order Completed
 * (remindFarmersToComplete in index.js): the day after the order's date
 * has passed — the date both sides agreed on (after a delay), else the
 * date the buyer asked for, else the day it was shipped — while it is
 * still "shipped" and has not been reminded yet. Pure functions, so they
 * are tested without Firebase.
 */

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

// The calendar day (in the Philippines) of an instant, as a day number.
function manilaDay(ms) {
  return Math.floor((ms + MANILA_OFFSET_MS) / (24 * 60 * 60 * 1000));
}

/** The date the order was due to reach the buyer, in ms, or null. */
function dueDateMs(order) {
  return millis(order.confirmedFulfillmentDate) ??
    millis(order.requestedFulfillmentDate) ??
    millis(order.neededBy) ??
    millis(order.shippedAt) ??
    millis(order.updatedAt);
}

/** Whether [order] should get its reminder at [nowMs]. */
function completionReminderDue(order, nowMs) {
  if (!order || order.status !== "shipped") return false;
  if (order.completionReminderSentAt) return false;
  const due = dueDateMs(order);
  if (due == null) return false;
  // From the day after the due date (Philippine calendar days).
  return manilaDay(nowMs) > manilaDay(due);
}

module.exports = { dueDateMs, completionReminderDue, manilaDay };
