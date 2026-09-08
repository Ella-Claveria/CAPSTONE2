import 'dart:math';

// ============================================================
// The 21 barangays of Laurel, Batangas — shared across the
// registration form (barangay dropdown) and the admin Demand
// Heatmap (barangay-level demand markers).
//
// Coordinates are illustrative offsets from the town center
// (14.0445, 120.9320), not surveyed barangay boundaries — good
// enough to place a marker per barangay on the map. Swap in real
// surveyed centers if precise placement is ever needed.
// ============================================================

const List<String> kLaurelBarangays = [
  'As-Is', 'Balakilong', 'Barangay 1', 'Barangay 2', 'Barangay 3',
  'Barangay 4', 'Barangay 5', 'Berinayan', 'Bugaan East', 'Bugaan West',
  'Buso-buso', 'Dayap Itaas', 'Gulod', 'J. Leviste', 'Molinete',
  'Niyugan', 'Paliparan', 'San Gabriel', 'San Gregorio', 'Santa Maria', 'Ticub',
];

class LaurelBarangayLocation {
  final String name;
  final double lat;
  final double lng;
  const LaurelBarangayLocation(this.name, this.lat, this.lng);
}

const double kLaurelCenterLat = 14.0445;
const double kLaurelCenterLng = 120.9320;

final List<LaurelBarangayLocation> kLaurelBarangayLocations =
    _buildLocations();

List<LaurelBarangayLocation> _buildLocations() {
  final locations = <LaurelBarangayLocation>[];
  for (var i = 0; i < kLaurelBarangays.length; i++) {
    final angle = (2 * pi * i) / kLaurelBarangays.length;
    // Vary the radius a little so markers don't all sit on one ring.
    final radiusDegrees = 0.02 + (i % 3) * 0.006;
    locations.add(
      LaurelBarangayLocation(
        kLaurelBarangays[i],
        kLaurelCenterLat + radiusDegrees * cos(angle),
        kLaurelCenterLng + radiusDegrees * sin(angle),
      ),
    );
  }
  return locations;
}

LaurelBarangayLocation? laurelBarangayLocationFor(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  for (final loc in kLaurelBarangayLocations) {
    if (loc.name.toLowerCase() == name.trim().toLowerCase()) return loc;
  }
  return null;
}
