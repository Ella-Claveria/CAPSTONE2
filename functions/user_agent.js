// Minimal hand-rolled User-Agent parse — just enough to label "Chrome on
// Windows" / "Safari on macOS" for the audit table and the Admin sign-in
// alerts, not a full UA database. Falls back to "Unknown" for anything it
// doesn't recognize rather than guessing.
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

module.exports = { parseUserAgent };
