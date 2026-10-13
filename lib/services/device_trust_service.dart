import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recognized devices, for the New Device Login Alert.
///
/// Each app installation makes up a random id the first time it runs and
/// keeps it in local storage. Only a SHA-256 hash of it is stored, under
/// `users/{uid}/trustedDevices/{hash}`. No hardware identifier (IMEI,
/// serial, MAC, advertising id) and no location is read or stored.
///
/// When an account signs in on an installation it has no record for, the
/// record is created — and that creation is what the onNewTrustedDevice
/// Cloud Function reacts to, sending the alert email once. A recognized
/// installation only has its `lastSeenAt` refreshed, so reopening the app,
/// logging out and back in, or hot restarts never send another email.
///
/// Because the id lives in app storage, reinstalling the app or clearing
/// its data makes it a new installation, which is treated (and alerted) as
/// a new device. It identifies an installation, not the physical phone.
class DeviceTrustService {
  DeviceTrustService._();
  static final DeviceTrustService instance = DeviceTrustService._();

  static const _installIdKey = 'device_install_id';
  static const _lastSeenWriteKey = 'device_last_seen_write_';
  // How often a recognized device's lastSeenAt is refreshed at most.
  static const Duration _lastSeenEvery = Duration(hours: 12);

  StreamSubscription<User?>? _authSub;
  // The account this app run has already checked the device for.
  String? _checkedUid;

  /// Call once, after Firebase is initialized. Covers every way of being
  /// signed in — email/password, Google, and a restored session — since
  /// all of them surface as a signed-in user here.
  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        // Logging out does not forget the device; it stays recognized.
        _checkedUid = null;
        return;
      }
      if (_checkedUid == user.uid) return;
      _checkedUid = user.uid;
      _recordDevice(user.uid).catchError((_) {
        // Best effort — never gets in the way of signing in. Try again on
        // the next sign-in or app start.
        _checkedUid = null;
      });
    });
  }

  /// SHA-256 of an installation id, hex-encoded — the trusted-device
  /// document id.
  @visibleForTesting
  static String hashInstallId(String installId) =>
      sha256.convert(utf8.encode(installId)).toString();

  Future<String> _installId(SharedPreferences prefs) async {
    final existing = prefs.getString(_installIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await prefs.setString(_installIdKey, id);
    return id;
  }

  /// This installation's id as it appears in the device list (the hash,
  /// never the raw id) — so the list can mark "This device".
  Future<String> currentDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return hashInstallId(await _installId(prefs));
  }

  Future<void> _recordDevice(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = hashInstallId(await _installId(prefs));
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('trustedDevices')
        .doc(deviceId);

    final existing = await ref.get();
    if (existing.exists) {
      // Recognized: just note it was seen, and not on every launch.
      final writeKey = '$_lastSeenWriteKey$uid';
      final last = prefs.getInt(writeKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _lastSeenEvery.inMilliseconds) return;
      await ref.update({
        'lastSeenAt': FieldValue.serverTimestamp(),
        'appVersion': await _appVersion(),
      });
      await prefs.setInt(writeKey, now);
      return;
    }

    final (platform, deviceName) = await _describeDevice();
    // New for this account. Creating the record is what triggers the
    // alert email, server-side.
    await ref.set({
      'deviceIdHash': deviceId,
      'platform': platform,
      'deviceName': deviceName,
      'appVersion': await _appVersion(),
      'trusted': true,
      'firstSeenAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
    await prefs.setInt(
      '$_lastSeenWriteKey$uid',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  // Platform and a general model name only — e.g. ("Android", "samsung
  // SM-A166P"). Nothing that identifies the individual unit.
  Future<(String, String)> _describeDevice() async {
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await info.webBrowserInfo;
        return ('Web', '${web.browserName.name} browser');
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = await info.androidInfo;
          return ('Android', '${android.manufacturer} ${android.model}'.trim());
        case TargetPlatform.iOS:
          final ios = await info.iosInfo;
          return ('iOS', ios.utsname.machine);
        default:
          return (defaultTargetPlatform.name, '');
      }
    } catch (_) {
      return (kIsWeb ? 'Web' : defaultTargetPlatform.name, '');
    }
  }
}
