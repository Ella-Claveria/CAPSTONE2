import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, per account and per role, the newest order activity the user
/// has already looked at in each status tab. The red tab badges count only
/// activity newer than this, so a farmer opening an order never clears the
/// buyer's badge (or the reverse).
///
/// Times are the orders' own server timestamps, not the device clock.
class OrderSeenStore {
  final String uid;
  final String role;

  const OrderSeenStore({required this.uid, required this.role});

  String get _key => 'orders_seen_${role}_$uid';

  /// Last-seen activity time (ms) per status, or null if this account has
  /// never opened Orders on this device.
  Future<Map<String, int>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Map<String, int> seen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(seen));
    } catch (_) {
      // Best effort — the badge just shows again next launch.
    }
  }
}
