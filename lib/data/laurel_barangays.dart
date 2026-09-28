import 'dart:math';
import 'package:geolocator/geolocator.dart';

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

// The barangay whose (illustrative) center is closest to a real GPS fix —
// used to auto-fill the barangay picker from "Use my current location"
// (buyer registration, and anywhere else a raw lat/lng needs mapping back
// to one of the 21 names). Plain planar distance is fine at this scale
// (a few km across); no need for Haversine precision.
LaurelBarangayLocation nearestLaurelBarangay(double lat, double lng) {
  var best = kLaurelBarangayLocations.first;
  var bestDist = _squaredDist(lat, lng, best.lat, best.lng);
  for (final loc in kLaurelBarangayLocations.skip(1)) {
    final dist = _squaredDist(lat, lng, loc.lat, loc.lng);
    if (dist < bestDist) {
      best = loc;
      bestDist = dist;
    }
  }
  return best;
}

double _squaredDist(double lat1, double lng1, double lat2, double lng2) {
  final dLat = lat1 - lat2;
  final dLng = lng1 - lng2;
  return dLat * dLat + dLng * dLng;
}

// Generous radius around the town center that comfortably covers all 21
// barangays plus normal GPS drift. nearestLaurelBarangay() alone always
// returns *something* — the closest barangay, no matter how far away the
// real fix is — so a farmer's "Use my location" flow needs this separate
// check to actually reject a fix that isn't in Laurel at all, rather than
// silently snapping it to whichever barangay happens to be nearest.
const double kLaurelMaxRadiusMeters = 10000;

bool isWithinLaurel(double lat, double lng) {
  return Geolocator.distanceBetween(lat, lng, kLaurelCenterLat, kLaurelCenterLng) <=
      kLaurelMaxRadiusMeters;
}
