import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/ph_locations_service.dart';
import '../services/delivery_coverage.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import 'app_search_bar.dart';

/// The farmer's Custom Areas picker: a searchable list of PH
/// municipalities/cities where several can be ticked. Resolves to the new
/// selection, or null if dismissed without Done.
Future<List<DeliveryArea>?> showDeliveryAreaPicker(
  BuildContext context, {
  required List<DeliveryArea> initial,
}) {
  return showAgriPanelSheet<List<DeliveryArea>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DeliveryAreaPicker(initial: initial),
  );
}

class _DeliveryAreaPicker extends StatefulWidget {
  final List<DeliveryArea> initial;

  const _DeliveryAreaPicker({required this.initial});

  @override
  State<_DeliveryAreaPicker> createState() => _DeliveryAreaPickerState();
}

class _DeliveryAreaPickerState extends State<_DeliveryAreaPicker> {
  static const int _maxResults = 80;

  late final List<DeliveryArea> _selected = [...widget.initial];
  final _search = TextEditingController();
  List<DeliveryArea> _all = kFallbackDeliveryAreas;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final cities = await PhLocationsService.instance
          .fetchAllCitiesMunicipalities();
      if (!mounted) return;
      setState(() {
        _all = [for (final c in cities) DeliveryArea(c.name, c.province)];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(DeliveryArea area) {
    setState(() {
      if (_selected.contains(area)) {
        _selected.remove(area);
      } else {
        _selected.add(area);
      }
    });
  }

  List<DeliveryArea> get _results {
    final query = normalizePlace(_search.text);
    final matches = query.isEmpty
        ? _all
        : _all.where(
            (a) =>
                normalizePlace(a.name).contains(query) ||
                normalizePlace(a.province).startsWith(query),
          );
    return matches.take(_maxResults).toList();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    final results = _results;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 2),
                child: Text(
                  'Delivery areas',
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.dark,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Text(
                  'Select every municipality or city you deliver to.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSearchBar(
                  hint: 'Search municipality or city',
                  controller: _search,
                  onClear: _search.clear,
                ),
              ),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final area in _selected)
                        InputChip(
                          label: Text(
                            area.name,
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.dark,
                            ),
                          ),
                          backgroundColor: const Color(0xFFE8F3E3),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onDeleted: () => _toggle(area),
                          deleteIconColor: AppTheme.dark,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              if (_offline)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: Text(
                    'Couldn\'t load the full list — showing nearby areas only.',
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.dark),
                      )
                    : results.isEmpty
                    ? Center(
                        child: Text(
                          'No matching municipality or city.',
                          style: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final area = results[i];
                          return CheckboxListTile(
                            dense: true,
                            value: _selected.contains(area),
                            activeColor: AppTheme.dark,
                            onChanged: (_) => _toggle(area),
                            title: Text(
                              area.name,
                              style: GoogleFonts.montserrat(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: area.province.isEmpty
                                ? null
                                : Text(
                                    area.province,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 11.5,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: AgriDialogButton(
                  label: _selected.isEmpty
                      ? 'Done'
                      : 'Done (${_selected.length} selected)',
                  kind: AgriButtonKind.primary,
                  onPressed: () => Navigator.pop(context, _selected),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
