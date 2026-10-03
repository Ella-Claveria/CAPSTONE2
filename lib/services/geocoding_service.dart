import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// Turns a buyer's raw GPS fix (latitude/longitude) into a human-readable
/// barangay/municipality/province for the admin Demand Heatmap's "Highest
/// Demand Areas" list. A buyer now sets this themselves when placing an
/// order (see BuyerLocationField/buyer_location_picker.dart), which saves
/// it immediately — this is only a backfill path for accounts that placed
/// an order before that existed and only have a bare coordinate on file.
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
/// A reverse-geocode result, kept separate from barangay/municipality/
/// province so a caller that only has partial address components (Google
/// doesn't always return all three) can still show whatever it got.
class ResolvedAddress {
  final String? barangay;
  final String? city;
  final String? province;

  /// e.g. "Calabarzon" — Google's top-level area for the Philippines.
  final String? region;

  /// ISO country code of the result, e.g. "PH".
  final String? countryCode;

  const ResolvedAddress({
    this.barangay,
    this.city,
    this.province,
    this.region,
    this.countryCode,
  });

  String get readable => [
    barangay,
    city,
    province,
  ].where((s) => s != null && s.isNotEmpty).join(', ');

  bool get isEmpty => barangay == null && city == null && province == null;
}

/// Reads a Google Geocoding API `results` list into an address.
///
/// For the Philippines, Google's levels are:
///   administrative_area_level_1  region        (Calabarzon)
///   administrative_area_level_2  province      (Batangas)
///   locality                     city / municipality (Malvar)
///   sublocality / neighborhood / administrative_area_level_3+  barangay
/// Each piece is taken from the first result that has it — the top result
/// is often a street or plus-code entry missing one of them — and no piece
/// is required: whatever is found is returned.
ResolvedAddress parseGeocodeResults(List<dynamic> results) {
  String? first(List<String> wanted) {
    for (final type in wanted) {
      for (final result in results) {
        final components =
            (result as Map<String, dynamic>)['address_components'] as List? ??
            const [];
        for (final raw in components) {
          final component = raw as Map<String, dynamic>;
          final types = (component['types'] as List? ?? const [])
              .cast<String>();
          if (!types.contains(type)) continue;
          final name =
              (component[type == 'country' ? 'short_name' : 'long_name']
                      as String?)
                  ?.trim();
          if (name != null && name.isNotEmpty) return name;
        }
      }
    }
    return null;
  }

  final region = first(['administrative_area_level_1']);
  return ResolvedAddress(
    barangay: first([
      'sublocality_level_1',
      'sublocality',
      'neighborhood',
      'administrative_area_level_5',
      'administrative_area_level_4',
      'administrative_area_level_3',
    ]),
    city: first(['locality', 'postal_town']),
    // Metro Manila's cities sit directly under the region, with no
    // province level — the region then stands in for it.
    province: first(['administrative_area_level_2']) ?? region,
    region: region,
    countryCode: first(['country']),
  );
}

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
      final addr = await reverseGeocode(lat, lng);
      if (addr == null || addr.isEmpty) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        if (addr.barangay != null) 'barangay': addr.barangay,
        if (addr.city != null) 'municipality': addr.city,
        if (addr.province != null) 'province': addr.province,
        'locationResolvedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort enrichment only — see the class doc comment on the
      // fallback this leaves in place.
    }
  }

  /// Turns a GPS fix into a readable barangay/city/province — used
  /// directly by the buyer location picker's "Use my current location"
  /// mode (shown to the user before they confirm) as well as by
  /// [_resolve]'s admin-triggered backfill above. Returns null on any
  /// failure (network, disabled API, no results) rather than throwing —
  /// callers decide how to surface that (e.g. "couldn't detect your
  /// address, please pick it from the list instead").
  static Future<ResolvedAddress?> reverseGeocode(double lat, double lng) async {
    return (await reverseGeocodeDetailed(lat, lng)).address;
  }

  /// [reverseGeocode] plus why it failed, for callers that need to tell
  /// "the lookup did not work" (network, API key, quota — `status` is the
  /// API's own, e.g. REQUEST_DENIED) from "it worked but found little".
  static Future<({ResolvedAddress? address, String status, String? error})>
  reverseGeocodeDetailed(double lat, double lng) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lng',
        'region': 'ph',
        'key': _apiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return (address: null, status: 'HTTP_${res.statusCode}', error: null);
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = (body['status'] ?? 'UNKNOWN').toString();
      final results = body['results'] as List?;
      if (status != 'OK' || results == null || results.isEmpty) {
        return (
          address: null,
          status: status,
          error: body['error_message']?.toString(),
        );
      }

      final addr = parseGeocodeResults(results);
      return (
        address: addr.isEmpty ? null : addr,
        status: addr.isEmpty ? 'NO_ADDRESS_COMPONENTS' : 'OK',
        error: null,
      );
    } catch (e) {
      return (address: null, status: 'EXCEPTION', error: e.toString());
    }
  }

  /// The forward-geocode counterpart — turns a chosen Region/Province/
  /// City/Barangay combination (no GPS fix) into an approximate
  /// coordinate, via the same Google Geocoding API already used above.
  /// This is the "reliable mapped coordinate source" the manual picker
  /// uses instead of ever inventing a barangay/city center itself; a
  /// failure here is non-fatal — the readable address is still saved,
  /// just without a coordinate (see buyer_location_picker.dart).
  static Future<({double lat, double lng})?> forwardGeocode(
    String address,
  ) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': address,
        'region': 'ph',
        'key': _apiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final results = body['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final location =
          (results.first as Map<String, dynamic>)['geometry']?['location']
              as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }
}
