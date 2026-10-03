/**
 * AgriTrade+ transactional email templates. Each builder returns
 * { subject, text, html } for mailer.sendMail().
 *
 * The HTML is table-based with inline styles only, which is what mail
 * clients (Gmail, Outlook, Yahoo) reliably render. Anything that comes from
 * a user or a device goes through escapeHtml().
 */

const BRAND_GREEN = "#0E3210";
const FONT = "'Montserrat','Segoe UI',Arial,Helvetica,sans-serif";

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (ch) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]
  ));
}

function greetingFor(name) {
  const clean = (name || "").toString().trim();
  return clean ? `Hello ${clean},` : "Hello,";
}

function paragraph(html) {
  return `<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#333333">${html}</p>`;
}

function button(label, url) {
  return `
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px">
      <tr>
        <td align="center" bgcolor="${BRAND_GREEN}" style="border-radius:28px">
          <a href="${escapeHtml(url)}" target="_blank"
             style="display:inline-block;padding:14px 32px;font-family:${FONT};font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:28px">${escapeHtml(label)}</a>
        </td>
      </tr>
    </table>`;
}

function linkFallback(url) {
  return `
    <p style="margin:0 0 6px;font-size:13px;line-height:1.5;color:#666666">If the button does not work, copy and paste this link into your browser:</p>
    <p style="margin:0 0 20px;font-size:13px;line-height:1.5;word-break:break-all"><a href="${escapeHtml(url)}" target="_blank" style="color:${BRAND_GREEN}">${escapeHtml(url)}</a></p>`;
}

function detailsTable(rows) {
  const body = rows.map(([label, value]) => `
      <tr>
        <td style="padding:6px 16px 6px 0;font-size:14px;color:#666666;white-space:nowrap;vertical-align:top">${escapeHtml(label)}</td>
        <td style="padding:6px 0;font-size:14px;font-weight:600;color:#222222">${escapeHtml(value)}</td>
      </tr>`).join("");
  return `
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
           style="margin:0 0 20px;background:#F4F7F4;border-radius:10px">
      <tr><td style="padding:12px 18px">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0">${body}
        </table>
      </td></tr>
    </table>`;
}

