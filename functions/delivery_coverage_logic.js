/**
 * Server copy of the app's delivery coverage check
 * (lib/services/delivery_coverage.dart — keep the two in step): whether a
 * listing's delivery coverage reaches the buyer's area. notifyNewOrder uses
 * it to turn away a delivery order the app would never have placed (one
 * written straight to the database, or from an outdated app), since the
 * database rules cannot check places.
 *
 * Pure functions only, so they are tested without Firebase.
 */

// "City of Tanauan", "Tanauan City" and "tanauan" → "tanauan".
function normalizePlace(raw) {
  let s = String(raw || "").toLowerCase().trim();
  s = s.replace(/\(.*?\)/g, " ");
  s = s.replace(/^(city|municipality) of\s+/, "");
  s = s.replace(/\s+city$/, "");
  return s.replace(/[^a-z0-9ñ]/g, "");
}

// Metro Manila has no province: "NCR", "National Capital Region" and
// "Metro Manila" all count as one.
function normalizeProvince(raw) {
  const s = String(raw || "").toLowerCase();
  if (s.includes("ncr") || s.includes("national capital") || s.includes("metro manila")) {
    return "metromanila";
  }
  return normalizePlace(raw);
}

// "Barangay 1 (Pob.)", "Brgy. 1" and "1" → "1".
function normalizeBarangay(raw) {
  let s = String(raw || "").toLowerCase().trim();
  s = s.replace(/\(.*?\)/g, " ");
  s = s.replace(/^(barangay|brgy\.?|bgy\.?)\s*/, "");
  return s.replace(/[^a-z0-9ñ]/g, "");
}

// The towns "Nearby" covers, per farm municipality (kNearbyDeliveryAreas).
const NEARBY = {
  "laurel|batangas": [
    ["Agoncillo", "Batangas"],
    ["Talisay", "Batangas"],
    ["Lemery", "Batangas"],
    ["Calaca", "Batangas"],
    ["Tanauan", "Batangas"],
    ["Tagaytay", "Cavite"],
  ],
};

const DEFAULT_ORIGIN = ["Laurel", "Batangas"];

function areaMatches([name, province], city, buyerProvince) {
  if (normalizePlace(name) !== normalizePlace(city)) return false;
  const a = normalizeProvince(province);
  const b = normalizeProvince(buyerProvince);
  return !a || !b || a === b;
}

/**
 * Whether [product]'s delivery coverage reaches the buyer at
 * { barangay, city, province }. An unknown buyer town is never covered.
 */
function deliveryCovers(product, buyer) {
  const city = String((buyer && buyer.city) || "").trim();
  if (!city) return false;
  const province = String((buyer && buyer.province) || "");
  const raw = product && product.deliveryCoverage;
  // A listing saved before coverage existed: its own municipality only.
  const coverage = raw && typeof raw === "object" ? raw : { type: "municipality" };
  const origin = coverage.originMunicipality
    ? [coverage.originMunicipality, coverage.originProvince || ""]
    : DEFAULT_ORIGIN;
  const type = ["sameBarangay", "municipality", "nearby", "custom"].includes(coverage.type)
    ? coverage.type
    : "municipality";

  if (type === "sameBarangay") {
    const originBarangay = String(coverage.originBarangay || "");
    return areaMatches(origin, city, province) &&
      originBarangay !== "" &&
      normalizeBarangay(originBarangay) === normalizeBarangay(buyer.barangay);
  }
  let areas;
  if (type === "municipality") {
    areas = [origin];
  } else if (type === "nearby") {
    const key = `${normalizePlace(origin[0])}|${normalizeProvince(origin[1])}`;
    areas = [origin, ...(NEARBY[key] || [])];
  } else {
    areas = (Array.isArray(coverage.areas) ? coverage.areas : [])
      .filter((a) => a && String(a.name || "").trim())
      .map((a) => [String(a.name), String(a.province || "")]);
  }
  return areas.some((area) => areaMatches(area, city, province));
}

/**
 * Whether a just-placed [order] must be turned away: a delivery order
 * outside the listing's coverage, or one claiming the old "arranged long
 * distance" exception, which the app no longer offers.
 */
function outsideCoverage(order, product) {
  if (!order || order.deliveryMethod !== "delivery") return false;
  if (order.deliveryArrangement === "longDistance") return true;
  return !deliveryCovers(product, {
    barangay: order.buyerBarangay,
    city: order.buyerMunicipality,
    province: order.buyerProvince,
  });
}

module.exports = {
  normalizePlace,
  normalizeProvince,
  normalizeBarangay,
  deliveryCovers,
  outsideCoverage,
};
