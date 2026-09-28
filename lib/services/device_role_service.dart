import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Restricts a device to one role (farmer or buyer) at a time — once this
/// device has registered a farmer account, it can't also register a buyer
/// account (and vice versa).
///
/// This is a soft, abuse-deterrence check, not a hard security boundary: it
/// keys off a random id generated once and stored in this device's local
/// app data, not a real hardware fingerprint — reinstalling the app (or
/// clearing app data) gets a fresh id and resets the restriction. A
/// tamper-proof version would need a native device fingerprint and
/// server-side (Cloud Function) enforcement; this keeps things simple and
/// consistent with how the rest of this app's client-trusts-itself,
/// rules-guarded writes already work.
class DeviceRoleService {
  static const _deviceIdKey = 'device_install_id';
  final _deviceRoles = FirebaseFirestore.instance.collection('deviceRoles');

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _generateId();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  static String _generateId() {
    final rand = Random.secure();
    return List<int>.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// The role already registered on this device ('farmer' or 'buyer'), or
  /// null if this device hasn't registered any account yet — or the check
  /// couldn't be reached (fails open, so a network hiccup never blocks
  /// sign-up).
  Future<String?> getRegisteredRole() async {
    try {
      final deviceId = await _getDeviceId();
      final doc = await _deviceRoles.doc(deviceId).get();
      return doc.data()?['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Call right after a successful sign-up to claim this device for that
  /// role. Best-effort — a failure here never undoes the account that was
  /// just created.
  Future<void> claimDevice({required String role, required String uid}) async {
    try {
      final deviceId = await _getDeviceId();
      await _deviceRoles.doc(deviceId).set({
        'role': role,
        'uid': uid,
        'claimedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
