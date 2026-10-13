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
  const PhProvince({
    required this.code,
    required this.name,
    required this.regionCode,
  });
}

class PhCityMunicipality {
  final String code;
  final String name;
  final bool isCity;
  const PhCityMunicipality({
    required this.code,
    required this.name,
    required this.isCity,
  });
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
    _regions =
        raw
            .map(
              (e) => PhRegion(
                code: e['code'] as String,
                name: e['name'] as String,
              ),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return _regions!;
  }

  Future<List<PhProvince>> fetchProvinces(String regionCode) async {
    final cached = _provincesByRegion[regionCode];
    if (cached != null) return cached;
    final raw = await _getJsonList('/regions/$regionCode/provinces/');
    final list =
        raw
            .map(
              (e) => PhProvince(
                code: e['code'] as String,
                name: e['name'] as String,
                regionCode: regionCode,
              ),
            )
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
    final list =
        raw
            .map(
              (e) => PhCityMunicipality(
                code: e['code'] as String,
                name: e['name'] as String,
                isCity: e['isCity'] == true,
              ),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    _citiesByParent[parentCode] = list;
    return list;
  }

  Future<List<PhBarangay>> fetchBarangays(String cityMunicipalityCode) async {
    final cached = _barangaysByCity[cityMunicipalityCode];
    if (cached != null) return cached;
    final raw = await _getJsonList(
      '/cities-municipalities/$cityMunicipalityCode/barangays/',
    );
    final list =
        raw
            .map(
              (e) => PhBarangay(
                code: e['code'] as String,
                name: e['name'] as String,
              ),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    _barangaysByCity[cityMunicipalityCode] = list;
    return list;
  }

  List<({String name, String province})>? _allCities;

  /// Every city/municipality in the Philippines with its province name, for
  /// a searchable list (the farmer's delivery Custom Areas). Metro Manila
  /// cities have no province, so they get "Metro Manila"; other cities
  /// independent of a province get an empty province.
  Future<List<({String name, String province})>>
  fetchAllCitiesMunicipalities() async {
    if (_allCities != null) return _allCities!;
    final provinces = await _getJsonList('/provinces/');
    final provinceNames = {
      for (final p in provinces) p['code'] as String: p['name'] as String,
    };
    final raw = await _getJsonList('/cities-municipalities/');
    final list = raw.map((e) {
      final provinceCode = e['provinceCode'];
      final province = provinceCode is String
          ? (provinceNames[provinceCode] ?? '')
          : (e['regionCode'] == '130000000' ? 'Metro Manila' : '');
      return (name: e['name'] as String, province: province);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
    _allCities = list;
    return list;
  }

  List<PhProvince>? _allProvinces;

  Future<List<PhProvince>> _fetchAllProvinces() async {
    if (_allProvinces != null) return _allProvinces!;
    final raw = await _getJsonList('/provinces/');
    _allProvinces = raw
        .map(
          (e) => PhProvince(
            code: e['code'] as String,
            name: e['name'] as String,
            regionCode: e['regionCode'] as String,
          ),
        )
        .toList();
    return _allProvinces!;
  }

  /// Maps a reverse-geocoded address ("Use My Current Location") onto this
  /// dataset's own Region -> Province -> City/Municipality entries, so the
  /// picker can open straight at that city's barangay list. PSGC stays the
  /// single source of truth for the names: the geocoder's are only used to
  /// find the matching entry. Returns null when the province/region or the
  /// city can't be matched — the caller then falls back to the manual list.
  /// `province` is null in the result for a region with no province level
  /// (NCR). Throws if the PSGC lists can't be loaded.
  Future<({PhRegion region, PhProvince? province, PhCityMunicipality city})?>
  matchDetectedLocation({
    required String city,
    String? province,
    String? region,
  }) async {
    final regions = await fetchRegions();
    final cityKey = phPlaceKey(city);
    if (cityKey.isEmpty) return null;

    PhCityMunicipality? findCity(List<PhCityMunicipality> cities) {
      final matches = cities
          .where((c) => phPlaceKey(c.name) == cityKey)
          .toList();
      return matches.length == 1 ? matches.first : null;
    }

    if (province != null) {
      final provinceKey = phPlaceKey(province);
      for (final p in await _fetchAllProvinces()) {
        if (phPlaceKey(p.name) != provinceKey) continue;
        final parent = regions.where((r) => r.code == p.regionCode).toList();
        if (parent.isEmpty) return null;
        final match = findCity(
          await fetchCitiesMunicipalities(provinceCode: p.code),
        );
        if (match == null) return null;
        return (region: parent.first, province: p, city: match);
      }
    }

    // No such province: a region whose cities hang directly off it. The
    // geocoder reports Metro Manila as the "province" there.
    for (final name in [province, region]) {
      if (name == null) continue;
      final regionKey = _regionKey(name);
      for (final r in regions) {
        if (_regionKey(r.name) != regionKey) continue;
        if ((await fetchProvinces(r.code)).isNotEmpty) return null;
        final match = findCity(
          await fetchCitiesMunicipalities(regionCode: r.code),
        );
        if (match == null) return null;
        return (region: r, province: null, city: match);
      }
    }
    return null;
  }

  /// The entry of [barangays] a reverse-geocoded barangay name refers to,
  /// or null unless exactly one matches.
  PhBarangay? matchBarangay(List<PhBarangay> barangays, String name) {
    final key = phPlaceKey(name);
    if (key.isEmpty) return null;
    final matches = barangays.where((b) => phPlaceKey(b.name) == key).toList();
    return matches.length == 1 ? matches.first : null;
  }

  static const _regionAliases = {
    'metro manila': 'ncr',
    'national capital': 'ncr',
    'cordillera administrative': 'car',
    'bangsamoro': 'barmm',
    'bangsamoro autonomous region in muslim mindanao': 'barmm',
  };

  String _regionKey(String name) {
    final key = phPlaceKey(name).replaceAll(RegExp(r' region$'), '');
    return _regionAliases[key] ?? key;
  }
}

/// A place name reduced to what identifies it, for matching a geocoder's
/// spelling against PSGC's: "City of Tanauan" and "Tanauan City" both give
/// "tanauan", "Sto. Niño (Pob.)" and "Santo Nino" both give "santo nino".
String phPlaceKey(String name) {
  var key = name.toLowerCase().replaceAll('ñ', 'n');
  key = key.replaceAll(RegExp(r'\(.*?\)'), ' ');
  key = key
      .replaceAll(RegExp(r'\bsto\b\.?'), 'santo')
      .replaceAll(RegExp(r'\bsta\b\.?'), 'santa');
  key = key.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  key = key.replaceAll(
    RegExp(r'\b(city of|municipality of|city|barangay|brgy)\b'),
    ' ',
  );
  return key.replaceAll(RegExp(r'\s+'), ' ').trim();
}
