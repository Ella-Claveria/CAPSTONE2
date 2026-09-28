import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../screen/pick_location_screen.dart';
import '../theme/app_theme.dart';

/// Buyer-registration counterpart to BarangayLocationField — buyers aren't
/// restricted to Laurel, so instead of picking from a barangay list, this
/// opens a full-Philippines map picker (PickLocationScreen) and shows
/// whatever was picked. Tapping "Use my location" jumps straight into the
/// picker pre-triggered to GPS-locate, for the common one-tap case.
class MyLocationField extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final ValueChanged<LatLng> onPicked;
  final String? errorText;

  const MyLocationField({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onPicked,
    this.errorText,
  });

  bool get _hasLocation => latitude != null && longitude != null;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(initialLat: latitude, initialLng: longitude),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Location', style: AppTheme.label()),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _openPicker(context),
          child: InputDecorator(
            decoration: AppTheme.inputBox(
              hint: 'Tap to set your location on the map',
              icon: Icons.my_location,
              suffix: const Icon(Icons.chevron_right, color: Colors.grey),
              errorText: errorText,
            ),
            isEmpty: !_hasLocation,
            child: _hasLocation
                ? Text(
                    '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.black87, fontSize: 14.5),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
