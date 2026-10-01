import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Explains why (if the OS hasn't decided yet) and then requests location
/// access. Shared by every screen that wants to ask for location contextually
/// — the buyer map view, the post-registration buyer prompt, and the farmer
/// registration's barangay picker — so the rationale wording and flow stay
/// consistent no matter where it's triggered from.
///
/// If the OS has already permanently denied the permission, this shows a
/// "go to Settings" dialog instead of calling Geolocator.requestPermission()
/// again — that call would never show a system dialog at that point, so
/// retrying it would just silently fail with no way for the user to fix it.
///
/// Returns true if permission ends up granted (whileInUse or always).
Future<bool> maybeRequestLocationPermission(
  BuildContext context, {
  required String title,
  required String message,
  List<String>? bullets,
  String denyLabel = 'Not now',
  String allowLabel = 'Continue',
}) async {
  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.deniedForever) {
    if (!context.mounted) return false;
    final openSettings = await showPermissionRationale(
      context,
      icon: Icons.location_off_outlined,
      title: title,
      message: 'Location access for AgriTrade+ is currently turned off in your '
          'device settings. Please enable it there to use this feature.',
      denyLabel: 'Not now',
      allowLabel: 'Open Settings',
    );
    if (openSettings) await Geolocator.openAppSettings();
    return false;
  }

  if (permission == LocationPermission.denied) {
    if (!context.mounted) return false;
    final proceed = await showPermissionRationale(
      context,
      icon: Icons.location_on_outlined,
      title: title,
      message: message,
      bullets: bullets,
      denyLabel: denyLabel,
      allowLabel: allowLabel,
    );
    if (!proceed) return false;
    if (!context.mounted) return false;
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
}

/// The one canonical "why we need your location" explanation for Farmer
/// accounts — same title/wording everywhere a farmer screen asks for
/// location, per AgriTrade+'s location-privacy policy (see PrivacyPolicyScreen
/// section E). [blockedFeature], when given, names the specific setup step
/// that can't continue without location (e.g. "Automatically detecting your
/// barangay"), appended as an extra line — the dialog is otherwise identical.
Future<bool> requestFarmerLocationPermission(
  BuildContext context, {
  String? blockedFeature,
}) {
  return maybeRequestLocationPermission(
    context,
    title: 'Set Your Farm Location',
    message: 'AgriTrade+ uses your location to estimate distance between '
        'buyers and farmers, support delivery or pick-up coordination, and '
        'improve location-based marketplace analytics.',
    bullets: [
      'Your general farm area may be shown to Buyers to help them understand '
          'where products are located — your barangay, municipality/city, and province.',
      'Exact location information is not publicly displayed unless required for an order.',
      'Location may also be used for distance calculation, nearby marketplace '
          'features, maps, and aggregated analytics.',
      'Location is required for Farmer accounts to use location-based marketplace features.',
      if (blockedFeature != null) '$blockedFeature requires location access to continue.',
    ],
    denyLabel: 'Not Now',
    allowLabel: 'Allow Location',
  );
}

/// The one canonical "why we need your location" explanation for Buyer
/// accounts — see PrivacyPolicyScreen section E for the written policy this
/// wording matches.
Future<bool> requestBuyerLocationPermission(BuildContext context) {
  return maybeRequestLocationPermission(
    context,
    title: 'Find Products Near You',
    message: 'AgriTrade+ uses your location to estimate distance between '
        'buyers and farmers, support delivery or pick-up coordination, and '
        'improve location-based marketplace analytics.',
    bullets: [
      'Used to show nearby farmers and products and estimate approximate distance.',
      'Used to support delivery and pick-up coordination for your orders.',
      'Your location may also be used in aggregated demand analytics to help '
          'administrators understand which areas have higher purchasing demand.',
      'Your precise location will not be displayed publicly to other users.',
      'You can manage location permission later in your device settings.',
    ],
    denyLabel: 'Not Now',
    allowLabel: 'Allow Location',
  );
}
