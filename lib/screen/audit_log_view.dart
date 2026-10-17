import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_perf.dart';
import 'admin_filter_controls.dart';
import '../services/audit_log_service.dart';
import '../services/audit_report_service.dart';
import 'admin_sub_nav.dart';
import 'audit_export_dialog.dart';
import 'admin_dashboard_screen.dart'
    show
        AdminThemeScope,
        AdminPalette,
        AdminStatusBadge,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminStreamError,
        AdminQuickActionButton;

const int _pageSize = 20;

/// One row of the Admin Portal audit trail, read from an `audit_logs`
/// document (see AuditLogService / functions/index.js's logAuditEvent —
/// this collection is written only by that Cloud Function, never by the
/// client, so every field here reflects what the server actually recorded).
class _AuditEntry {
  final String id;
  final String? adminId;
  final String? adminName;
  final String? adminEmail;
  final String? attemptedEmail;
  final String action;
  final String details;
  final String browser;
  final String os;
  final String location;
  final DateTime? timestamp;

  _AuditEntry.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc)
    : id = doc.id,
      adminId = doc.data()['adminId'] as String?,
      adminName = doc.data()['adminName'] as String?,
      adminEmail = doc.data()['adminEmail'] as String?,
      attemptedEmail = doc.data()['attemptedEmail'] as String?,
      action = (doc.data()['action'] ?? '').toString(),
      details = (doc.data()['details'] ?? '').toString(),
      browser = ((doc.data()['device'] as Map?)?['browser'] ?? 'Unknown')
          .toString(),
      os = ((doc.data()['device'] as Map?)?['os'] ?? 'Unknown').toString(),
      location = (doc.data()['location'] ?? 'Unknown').toString(),
      timestamp = (doc.data()['timestamp'] as Timestamp?)?.toDate();

  // No confirmed admin identity for a pre-auth entry (a failed login or a
  // password-reset request) — only the email that was typed, which is why
  // it's labeled "Attempt:" instead of shown as if it were verified.
  String get who =>
      adminName ??
      adminEmail ??
      (attemptedEmail != null ? 'Attempt: $attemptedEmail' : 'Unknown');

  String get device => '$browser on $os';

  String get whenLabel => timestamp != null
      ? DateFormat('MMM d, y – h:mm a').format(timestamp!)
      : 'Just now';

  String get actionLabel => action
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
      .join(' ');
}

