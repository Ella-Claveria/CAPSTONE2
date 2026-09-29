import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// Turns a buyer's raw map pin (latitude/longitude — the location they
/// entered at registration, see MyLocationField/register_screen.dart) into
/// a human-readable barangay/municipality/province for the admin Demand
/// Heatmap's "Highest Demand Areas" list. A buyer outside Laurel has no
/// barangay picker, only a free map pin, so unlike a Laurel farmer or a
/// legacy Laurel buyer there's no text field to read directly — this is
/// what fills that in.
///
/// Calls Google's Geocoding API with the same Maps key already embedded in
/// web/index.html (no new key/secret introduced), and caches the result
/// permanently onto the buyer's own users/{uid} doc, in the SAME
/// barangay/municipality/province fields a legacy account already uses
/// (see DashboardAnalyticsService's _resolveBuyerArea) — once per buyer,
/// not once per dashboard load or per order, since a buyer's registered
/// pin essentially never changes.
///
/// Requires the "Geocoding API" to be enabled for that Maps key in Google
/// Cloud Console (a separate toggle from "Maps JavaScript API", which is
/// already in use for the map itself and therefore already confirmed
/// working). A disabled key, quota error, or any other failure here is
/// non-fatal — DashboardAnalyticsService's coordinate-based fallback label
/// stays in place until this succeeds on a later attempt.
class GeocodingService {
  GeocodingService._();

  static const _apiKey = 'AIzaSyBbYUgbR0tHaSfrujL8184AXYOCTP5W6NE';
  static final Set<String> _inFlight = {};

  /// Fire-and-forget: resolves [uid]'s area from [lat]/[lng] and writes it
  /// back onto users/{uid}, unless [alreadyResolved] says the buyer
  /// already has a saved area (nothing to do) or a call for this buyer is
  /// already running. Safe to call on every dashboard rebuild.
  static void resolveAndCacheIfNeeded({
    required String uid,
    required double lat,
    required double lng,
    required bool alreadyResolved,
  }) {
    if (alreadyResolved || uid.isEmpty || _inFlight.contains(uid)) return;
    _inFlight.add(uid);
    _resolve(uid, lat, lng).whenComplete(() => _inFlight.remove(uid));
  }

  static Future<void> _resolve(String uid, double lat, double lng) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lng',
        'key': _apiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return;
      final results = body['results'] as List?;
      if (results == null || results.isEmpty) return;

      String? barangay;
      String? municipality;
      String? province;
      final components = (results.first as Map<String, dynamic>)['address_components'] as List? ?? [];
      for (final raw in components) {
        final c = raw as Map<String, dynamic>;
        final types = (c['types'] as List).cast<String>();
        final name = (c['long_name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        if (barangay == null && (types.contains('sublocality') || types.contains('sublocality_level_1'))) {
          barangay = name;
        } else if (municipality == null &&
            (types.contains('locality') || types.contains('administrative_area_level_2'))) {
          municipality = name;
        } else if (province == null && types.contains('administrative_area_level_1')) {
          province = name;
        }
      }

      if ((barangay == null || barangay.isEmpty) &&
          (municipality == null || municipality.isEmpty) &&
          (province == null || province.isEmpty)) {
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        if (barangay != null && barangay.isNotEmpty) 'barangay': barangay,
        if (municipality != null && municipality.isNotEmpty) 'municipality': municipality,
        if (province != null && province.isNotEmpty) 'province': province,
        'locationResolvedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort enrichment only — see the class doc comment on the
      // fallback this leaves in place.
    }
  }
}
