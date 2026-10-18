// Run with: npm test   (from the functions folder)
const test = require("node:test");
const assert = require("node:assert");
const { passwordProblem } = require("../password_policy");

test("the same rules as the app's password checklist", () => {
  assert.strictEqual(passwordProblem("Abcdefgh12!x"), null);
  assert.match(passwordProblem("Abc12!x"), /12 characters/);
  assert.match(passwordProblem("abcdefgh12!x"), /uppercase/);
  assert.match(passwordProblem("ABCDEFGH12!X"), /lowercase/);
  assert.match(passwordProblem("Abcdefghij!x"), /number/);
  assert.match(passwordProblem("Abcdefgh123x"), /symbol/);
  assert.ok(passwordProblem(undefined));
});
