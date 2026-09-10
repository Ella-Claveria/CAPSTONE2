import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/laurel_barangays.dart';
import '../services/location_permission_prompt.dart';

/// Uses OpenStreetMap via flutter_map — no Google Maps API key or billing
/// account needed, unlike the admin Demand Heatmap. Good enough for showing
/// barangay-level farmer density; swap to Google Maps later if you want
/// satellite imagery or Google's POI data.
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

  List<Marker> _buildMarkers(
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> farmersByBarangay,
  ) {
    final markers = <Marker>[];
    for (final loc in kLaurelBarangayLocations) {
      final farmers = farmersByBarangay[loc.name];
      if (farmers == null || farmers.isEmpty) continue;

      final size = 40.0 + math.min(farmers.length, 5) * 8.0;
      markers.add(
        Marker(
          point: LatLng(loc.lat, loc.lng),
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () => _showFarmDetails(loc, farmers),
            // Offset from any single farm's exact address to protect
            // farmer privacy — this marks the barangay, not a home.
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.35),
                border: Border.all(color: Colors.green[800]!, width: 2),
              ),
            ),
          ),
        ),
      );
    }

    if (_myPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_myPosition!.latitude, _myPosition!.longitude),
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  void _showFarmDetails(
    LaurelBarangayLocation loc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> farmers,
  ) {
    final distanceKm = _distanceKmTo(loc.lat, loc.lng);
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
                      'Brgy. ${loc.name}',
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
    final markers = _buildMarkers(farmersByBarangay);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: _laurelCenter,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.agritrade',
              ),
              MarkerLayer(markers: markers),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
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
