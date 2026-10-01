import 'dart:convert';
import 'package:http/http.dart' as http;

// ============================================================
// Region -> Province -> City/Municipality -> Barangay lookups for the
// buyer location picker's "Select from list" mode. Backed by the public
// PSGC (Philippine Standard Geographic Code) mirror at psgc.gitlab.io,
// which serves the PSA's own official region/province/city/barangay
// names as static JSON (hosted on GitLab Pages, so no API key and no
// meaningful rate limit) — this app has no reliable way to hand-author
// or ship the ~42,000 barangay names itself, so this is the "reliable
// mapped" name source the manual picker depends on. It never returns
// coordinates (PSGC has none at the barangay level) — those come from
// GeocodingService instead (see buyer_location_picker.dart).
//
// NCR (and a couple of other regions) have no province level at all —
// PhLocationsService.fetchCitiesMunicipalities already handles that by
// falling back to the region's own cities endpoint when the province
// list for that region comes back empty (see fetchProvinces/cachedCities
// in the picker's usage).
// ============================================================

class PhRegion {
  final String code;
  final String name;
  const PhRegion({required this.code, required this.name});
}

class PhProvince {
  final String code;
  final String name;
  final String regionCode;
  const PhProvince({required this.code, required this.name, required this.regionCode});
}

class PhCityMunicipality {
  final String code;
  final String name;
  final bool isCity;
  const PhCityMunicipality({required this.code, required this.name, required this.isCity});
}

class PhBarangay {
  final String code;
  final String name;
  const PhBarangay({required this.code, required this.name});
}

class PhLocationsService {
  PhLocationsService._();
  static final PhLocationsService instance = PhLocationsService._();

  static const _base = 'https://psgc.gitlab.io/api';
  static const _timeout = Duration(seconds: 10);

  // Reference data never changes during a session, so a plain in-memory
  // cache (never invalidated) is enough — no TTL needed, unlike the
  // operational Firestore data elsewhere in the app.
  List<PhRegion>? _regions;
  final Map<String, List<PhProvince>> _provincesByRegion = {};
  final Map<String, List<PhCityMunicipality>> _citiesByParent = {};
  final Map<String, List<PhBarangay>> _barangaysByCity = {};

  Future<List<dynamic>> _getJsonList(String path) async {
    final res = await http.get(Uri.parse('$_base$path')).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('PSGC request failed (${res.statusCode})');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<List<PhRegion>> fetchRegions() async {
    if (_regions != null) return _regions!;
    final raw = await _getJsonList('/regions/');
    _regions = raw
        .map((e) => PhRegion(code: e['code'] as String, name: e['name'] as String))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _regions!;
  }

  Future<List<PhProvince>> fetchProvinces(String regionCode) async {
    final cached = _provincesByRegion[regionCode];
    if (cached != null) return cached;
    final raw = await _getJsonList('/regions/$regionCode/provinces/');
    final list = raw
        .map((e) => PhProvince(
              code: e['code'] as String,
              name: e['name'] as String,
              regionCode: regionCode,
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _provincesByRegion[regionCode] = list;
    return list;
  }

  // Some regions (NCR and a few others) have no province level — their
  // cities/municipalities hang directly off the region. Pass whichever
  // parent is relevant: a province code to list that province's cities,
  // or a region code (only when that region has no provinces) to list
  // its cities directly.
  Future<List<PhCityMunicipality>> fetchCitiesMunicipalities({
    String? provinceCode,
    String? regionCode,
  }) async {
    final parentCode = provinceCode ?? regionCode;
    if (parentCode == null) return const [];
    final cached = _citiesByParent[parentCode];
    if (cached != null) return cached;
    final path = provinceCode != null
        ? '/provinces/$provinceCode/cities-municipalities/'
        : '/regions/$regionCode/cities-municipalities/';
    final raw = await _getJsonList(path);
    final list = raw
        .map((e) => PhCityMunicipality(
              code: e['code'] as String,
              name: e['name'] as String,
              isCity: e['isCity'] == true,
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _citiesByParent[parentCode] = list;
    return list;
  }

  Future<List<PhBarangay>> fetchBarangays(String cityMunicipalityCode) async {
    final cached = _barangaysByCity[cityMunicipalityCode];
    if (cached != null) return cached;
    final raw = await _getJsonList('/cities-municipalities/$cityMunicipalityCode/barangays/');
    final list = raw
        .map((e) => PhBarangay(code: e['code'] as String, name: e['name'] as String))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _barangaysByCity[cityMunicipalityCode] = list;
    return list;
  }

  // Google's reverse-geocode (used by the "Use my current location" mode)
  // returns a province name but no region — PSGC is the single source of
  // truth for region names here too, so this cross-references the
  // already-cached province lists instead of hand-maintaining a separate
  // province->region table that could drift from the dropdown data.
  Future<String?> regionNameForProvinceName(String provinceName) async {
    final needle = _normalize(provinceName);
    final regions = await fetchRegions();
    for (final region in regions) {
      final provinces = await fetchProvinces(region.code);
      for (final province in provinces) {
        if (_normalize(province.name) == needle) return region.name;
      }
    }
    return null;
  }

  String _normalize(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'^city of\s+'), '');
}
