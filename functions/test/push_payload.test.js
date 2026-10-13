// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { CHANNELS, NEW_DEVICE_TYPE, pushData, newDeviceAlert } = require("../push_payload");

test("push data is strings only, so one empty value cannot fail the send", () => {
  const data = pushData("moderation_warning", {
    reportId: "r1",
    productId: null,
    missing: undefined,
    count: 3,
    flag: true,
  });
  assert.deepStrictEqual(data, {
    type: "moderation_warning",
    reportId: "r1",
    count: "3",
    flag: "true",
  });
  for (const value of Object.values(data)) assert.strictEqual(typeof value, "string");
});

test("push data works with nothing but a type", () => {
  assert.deepStrictEqual(pushData("chat_message"), { type: "chat_message" });
  assert.deepStrictEqual(pushData("chat_message", null), { type: "chat_message" });
});

test("security alerts use their own channel and type", () => {
  assert.notStrictEqual(CHANNELS.security, CHANNELS.transactions);
  assert.strictEqual(NEW_DEVICE_TYPE, "security_new_device");
});

test("the new-device alert names the device and says what to do", () => {
  const alert = newDeviceAlert({ deviceName: "samsung SM-A166P", platform: "Android" });
  assert.strictEqual(alert.title, "New Device Login");
  assert.match(alert.body, /samsung SM-A166P, Android/);
  assert.match(alert.body, /change your password/);
});

test("the new-device alert reads properly when the device is unknown", () => {
  for (const input of [{}, undefined, { deviceName: "Unknown device", platform: "Unknown" }, { deviceName: " " }]) {
    const { body } = newDeviceAlert(input);
    assert.match(body, /on a new device\. If this wasn't you/);
  }
});

test("the new-device alert is not worded as an approval request", () => {
  const { title, body } = newDeviceAlert({ deviceName: "Pixel 8", platform: "Android" });
  assert.doesNotMatch(`${title} ${body}`, /approve|trying to log in|was this you/i);
});
