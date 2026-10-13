/**
 * Points a Firebase password-reset link at the AgriTrade+ reset page
 * (web/reset-password/index.html, served by Firebase Hosting) instead of
 * Firebase's own hosted page. No Firebase in here, so it can be unit
 * tested (see test/reset_link.test.js).
 *
 * Firebase Authentication still creates the one-time code
 * (generatePasswordResetLink) and still checks it; only the page the link
 * opens changes. The query string is carried over unchanged, so the page
 * receives exactly what Firebase's own handler would: mode, oobCode,
 * apiKey and lang.
 */

const RESET_PAGE_URL = "https://agritrade-bef87.web.app/reset-password/";

/**
 * `firebaseLink` is what generatePasswordResetLink returned. If it is not
 * a reset link in the shape expected, it is returned untouched, so the
 * email still carries a working link (to Firebase's own page).
 *
 * `admin: true` adds portal=admin, which makes the page offer the Admin
 * web login once the password is changed. Everyone else is told to open
 * the mobile app, and is never shown a way into the Admin site. The flag
 * only picks that message — it gives no access to anything.
 */
function resetPageLink(firebaseLink, { admin = false, pageUrl = RESET_PAGE_URL } = {}) {
  try {
    const source = new URL(firebaseLink);
    if (source.searchParams.get("mode") !== "resetPassword" || !source.searchParams.get("oobCode")) {
      return firebaseLink;
    }
    const target = new URL(pageUrl);
    target.search = source.search;
    if (admin) target.searchParams.set("portal", "admin");
    return target.toString();
  } catch (_) {
    return firebaseLink;
  }
}

module.exports = { RESET_PAGE_URL, resetPageLink };
