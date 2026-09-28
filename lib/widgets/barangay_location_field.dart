import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/laurel_barangays.dart';
import '../services/location_permission_prompt.dart';
import '../theme/app_theme.dart';

/// Farmer-only barangay picker (buyers use MyLocationField instead, since
/// buyer registration isn't restricted to Laurel): a dropdown
/// (kLaurelBarangays) plus a "Use my current location" action that
/// requests GPS and snaps to the nearest real barangay via
/// nearestLaurelBarangay — there's no surveyed-boundary data to do exact
/// point-in-barangay lookup, so "nearest illustrative center" is the best
/// available match once a fix is confirmed to actually be in Laurel (see
/// isWithinLaurel — a fix that isn't gets rejected instead of silently
/// snapped to whatever's closest). [onLocationDetected] additionally hands
/// back the raw coordinates, for callers that want to store a precise
/// point alongside the barangay name (the way a farmer's real GPS pin
/// already works).
class BarangayLocationField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final void Function(double lat, double lng)? onLocationDetected;
  final String label;
  final String? errorText;

  const BarangayLocationField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onLocationDetected,
    this.label = 'Barangay (Laurel)',
    this.errorText,
  });

  @override
  State<BarangayLocationField> createState() => _BarangayLocationFieldState();
}

class _BarangayLocationFieldState extends State<BarangayLocationField> {
  bool _locating = false;
  bool _dropdownPromptShown = false;

  // Opening the dropdown is the clearest signal they've reached the
  // location-relevant part of the form — matches the existing farmer
  // barangay picker's rationale-priming pattern.
  void _maybeRequestOnOpen() {
    if (_dropdownPromptShown) return;
    _dropdownPromptShown = true;
    maybeRequestLocationPermission(
      context,
      title: 'Find your barangay',
      message: "AgriTrade+ uses your location to help confirm you're in Laurel, Batangas.",
    );
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final granted = await maybeRequestLocationPermission(
        context,
        title: 'Find your barangay',
        message: "AgriTrade+ uses your current GPS position to find your barangay "
            "automatically. You can still pick it manually instead.",
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      if (!isWithinLaurel(position.latitude, position.longitude)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "This doesn't look like Laurel, Batangas. Farmers must be "
              'located within Laurel to register — please select your '
              'barangay manually if this seems wrong.',
            ),
          ),
        );
        return;
      }
      final nearest = nearestLaurelBarangay(position.latitude, position.longitude);
      widget.onChanged(nearest.name);
      widget.onLocationDetected?.call(position.latitude, position.longitude);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect your location. Please pick it manually.')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: AppTheme.label()),
            TextButton.icon(
              onPressed: _locating ? null : _useMyLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.mid),
                    )
                  : const Icon(Icons.my_location, size: 16),
              label: const Text('Use my location', style: TextStyle(fontSize: 12.5)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.mid,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: widget.value,
          isExpanded: true,
          onTap: _maybeRequestOnOpen,
          decoration: AppTheme.inputBox(
            hint: 'Select your barangay',
            icon: Icons.location_on_outlined,
            errorText: widget.errorText,
          ),
          items: kLaurelBarangays.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
