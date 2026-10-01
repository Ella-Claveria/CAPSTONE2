import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/audit_log_service.dart';
import '../services/pdf_report_service.dart';
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
  final String ip;
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
        browser = ((doc.data()['device'] as Map?)?['browser'] ?? 'Unknown').toString(),
        os = ((doc.data()['device'] as Map?)?['os'] ?? 'Unknown').toString(),
        ip = (doc.data()['ip'] ?? 'Unknown').toString(),
        location = (doc.data()['location'] ?? 'Unknown').toString(),
        timestamp = (doc.data()['timestamp'] as Timestamp?)?.toDate();

  // No confirmed admin identity for a pre-auth entry (a failed login or a
  // password-reset request) — only the email that was typed, which is why
  // it's labeled "Attempt:" instead of shown as if it were verified.
  String get who => adminName ?? adminEmail ?? (attemptedEmail != null ? 'Attempt: $attemptedEmail' : 'Unknown');

  String get device => '$browser on $os';

  String get whenLabel => timestamp != null ? DateFormat('MMM d, y – h:mm a').format(timestamp!) : 'Just now';

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

class _AuditLogViewState extends State<AuditLogView> {
  final List<_AuditEntry> _entries = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  bool _loadError = false;

  String? _actionFilter;
  String? _adminFilter; // admin uid
  DateTimeRange? _dateRange;
  String _search = '';

  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _adminsFuture = FirebaseFirestore
      .instance
      .collection('users')
      .where('role', isEqualTo: 'admin')
      .get()
      .then((s) => s.docs);

  @override
  void initState() {
    super.initState();
    _fetchPage(reset: true);
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('audit_logs');
    // Only one equality filter goes server-side at a time — Firestore needs
    // a distinct composite index per combination of equality/range fields,
    // and indexing every admin-x-action pairing doesn't scale. Action wins
    // when both are set; the admin filter is then applied client-side in
    // _fetchPage below (see needsClientAdminFilter there).
    if (_actionFilter != null) {
      q = q.where('action', isEqualTo: _actionFilter);
    } else if (_adminFilter != null) {
      q = q.where('adminId', isEqualTo: _adminFilter);
    }
    if (_dateRange != null) {
      final end = _dateRange!.end;
      q = q
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange!.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(DateTime(end.year, end.month, end.day, 23, 59, 59)));
    }
    return q.orderBy('timestamp', descending: true);
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;

    setState(() {
      _loading = true;
      if (reset) {
        _entries.clear();
        _cursor = null;
        _hasMore = true;
        _loadError = false;
      }
    });

    final needsClientAdminFilter = _actionFilter != null && _adminFilter != null;

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
        final snap = await query.get();

        if (snap.docs.isEmpty) {
          _hasMore = false;
          break;
        }
        _cursor = snap.docs.last;
        if (snap.docs.length < _pageSize) _hasMore = false;

