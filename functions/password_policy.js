/**
 * The password rules, the same as the app's PasswordRules
 * (lib/widgets/password_requirements.dart): at least 12 characters, with
 * an uppercase and a lowercase letter, a number and a symbol. Checked
 * again on the server before a password is changed.
 */

const MIN_LENGTH = 12;
const SYMBOL = /[!@#$%^&*(),.?":{}|<>_+\-=[\]]/;

/** Null when [password] meets every rule, or what is missing. */
function passwordProblem(password) {
  if (typeof password !== "string" || password.length < MIN_LENGTH) {
    return `The new password needs at least ${MIN_LENGTH} characters.`;
  }
  if (password.length > 128) return "The new password is too long.";
  if (!/[A-Z]/.test(password)) return "The new password needs an uppercase letter.";
  if (!/[a-z]/.test(password)) return "The new password needs a lowercase letter.";
  if (!/[0-9]/.test(password)) return "The new password needs a number.";
  if (!SYMBOL.test(password)) return "The new password needs a symbol.";
  return null;
}

module.exports = { MIN_LENGTH, passwordProblem };
