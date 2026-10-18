import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/laurel_barangays.dart';
import '../screen/confirm_farm_location_screen.dart';
import '../services/location_permission_prompt.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';

/// Farmer-only barangay picker (buyers use BuyerLocationField instead, since
/// buyer registration isn't restricted to Laurel): a field that opens a
/// searchable list (kLaurelBarangays, see [showBarangayPicker]) plus a "Use my location" action that
/// gets a GPS fix and opens a map on it (ConfirmFarmLocationScreen) for
/// the farmer to confirm. The barangay is only suggested there when the
/// position's looked-up address clearly names one of Laurel's — it is
/// never taken from which barangay happens to be nearest, since the
/// barangay points in laurel_barangays.dart are placeholders, not
/// surveyed centers. [onLocationDetected] additionally hands
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

  // Opening the list is the clearest signal they've reached the
  // location-relevant part of the form — matches the existing farmer
  // barangay picker's rationale-priming pattern.
  void _maybeRequestOnOpen() {
    if (_dropdownPromptShown) return;
    _dropdownPromptShown = true;
    requestFarmerLocationPermission(context);
  }

  Future<void> _openPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _maybeRequestOnOpen();
    final picked = await showBarangayPicker(context, selected: widget.value);
    if (picked != null && mounted) widget.onChanged(picked);
  }

  // "Use my location": get one GPS fix (nothing is tracked afterwards),
  // then open the map on it for the farmer to confirm. The map opens
  // whether or not the position's address can be looked up; a barangay is
  // only ever suggested there, never chosen for them.
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final granted = await requestFarmerLocationPermission(
        context,
        blockedFeature: 'Automatically detecting your barangay',
      );
      if (!mounted) return;
      if (!granted) {
        // The permission helper has just explained this (and offered
        // Settings), so no second dialog — only the way to carry on.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location permission is needed to detect your barangay.',
            ),
            action: SnackBarAction(
              label: 'Select Manually',
              onPressed: _openPicker,
            ),
          ),
        );
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        await _locationProblem(
          title: 'Location Is Turned Off',
          message:
              'Turn on Location (GPS) on your phone and try again, or '
              'select your barangay from the list instead.',
        );
        return;
      }

      final Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        await _locationProblem(
          title: 'Could Not Find Your Location',
          message:
              'Your phone could not get a GPS position. Try again '
              'outdoors or near a window, or select your barangay from '
              'the list instead.',
        );
        return;
      }
      if (!mounted) return;

      final result = await Navigator.push<FarmLocationResult>(
        context,
        MaterialPageRoute(
          builder: (_) => ConfirmFarmLocationScreen(
            initialLat: position.latitude,
            initialLng: position.longitude,
          ),
        ),
      );
      if (result == null || !mounted) return;
      widget.onChanged(result.barangay);
      widget.onLocationDetected?.call(result.lat, result.lng);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // Says what stopped the location from being found, with a way to try
  // again and a way to carry on without it.
  Future<void> _locationProblem({
    required String title,
    required String message,
  }) async {
    final choice = await showAgriDialog<String>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.location_off_outlined,
        tone: AgriTone.warning,
        title: Text(title),
        content: Text(message),
        actions: [
          AgriDialogButton(
            label: 'Select Manually',
            onPressed: () => Navigator.pop(dialogContext, 'manual'),
          ),
          AgriDialogButton(
            label: 'Retry',
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.pop(dialogContext, 'retry'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'retry') {
      await _useMyLocation();
    } else if (choice == 'manual') {
      await _openPicker();
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.mid,
                      ),
                    )
                  : const Icon(Icons.my_location, size: 16),
              label: const Text(
                'Use my location',
                style: TextStyle(fontSize: 12.5),
              ),
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
        // Looks like the form's other fields, but opens the searchable
        // list instead of taking typed text.
        Semantics(
          button: true,
          label: widget.value == null
              ? 'Select your barangay'
              : 'Barangay, ${widget.value}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _openPicker,
              child: Ink(
                decoration: AppTheme.glowFieldWrapper(),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 18, right: 12),
                      child: Icon(
                        Icons.location_on_outlined,
                        color: AppTheme.mid,
                        size: 20,
                      ),
                    ),
                    Container(height: 22, width: 1, color: Colors.black12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 12,
                        ),
                        child: Text(
                          widget.value ?? 'Select your barangay',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            color: widget.value == null
                                ? Colors.black45
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// The searchable "Select Barangay" bottom sheet. Returns the barangay
/// tapped, or null if the sheet was closed without choosing one. Nothing
/// is ever picked on the user's behalf.
Future<String?> showBarangayPicker(BuildContext context, {String? selected}) {
  // The app's frosted panel sheet and dimmed background, like every other.
  return showAgriPanelSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BarangayPickerSheet(selected: selected),
  );
}

class _BarangayPickerSheet extends StatefulWidget {
  final String? selected;

  const _BarangayPickerSheet({this.selected});

  @override
  State<_BarangayPickerSheet> createState() => _BarangayPickerSheetState();
}

class _BarangayPickerSheetState extends State<_BarangayPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kLaurelBarangays;
    return kLaurelBarangays.where((b) => b.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final matches = _matches;
    return Padding(
      // Lifts the sheet above the keyboard while searching.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Barangay',
                          style: GoogleFonts.montserrat(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.dark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Laurel, Batangas',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => setState(() => _query = value),
                style: GoogleFonts.montserrat(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Search barangay',
                  hintStyle: GoogleFonts.montserrat(
                    fontSize: 14.5,
                    color: Colors.black45,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.mid,
                    size: 21,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          color: Colors.black38,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF4F6F4),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(
                      color: AppTheme.mid,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE8EDE8)),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                      child: Text(
                        'No barangay in Laurel matches "${_query.trim()}".',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 13.5,
                          color: Colors.black54,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: 12 + media.viewPadding.bottom,
                      ),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 20,
                        color: Color(0xFFEEF1EE),
                      ),
                      itemBuilder: (context, index) {
                        final name = matches[index];
                        final isSelected = name == widget.selected;
                        return ListTile(
                          onTap: () => Navigator.pop(context, name),
                          selected: isSelected,
                          selectedTileColor: AppTheme.accent.withValues(
                            alpha: 0.35,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                          ),
                          horizontalTitleGap: 12,
                          minLeadingWidth: 24,
                          leading: Icon(
                            isSelected
                                ? Icons.location_on
                                : Icons.location_on_outlined,
                            color: isSelected ? AppTheme.mid : Colors.black45,
                            size: 21,
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.montserrat(
                              fontSize: 14.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppTheme.dark
                                  : Colors.black87,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.mid,
                                  size: 20,
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