        for (final doc in snap.docs) {
          if (needsClientAdminFilter && doc.data()['adminId'] != _adminFilter) continue;
          _entries.add(_AuditEntry.fromDoc(doc));
          collected++;
        }
      }
    } catch (_) {
      if (_entries.isEmpty) _loadError = true;
    }

    if (mounted) setState(() => _loading = false);
  }

  List<_AuditEntry> get _visibleEntries {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries
        .where((e) =>
            e.who.toLowerCase().contains(q) ||
            e.actionLabel.toLowerCase().contains(q) ||
            e.details.toLowerCase().contains(q))
        .toList();
  }

  void _clearFilters() {
    setState(() {
      _actionFilter = null;
      _adminFilter = null;
      _dateRange = null;
      _search = '';
    });
    _fetchPage(reset: true);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    _fetchPage(reset: true);
  }

  Future<void> _export() async {
    final rows = _visibleEntries
        .map((e) => (
              when: e.whenLabel,
              admin: e.who,
              action: e.actionLabel,
              details: e.details,
              device: e.device,
              location: '${e.ip} • ${e.location}',
            ))
        .toList();
    final bytes = await PdfReportService.buildAuditLogReport(entries: rows);
    if (!mounted) return;
    await PdfReportService.share(bytes, 'agritrade_audit_log.pdf');
    AuditLogService.log(AuditAction.exportReport, 'Exported the Audit Log (${rows.length} entries).');
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audit Log',
                      style: TextStyle(color: c.textPrimary, fontSize: 30, height: 1.15, letterSpacing: -0.6, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Every admin login and action on this portal — append-only, cannot be edited.',
                      style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5)),
                ],
              ),
              AdminQuickActionButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Export Report',
                onPressed: entries.isEmpty ? () {} : _export,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _FilterBar(
            search: _search,
            onSearchChanged: (v) => setState(() => _search = v),
            actionFilter: _actionFilter,
            onActionChanged: (v) {
              setState(() => _actionFilter = v);
              _fetchPage(reset: true);
            },
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
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadError)
                  const AdminStreamError()
                else if (entries.isEmpty && !_loading)
                  AdminEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: _search.isNotEmpty || _actionFilter != null || _adminFilter != null || _dateRange != null
                        ? 'No entries match these filters'
                        : 'No audit log entries yet',
                    subtitle: _search.isNotEmpty || _actionFilter != null || _adminFilter != null || _dateRange != null
                        ? 'Try clearing a filter or loading more entries.'
                        : 'Admin logins and actions will appear here as they happen.',
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(c.surfaceAlt),
                      dataRowColor: WidgetStateProperty.all(Colors.transparent),
                      columnSpacing: 32,
                      horizontalMargin: 12,
                      headingTextStyle: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
                      columns: const [
                        DataColumn(label: Text('Date & Time')),
                        DataColumn(label: Text('Admin')),
                        DataColumn(label: Text('Action')),
                        DataColumn(label: Text('Details')),
                        DataColumn(label: Text('Device/Browser')),
                        DataColumn(label: Text('Location/IP')),
                      ],
                      rows: entries.map((e) {
                        final (color, bg) = _badgeColors(c, e.action);
                        return DataRow(cells: [
                          DataCell(Text(e.whenLabel)),
                          DataCell(SizedBox(width: 160, child: Text(e.who, overflow: TextOverflow.ellipsis))),
                          DataCell(AdminStatusBadge(text: e.actionLabel, color: color, bg: bg)),
                          DataCell(SizedBox(
                            width: 260,
                            child: Tooltip(
                              message: e.details,
                              child: Text(e.details, overflow: TextOverflow.ellipsis, maxLines: 1),
                            ),
                          )),
                          DataCell(Text(e.device)),
                          DataCell(Text('${e.ip} • ${e.location}')),
                        ]);
                      }).toList(),
                    ),
                  ),
                if (_loading)
                  const AdminLoadingSpinner()
                else if (_hasMore && !_loadError && entries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: () => _fetchPage(),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: c.border)),
                        child: const Text('Load more'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final String? actionFilter;
  final ValueChanged<String?> onActionChanged;
  final String? adminFilter;
  final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> adminsFuture;
  final ValueChanged<String?> onAdminChanged;
  final DateTimeRange? dateRange;
  final VoidCallback onPickDateRange;
  final VoidCallback onClear;

  const _FilterBar({
    required this.search,
    required this.onSearchChanged,
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
    final hasFilters = actionFilter != null || adminFilter != null || dateRange != null || search.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
              borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              onChanged: onSearchChanged,
              style: TextStyle(color: c.textPrimary, fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search loaded entries…',
                hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: c.textMuted, size: 18),
                filled: true,
                fillColor: c.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: actionFilter,
              isExpanded: true,
              decoration: _dropdownDecoration(c, 'Action'),
              style: TextStyle(color: c.textPrimary, fontSize: 13),
              dropdownColor: c.surface,
              items: [
                const DropdownMenuItem(value: null, child: Text('All actions')),
                ...AuditAction.all.map((a) => DropdownMenuItem(
                      value: a,
                      child: Text(
                        a.split('_').map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}').join(' '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: onActionChanged,
            ),
          ),
          SizedBox(
            width: 190,
            child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              future: adminsFuture,
              builder: (context, snap) {
                final admins = snap.data ?? const [];
                return DropdownButtonFormField<String>(
                  initialValue: adminFilter,
                  isExpanded: true,
                  decoration: _dropdownDecoration(c, 'Admin'),
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  dropdownColor: c.surface,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All admins')),
                    ...admins.map((d) {
                      final data = d.data();
                      final label = (data['name'] ?? data['fullName'] ?? data['email'] ?? d.id).toString();
                      return DropdownMenuItem(value: d.id, child: Text(label, overflow: TextOverflow.ellipsis));
                    }),
                  ],
                  onChanged: onAdminChanged,
                );
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickDateRange,
            icon: Icon(Icons.date_range_outlined, size: 16, color: c.textPrimary),
            label: Text(
              dateRange == null
                  ? 'Date range'
                  : '${DateFormat('MMM d').format(dateRange!.start)} – ${DateFormat('MMM d').format(dateRange!.end)}',
              style: TextStyle(color: c.textPrimary, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(side: BorderSide(color: c.border)),
          ),
          if (hasFilters)
            TextButton.icon(
              onPressed: onClear,
              icon: Icon(Icons.close, size: 16, color: c.textSecondary),
              label: Text('Clear filters', style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  InputDecoration _dropdownDecoration(AdminPalette c, String label) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: TextStyle(color: c.textMuted, fontSize: 12),
      filled: true,
      fillColor: c.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}
