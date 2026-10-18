import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_permission_prompt.dart';
import '../services/public_farm_location.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/agri_empty_state.dart';

/// "Approx. 4.8 km away" — never presented as exact: one decimal below
/// 10 km, whole kilometres beyond that. Null (no buyer location, or no
/// farm area to measure to) reads "Distance unavailable".
String approxDistanceLabel(double? km) {
  if (km == null) return 'Distance unavailable';
  if (km < 0.1) return 'Approx. less than 0.1 km away';
  return km < 10
      ? 'Approx. ${km.toStringAsFixed(1)} km away'
      : 'Approx. ${km.round()} km away';
}

/// Whether the buyer is close enough to the farm area for one map view to
/// usefully hold both. Beyond this the map stays on the farm area (fitting
/// both would zoom out to a whole-country or whole-world view).
bool shouldFitBuyerAndFarm(double? distanceKm) =>
    distanceKm != null && distanceKm <= 150;

/// Farm Location — the map opened from a product's details. It is about
/// that one farmer only: the general area their farm is in, the buyer's
/// own position (if they allow it), and roughly how far apart the two are.
///
/// The farm marker is the farmer's public, barangay-level location (see
/// public_farm_location.dart) — the same point every time for the same
/// barangay, never the farm's exact pin and never anything derived from
/// the buyer. The buyer's position is only ever the origin of the
/// distance; it stays on this device and is not written anywhere here.
///
/// Camera: the map is created only once the farm point is known, already
/// centred on it. The single later move is to bring the buyer into view,
/// once, when their position arrives. Nothing re-centres on rebuilds.
class BuyerMapView extends StatefulWidget {
  final String farmerId;

  /// Shown until the farmer's public profile loads (and if it can't).
  final String farmerName;

  const BuyerMapView({
    super.key,
    required this.farmerId,
    required this.farmerName,
  });

  @override
  State<BuyerMapView> createState() => _BuyerMapViewState();
}

class _BuyerMapViewState extends State<BuyerMapView> {
  static const Color _dark = AppTheme.dark;

  // Close enough to read a barangay and its surroundings.
  static const double _farmZoom = 13.5;

  GoogleMapController? _map;

  bool _loadingFarm = true;
  PublicFarmLocation? _farm;

  Position? _myPosition;
  // Why there is no distance, when the buyer could do something about it.
  String? _locationNotice;
  bool _fittedBoth = false;

