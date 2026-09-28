import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../data/laurel_barangays.dart';
import '../services/location_permission_prompt.dart';

/// Barangay-level farmer density on a real Google Map. Farmer clusters are
/// drawn as circles (not individual pins) — see the privacy note in
/// _showFarmDetails: exact farm locations stay hidden until an order is
/// confirmed with that farmer.
class BuyerMapView extends StatefulWidget {
  const BuyerMapView({super.key});

  @override
  State<BuyerMapView> createState() => _BuyerMapViewState();
}

class _BuyerMapViewState extends State<BuyerMapView> {
  static const _laurelCenter = LatLng(kLaurelCenterLat, kLaurelCenterLng);

  Position? _myPosition;
  String? _locationNotice;

  StreamSubscription? _usersSub;
  StreamSubscription? _productsSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _farmerDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _productDocs = [];

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _usersSub = FirebaseFirestore.instance.collection('users').snapshots().listen((snap) {
      if (mounted) setState(() => _farmerDocs = snap.docs);
    });
    _productsSub = FirebaseFirestore.instance.collection('products').snapshots().listen((snap) {
      if (mounted) setState(() => _productDocs = snap.docs);
    });
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _productsSub?.cancel();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      // Explain why before the OS prompt appears, instead of surprising
      // them with a permission dialog the moment they open the map.
      if (!mounted) return;
      final granted = await maybeRequestLocationPermission(
        context,
        title: 'See farms near you',
        message: "AgriTrade+ uses your location to show how far nearby "
            "farms are and sort them by distance. You can skip this and "
            "still browse everything.",
      );
      if (!granted) {
        if (!mounted) return;
        setState(() => _locationNotice =
            'Location skipped — showing farms without distances.');
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() => _locationNotice = 'Turn on location services to see distances.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _myPosition = position;
        _locationNotice = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationNotice = 'Could not get your location right now.');
    }
  }

  /// Straight-line distance from the buyer's device to a barangay's
  /// (illustrative) center, in kilometers. Null until location is known.
  double? _distanceKmTo(double lat, double lng) {
    final pos = _myPosition;
    if (pos == null) return null;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng) / 1000;
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _farmersByBarangay() {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in _farmerDocs) {
      final data = doc.data();
      if ((data['role'] ?? '') != 'farmer') continue;
      if ((data['approvalStatus'] ?? '') != 'approved') continue;
      final barangay = (data['barangay'] ?? '').toString();
      if (barangay.isEmpty) continue;
      map.putIfAbsent(barangay, () => []).add(doc);
    }
    return map;
  }

  Map<String, int> _topCategoriesFor(Set<String> farmerIds) {
    final counts = <String, int>{};
    for (final doc in _productDocs) {
      final data = doc.data();
      if (data['isArchived'] == true || data['isSuspended'] == true) continue;
      final farmerId = (data['farmerId'] ?? '').toString();
      if (!farmerIds.contains(farmerId)) continue;
      final category = (data['category'] ?? 'General').toString();
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts;
  }

  /// The real, privacy-preserving cluster center for a barangay: the
  /// average of that barangay's farmers' pinned GPS locations where any
  /// have set one, otherwise the illustrative ring position. Buyers only
  /// ever see this cluster point, never an individual farm's exact pin.
  LatLng _clusterPointFor(
    LaurelBarangayLocation loc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> farmers,
  ) {
    final realPoints = <LatLng>[];
    for (final doc in farmers) {
      final data = doc.data();
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) realPoints.add(LatLng(lat, lng));
    }
    if (realPoints.isEmpty) return LatLng(loc.lat, loc.lng);
    final avgLat = realPoints.map((p) => p.latitude).reduce((a, b) => a + b) / realPoints.length;
    final avgLng = realPoints.map((p) => p.longitude).reduce((a, b) => a + b) / realPoints.length;
    return LatLng(avgLat, avgLng);
  }

  Set<Circle> _buildCircles(
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> farmersByBarangay,
  ) {
    final circles = <Circle>{};
    for (final loc in kLaurelBarangayLocations) {
      final farmers = farmersByBarangay[loc.name];
      if (farmers == null || farmers.isEmpty) continue;

      final point = _clusterPointFor(loc, farmers);
      // Radius in meters, not pixels — scales with farmer count but stays
      // wide enough to read as "this barangay", never a single address.
      final radius = 180.0 + math.min(farmers.length, 5) * 60.0;
      circles.add(
        Circle(
          circleId: CircleId(loc.name),
          center: point,
          radius: radius,
          fillColor: Colors.green.withValues(alpha: 0.35),
          strokeColor: Colors.green[800]!,
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () => _showFarmDetails(loc.name, point, farmers),
        ),
      );
    }
    return circles;
  }

  void _showFarmDetails(
    String barangayName,
    LatLng point,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> farmers,
  ) {
    final distanceKm = _distanceKmTo(point.latitude, point.longitude);
    final categories = _topCategoriesFor(farmers.map((d) => d.id).toSet());
    final topProducts = (categories.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => e.key)
        .join(', ');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Brgy. $barangayName',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${farmers.length} VERIFIED FARMER(S)',
                      style: TextStyle(color: Colors.green[800], fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    distanceKm != null
                        ? 'Laurel, Batangas • ~${distanceKm.toStringAsFixed(1)} km away'
                        : 'Laurel, Batangas • distance unavailable',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined, size: 16, color: Colors.orange[800]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Exact address is hidden for farmer privacy and will be revealed upon order confirmation.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Active Categories in this Barangay', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                topProducts.isEmpty ? 'No active listings yet.' : topProducts,
                style: TextStyle(color: Colors.grey[800]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final farmersByBarangay = _farmersByBarangay();
    final farmMarkerCount = farmersByBarangay.values.where((f) => f.isNotEmpty).length;
    final circles = _buildCircles(farmersByBarangay);

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _laurelCenter, zoom: 13.0),
            circles: circles,
            myLocationEnabled: _myPosition != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.map_outlined, color: Colors.grey),
                  ),
                  Expanded(
                    child: Text(
                      farmMarkerCount == 0
                          ? 'No verified farmers mapped yet'
                          : '$farmMarkerCount barangay(s) with active farmers',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_locationNotice != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_locationNotice!, style: const TextStyle(fontSize: 12.5)),
                    ),
                    TextButton(
                      onPressed: _determinePosition,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
