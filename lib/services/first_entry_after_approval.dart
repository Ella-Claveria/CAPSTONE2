import 'package:shared_preferences/shared_preferences.dart';

/// A farmer just approved is sent back to log in (PendingApprovalScreen)
/// rather than straight into the app. That login is still their first time
/// in it, so — unlike any other login, which means an existing user — it
/// must not mark the feature walkthrough as seen. This remembers, on this
/// phone, which account that is until it has logged in.
class FirstEntryAfterApproval {
  FirstEntryAfterApproval._();

  static const _key = 'first_entry_after_approval_uid';

  static Future<void> mark(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, uid);
    } catch (_) {
      // Best effort: at worst the walkthrough is skipped.
    }
  }

  /// Whether [uid] is logging in for the first time since its approval;
  /// forgotten once asked, so it counts for that one login only.
  static Future<bool> take(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key) != uid) return false;
      await prefs.remove(_key);
      return true;
    } catch (_) {
      return false;
    }
  }
}
