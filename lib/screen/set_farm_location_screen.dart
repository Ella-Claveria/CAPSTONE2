import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../data/laurel_barangays.dart';
import '../services/location_permission_prompt.dart';

/// Lets a farmer drop a pin at their real farm location — the map stays
/// still and the pin stays centered while the farmer drags the map
/// underneath it. Saves straight to the farmer's own users doc so callers
/// just re-read it rather than plumb state back through Navigator; the
/// picked point is also returned for an immediate local update of the
/// caller's UI.
class SetFarmLocationScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const SetFarmLocationScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<SetFarmLocationScreen> createState() => _SetFarmLocationScreenState();
}

class _SetFarmLocationScreenState extends State<SetFarmLocationScreen> {
  static const Color _dark = Color(0xFF1B5E20);

  GoogleMapController? _mapController;
  late LatLng _picked;
  bool _saving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _picked = (widget.initialLat != null && widget.initialLng != null)
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : const LatLng(kLaurelCenterLat, kLaurelCenterLng);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final granted = await requestFarmerLocationPermission(
        context,
        blockedFeature: 'Pinning your exact farm location',
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
      await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(here, 16.0));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your current location.')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      // Exact coordinates live under users/{uid}/private/geo, not on the
      // main user doc — that doc is readable by any signed-in user, so an
      // exact pin must never be a field on it (see firestore.rules).
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('private')
          .doc('geo')
          .set(
        {
          'latitude': _picked.latitude,
          'longitude': _picked.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      Navigator.pop(context, _picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your location. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Set Farm Location',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _picked, zoom: 15.0),
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
                'Drag the map so the pin sits over your farm, or use your current location.',
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
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Farm Location', style: TextStyle(fontWeight: FontWeight.bold)),
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
