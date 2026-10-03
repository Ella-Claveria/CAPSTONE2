import '../theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'agri_dialog.dart';
import 'package:geolocator/geolocator.dart';

import '../data/laurel_barangays.dart';
import '../data/ph_locations_service.dart';
import '../services/geocoding_service.dart';
import '../services/location_permission_prompt.dart';

/// What the buyer location popup hands back — always a readable region/
/// province/city/barangay; latitude/longitude are best-effort (see
/// AuthService.saveBuyerLocation's doc comment on why a missing pin here
/// isn't an error).
class BuyerLocationResult {
  final String region;
  final String province;
  final String city;
  final String barangay;
  final double? latitude;
  final double? longitude;

  const BuyerLocationResult({
    required this.region,
    required this.province,
    required this.city,
    required this.barangay,
    this.latitude,
    this.longitude,
  });

  String get readable => '$barangay, $city, $province';
}

/// Opens the buyer location popup — a bottom sheet, never a separate
/// full-screen route — with a "Use My Current Location" shortcut pinned
/// at the top and, below it, a single step-by-step Region -> Province ->
/// City/Municipality -> Barangay selector: only ONE level's list is ever
/// on screen at a time (never several dropdowns at once), so picking
/// "CALABARZON" immediately narrows the very next list to CALABARZON's
/// provinces, picking "Batangas" narrows it to Batangas's cities/
/// municipalities, and so on down to barangay, which closes the sheet.
///
/// [initial], when given (e.g. "Edit Location"), best-effort drills the
/// list down to match the previous pick so the buyer doesn't have to
/// start over from Region — any step that fails to match just stops
/// there, leaving the rest to pick fresh.
Future<BuyerLocationResult?> showBuyerLocationPicker(
  BuildContext context, {
  BuyerLocationResult? initial,
}) {
  return showAgriPanelSheet<BuyerLocationResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BuyerLocationPopup(initial: initial),
  );
}

class _BuyerLocationPopup extends StatefulWidget {
  final BuyerLocationResult? initial;
  const _BuyerLocationPopup({this.initial});

  @override
  State<_BuyerLocationPopup> createState() => _BuyerLocationPopupState();
}

class _BuyerLocationPopupState extends State<_BuyerLocationPopup> {
  static const Color _dark = AppTheme.dark;
  final _psgc = PhLocationsService.instance;

  List<PhRegion> _regions = const [];
  List<PhProvince> _provinces = const [];
  List<PhCityMunicipality> _cities = const [];
  List<PhBarangay> _barangays = const [];

  PhRegion? _selectedRegion;
  PhProvince? _selectedProvince;
  PhCityMunicipality? _selectedCity;

  bool _loadingList = true;
  bool _regionHasNoProvinces = false;
  bool _confirming = false;
  String? _listError;