function layout({ title, preheader, bodyHtml }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
</head>
<body style="margin:0;padding:0;background:#EEF2EE">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent">${escapeHtml(preheader)}</div>
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#EEF2EE">
    <tr>
      <td align="center" style="padding:24px 12px">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
               style="max-width:560px;background:#ffffff;border-radius:14px;overflow:hidden;font-family:${FONT}">
          <tr>
            <td bgcolor="${BRAND_GREEN}" style="padding:22px 28px;font-family:${FONT};font-size:22px;font-weight:700;color:#ffffff;letter-spacing:0.3px">AgriTrade+</td>
          </tr>
          <tr>
            <td style="padding:28px 28px 8px;font-family:${FONT}">
              <h1 style="margin:0 0 18px;font-size:20px;line-height:1.3;font-weight:700;color:${BRAND_GREEN}">${escapeHtml(title)}</h1>
              ${bodyHtml}
            </td>
          </tr>
          <tr>
            <td style="padding:16px 28px 24px;border-top:1px solid #E6ECE6;font-family:${FONT};font-size:12px;line-height:1.5;color:#888888">
              This is an automated message from AgriTrade+. Please do not reply to this email.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function verificationEmail({ name, link }) {
  const greeting = greetingFor(name);
  return {
    subject: "Verify your email for AgriTrade+",
    text: [
      greeting,
      "",
      "Thank you for registering with AgriTrade+. Please confirm your email address by opening the link below:",
      "",
      link,
      "",
      "If you did not create an AgriTrade+ account, you can ignore this email.",
      "",
      "The AgriTrade+ Team",
    ].join("\n"),
    html: layout({
      title: "Verify your email address",
      preheader: "Confirm your email address to finish setting up your AgriTrade+ account.",
      bodyHtml: [
        paragraph(`<strong>${escapeHtml(greeting)}</strong>`),
        paragraph("Thank you for registering with AgriTrade+. Please confirm your email address to finish setting up your account."),
        button("Verify Email", link),
        linkFallback(link),
        paragraph("If you did not create an AgriTrade+ account, you can ignore this email."),
        paragraph(`<strong style="color:${BRAND_GREEN}">The AgriTrade+ Team</strong>`),
      ].join("\n"),
    }),
  };
}

// The 6-digit code from email_otp.js, shown as "482 731".
function otpEmail({ code }) {
  const spaced = `${code.slice(0, 3)} ${code.slice(3)}`;
  return {
    subject: "Your AgriTrade+ verification code",
    text: [
      "Verify your email address",
      "",
      "Your AgriTrade+ verification code is:",
      "",
      spaced,
      "",
      "This code will expire in 10 minutes.",
      "",
      "If you did not create an AgriTrade+ account, you may safely ignore this email.",
      "",
      "AgriTrade+ Team",
    ].join("\n"),
    html: layout({
      title: "Verify your email address",
      preheader: "Your AgriTrade+ verification code. It expires in 10 minutes.",
      bodyHtml: [
        paragraph("Your AgriTrade+ verification code is:"),
        `<p style="margin:0 0 20px;padding:16px 12px;background:#F4F7F4;border-radius:10px;text-align:center;font-size:32px;line-height:1.2;font-weight:700;letter-spacing:6px;color:${BRAND_GREEN}">${escapeHtml(spaced)}</p>`,
        paragraph("This code will expire in 10 minutes."),
        paragraph("If you did not create an AgriTrade+ account, you may safely ignore this email."),
        paragraph(`<strong style="color:${BRAND_GREEN}">AgriTrade+ Team</strong>`),
      ].join("\n"),
    }),
  };
}

function passwordResetEmail({ name, link }) {
  const greeting = greetingFor(name);
  return {
    subject: "Reset your AgriTrade+ password",
    text: [
      greeting,
      "",
      "We received a request to reset the password for your AgriTrade+ account. Open the link below to choose a new password:",
      "",
      link,
      "",
      "If you did not request a password reset, you can ignore this email. Your password will not change.",
      "",
      "The AgriTrade+ Team",
    ].join("\n"),
    html: layout({
      title: "Reset your password",
      preheader: "Use this link to choose a new password for your AgriTrade+ account.",
      bodyHtml: [
        paragraph(`<strong>${escapeHtml(greeting)}</strong>`),
        paragraph("We received a request to reset the password for your AgriTrade+ account. Use the button below to choose a new password."),
        button("Reset Password", link),
        linkFallback(link),
        paragraph("If you did not request a password reset, you can ignore this email. Your password will not change."),
        paragraph(`<strong style="color:${BRAND_GREEN}">The AgriTrade+ Team</strong>`),
      ].join("\n"),
    }),
  };
}

function newDeviceEmail({ name, deviceName, platform, when }) {
  const greeting = greetingFor(name);
  return {
    subject: "New sign-in to your AgriTrade+ account",
    text: [
      greeting,
      "",
      "We detected a successful sign-in to your AgriTrade+ account from a new device.",
      "",
      "Sign-in details",
      `Device: ${deviceName}`,
      `Platform: ${platform}`,
      `Date and time: ${when} (Philippine time)`,
      "",
      "If this was you, no action is required.",
      "",
      "If you do not recognize this sign-in, please change your AgriTrade+ password immediately and secure your account.",
      "",
      "AgriTrade+ Security",
    ].join("\n"),
    html: layout({
      title: "New sign-in detected",
      preheader: "Your AgriTrade+ account was signed in to from a new device.",
      bodyHtml: [
        paragraph(`<strong>${escapeHtml(greeting)}</strong>`),
        paragraph("We detected a successful sign-in to your AgriTrade+ account from a new device."),
        detailsTable([
          ["Device", deviceName],
          ["Platform", platform],
          ["Date and time", `${when} (Philippine time)`],
        ]),
        paragraph("If this was you, no action is required."),
        paragraph("If you do not recognize this sign-in, please change your AgriTrade+ password immediately and secure your account."),
        paragraph(`<strong style="color:${BRAND_GREEN}">AgriTrade+ Security</strong>`),
      ].join("\n"),
    }),
  };
}

module.exports = { escapeHtml, verificationEmail, otpEmail, passwordResetEmail, newDeviceEmail };
