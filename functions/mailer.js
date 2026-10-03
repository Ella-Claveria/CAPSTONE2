/**
 * The one place AgriTrade+ sends transactional email from: Nodemailer over
 * Gmail SMTP, signed in as the dedicated AgriTrade+ Gmail account. Every
 * email (verification code, password reset, security alerts) goes through
 * sendMail() below.
 *
 * Credentials live in Firebase Functions Secret Manager, never in source:
 *
 *   firebase functions:secrets:set GMAIL_APP_PASSWORD   (a Google App Password for GMAIL_USER)
 *
 * A function that sends email must list MAIL_SECRETS in its `secrets`
 * option, or the value is not available to it at runtime.
 */

const { defineSecret } = require("firebase-functions/params");
const nodemailer = require("nodemailer");

// Both the SMTP username and the From address: Gmail only sends as the
// account it is signed in to. Not a secret — every recipient sees it.
const GMAIL_USER = "agritrade.team@gmail.com";
// The sender every AgriTrade+ email carries — recipients see the name
// "AgriTrade+", not the bare address.
const MAIL_FROM = `"AgriTrade+" <${GMAIL_USER}>`;
const GMAIL_APP_PASSWORD = defineSecret("GMAIL_APP_PASSWORD");

const MAIL_SECRETS = [GMAIL_APP_PASSWORD];

const SMTP_HOST = "smtp.gmail.com";
const SMTP_PORT = 587;

// One pooled connection per function instance, created on first use (the
// secrets are only readable at runtime, not while the module loads).
let transport = null;

function getTransport() {
  if (!transport) {
    transport = nodemailer.createTransport({
      host: SMTP_HOST,
      port: SMTP_PORT,
      secure: false, // STARTTLS on 587
      requireTLS: true,
      auth: {
        user: GMAIL_USER,
        // Google shows App Passwords in groups of four; the spaces are not
        // part of the password.
        pass: GMAIL_APP_PASSWORD.value().replace(/\s/g, ""),
      },
    });
  }
  return transport;
}

/**
 * Sends one email. `message` is what email_templates.js builds:
 * { subject, text, html }. Throws if Gmail does not accept it.
 */
async function sendMail(to, message) {
  return getTransport().sendMail({
    from: MAIL_FROM,
    to,
    subject: message.subject,
    text: message.text,
    html: message.html,
  });
}

/**
 * What went wrong with a send, for the function logs: the SMTP stage and
 * Gmail's reply. Never the password, the recipient or the message itself.
 *   EAUTH              wrong/revoked App Password, or 2-Step Verification off
 *   ESOCKET/ETIMEDOUT  could not reach smtp.gmail.com:587
 *   EENVELOPE          Gmail refused the sender or recipient
 */
function describeMailError(err) {
  return {
    code: (err && err.code) || "unknown",
    command: (err && err.command) || null,
    responseCode: (err && err.responseCode) || null,
    response: err && err.response ? String(err.response).slice(0, 300) : null,
    message: err && err.message ? String(err.message).slice(0, 300) : null,
  };
}

module.exports = { MAIL_SECRETS, MAIL_FROM, sendMail, describeMailError };
