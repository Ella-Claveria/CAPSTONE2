import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/laurel_barangay_match.dart';
import '../data/laurel_barangays.dart';
import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/barangay_location_field.dart';

/// What the farmer confirmed: the barangay, and the point it was read at.
class FarmLocationResult {
  final String barangay;
  final double lat;
  final double lng;

  const FarmLocationResult({
    required this.barangay,
    required this.lat,
    required this.lng,
  });
}

/// What a position turned out to be, as far as it could be told.
class FarmLocationReading {
  /// One of Laurel's barangays, only when the address lookup clearly named
  /// exactly one — never a guess from distance.
  final String? barangay;
  final String? municipality;
  final String? province;

  /// False when the position is known not to be in Laurel, Batangas.
  final bool inLaurel;

  /// False when no address could be looked up at all (no connection, or
  /// the service gave nothing).
  final bool lookedUp;

  const FarmLocationReading({
    this.barangay,
    this.municipality,
    this.province,
    required this.inLaurel,
    required this.lookedUp,
  });
}

/// Turns a looked-up address (or the lack of one) into a reading. With an
/// address, Laurel is decided by the municipality it names; without one,
/// only by a generous distance from the town — enough to turn away a
/// position that is plainly somewhere else, and nothing more.
FarmLocationReading readFarmLocation(
  ResolvedAddress? address,
  double lat,
  double lng,
) {
  if (address == null) {
    return FarmLocationReading(
      inLaurel: isWithinLaurel(lat, lng),
      lookedUp: false,
    );
  }
  final inLaurel = address.city == null
      ? isWithinLaurel(lat, lng)
      : isLaurelMunicipality(address.city);
  return FarmLocationReading(
    barangay: inLaurel
        ? matchLaurelBarangay([address.barangay, ...address.barangayCandidates])
        : null,
    municipality: address.city,
    province: address.province,
    inLaurel: inLaurel,
    lookedUp: true,
  );
}

/// The map a farmer confirms their location on, opened by "Use my
/// location" once a GPS position is in hand.
///
/// The map opens on that position whether or not its address could be
/// looked up. The pin stays in the middle while the map is moved under it;
/// each time it settles the position is read again. A barangay is only
/// suggested when the lookup clearly names one of Laurel's — otherwise the
/// farmer picks it from the list, and can always change a suggestion.
/// Nothing is saved here: the choice goes back to the registration form.
class ConfirmFarmLocationScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  /// For tests: stand in for the address lookup and for the map itself.
  final Future<ResolvedAddress?> Function(double lat, double lng)? lookup;
  final WidgetBuilder? mapBuilder;

  const ConfirmFarmLocationScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.lookup,
    this.mapBuilder,
  });

  @override
  State<ConfirmFarmLocationScreen> createState() =>
      _ConfirmFarmLocationScreenState();
}

class _ConfirmFarmLocationScreenState extends State<ConfirmFarmLocationScreen> {
  static const String _fallbackMessage =
      "We found your location, but couldn't identify your Barangay "
      'automatically. Please select your Barangay to continue.';

  GoogleMapController? _map;
  late LatLng _pin = LatLng(widget.initialLat, widget.initialLng);
  LatLng? _lastRead;
  Timer? _settle;

