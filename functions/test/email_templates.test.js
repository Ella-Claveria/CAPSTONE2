// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const nodemailer = require("nodemailer");
const templates = require("../email_templates");

const link = "https://agritrade-bef87.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=abc&lang=en";

test("verification email carries the Firebase link in text and html", () => {
  const mail = templates.verificationEmail({ name: "Juan", link });
  assert.match(mail.subject, /Verify your email/);
  assert.ok(mail.text.includes(link));
  // & in the link is escaped inside the href, as HTML requires.
  assert.ok(mail.html.includes(`href="${link.replace(/&/g, "&amp;")}"`));
  assert.ok(mail.html.includes("Hello Juan,"));
});

test("verification code email shows the code and nothing sensitive", () => {
  const mail = templates.otpEmail({ code: "482731" });
  assert.strictEqual(mail.subject, "Your AgriTrade+ verification code");
  assert.ok(mail.text.includes("482 731"));
  assert.ok(mail.html.includes("482 731"));
  assert.ok(mail.text.includes("This code will expire in 10 minutes."));
  assert.ok(!/href=/.test(mail.html));
});

test("password reset email carries the reset link", () => {
  const mail = templates.passwordResetEmail({ name: "", link });
  assert.match(mail.subject, /Reset your AgriTrade\+ password/);
  assert.ok(mail.text.startsWith("Hello,"));
  assert.ok(mail.text.includes(link));
  assert.ok(mail.html.includes("Reset Password"));
});

test("a Google-only account is told how to log in and gets no link", () => {
  const mail = templates.googleSignInEmail({ name: "Ana" });
  assert.match(mail.subject, /log in to your AgriTrade\+ account/);
  assert.ok(mail.text.includes("Continue with Google"));
  assert.ok(mail.html.includes("Continue with Google"));
  assert.ok(!mail.text.includes("http"));
  assert.ok(!/oobCode|href=/.test(mail.html));
});

test("new-device email shows the login details and escapes them", () => {
  const mail = templates.newDeviceEmail({
    name: "<b>Ana</b>",
    deviceName: "samsung SM-A166P <script>",
    platform: "Android",
    when: "October 3, 2026 at 9:15 AM",
  });
  assert.ok(mail.text.includes("Device: samsung SM-A166P <script>"));
  assert.ok(!mail.html.includes("<script>"));
  assert.ok(!mail.html.includes("<b>Ana</b>"));
  assert.ok(mail.html.includes("samsung SM-A166P &lt;script&gt;"));
  assert.ok(mail.html.includes("October 3, 2026 at 9:15 AM (Philippine time)"));
});

test("every email is sent as AgriTrade+ <agritrade.team@gmail.com>", async () => {
  const { MAIL_FROM } = require("../mailer");
  const transport = nodemailer.createTransport({ jsonTransport: true });
  const info = await transport.sendMail({
    from: MAIL_FROM,
    to: "juan@example.com",
    ...templates.otpEmail({ code: "482731" }),
  });
  const sent = JSON.parse(info.message);
  assert.strictEqual(sent.from.name, "AgriTrade+");
  assert.strictEqual(sent.from.address, "agritrade.team@gmail.com");
  assert.strictEqual(sent.subject, "Your AgriTrade+ verification code");
});

test("templates build a message Nodemailer accepts", async () => {
  const transport = nodemailer.createTransport({ jsonTransport: true });
  const mail = templates.verificationEmail({ name: "Juan", link });
  const info = await transport.sendMail({
    from: { name: "AgriTrade+", address: "no-reply@example.com" },
    to: "juan@example.com",
    ...mail,
  });
  const sent = JSON.parse(info.message);
  assert.strictEqual(sent.subject, mail.subject);
  assert.strictEqual(sent.to[0].address, "juan@example.com");
  assert.ok(sent.html.includes("AgriTrade+"));
});
