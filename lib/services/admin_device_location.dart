import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geocoding_service.dart';

/// The place an Audit Log entry is shown with, e.g. "Poblacion, Laurel,
/// Batangas" — or null when there is nothing to name. Pure, so it can be
/// tested.
String? adminLocationLabel(ResolvedAddress? address) {
  if (address == null || address.isEmpty) return null;
  final label = address.readable.trim();
  return label.isEmpty ? null : label;
}

/// Where the Admin's own device is, for the Audit Log's Location column:
/// the browser's position (the Admin is asked to allow it, once), named as
/// barangay, municipality and province.
///
/// Only the place name leaves the browser — never the coordinates. When the
/// Admin does not allow it, or the lookup fails, there is no location and
/// the entry says "Unknown"; nothing is guessed from the IP address.
class AdminDeviceLocation {
  AdminDeviceLocation._();

  // A device does not move much within a sitting.
  static const Duration _keepFor = Duration(minutes: 10);
  // A lookup that failed (not allowed, no signal) is not retried at once.
  static const Duration _retryAfter = Duration(minutes: 2);

  static String? _label;
  static DateTime? _lookedUpAt;
  static Future<String?>? _pending;

  // The last place found is remembered by the browser, so the first
  // entries after the portal is opened again (a login, above all) have a
  // location at once instead of "Unknown" while the new lookup runs. A
  // place found longer ago than this is not used.
  static const Duration _rememberFor = Duration(hours: 12);
  static const String _labelKey = 'admin_device_location_label';
  static const String _atKey = 'admin_device_location_at';
  static bool _restored = false;

  static Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final label = prefs.getString(_labelKey);
      final at = prefs.getInt(_atKey);
      if (label == null || label.isEmpty || at == null || _label != null) {
        return;
      }
      final found = DateTime.fromMillisecondsSinceEpoch(at);
      if (DateTime.now().difference(found) <= _rememberFor) _label = label;
    } catch (_) {}
  }

  /// Starts finding the device's location without waiting for it — called
  /// when the portal opens, so it is known by the time anything is logged.
  static void warmUp() {
    if (!kIsWeb) return;
    current(wait: Duration.zero);
  }

  /// The device's location, waiting at most [wait] for it: an action is
  /// never held up by this. A lookup still running carries on, and the
  /// next entry has it.
  static Future<String?> current({
    Duration wait = const Duration(seconds: 4),
  }) async {
    // The Admin Portal is the website; the phone app is never asked.
    if (!kIsWeb) return null;
    await _restore();
    final at = _lookedUpAt;
    if (at != null) {
      final age = DateTime.now().difference(at);
      if (age < (_lastFailed ? _retryAfter : _keepFor)) return _label;
    }
    final lookup = _pending ??= _lookUp().whenComplete(() => _pending = null);
    try {
      return await lookup.timeout(wait);
    } on TimeoutException {
      return _label;
    }
  }

  // Whether the latest lookup found nothing.
  static bool _lastFailed = false;

  static Future<String?> _lookUp() async {
    String? label;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
        label = adminLocationLabel(
          await GeocodingService.reverseGeocode(
            position.latitude,
            position.longitude,
          ),
        );
      }
    } catch (error) {
      debugPrint('[AdminDeviceLocation] no location: $error');
    }
    _lastFailed = label == null;
    // A lookup that fails keeps the place last found.
    if (label != null) {
      _label = label;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_labelKey, label);
        await prefs.setInt(_atKey, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    }
    _lookedUpAt = DateTime.now();
    return _label;
  }
}