  FarmLocationReading? _reading;
  bool _checking = false;
  bool _recentering = false;
  // The barangay to confirm: the suggestion, or the farmer's own pick —
  // which a later suggestion never overrides.
  String? _barangay;
  bool _pickedByHand = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final at = _pin;
    _lastRead = at;
    setState(() => _checking = true);
    final address =
        await (widget.lookup?.call(at.latitude, at.longitude) ??
            GeocodingService.reverseGeocode(at.latitude, at.longitude));
    if (!mounted || _lastRead != at) return;
    final reading = readFarmLocation(address, at.latitude, at.longitude);
    setState(() {
      _reading = reading;
      _checking = false;
      if (!reading.inLaurel) {
        _barangay = null;
        _pickedByHand = false;
      } else if (!_pickedByHand) {
        _barangay = reading.barangay;
      }
    });
  }

  // The map stopped moving. Read the new position — but not for a nudge
  // of a few metres, and never more than once a second.
  void _onSettled() {
    final last = _lastRead;
    if (last != null &&
        Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              _pin.latitude,
              _pin.longitude,
            ) <
            25) {
      return;
    }
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      // A pin moved by hand is a new place: a pick made for the old one
      // no longer stands.
      _pickedByHand = false;
      _read();
    });
  }

  Future<void> _recenter() async {
    setState(() => _recentering = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _pin = LatLng(position.latitude, position.longitude);
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(_pin, 16.5));
      _pickedByHand = false;
      _read();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get your current location. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _recentering = false);
    }
  }

  Future<void> _pickBarangay() async {
    final picked = await showBarangayPicker(context, selected: _barangay);
    if (picked == null || !mounted) return;
    setState(() {
      _barangay = picked;
      _pickedByHand = true;
    });
  }

  void _confirm() {
    final barangay = _barangay;
    if (barangay == null) return;
    Navigator.pop(
      context,
      FarmLocationResult(
        barangay: barangay,
        lat: _pin.latitude,
        lng: _pin.longitude,
      ),
    );
  }

  TextStyle _text(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.montserrat(
        fontSize: size,
        color: color ?? Colors.black87,
        fontWeight: weight ?? FontWeight.w400,
        height: 1.4,
      );

  Widget _mapArea() {
    return Stack(
      children: [
        Positioned.fill(
          child:
              widget.mapBuilder?.call(context) ??
              GoogleMap(
                initialCameraPosition: CameraPosition(target: _pin, zoom: 16.5),
                onMapCreated: (controller) => _map = controller,
                onCameraMove: (camera) => _pin = camera.target,
                onCameraIdle: _onSettled,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
              ),
        ),
        // The pin: fixed in the middle, with its tip on the map's center.
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Icon(
                Icons.location_on,
                size: 48,
                color: Color(0xFFD32F2F),
              ),
            ),
          ),
        ),
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Move the map so the pin sits on your farm.',
              textAlign: TextAlign.center,
              style: _text(12, color: Colors.black54),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'farm-location-recenter',
            tooltip: 'Use Current Location',
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.mid,
            onPressed: _recentering ? null : _recenter,
            child: _recentering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.mid,
                    ),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: _text(12.5, color: Colors.black54)),
        ),
        Expanded(
          child: Text(value, style: _text(13, weight: FontWeight.w600)),
        ),
      ],
    ),
  );

  Widget _panel() {
    final reading = _reading;
    final outside = reading != null && !reading.inLaurel;
    final suggested =
        reading?.barangay != null && _barangay == reading!.barangay;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_checking && reading == null)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.mid,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Checking this location…', style: _text(13)),
              ],
            )
          else if (outside) ...[
            Text(
              'This location is outside Laurel, Batangas.',
              style: _text(
                14,
                color: Colors.red.shade700,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Farmer registration is only open to farms in Laurel. Move '
              'the pin to your farm in Laurel, or go back and select your '
              'barangay from the list.',
              style: _text(12.5, color: Colors.black54),
            ),
          ] else ...[
            _line(
              'Barangay',
              _barangay == null
                  ? 'Not selected'
                  : suggested
                  ? '$_barangay (suggested)'
                  : _barangay!,
            ),
            _line('Municipality', reading?.municipality ?? 'Laurel'),
            _line('Province', reading?.province ?? 'Batangas'),
            if (_barangay == null && !_checking) ...[
              const SizedBox(height: 4),
              Text(
                reading?.lookedUp == false
                    ? "We found your location, but couldn't look up its "
                          'address — check your internet connection. You '
                          'can still select your Barangay to continue.'
                    : _fallbackMessage,
                style: _text(12.5, color: Colors.orange.shade900),
              ),
            ] else if (suggested) ...[
              const SizedBox(height: 4),
              Text(
                'Please check that this is your barangay before confirming.',
                style: _text(12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickBarangay,
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: Text(
                  _barangay == null ? 'Select Barangay' : 'Change Barangay',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.mid,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _barangay == null || outside ? null : _confirm,
              style: AppTheme.primaryButton().copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              child: Text('Confirm Location', style: AppTheme.buttonText()),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Your exact position is not shown to buyers — only your barangay.',
              textAlign: TextAlign.center,
              style: _text(11, color: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AgriAppBar(title: 'Confirm Your Location'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _mapArea()),
            _panel(),
          ],
        ),
      ),
    );
  }
}