class AuditLogView extends StatefulWidget {
  const AuditLogView({super.key});

  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> with AdminPageSearch {
  final List<_AuditEntry> _entries = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  bool _loadError = false;

  String? _actionFilter;
  String? _adminFilter; // admin uid
  DateTimeRange? _dateRange;
  // Typed in the header's search box.
  String get _search => pageSearch;
  bool _reloadQueued = false;

  // The open page of the table (10 entries each), from 0. Back to the
  // first on a new search or filter.
  int _page = 0;

  @override
  void onPageSearchChanged() => _page = 0;

  // The entries whose box is ticked.
  final Set<String> _ticked = {};

  void _setAction(String? action) {
    setState(() {
      _actionFilter = action;
      _ticked.clear();
    });
    _fetchPage(reset: true);
  }

  // Live: a listener on just the newest entry. When a new one is written,
  // the first page is loaded again, so the log stays current by itself. It
  // is left alone while more pages are loaded — reloading then would throw
  // away what the admin has scrolled to.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newestSubscription;
  String? _newestId;

  void _watchNewest() {
    _newestSubscription = FirebaseFirestore.instance
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isEmpty) return;
          final id = snapshot.docs.first.id;
          final first = _newestId == null;
          final changed = _newestId != id;
          _newestId = id;
          if (first || !changed || !mounted) return;
          if (_entries.length <= _pageSize) _fetchPage(reset: true);
        }, onError: (Object _) {});
  }

  // The sidebar's Audit Log submenu (or anything else) chose a section:
  // drop the single-action filter, which may not belong to it, and reload.
  void _onSectionChanged() {
    if (!mounted) return;
    setState(() {
      _actionFilter = null;
      _ticked.clear();
    });
    _fetchPage(reset: true);
  }

  @override
  void dispose() {
    AdminSubNav.audit.removeListener(_onSectionChanged);
    _newestSubscription?.cancel();
    super.dispose();
  }

  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _adminsFuture = FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'admin')
      .get()
      .then((s) => s.docs);

  @override
  void initState() {
    super.initState();
    AdminSubNav.audit.addListener(_onSectionChanged);
    _watchNewest();
    _fetchPage(reset: true);
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'audit_logs',
    );
    // Only one equality filter goes server-side at a time — Firestore needs
    // a distinct composite index per combination of equality/range fields,
    // and indexing every admin-x-action pairing doesn't scale. Action wins
    // when both are set; the admin filter is then applied client-side in
    // _fetchPage below (see needsClientAdminFilter there).
    // An Audit Log section (see AdminSubNav) is a group of actions: the
    // same action index, queried with whereIn. A single chosen action is
    // always one of the section's own, so it simply narrows it.
    final sectionActions = AdminSubNav.audit.value.actions;
    if (_actionFilter != null) {
      q = q.where('action', isEqualTo: _actionFilter);
    } else if (sectionActions != null) {
      q = q.where('action', whereIn: sectionActions);
    } else if (_adminFilter != null) {
      q = q.where('adminId', isEqualTo: _adminFilter);
    }
    if (_dateRange != null) {
      final end = _dateRange!.end;
      q = q
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange!.start),
          )
          .where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(
              DateTime(end.year, end.month, end.day, 23, 59, 59),
            ),
          );
    }
    return q.orderBy('timestamp', descending: true);
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_loading) {
      // A filter changed mid-load: run again once this load is done.
      if (reset) _reloadQueued = true;
      return;
    }
    if (!reset && !_hasMore) return;

    setState(() {
      _loading = true;
      if (reset) {
        _page = 0;
        _entries.clear();
        _cursor = null;
        _hasMore = true;
        _loadError = false;
      }
    });

    final needsClientAdminFilter =
        (_actionFilter != null || AdminSubNav.audit.value.actions != null) &&
        _adminFilter != null;

    try {
      var collected = 0;
      // When a client-side admin filter is also needed, one server page
      // might not contain 20 matches — fetch a few more underlying pages
      // so "Load more" still surfaces a full page of real results, capped
      // so a very narrow filter combination can't trigger unbounded reads.
      var underlyingFetches = 0;
      while (collected < _pageSize && _hasMore && underlyingFetches < 5) {
        underlyingFetches++;
        var query = _baseQuery().limit(_pageSize);
        if (_cursor != null) query = query.startAfterDocument(_cursor!);
        final snap = await AdminPerf.time(
          'audit log: page',
          () => query.get(),
          describe: (s) => '${s.docs.length} entries',
        );

        if (snap.docs.isEmpty) {
          _hasMore = false;
          break;
        }
        _cursor = snap.docs.last;
        if (snap.docs.length < _pageSize) _hasMore = false;

        for (final doc in snap.docs) {
          if (needsClientAdminFilter && doc.data()['adminId'] != _adminFilter) {
            continue;
          }
          _entries.add(_AuditEntry.fromDoc(doc));
          collected++;
        }
      }
    } catch (_) {
      if (_entries.isEmpty) _loadError = true;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    if (_reloadQueued) {
      _reloadQueued = false;
      _fetchPage(reset: true);
    }
  }

  List<_AuditEntry> get _visibleEntries => _searched(_entries);

  // [entries] narrowed by the header's search box.
  List<_AuditEntry> _searched(List<_AuditEntry> entries) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries
        .where(
          (e) =>
              e.who.toLowerCase().contains(q) ||
              e.actionLabel.toLowerCase().contains(q) ||
              e.details.toLowerCase().contains(q),
        )
        .toList();
  }

  void _clearFilters() {
    setState(() {
      _actionFilter = null;
      _adminFilter = null;
      _dateRange = null;
    });
    // Clears the header's search box too.
    adminPageSearch.value = '';
    _fetchPage(reset: true);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showAdminDateRangePicker(
      context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    _fetchPage(reset: true);
  }

  // The most entries "All entries matching the filters" puts in a report.
  static const int _exportCap = 2000;

  /// Every entry matching the page's filters and search, newest first, up
  /// to [_exportCap] — read in large pages rather than the table's 20.
  Future<List<_AuditEntry>> _fetchAllMatching() async {
    final needsClientAdminFilter =
        (_actionFilter != null || AdminSubNav.audit.value.actions != null) &&
        _adminFilter != null;
    final found = <_AuditEntry>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (found.length < _exportCap) {
      var query = _baseQuery().limit(500);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snap = await query.get();
      if (snap.docs.isEmpty) break;
      cursor = snap.docs.last;
      for (final doc in snap.docs) {
        if (needsClientAdminFilter && doc.data()['adminId'] != _adminFilter) {
          continue;
        }
        found.add(_AuditEntry.fromDoc(doc));
      }
      if (snap.docs.length < 500) break;
    }
    return _searched(found.take(_exportCap).toList());
  }

  // The page's filters in words, for the report and its menu.
  Future<String> _filtersLabel() async {
    final parts = <String>[AdminSubNav.audit.value.label];
    if (_actionFilter != null) parts.add(auditActionLabel(_actionFilter!));
    if (_adminFilter != null) {
      String? name;
      try {
        final admins = await _adminsFuture;
        final admin = admins.where((d) => d.id == _adminFilter).firstOrNull;
        name =
            (admin?.data()['name'] ??
                    admin?.data()['fullName'] ??
                    admin?.data()['email'])
                ?.toString();
      } catch (_) {}
      parts.add('Admin: ${name ?? 'selected admin'}');
    }
    if (_dateRange != null) {
      parts.add(_rangeLabel(_dateRange!.start, _dateRange!.end));
    }
    if (_search.trim().isNotEmpty) parts.add('Search: "${_search.trim()}"');
    return parts.join(' · ');
  }

  static String _rangeLabel(DateTime start, DateTime end) =>
      '${DateFormat('MMM d, y').format(start)} – ${DateFormat('MMM d, y').format(end)}';

  static AuditReportRow _reportRow(_AuditEntry e) => AuditReportRow(
    at: e.timestamp,
    admin: e.who,
    actionCode: e.action,
    action: e.actionLabel,
    details: e.details,
    device: e.device,
    location: e.location,
  );

  // Export Report: the menu to choose what the report holds, then the
  // report itself (see AuditReportService).
  Future<void> _export() async {
    final c = AdminThemeScope.of(context).palette;
    final filters = await _filtersLabel();
    if (!mounted) return;
    final onScreen = _visibleEntries;
    final selected = [
      for (final e in _entries)
        if (_ticked.contains(e.id)) e,
    ];
    await showDialog<void>(
      context: context,
      builder: (_) => AuditExportDialog(
        palette: c,
        filtersLabel: filters,
        onScreenCount: onScreen.length,
        selectedCount: selected.length,
        exporter: (scope, options, onProgress) async {
          final List<_AuditEntry> chosen;
          switch (scope) {
            case AuditExportScope.allMatching:
              onProgress('Loading the matching entries…');
              chosen = await _fetchAllMatching();
            case AuditExportScope.onScreen:
              chosen = onScreen;
            case AuditExportScope.selected:
              chosen = selected;
          }
          // The period: the date filter, or else the dates the entries span.
          final dates = [
            for (final e in chosen)
              if (e.timestamp != null) e.timestamp!,
          ]..sort();
          final period = _dateRange != null
              ? _rangeLabel(_dateRange!.start, _dateRange!.end)
              : dates.isEmpty
              ? 'All dates'
              : _rangeLabel(dates.first, dates.last);
          return AuditReportService.export(
            rows: [for (final e in chosen) _reportRow(e)],
            options: options,
            periodLabel: period,
            filtersLabel: filters,
            scopeLabel: switch (scope) {
              AuditExportScope.allMatching => 'All matching entries',
              AuditExportScope.onScreen => 'Entries shown on screen',
              AuditExportScope.selected => 'Selected entries',
            },
            onProgress: onProgress,
          );
        },
      ),
    );
  }

  (Color, Color) _badgeColors(AdminPalette c, String action) {
    switch (action) {
      case AuditAction.loginSuccess:
        return (c.green, c.greenBg);
      case AuditAction.loginFailed:
        return (c.red, c.redBg);
      case AuditAction.logout:
        return (c.textSecondary, c.surfaceAlt);
      default:
        return (c.blue, c.blueBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final entries = _visibleEntries;
    // Ten a page. The page after the last loaded one stands for the
    // entries not loaded yet: opening it loads them.
    final loadedPages = adminPageCount(entries.length);
    final page = _page.clamp(0, loadedPages - 1);
    final pageEntries = adminPageOf(entries, page);
    final pageCount = loadedPages + (_hasMore && entries.isNotEmpty ? 1 : 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title is in the utility bar above. The filters, and Export
          // Report level with them.
          Row(
            children: [
              Expanded(
                child: _FilterBar(
                  // Rebuilt per section, so its Action dropdown resets with it.
                  key: ValueKey(AdminSubNav.audit.value),
                  actions: AdminSubNav.audit.value.actions ?? AuditAction.all,
                  search: _search,
                  actionFilter: _actionFilter,
                  onActionChanged: _setAction,
                  adminFilter: _adminFilter,
                  adminsFuture: _adminsFuture,
                  onAdminChanged: (v) {
                    setState(() => _adminFilter = v);
                    _fetchPage(reset: true);
                  },
                  dateRange: _dateRange,
                  onPickDateRange: _pickDateRange,
                  onClear: _clearFilters,
                ),
              ),
              // How many rows are ticked, and Clear: up here, in view
              // without scrolling to the table's end.
              AdminSelectionNote(
                count: _ticked.length,
                onClear: () => setState(_ticked.clear),
              ),
              const SizedBox(width: 12),
              // Opens the menu; with nothing loaded yet the report can still
              // gather every matching entry itself.
              AdminQuickActionButton(
                icon: Icons.file_download_outlined,
                label: 'Export Report',
                onPressed: _export,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: kAdminTablePadding,
            decoration: adminTableCard(c),
            // The header band follows the rounded corners.
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadError)
                  const AdminStreamError()
                else if (entries.isEmpty && !_loading)
                  AdminEmptyState(
                    icon: Icons.fact_check_outlined,
                    title:
                        _search.isNotEmpty ||
                            _actionFilter != null ||
                            _adminFilter != null ||
                            _dateRange != null
                        ? 'No entries match these filters'
                        : 'No audit log entries yet',
                    subtitle:
                        _search.isNotEmpty ||
                            _actionFilter != null ||
                            _adminFilter != null ||
                            _dateRange != null
                        ? 'Try clearing a filter or loading more entries.'
                        : 'Admin logins and actions will appear here as they happen.',
                  )
                else
                  AdminTableFit(
                    table: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        adminTableHeaderColor(c),
                      ),
                      dataRowColor: adminTableRowColor(c),
                      columnSpacing: kAdminTableColumnSpacing,
                      horizontalMargin: kAdminTableMargin,
                      headingTextStyle: adminTableHeaderStyle(c),
                      dataTextStyle: TextStyle(
                        fontFamily: kAdminFontFamily,
                        color: c.textPrimary,
                        fontSize: 13,
                      ),
                      columns: const [
                        DataColumn(label: Text('Date & Time')),
                        DataColumn(label: Text('Admin')),
                        DataColumn(label: Text('Action')),
                        DataColumn(label: Text('Details')),
                        DataColumn(label: Text('Device/Browser')),
                        DataColumn(label: Text('Location')),
                      ],
                      rows: pageEntries.map((e) {
                        final (color, bg) = _badgeColors(c, e.action);
                        return DataRow(
                          selected: _ticked.contains(e.id),
                          onSelectChanged: (on) => setState(() {
                            if (on ?? false) {
                              _ticked.add(e.id);
                            } else {
                              _ticked.remove(e.id);
                            }
                          }),
                          cells: [
                            DataCell(Text(e.whenLabel)),
                            DataCell(
                              SizedBox(
                                width: 160,
                                child: Text(
                                  e.who,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              AdminStatusBadge(
                                text: e.actionLabel,
                                color: color,
                                bg: bg,
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 260,
                                child: Tooltip(
                                  message: e.details,
                                  child: Text(
                                    e.details,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(e.device)),
                            DataCell(Text(e.location)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                if (_loading)
                  const AdminLoadingSpinner()
                else if (!_loadError && pageCount > 1)
                  AdminTablePager(
                    page: page,
                    pageCount: pageCount,
                    total: entries.length,
                    more: _hasMore,
                    onPage: (p) async {
                      // Past what is loaded: load the next entries first.
                      if (p >= loadedPages) await _fetchPage();
                      if (mounted) setState(() => _page = p);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "LOGIN_SUCCESS" as "Login Success".
String auditActionLabel(String action) => action
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
    .join(' ');

class _FilterBar extends StatelessWidget {
  final String search;

  /// The actions offered by the Action dropdown.
  final List<String> actions;

  final String? actionFilter;
  final ValueChanged<String?> onActionChanged;
  final String? adminFilter;
  final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> adminsFuture;
  final ValueChanged<String?> onAdminChanged;
  final DateTimeRange? dateRange;
  final VoidCallback onPickDateRange;
  final VoidCallback onClear;

  const _FilterBar({
    super.key,
    required this.actions,
    required this.search,
    required this.actionFilter,
    required this.onActionChanged,
    required this.adminFilter,
    required this.adminsFuture,
    required this.onAdminChanged,
    required this.dateRange,
    required this.onPickDateRange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final hasFilters =
        actionFilter != null ||
        adminFilter != null ||
        dateRange != null ||
        search.isNotEmpty;

    return SizedBox(
      child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: adminsFuture,
        builder: (context, snap) {
          final admins = snap.data ?? const [];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminPillDropdown<String?>(
                value: actionFilter,
                width: 210,
                icon: Icons.bolt_outlined,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All actions'),
                  ),
                  for (final a in actions)
                    DropdownMenuItem(
                      value: a,
                      child: Text(auditActionLabel(a)),
                    ),
                ],
                onChanged: onActionChanged,
              ),
              // Only when there is more than one admin to choose between.
              if (admins.length > 1)
                AdminPillDropdown<String?>(
                  value: admins.any((d) => d.id == adminFilter)
                      ? adminFilter
                      : null,
                  width: 210,
                  icon: Icons.person_outline,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All admins'),
                    ),
                    for (final d in admins)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          (d.data()['name'] ??
                                  d.data()['fullName'] ??
                                  d.data()['email'] ??
                                  d.id)
                              .toString(),
                        ),
                      ),
                  ],
                  onChanged: onAdminChanged,
                ),
              OutlinedButton.icon(
                onPressed: onPickDateRange,
                icon: Icon(
                  Icons.date_range_outlined,
                  size: 16,
                  color: c.textPrimary,
                ),
                label: Text(
                  dateRange == null
                      ? 'Date range'
                      : '${DateFormat('MMM d').format(dateRange!.start)} – ${DateFormat('MMM d').format(dateRange!.end)}',
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.border),
                ),
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onClear,
                  icon: Icon(Icons.close, size: 16, color: c.textSecondary),
                  label: Text(
                    'Clear filters',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
