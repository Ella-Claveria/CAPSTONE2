import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Explains why (if the OS hasn't decided yet) and then requests location
/// access. Shared by every screen that wants to ask for location contextually
/// — the buyer map view, the post-registration buyer prompt, and the farmer
/// registration's barangay picker — so the rationale wording and flow stay
/// consistent no matter where it's triggered from.
///
/// Returns true if permission ends up granted (whileInUse or always).
Future<bool> maybeRequestLocationPermission(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    if (!context.mounted) return false;
    final proceed = await showPermissionRationale(
      context,
      icon: Icons.location_on_outlined,
      title: title,
      message: message,
    );
    if (!proceed) return false;
    if (!context.mounted) return false;
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
}
