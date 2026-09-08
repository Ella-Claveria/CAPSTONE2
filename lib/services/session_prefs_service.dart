import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// One device-remembered account: which role it logged in as, and the email
/// it used. Firebase Auth accounts are always unique per email, so email is
/// the natural key for telling saved accounts apart — this is how the same
/// device can remember a farmer account and a buyer account (or several of
/// each) side by side, as long as each uses a different email address.
class SavedAccount {
  final String role;
  final String email;
  const SavedAccount({required this.role, required this.email});

  Map<String, dynamic> toJson() => {'role': role, 'email': email};
  factory SavedAccount.fromJson(Map<String, dynamic> json) =>
      SavedAccount(role: json['role'] as String, email: json['email'] as String);
}

/// Remembers, per device, the accounts that have logged in with "Save login
/// info" checked, most-recently-used first — so next time, instead of
/// typing an email and password again, they can just tap the account they
/// want to continue as.
///
/// IMPORTANT security note: this only ever stores an email + role, never a
/// password. Firebase Auth keeps exactly one account's session alive on a
/// device at a time (whichever logged in most recently) — so tapping THAT
/// saved account is genuinely one tap, no re-entry needed. Tapping a
/// *different* saved account still asks for its password once: there is no
/// secure way to silently re-authenticate a second account without either
/// storing its password (which this app deliberately never does) or a much
/// larger "multiple simultaneous Firebase sessions" architecture change.
class SessionPrefsService {
  static const _roleKey = 'last_used_role';
  static const _emailKey = 'last_used_email';
  static const _accountsKey = 'saved_accounts';
  static const _maxSavedAccounts = 5;

  Future<void> saveLastLogin({required String role, required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role);
    await prefs.setString(_emailKey, email);

    final accounts = await getSavedAccounts();
    accounts.removeWhere((a) => a.email.toLowerCase() == email.toLowerCase());
    accounts.insert(0, SavedAccount(role: role, email: email));
    await _writeAccounts(prefs, accounts.take(_maxSavedAccounts).toList());
  }

  /// Most-recently-used first.
  Future<List<SavedAccount>> getSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedAccount.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Forgets one saved account (e.g. they unchecked "Save login info" for it,
  // or asked to remove it from the list) without touching any others.
  Future<void> removeSavedAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getSavedAccounts();
    accounts.removeWhere((a) => a.email.toLowerCase() == email.toLowerCase());
    await _writeAccounts(prefs, accounts);

    final lastEmail = prefs.getString(_emailKey);
    if (lastEmail != null && lastEmail.toLowerCase() == email.toLowerCase()) {
      await prefs.remove(_roleKey);
      await prefs.remove(_emailKey);
    }
  }

  Future<void> _writeAccounts(SharedPreferences prefs, List<SavedAccount> accounts) async {
    await prefs.setString(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  Future<String?> getLastRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  Future<String?> getLastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  // Forgets everything remembered on this device (all saved accounts).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_accountsKey);
  }
}
