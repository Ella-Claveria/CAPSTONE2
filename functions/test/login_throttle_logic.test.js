// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const throttle = require("../login_throttle_logic");

const now = 1_800_000_000_000;
const MINUTE = 60 * 1000;

// Applies `count` wrong passwords, `gapMs` apart, starting at `start`.
function fail(count, { record = null, start = now, gapMs = 1000 } = {}) {
  let result;
  let at = start;
  for (let i = 0; i < count; i++) {
    const outcome = throttle.recordFailure(record, at);
    if (outcome.next) record = outcome.next;
    result = outcome.result;
    at += gapMs;
  }
  return { record, result, at: at - gapMs };
}

test("no record means login is allowed with all five attempts", () => {
  assert.deepStrictEqual(throttle.status(null, now), {
    locked: false,
    retryAfterSeconds: 0,
    attemptsRemaining: 5,
  });
});

test("the first four failures count down without pausing", () => {
  for (let n = 1; n <= 4; n++) {
    const { result } = fail(n);
    assert.strictEqual(result.locked, false);
    assert.strictEqual(result.attemptsRemaining, 5 - n);
  }
});

test("the fifth failure pauses login for five minutes", () => {
  const { record, result, at } = fail(5);
  assert.deepStrictEqual(result, { locked: true, retryAfterSeconds: 300, attemptsRemaining: 0 });
  assert.strictEqual(record.lockedUntil, at + throttle.LOCK_MS);
  assert.strictEqual(throttle.status(record, at + 2 * MINUTE).retryAfterSeconds, 180);
});

test("attempts during a pause never extend it", () => {
  const { record, at } = fail(5);
  const during = throttle.recordFailure(record, at + 4 * MINUTE);
  assert.strictEqual(during.next, null);
  assert.strictEqual(during.result.locked, true);
  assert.strictEqual(during.result.retryAfterSeconds, 60);
});

test("the pause ends by itself and the count starts again", () => {
  const { record, at } = fail(5);
  const after = at + throttle.LOCK_MS + 1000;
  assert.deepStrictEqual(throttle.status(record, after), {
    locked: false,
    retryAfterSeconds: 0,
    attemptsRemaining: 5,
  });
  const next = throttle.recordFailure(record, after);
  assert.strictEqual(next.result.locked, false);
  assert.strictEqual(next.result.attemptsRemaining, 4);
});

test("old failures stop counting as consecutive", () => {
  const { record, at } = fail(4);
  const later = at + throttle.STALE_MS + 1000;
  assert.strictEqual(throttle.status(record, later).attemptsRemaining, 5);
  assert.strictEqual(throttle.recordFailure(record, later).result.attemptsRemaining, 4);
});

test("emails are normalized and keyed by a hash", () => {
  assert.strictEqual(throttle.normalizeEmail("  Juan@Example.COM "), "juan@example.com");
  assert.strictEqual(throttle.normalizeEmail("not-an-email"), "");
  assert.strictEqual(throttle.normalizeEmail(42), "");
  const key = throttle.keyFor("juan@example.com");
  assert.match(key, /^[0-9a-f]{64}$/);
  assert.ok(!key.includes("juan"));
  assert.notStrictEqual(key, throttle.keyFor("maria@example.com"));
});
