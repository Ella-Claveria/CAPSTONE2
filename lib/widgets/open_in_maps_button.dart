import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// Shared launcher — the one place that actually opens Google Maps.
// Both widgets below call this, so there's only one implementation
// to maintain.
// ============================================================
class MapsLauncher {
  static Future<void> open(
    BuildContext context, {
    required double? latitude,
    required double? longitude,
  }) async {
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This seller has not shared a location yet.')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps.')),
      );
    }
  }
}

// ============================================================
// FULL BUTTON — use on Product Detail.
//
//   OpenInMapsButton(
//     latitude: data['latitude'],
//     longitude: data['longitude'],
//     farmerName: data['farmerName'] ?? 'Farmer',
//   )
// ============================================================
class OpenInMapsButton extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final String farmerName;

  const OpenInMapsButton({
    super.key,
    required this.latitude,
    required this.longitude,
    this.farmerName = 'Farmer',
  });

  static const Color _dark = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    final hasLocation = latitude != null && longitude != null;

    if (!hasLocation) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _dark.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, color: Colors.grey[500], size: 20),
            const SizedBox(width: 10),
            Text('Location not shared yet',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => MapsLauncher.open(context, latitude: latitude, longitude: longitude),
        icon: const Icon(Icons.map_outlined, size: 20),
        label: Text("View $farmerName's Location"),
        style: OutlinedButton.styleFrom(
          foregroundColor: _dark,
          side: const BorderSide(color: _dark),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ============================================================
// COMPACT ICON — use on Marketplace feed cards and the Chat header,
// where space is tight. Just a small pin icon; tapping opens Maps
// the same way. Silently does nothing if there's no location (so
// feed cards don't show a broken/dead-looking icon).
//
//   MapPinIconButton(latitude: .., longitude: .., farmerName: ..)
// ============================================================
class MapPinIconButton extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final String farmerName;
  final double size;
  final Color? color;

  const MapPinIconButton({
    super.key,
    required this.latitude,
    required this.longitude,
    this.farmerName = 'Farmer',
    this.size = 20,
    this.color,
  });

  static const Color _dark = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    final hasLocation = latitude != null && longitude != null;

    return IconButton(
      icon: Icon(
        Icons.location_on,
        size: size,
        color: hasLocation ? (color ?? _dark) : Colors.grey.shade400,
      ),
      tooltip: hasLocation ? "View $farmerName's location" : 'Location not shared',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: hasLocation
          ? () => MapsLauncher.open(context, latitude: latitude, longitude: longitude)
          : () => MapsLauncher.open(context, latitude: null, longitude: null), // shows the snackbar
    );
  }
}