  bool _locating = false;
  String? _gpsError;
  // "Use My Current Location" got a valid position but not a full address:
  // the position is kept, and used as the pin for whichever barangay the
  // buyer then picks from the list.
  String? _gpsNote;
  double? _detectedLatitude;
  double? _detectedLongitude;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadRegions();
    if (!mounted) return;
    final initial = widget.initial;
    if (initial == null) return;
    try {
      final region = _regions.firstWhereOrNull(
        (r) => r.name.toLowerCase() == initial.region.toLowerCase(),
      );
      if (region == null) return;
      await _pickRegion(region);
      if (!mounted) return;

      if (!_regionHasNoProvinces) {
        final province = _provinces.firstWhereOrNull(
          (p) => p.name.toLowerCase() == initial.province.toLowerCase(),
        );
        if (province == null) return;
        await _pickProvince(province);
        if (!mounted) return;
      }

      final city = _cities.firstWhereOrNull(
        (c) => c.name.toLowerCase() == initial.city.toLowerCase(),
      );
      if (city == null) return;
      await _pickCity(city);
      // Left showing the barangay list (not auto-selected) so editing
      // still ends in an explicit tap, same as a fresh pick.
    } catch (_) {
      // Prefill is best-effort only.
    }
  }

  Future<void> _loadRegions() async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final regions = await _psgc.fetchRegions();
      if (!mounted) return;
      setState(() {
        _regions = regions;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _listError =
            'Could not load the location list. Check your connection and try again.';
      });
    }
  }

  Future<void> _pickRegion(PhRegion region) async {
    setState(() {
      _selectedRegion = region;
      _selectedProvince = null;
      _selectedCity = null;
      _provinces = const [];
      _cities = const [];
      _barangays = const [];
      _regionHasNoProvinces = false;
      _loadingList = true;
      _listError = null;
    });
    try {
      final provinces = await _psgc.fetchProvinces(region.code);
      if (!mounted) return;
      if (provinces.isEmpty) {
        final cities = await _psgc.fetchCitiesMunicipalities(
          regionCode: region.code,
        );
        if (!mounted) return;
        setState(() {
          _regionHasNoProvinces = true;
          _cities = cities;
          _loadingList = false;
        });
      } else {
        setState(() {
          _provinces = provinces;
          _loadingList = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _listError = 'Could not load that region\'s list. Please try again.';
      });
    }
  }

  Future<void> _pickProvince(PhProvince province) async {
    setState(() {
      _selectedProvince = province;
      _selectedCity = null;
      _cities = const [];
      _barangays = const [];
      _loadingList = true;
      _listError = null;
    });
    try {
      final cities = await _psgc.fetchCitiesMunicipalities(
        provinceCode: province.code,
      );
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _listError = 'Could not load that province\'s list. Please try again.';
      });
    }
  }

  Future<void> _pickCity(PhCityMunicipality city) async {
    setState(() {
      _selectedCity = city;
      _barangays = const [];
      _loadingList = true;
      _listError = null;
    });
    try {
      final barangays = await _psgc.fetchBarangays(city.code);
      if (!mounted) return;
      setState(() {
        _barangays = barangays;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _listError =
            'Could not load that city/municipality\'s barangays. Please try again.';
      });
    }
  }

  Future<void> _pickBarangay(PhBarangay barangay) async {
    setState(() => _confirming = true);
    final region = _selectedRegion!.name;
    final province = _regionHasNoProvinces ? region : _selectedProvince!.name;
    final city = _selectedCity!.name;

    // A position detected just now is the better pin; otherwise the
    // barangay itself is looked up.
    final detectedLat = _detectedLatitude;
    final detectedLng = _detectedLongitude;
    final coord = detectedLat != null && detectedLng != null
        ? (lat: detectedLat, lng: detectedLng)
        : await GeocodingService.forwardGeocode(
            '${barangay.name}, $city, $province, Philippines',
          );
    if (!mounted) return;
    Navigator.pop(
      context,
      BuyerLocationResult(
        region: region,
        province: province,
        city: city,
        barangay: barangay.name,
        latitude: coord?.lat,
        longitude: coord?.lng,
      ),
    );
  }

  void _goBack() {
    setState(() {
      if (_selectedCity != null) {
        _selectedCity = null;
        _barangays = const [];
      } else if (_selectedProvince != null) {
        _selectedProvince = null;
        _cities = const [];
      } else if (_regionHasNoProvinces) {
        _selectedRegion = null;
        _regionHasNoProvinces = false;
        _cities = const [];
      } else if (_selectedRegion != null) {
        _selectedRegion = null;
        _provinces = const [];
      }
    });
  }

  // Debug builds only — never compiled into a release. Each line names the
  // step, so a failure can be placed: GPS, Philippines check, reverse
  // geocoding, or address parsing.
  void _log(String step, String message) {
    if (kDebugMode) debugPrint('UseMyLocation[$step]: $message');
  }

  // A fresh fix, not a remembered one. On Android the default (fused)
  // provider can hand back a cached position — on an emulator, the one
  // from before its location was changed. If what comes back is old, the
  // position is read again straight from the device's location manager.
  Future<Position> _freshPosition() async {
    var position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    final age = DateTime.now().difference(position.timestamp);
    _log(
      'gps',
      'fix received: (${position.latitude}, ${position.longitude}), '
          'age ${age.inSeconds}s, mocked=${position.isMocked}',
    );

    if (age > const Duration(minutes: 2) &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 15),
          ),
        );
        _log(
          'gps',
          'stale fix refreshed: (${position.latitude}, ${position.longitude})',
        );
      } catch (e) {
        _log('gps', 'refresh failed, keeping the first fix: $e');
      }
    }
    return position;
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _gpsError = null;
      _gpsNote = null;
    });
    try {
      final granted = await requestBuyerLocationPermission(context);
      _log('gps', 'permission ${granted ? 'granted' : 'NOT granted'}');
      if (!granted) return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log('gps', 'FAILED: location services are off');
        if (!mounted) return;
        setState(() => _gpsError = 'Turn on location services to use this.');
        return;
      }

      final Position position;
      try {
        position = await _freshPosition();
      } catch (e) {
        _log('gps', 'FAILED: could not get a position: $e');
        rethrow;
      }
      if (!mounted) return;

      // The Philippines check is on the coordinates themselves — it does
      // not depend on any address coming back.
      if (!isWithinPhilippines(position.latitude, position.longitude)) {
        _log('philippines', 'FAILED: coordinates are outside the Philippines');
        setState(
          () => _gpsError =
              "This doesn't look like a location within the Philippines.",
        );
        return;
      }
      _log('philippines', 'ok: coordinates are inside the Philippines');

      final lookup = await GeocodingService.reverseGeocodeDetailed(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      final addr = lookup.address;
      _log(
        'reverse-geocoding',
        lookup.status == 'OK'
            ? 'ok'
            : 'FAILED: status=${lookup.status}'
                  '${lookup.error == null ? '' : ', ${lookup.error}'}',
      );
      _log(
        'address',
        'country=${addr?.countryCode}, region=${addr?.region}, '
            'province=${addr?.province}, city=${addr?.city}, '
            'barangay=${addr?.barangay}',
      );

      // An address that says it is another country (the bounds above also
      // take in a little of the Philippines' neighbours).
      final country = addr?.countryCode;
      if (country != null && country.toUpperCase() != 'PH') {
        _log('philippines', 'FAILED: address country is $country');
        setState(
          () => _gpsError =
              "This doesn't look like a location within the Philippines.",
        );
        return;
      }

      final city = addr?.city;
      final province = addr?.province;
      if (city == null || province == null) {
        // The coordinates are good; only the address is incomplete (or the
        // lookup itself failed). Keep the fix and let the buyer finish the
        // address from the list — the pin saved will be this GPS position.
        _log(
          'address',
          'incomplete (city=$city, province=$province) — keeping the '
              'coordinates and asking the buyer to pick the barangay',
        );
        setState(() {
          _detectedLatitude = position.latitude;
          _detectedLongitude = position.longitude;
          _gpsNote =
              'Location detected. Please choose your barangay from the list '
              'below to confirm.';
        });
        return;
      }

      final region =
          await _psgc.regionNameForProvinceName(province) ??
          addr?.region ??
          province;
      if (!mounted) return;
      _log('address', 'ok: $city, $province ($region)');

      Navigator.pop(
        context,
        BuyerLocationResult(
          region: region,
          province: province,
          city: city,
          barangay: addr?.barangay ?? city,
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _gpsError = 'Could not detect your location. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  List<String> get _breadcrumb => [
    if (_selectedRegion != null) _selectedRegion!.name,
    if (_selectedProvince != null) _selectedProvince!.name,
    if (_selectedCity != null) _selectedCity!.name,
  ];

  String get _levelLabel {
    if (_selectedCity != null) return 'Barangay';
    if (_selectedProvince != null || _regionHasNoProvinces) {
      return 'City / Municipality';
    }
    if (_selectedRegion != null) return 'Province';
    return 'Region';
  }

  @override
  Widget build(BuildContext context) {
    final mediaHeight = MediaQuery.of(context).size.height;
    return SafeArea(
      child: SizedBox(
        height: mediaHeight * 0.82,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Set Your Location',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _locating ? null : _useMyLocation,
                      icon: _locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _dark,
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Use My Current Location'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _dark,
                        side: const BorderSide(color: _dark),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_gpsNote != null && _gpsError == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _gpsNote!,
                      style: const TextStyle(
                        color: _dark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_gpsError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _gpsError!,
                      style: const TextStyle(color: Colors.red, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Or choose manually',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  if (_selectedRegion != null) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: _goBack,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _breadcrumb.isEmpty
                          ? 'Select your $_levelLabel'
                          : '${_breadcrumb.join(' › ')} — Select $_levelLabel',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildCurrentList()),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentList() {
    if (_confirming || _loadingList) {
      return const Center(child: CircularProgressIndicator(color: _dark));
    }
    if (_listError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 36, color: Colors.black38),
              const SizedBox(height: 10),
              Text(
                _listError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retryCurrentLevel,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedCity != null) {
      return _list(_barangays, (b) => b.name, _pickBarangay);
    }
    if (_selectedProvince != null || _regionHasNoProvinces) {
      return _list(_cities, (c) => c.name, _pickCity);
    }
    if (_selectedRegion != null) {
      return _list(_provinces, (p) => p.name, _pickProvince);
    }
    return _list(_regions, (r) => r.name, _pickRegion);
  }

  void _retryCurrentLevel() {
    if (_selectedCity != null) {
      _pickCity(_selectedCity!);
    } else if (_selectedProvince != null) {
      _pickProvince(_selectedProvince!);
    } else if (_selectedRegion != null) {
      _pickRegion(_selectedRegion!);
    } else {
      _loadRegions();
    }
  }

  Widget _list<T>(
    List<T> items,
    String Function(T) label,
    ValueChanged<T> onTap,
  ) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No entries found.',
          style: TextStyle(color: Colors.black45),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        return ListTile(
          title: Text(label(item), style: const TextStyle(fontSize: 14)),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.grey,
            size: 20,
          ),
          onTap: () => onTap(item),
        );
      },
    );
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