  @override
  void initState() {
    super.initState();
    _loadFarm();
    // Asked for here — when the buyer opens a location feature — and not
    // at login, registration or app start.
    _determinePosition();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  LatLng? get _farmPoint {
    final farm = _farm;
    return farm == null || !farm.hasPoint
        ? null
        : LatLng(farm.latitude!, farm.longitude!);
  }

  Future<void> _loadFarm() async {
    PublicFarmLocation? farm;
    try {
      farm = await loadPublicFarmLocation(
        widget.farmerId,
        fallbackName: widget.farmerName,
      );
    } catch (_) {
      farm = null;
    }
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        'FarmLocation[debug]: farmer ${widget.farmerId} area = '
        '"${farm?.area}", public point = '
        '(${farm?.latitude}, ${farm?.longitude})',
      );
    }
    setState(() {
      _farm = farm;
      _loadingFarm = false;
    });
  }

  Future<void> _determinePosition() async {
    try {
      // The AgriTrade+ explanation first, then the system prompt.
      if (!mounted) return;
      final granted = await requestBuyerLocationPermission(context);
      if (kDebugMode) {
        debugPrint(
          'FarmLocation: buyer location permission '
          '${granted ? 'granted' : 'not granted'}',
        );
      }
      if (!mounted) return;
      if (!granted) {
        setState(() => _locationNotice = 'Allow location to see the distance.');
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        setState(
          () => _locationNotice =
              'Turn on location services to see the distance.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      // Debug builds only — never compiled into a release.
      if (kDebugMode) {
        debugPrint(
          'FarmLocation[debug]: buyer position = '
          '(${position.latitude}, ${position.longitude})',
        );
      }
      if (!mounted) return;
      // A device position that is not in the Philippines (an emulator's
      // default location, a mock location, a bad fix) is not a usable
      // origin: it would give a distance of thousands of kilometres. It
      // is discarded rather than shown.
      if (!isValidPublicCoordinate(position.latitude, position.longitude)) {
        setState(() {
          _myPosition = null;
          _locationNotice = 'Your device location could not be confirmed.';
        });
        return;
      }
      setState(() {
        _myPosition = position;
        _locationNotice = null;
      });
      _fitBuyerOnce();
    } catch (_) {
      if (kDebugMode) debugPrint('FarmLocation: buyer position NOT found');
      if (!mounted) return;
      setState(
        () => _locationNotice = 'Could not get your location right now.',
      );
    }
  }

  /// Buyer's current position -> the farmer's public barangay point.
  double? get _distanceKm {
    final me = _myPosition;
    final farm = _farmPoint;
    if (me == null || farm == null) return null;
    return Geolocator.distanceBetween(
          me.latitude,
          me.longitude,
          farm.latitude,
          farm.longitude,
        ) /
        1000;
  }

  // The one camera move after the map opens: bring the buyer into view
  // alongside the farm area. Runs once, whichever of "map ready" and
  // "buyer position ready" happens last, and only when the two are near
  // enough to share a view. The farm marker itself never moves.
  void _fitBuyerOnce() {
    final map = _map;
    final farm = _farmPoint;
    final me = _myPosition;
    if (_fittedBoth || map == null || farm == null || me == null) return;
    _fittedBoth = true;

    final km = _distanceKm;
    if (kDebugMode) {
      debugPrint(
        'FarmLocation[debug]: distance = ${km?.toStringAsFixed(2)} km; '
        '${shouldFitBuyerAndFarm(km) ? "camera fits buyer + farm" : "camera stays on farm point"}',
      );
    }
    if (!shouldFitBuyerAndFarm(km)) return;

    final south = me.latitude < farm.latitude ? me.latitude : farm.latitude;
    final north = me.latitude > farm.latitude ? me.latitude : farm.latitude;
    final west = me.longitude < farm.longitude ? me.longitude : farm.longitude;
    final east = me.longitude > farm.longitude ? me.longitude : farm.longitude;
    map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farm = _farmPoint;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AgriAppBar(
        title: 'Farm Location',
        // Returns to the Product Details this map was opened from.
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loadingFarm
                ? const Center(child: CircularProgressIndicator(color: _dark))
                : farm == null
                ? _unavailable()
                : _mapFor(farm),
          ),
          Positioned(left: 12, right: 12, bottom: 12, child: _infoCard()),
        ],
      ),
    );
  }

  // Built only when the farm point is known, so the very first frame of
  // the map is already on the farmer's barangay — there is no default
  // position for it to open on.
  Widget _mapFor(LatLng farm) {
    final me = _myPosition;
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: farm, zoom: _farmZoom),
      onMapCreated: (controller) {
        _map = controller;
        if (kDebugMode) {
          debugPrint(
            'FarmLocation[debug]: map created, camera target = farm point '
            '(${farm.latitude}, ${farm.longitude}), zoom $_farmZoom',
          );
        }
        _fitBuyerOnce();
      },
      // Keeps the zoom buttons and the Google logo clear of the card.
      padding: const EdgeInsets.only(bottom: 176),
      // The buyer's own position: the standard blue dot.
      myLocationEnabled: me != null,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      markers: {
        Marker(
          markerId: const MarkerId('approximate_farm'),
          position: farm,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Approximate Farm Location',
            snippet: _farm?.area,
          ),
        ),
      },
      // A wide circle: this is a barangay, not an address.
      circles: {
        Circle(
          circleId: const CircleId('approximate_farm_area'),
          center: farm,
          radius: 700,
          fillColor: _dark.withValues(alpha: 0.12),
          strokeColor: _dark.withValues(alpha: 0.55),
          strokeWidth: 1,
        ),
      },
    );
  }

  // No resolvable public point: say so, rather than draw a map of
  // somewhere else. The saved area text is still shown in the card.
  Widget _unavailable() {
    return Container(
      color: AppTheme.surface,
      alignment: const Alignment(0, -0.35),
      child: const AgriEmptyState(
        icon: Icons.location_off_outlined,
        title: 'Farm location unavailable',
        subtitle: 'We could not place this farmer’s area on the map.',
        padding: EdgeInsets.all(32),
      ),
    );
  }

  // Compact floating card — not a sheet: the map stays in view above it.
  Widget _infoCard() {
    final farm = _farm;
    final name = farm?.farmerName ?? widget.farmerName;
    final area = farm?.area ?? '';
    final distanceKm = _distanceKm;
    final hasDistance = distanceKm != null;
    final notice = _locationNotice;
    // Without a farm point there is nothing to measure to, whatever the
    // buyer's permission is.
    final canRetry = !hasDistance && notice != null && _farmPoint != null;

    return SafeArea(
      top: false,
      child: Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    photoUrl: farm?.photoUrl,
                    name: name,
                    radius: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Farmer' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          area.isNotEmpty
                              ? area
                              : (_loadingFarm
                                    ? 'Loading farm area…'
                                    : 'General location not set'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    hasDistance
                        ? Icons.near_me_outlined
                        : Icons.location_disabled_outlined,
                    size: 17,
                    color: hasDistance ? _dark : Colors.grey[700],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      approxDistanceLabel(distanceKm),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: hasDistance ? _dark : Colors.grey[800],
                      ),
                    ),
                  ),
                  if (canRetry)
                    TextButton(
                      onPressed: _determinePosition,
                      style: TextButton.styleFrom(
                        foregroundColor: _dark,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Try Again',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                hasDistance
                    ? 'Distance is estimated using the farmer’s general barangay location.'
                    : (canRetry ? notice : 'Farm area could not be mapped.'),
                style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.grey[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The map shows only the farmer’s general barangay area. Exact farm location is private.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
