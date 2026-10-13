// What a farmer is told when the Agricultural Office archives a commodity
// they sell (stops its selling for a reason — a livestock disease, say) or
// restores it — kept free of Firebase so it can be tested on its own
// (see test/commodity_notice.test.js). onCommodityArchiveChanged in
// index.js sends it, only to the farmers with a listing of that commodity.

/** The value written to a listing hidden because its commodity is archived. */
const COMMODITY_ARCHIVED = "commodity_archived";

/**
 * What changed on a market_prices document: "archived", "restored", or
 * null. A commodity with no isActive field is in use (the app's own rule).
 */
function archiveChange(before, after) {
  const was = !before || before.isActive !== false;
  const is = !after || after.isActive !== false;
  if (was && !is) return "archived";
  if (!was && is) return "restored";
  return null;
}

function plural(count, word) {
  return `${count} ${word}${count === 1 ? "" : "s"}`;
}

/**
 * The notice for one farmer.
 *   listings  how many of this farmer's own listings were hidden/returned
 */
function commodityNotice({ change, name, reason, listings }) {
  const why = (reason || "").toString().trim();
  const because = why ? ` Reason: ${why}` : "";
  const theirs = `Your ${plural(listings, "listing")} of ${name} ${listings === 1 ? "is" : "are"}`;
  if (change === "archived") {
    return {
      title: `${name} is temporarily unavailable`,
      body:
        `The Agricultural Office has stopped the selling of ${name} for now.${because} ` +
        `${theirs} hidden from the marketplace until it is restored.`,
    };
  }
  return {
    title: `${name} is available again`,
    body: `The Agricultural Office has restored ${name}. ${theirs} back on the marketplace.`,
  };
}

module.exports = { COMMODITY_ARCHIVED, archiveChange, commodityNotice };
