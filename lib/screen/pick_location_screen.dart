import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_permission_prompt.dart';

/// Anywhere-in-the-Philippines location picker — unlike
/// SetFarmLocationScreen (farmer-only, auto-saves straight to Firestore,
/// no restriction of its own), this just hands the picked point back via
/// Navigator.pop, since it's used during registration before an account
/// (and therefore a Firestore doc to save to) even exists yet. No
/// geographic restriction — used for buyer registration, which unlike
/// farmer registration isn't limited to Laurel, Batangas.
class PickLocationScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const PickLocationScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  // Roughly the geographic center of the Philippines — used only when the
  // caller has no earlier pick to re-center on.
  static const LatLng _philippinesCenter = LatLng(12.8797, 121.7740);

  GoogleMapController? _mapController;
  late LatLng _picked;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _picked = (widget.initialLat != null && widget.initialLng != null)
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : _philippinesCenter;
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final granted = await maybeRequestLocationPermission(
        context,
        title: 'Set your location',
        message: 'AgriTrade+ uses your current GPS position to place your location on the map. '
            'You can still drag the map to fine-tune it afterward.',
      );
      if (!granted) return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on location services to use this.')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      final here = LatLng(position.latitude, position.longitude);
      _picked = here;
      await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(here, 15.0));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your current location.')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initialLat != null && widget.initialLng != null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('My Location',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _picked, zoom: hasInitial ? 15.0 : 5.0),
            onMapCreated: (controller) => _mapController = controller,
            onCameraMove: (position) => _picked = position.target,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),
          const IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_on, color: _dark, size: 44),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: const Text(
                'Drag the map so the pin sits over your location, or use your current location.',
                style: TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _locating ? null : _useMyLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _dark))
                        : const Icon(Icons.my_location),
                    label: const Text('Use My Current Location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _dark,
                      side: const BorderSide(color: _dark),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _picked),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Confirm Location', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
