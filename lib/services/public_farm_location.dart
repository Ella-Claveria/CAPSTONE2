import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/laurel_barangays.dart';
import 'geocoding_service.dart';

/// What a buyer may know about where a farmer is: the farmer's name and
/// photo, the general area as text ("Bugaan East, Laurel, Batangas"), and
/// one barangay-level point for the map.
///
/// There are two different farmer locations in AgriTrade+:
///   Private  the farm's exact pin (users/{uid}/private/geo) — for the
///            farmer and for order/delivery handling, never for a buyer's
///            map.
///   Public   barangay + municipality + province from publicProfiles, and
///            the point derived from that text here.
/// This file only ever touches the public one. In particular it does not
/// use barangayClusters: that is an average of the exact pins in a
/// barangay, which for a barangay with a single farmer is that farmer's
/// exact pin.
class PublicFarmLocation {
  final String farmerName;
  final String? photoUrl;

  /// "Barangay, Municipality, Province" — empty if the farmer has none.
  final String area;

  /// The barangay's general position, or null when it cannot be resolved
  /// (in which case no map position or distance should be shown).
  final double? latitude;
  final double? longitude;

  const PublicFarmLocation({
    required this.farmerName,
    required this.photoUrl,
    required this.area,
    required this.latitude,
    required this.longitude,
  });

  bool get hasPoint => latitude != null && longitude != null;
}

/// A coordinate that can be a real place in the Philippines: numeric, in
/// range, not the (0, 0) "no data" point, and not latitude/longitude the
/// wrong way round (the Philippines is roughly 4–22°N, 116–127°E — swapped
/// values fall far outside it).
bool isValidPublicCoordinate(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  return lat >= 4 && lat <= 22 && lng >= 116 && lng <= 127;
}

// Resolved once per area per app session…
final Map<String, ({double lat, double lng})> _sessionPoints = {};

// …and remembered on the device after that, so the same barangay always
// opens at exactly the same place.
String _cacheKey(String area) =>
    'public_area_point_${area.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

/// The stable, barangay-level point for [barangay] in [area]:
///   1. the point already resolved for this area (this session, then this
///      device);
///   2. Google's geocode of the area text itself — the barangay as a
///      place, not anybody's address — which is then remembered;
///   3. for a Laurel barangay, the app's own reference point for it;
///   4. otherwise nothing.
/// Never random, never offset per call, and never derived from a farm pin.
Future<({double lat, double lng})?> resolvePublicAreaPoint({
  required String barangay,
  required String area,
}) async {
  if (barangay.isEmpty || area.isEmpty) return null;

  final session = _sessionPoints[area];
  if (session != null) return session;

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_cacheKey(area));
    if (saved != null && saved.length == 2) {
      final lat = double.tryParse(saved[0]);
      final lng = double.tryParse(saved[1]);
      if (isValidPublicCoordinate(lat, lng)) {
        return _sessionPoints[area] = (lat: lat!, lng: lng!);
      }
    }
  } catch (_) {}

  final geocoded = await GeocodingService.forwardGeocode('$area, Philippines');
  if (geocoded != null && isValidPublicCoordinate(geocoded.lat, geocoded.lng)) {
    try {
      await prefs?.setStringList(_cacheKey(area), [
        geocoded.lat.toString(),
        geocoded.lng.toString(),
      ]);
    } catch (_) {}
    return _sessionPoints[area] = geocoded;
  }

  // Geocoding unavailable: a fixed reference point for the barangay. Not
  // cached, so a later successful geocode can replace it.
  final reference = laurelBarangayLocationFor(barangay);
  if (reference != null &&
      isValidPublicCoordinate(reference.lat, reference.lng)) {
    return (lat: reference.lat, lng: reference.lng);
  }
  return null;
}

/// Everything the Farm Location map needs for [farmerId] — read from that
/// farmer's own public profile, so it can never be another farmer's.
Future<PublicFarmLocation> loadPublicFarmLocation(
  String farmerId, {
  String fallbackName = 'Farmer',
}) async {
  final profile =
      (await FirebaseFirestore.instance
              .collection('publicProfiles')
              .doc(farmerId)
              .get())
          .data() ??
      const <String, dynamic>{};

  final barangay = (profile['barangay'] ?? '').toString().trim();
  final area = [barangay, profile['municipality'], profile['province']]
      .map((part) => (part ?? '').toString().trim())
      .where((part) => part.isNotEmpty)
      .join(', ');
  final point = await resolvePublicAreaPoint(barangay: barangay, area: area);

  final name = (profile['name'] ?? profile['fullName'] ?? '').toString().trim();

  // Debug builds only, and no coordinates — just whether there are any.
  if (kDebugMode) {
    debugPrint(
      'FarmLocation: area="${area.isEmpty ? '(none)' : area}", '
      'public point ${point == null ? 'NOT found' : 'found'}',
    );
  }

  return PublicFarmLocation(
    farmerName: name.isEmpty ? fallbackName : name,
    photoUrl: profile['photoUrl']?.toString(),
    area: area,
    latitude: point?.lat,
    longitude: point?.lng,
  );
}
