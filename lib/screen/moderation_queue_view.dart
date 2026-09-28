import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/audit_log_service.dart';
import '../services/connectivity_service.dart';
import '../services/market_price_helpers.dart';
import 'admin_dashboard_screen.dart'
    show
        AdminPalette,
        AdminThemeScope,
        AdminStatCard,
        AdminStatusBadge,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminStreamError;

/// Admin Moderation Queue — reviews reports submitted by Buyers/users
/// against a Farmer's listing or a Farmer's account (the existing `reports`
/// collection, populated today by chat_screen.dart's "Report User" flow).
///
/// A report is only an allegation. Nothing here treats a report itself as a
/// violation — only an explicit Admin decision (Warning/Hide/Remove/
/// Suspend/Ban) sets `violationConfirmed: true` on the report and, for
/// account-level actions, `accountStatus` on the reported farmer's
/// users/{uid} doc. Report volume and confirmed-violation count are kept
/// strictly separate (see _FarmerViolationHistory).
enum _ModTab { pending, underReview, resolved, violations }

String? _firstNonEmpty(List<dynamic> candidates) {
  for (final c in candidates) {
    final s = c?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Maps a moderation decision (report['moderationAction'] values) to its
/// Audit Log action — every real decision except 'dismissed', which isn't
/// an action taken against anyone.
String? _auditActionFor(String moderationAction) {
  switch (moderationAction) {
    case 'warning':
      return AuditAction.warnSeller;
    case 'hidden':
      return AuditAction.suspendListing;
    case 'removed':
      return AuditAction.removeListing;
    case 'suspended':
      return AuditAction.suspendFarmer;
    case 'banned':
      return AuditAction.banFarmer;
    default:
      return null;
  }
}

String _formatDate(Timestamp? t) =>
    t != null ? DateFormat('MMM d, y – h:mm a').format(t.toDate()) : '—';

Future<bool> _ensureOnline(BuildContext context) async {
  if (await ConnectivityService.instance.checkNow()) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
  }
  return false;
}

Widget _sectionLabel(String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(
      label,
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey[600], letterSpacing: 0.4),
    ),
  );
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

Widget _accountStatusBadge(AdminPalette c, String status) {
  switch (status) {
    case 'suspended':
      return AdminStatusBadge(text: 'Suspended', color: c.amber, bg: c.amberBg);
    case 'banned':
      return AdminStatusBadge(text: 'Banned', color: c.red, bg: c.redBg);
    default:
      return AdminStatusBadge(text: 'Active', color: c.green, bg: c.greenBg);
  }
}

// ============================================================
// ROW MODEL
// ============================================================

class _ReportRow {
  final String id;
  final Map<String, dynamic> data;
  final String farmerId;
  final String farmerName;
  final String farmerBarangay;
  final String farmerApprovalStatus;
  final String farmerAccountStatus;

  const _ReportRow({
    required this.id,
    required this.data,
    required this.farmerId,
    required this.farmerName,
    required this.farmerBarangay,
    required this.farmerApprovalStatus,
    required this.farmerAccountStatus,
  });

  bool get hasProduct => (data['productId']?.toString().trim().isNotEmpty ?? false);
  String get targetType => (data['targetType'] ?? (hasProduct ? 'listing' : 'farmer')).toString();
  String get targetLabel => hasProduct ? (data['productName'] ?? 'Listing').toString() : farmerName;
  String get reason => (data['issueType'] ?? data['reason'] ?? 'General Report').toString();
  String get description => (data['description'] ?? '').toString();
  String get reporterName => (data['reporterName'] ?? 'Unknown user').toString();
  String get rawStatus => (data['status'] ?? 'pending').toString();
  // 'dismissed' is the legacy value the old admin stub wrote — treated as a
  // resolved outcome for tab/bucket purposes, never rewritten.
  String get bucketStatus => rawStatus == 'dismissed' ? 'resolved' : rawStatus;
  String? get moderationAction => (data['moderationAction'] ?? data['action'])?.toString();
  bool get violationConfirmed => data['violationConfirmed'] == true;
  Timestamp? get createdAt => data['createdAt'] as Timestamp?;
}

String _reportStatusLabel(_ReportRow r) {
  if (r.violationConfirmed) return 'Violation Confirmed';
  switch (r.bucketStatus) {
    case 'pending':
      return 'Pending';
    case 'under_review':
      return 'Under Review';
    case 'resolved':
      return 'Resolved';
    default:
      return _capitalize(r.bucketStatus);
  }
}

Color _reportStatusColor(AdminPalette c, _ReportRow r) {
  if (r.violationConfirmed) return c.red;
  switch (r.bucketStatus) {
    case 'pending':
      return c.amber;
    case 'under_review':
      return c.blue;
    case 'resolved':
      return c.green;
    default:
      return c.textSecondary;
  }
}

Color _reportStatusBg(AdminPalette c, _ReportRow r) {
  if (r.violationConfirmed) return c.redBg;
  switch (r.bucketStatus) {
    case 'pending':
      return c.amberBg;
    case 'under_review':
      return c.blueBg;
    case 'resolved':
      return c.greenBg;
    default:
      return c.surfaceAlt;
  }
}

// ============================================================
// ROOT VIEW
// ============================================================

class ModerationQueueView extends StatefulWidget {
  const ModerationQueueView({super.key});

  @override
  State<ModerationQueueView> createState() => _ModerationQueueViewState();
}

class _ModerationQueueViewState extends State<ModerationQueueView> {
  _ModTab _tab = _ModTab.pending;
  String _search = '';
  String _targetTypeFilter = 'All';
  String _reasonFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Moderation Queue',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text('Review reports against Farmer listings and accounts before any action is taken.',
              style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 20),

          // Two live streams — every report, every user — combined and
          // aggregated client-side, same real-time pattern used across the
          // rest of this dashboard (Verified Farmers/Farmer List, Analytics).
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('reports').snapshots(),
              builder: (context, reportsSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, usersSnap) {
                    final snapshots = [reportsSnap, usersSnap];
                    if (snapshots.any((s) => s.hasError)) return const AdminStreamError();
                    if (snapshots.any((s) => !s.hasData)) return const AdminLoadingSpinner();

                    final usersByUid = <String, Map<String, dynamic>>{
                      for (final d in usersSnap.data!.docs) d.id: d.data(),
                    };

                    final allRows = reportsSnap.data!.docs.map((doc) {
                      final data = doc.data();
                      final farmerId = (data['farmerId'] ?? data['reportedUserId'] ?? '').toString();
                      final farmerUser = usersByUid[farmerId];
                      final farmerName = _firstNonEmpty([
                            farmerUser?['fullName'],
                            farmerUser?['name'],
                            data['reportedUserName'],
                            data['sellerName'],
                          ]) ??
                          'Unknown Farmer';
                      final farmerBarangay = _firstNonEmpty([farmerUser?['barangay']]) ?? '—';
                      final farmerApprovalStatus = (farmerUser?['approvalStatus'] ?? '—').toString();
                      final farmerAccountStatus = (farmerUser?['accountStatus'] ?? 'active').toString();
                      return _ReportRow(
                        id: doc.id,
                        data: data,
                        farmerId: farmerId,
                        farmerName: farmerName,
                        farmerBarangay: farmerBarangay,
                        farmerApprovalStatus: farmerApprovalStatus,
                        farmerAccountStatus: farmerAccountStatus,
                      );
                    }).toList();

                    final pendingCount = allRows.where((r) => r.bucketStatus == 'pending').length;
                    final underReviewCount = allRows.where((r) => r.bucketStatus == 'under_review').length;
                    final resolvedCount = allRows.where((r) => r.bucketStatus == 'resolved').length;
                    final violationsCount = allRows.where((r) => r.violationConfirmed).length;

                    final reasonOptions = {'All', ...allRows.map((r) => r.reason)}.toList()..sort();

                    List<_ReportRow> bucketRows;
                    switch (_tab) {
                      case _ModTab.pending:
                        bucketRows = allRows.where((r) => r.bucketStatus == 'pending').toList();
                        break;
                      case _ModTab.underReview:
                        bucketRows = allRows.where((r) => r.bucketStatus == 'under_review').toList();
                        break;
                      case _ModTab.resolved:
                        bucketRows = allRows.where((r) => r.bucketStatus == 'resolved').toList();
                        break;
                      case _ModTab.violations:
                        bucketRows = allRows.where((r) => r.violationConfirmed).toList();
                        break;
                    }

                    final rows = bucketRows.where((r) {
                      if (_targetTypeFilter != 'All' && r.targetType != _targetTypeFilter.toLowerCase()) {
                        return false;
                      }
                      if (_reasonFilter != 'All' && r.reason != _reasonFilter) return false;
                      final q = _search.trim().toLowerCase();
                      if (q.isEmpty) return true;
                      return r.farmerName.toLowerCase().contains(q) ||
                          r.targetLabel.toLowerCase().contains(q) ||
                          r.id.toLowerCase().contains(q) ||
                          r.reporterName.toLowerCase().contains(q);
                    }).toList()
                      ..sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
                          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(builder: (context, constraints) {
                            // A Wrap (not a fixed-childAspectRatio
                            // GridView) so each card sizes to its own
                            // content height — it can't overflow at any
                            // width — while the column count still reflows
                            // continuously with the available space (see
                            // the same fix on the Dashboard Overview's KPI
                            // row).
                            const spacing = 16.0;
                            final width = constraints.maxWidth;
                            final columns = width >= 900 ? 4 : (width >= 560 ? 2 : 1);
                            final cardWidth = (width - spacing * (columns - 1)) / columns;
                            final cards = [
                              AdminStatCard(
                                label: 'Pending Reports',
                                value: '$pendingCount',
                                delta: 'Awaiting Admin review',
                                icon: Icons.hourglass_empty_rounded,
                                iconColor: (c) => c.amber,
                                iconBg: (c) => c.amberBg,
                                isEmpty: pendingCount == 0,
                              ),
                              AdminStatCard(
                                label: 'Under Review',
                                value: '$underReviewCount',
                                delta: 'Currently being investigated',
                                icon: Icons.search_rounded,
                                iconColor: (c) => c.blue,
                                iconBg: (c) => c.blueBg,
                                isEmpty: underReviewCount == 0,
                              ),
                              AdminStatCard(
                                label: 'Confirmed Violations',
                                value: '$violationsCount',
                                delta: 'Admin-confirmed only',
                                icon: Icons.gavel_rounded,
                                iconColor: (c) => c.red,
                                iconBg: (c) => c.redBg,
                                isEmpty: violationsCount == 0,
                              ),
                              AdminStatCard(
                                label: 'Resolved Reports',
                                value: '$resolvedCount',
                                delta: 'Including dismissed reports',
                                icon: Icons.task_alt_rounded,
                                iconColor: (c) => c.green,
                                iconBg: (c) => c.greenBg,
                                isEmpty: resolvedCount == 0,
                              ),
                            ];
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                for (final card in cards) SizedBox(width: cardWidth, child: card),
                              ],
                            );
                          }),
                          const SizedBox(height: 20),

                          _ModTabBar(
                            c: c,
                            tab: _tab,
                            onChanged: (t) => setState(() => _tab = t),
                            pendingCount: pendingCount,
                            underReviewCount: underReviewCount,
                            resolvedCount: resolvedCount,
                            violationsCount: violationsCount,
                          ),
                          const SizedBox(height: 16),

                          if (_tab != _ModTab.violations) ...[
                            _ReportFilterBar(
                              c: c,
                              search: _search,
                              onSearchChanged: (v) => setState(() => _search = v),
                              targetTypeFilter: _targetTypeFilter,
                              onTargetTypeChanged: (v) => setState(() => _targetTypeFilter = v),
                              reasonOptions: reasonOptions,
                              reasonFilter: _reasonFilter,
                              onReasonChanged: (v) => setState(() => _reasonFilter = v),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_tab == _ModTab.violations)
                            _buildViolationsSection(c, allRows)
                          else if (bucketRows.isEmpty)
                            AdminEmptyState(
                              icon: Icons.fact_check_outlined,
                              title: _emptyTitleFor(_tab),
                              subtitle: _emptySubtitleFor(_tab),
                            )
                          else if (rows.isEmpty)
                            AdminEmptyState(
                              icon: Icons.search_off,
                              title: 'No matches for the current search/filters.',
                              subtitle: 'Try clearing the search or filters above.',
                            )
                          else
                            _ReportTable(c: c, rows: rows),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _emptyTitleFor(_ModTab tab) {
    switch (tab) {
      case _ModTab.pending:
        return 'No pending reports.';
      case _ModTab.underReview:
        return 'No reports under review.';
      case _ModTab.resolved:
        return 'No resolved reports yet.';
      case _ModTab.violations:
        return 'No confirmed violations.';
    }
  }

  String _emptySubtitleFor(_ModTab tab) {
    switch (tab) {
      case _ModTab.pending:
        return 'New reports from Buyers/users will appear here.';
      case _ModTab.underReview:
        return 'Reports an Admin has started investigating will appear here.';
      case _ModTab.resolved:
        return 'Dismissed and completed reports will appear here.';
      case _ModTab.violations:
        return 'Farmers/listings with an Admin-confirmed violation will appear here.';
    }
  }

  Widget _buildViolationsSection(AdminPalette c, List<_ReportRow> allRows) {
    final confirmed = allRows.where((r) => r.violationConfirmed).toList();
    if (confirmed.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.verified_outlined,
        title: 'No confirmed violations.',
        subtitle: 'Farmers/listings with an Admin-confirmed violation will appear here.',
      );
    }

    final byFarmer = <String, List<_ReportRow>>{};
    for (final r in confirmed) {
      if (r.farmerId.isEmpty) continue;
      byFarmer.putIfAbsent(r.farmerId, () => []).add(r);
    }

    final summaries = byFarmer.entries.map((e) {
      final reports = [...e.value]
        ..sort((a, b) =>
            (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      final latest = reports.first;
      return _ViolationSummary(
        farmerId: e.key,
        farmerName: latest.farmerName,
        accountStatus: latest.farmerAccountStatus,
        confirmedCount: reports.length,
        lastViolation: latest.createdAt,
        lastAction: latest.moderationAction,
      );
    }).toList()
      ..sort((a, b) =>
          (b.lastViolation?.millisecondsSinceEpoch ?? 0).compareTo(a.lastViolation?.millisecondsSinceEpoch ?? 0));

    return _ViolationsTable(c: c, rows: summaries);
  }
}

// ============================================================
// TAB BAR
// ============================================================

class _ModTabBar extends StatelessWidget {
  final AdminPalette c;
  final _ModTab tab;
  final ValueChanged<_ModTab> onChanged;
  final int pendingCount;
  final int underReviewCount;
  final int resolvedCount;
  final int violationsCount;

  const _ModTabBar({
    required this.c,
    required this.tab,
    required this.onChanged,
    required this.pendingCount,
    required this.underReviewCount,
    required this.resolvedCount,
    required this.violationsCount,
  });

  @override
  Widget build(BuildContext context) {
    Widget tabButton(_ModTab t, String label, int count) {
      final selected = t == tab;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? c.greenBg : c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(t),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                '$label ($count)',
                style: TextStyle(
                  color: selected ? c.green : c.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      children: [
        tabButton(_ModTab.pending, 'Pending', pendingCount),
        tabButton(_ModTab.underReview, 'Under Review', underReviewCount),
        tabButton(_ModTab.resolved, 'Resolved', resolvedCount),
        tabButton(_ModTab.violations, 'Violations', violationsCount),
      ],
    );
  }
}

// ============================================================
// FILTER BAR
// ============================================================

class _ReportFilterBar extends StatelessWidget {
  final AdminPalette c;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final String targetTypeFilter;
  final ValueChanged<String> onTargetTypeChanged;
  final List<String> reasonOptions;
  final String reasonFilter;
  final ValueChanged<String> onReasonChanged;

  const _ReportFilterBar({
    required this.c,
    required this.search,
    required this.onSearchChanged,
    required this.targetTypeFilter,
    required this.onTargetTypeChanged,
    required this.reasonOptions,
    required this.reasonFilter,
    required this.onReasonChanged,
  });

  InputDecoration _fieldDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: c.textSecondary),
      filled: true,
      fillColor: c.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fieldStyle = TextStyle(color: c.textPrimary, fontSize: 13);
    final validReason = reasonOptions.contains(reasonFilter) ? reasonFilter : 'All';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            style: fieldStyle,
            decoration: _fieldDecoration('Search farmer, listing, report ID, reporter…', Icons.search),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            initialValue: targetTypeFilter,
            style: fieldStyle,
            dropdownColor: c.surface,
            decoration: _fieldDecoration('Target Type', Icons.category_outlined),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'Listing', child: Text('Listing')),
              DropdownMenuItem(value: 'Farmer', child: Text('Farmer')),
            ],
            onChanged: (v) => v != null ? onTargetTypeChanged(v) : null,
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: validReason,
            style: fieldStyle,
            dropdownColor: c.surface,
            decoration: _fieldDecoration('Reason', Icons.report_gmailerrorred_outlined),
            items: reasonOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (v) => v != null ? onReasonChanged(v) : null,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// REPORT TABLE
// ============================================================

class _ReportTable extends StatelessWidget {
  final AdminPalette c;
  final List<_ReportRow> rows;
  const _ReportTable({required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(c.surfaceAlt),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          columnSpacing: 28,
          horizontalMargin: 12,
          headingTextStyle: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
          columns: const [
            DataColumn(label: Text('Report ID')),
            DataColumn(label: Text('Reported Target')),
            DataColumn(label: Text('Target Type')),
            DataColumn(label: Text('Reported Farmer')),
            DataColumn(label: Text('Reason')),
            DataColumn(label: Text('Reported By')),
            DataColumn(label: Text('Date Reported')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Action')),
          ],
          rows: rows.map((r) {
            return DataRow(cells: [
              DataCell(Text(_shortId(r.id))),
              DataCell(Text(r.targetLabel)),
              DataCell(Text(_capitalize(r.targetType))),
              DataCell(Text(r.farmerName)),
              DataCell(Text(r.reason)),
              DataCell(Text(r.reporterName)),
              DataCell(Text(_formatDate(r.createdAt))),
              DataCell(AdminStatusBadge(
                  text: _reportStatusLabel(r), color: _reportStatusColor(c, r), bg: _reportStatusBg(c, r))),
              DataCell(TextButton.icon(
                icon: Icon(Icons.visibility_outlined, size: 16, color: c.green),
                label: Text('View Report', style: TextStyle(color: c.green, fontSize: 12.5)),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ReportDetailDialog(reportId: r.id),
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ============================================================
// VIOLATIONS TAB
// ============================================================

class _ViolationSummary {
  final String farmerId;
  final String farmerName;
  final String accountStatus;
  final int confirmedCount;
  final Timestamp? lastViolation;
  final String? lastAction;
  const _ViolationSummary({
    required this.farmerId,
    required this.farmerName,
    required this.accountStatus,
    required this.confirmedCount,
    required this.lastViolation,
    required this.lastAction,
  });
}

class _ViolationsTable extends StatelessWidget {
  final AdminPalette c;
  final List<_ViolationSummary> rows;
  const _ViolationsTable({required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(c.surfaceAlt),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          columnSpacing: 28,
          horizontalMargin: 12,
          headingTextStyle: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
          columns: const [
            DataColumn(label: Text('Farmer ID')),
            DataColumn(label: Text('Farmer Name')),
            DataColumn(label: Text('Confirmed Violations'), numeric: true),
            DataColumn(label: Text('Last Violation')),
            DataColumn(label: Text('Current Account Status')),
            DataColumn(label: Text('Last Admin Action')),
            DataColumn(label: Text('View History')),
          ],
          rows: rows.map((r) {
            return DataRow(cells: [
              DataCell(Text(_shortId(r.farmerId))),
              DataCell(Text(r.farmerName)),
              DataCell(Text('${r.confirmedCount}')),
              DataCell(Text(_formatDate(r.lastViolation))),
              DataCell(_accountStatusBadge(c, r.accountStatus)),
              DataCell(Text(r.lastAction != null ? _capitalize(r.lastAction!) : '—')),
              DataCell(TextButton.icon(
                icon: Icon(Icons.history, size: 16, color: c.green),
                label: Text('View History', style: TextStyle(color: c.green, fontSize: 12.5)),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _FarmerViolationHistoryDialog(farmerId: r.farmerId, farmerName: r.farmerName),
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ============================================================
// FARMER VIOLATION HISTORY (used by both the Violations tab and
// the "Violation History" section of the report detail dialog)
// ============================================================

class _FarmerViolationHistory {
  final int confirmedViolations;
  final int warnings;
  final int suspensions;
  final List<_ReportRow> relatedReports;
  const _FarmerViolationHistory({
    required this.confirmedViolations,
    required this.warnings,
    required this.suspensions,
    required this.relatedReports,
  });
}

/// One-shot fetch — queries both `farmerId` (the canonical field going
/// forward) and the legacy `reportedUserId` (older chat reports predating
/// that field) so history is complete regardless of when a report was
/// filed, then de-dupes by report id.
Future<_FarmerViolationHistory> _loadFarmerViolationHistory(String farmerId) async {
  if (farmerId.isEmpty) {
    return const _FarmerViolationHistory(confirmedViolations: 0, warnings: 0, suspensions: 0, relatedReports: []);
  }

  final byFarmerId =
      await FirebaseFirestore.instance.collection('reports').where('farmerId', isEqualTo: farmerId).get();
  final byReportedUserId =
      await FirebaseFirestore.instance.collection('reports').where('reportedUserId', isEqualTo: farmerId).get();

  final seen = <String>{};
  final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final d in [...byFarmerId.docs, ...byReportedUserId.docs]) {
    if (seen.add(d.id)) docs.add(d);
  }

  docs.sort((a, b) {
    final at = a.data()['createdAt'] as Timestamp?;
    final bt = b.data()['createdAt'] as Timestamp?;
    return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
  });

  var confirmed = 0, warnings = 0, suspensions = 0;
  for (final d in docs) {
    final data = d.data();
    if (data['violationConfirmed'] == true) confirmed++;
    final action = (data['moderationAction'] ?? data['action'])?.toString();
    if (action == 'warning') warnings++;
    if (action == 'suspended') suspensions++;
  }

  return _FarmerViolationHistory(
    confirmedViolations: confirmed,
    warnings: warnings,
    suspensions: suspensions,
    relatedReports: docs
        .map((d) => _ReportRow(
              id: d.id,
              data: d.data(),
              farmerId: farmerId,
              farmerName: '',
              farmerBarangay: '—',
              farmerApprovalStatus: '—',
              farmerAccountStatus: '—',
            ))
        .take(10)
        .toList(),
  );
}

class _FarmerViolationHistoryDialog extends StatelessWidget {
  final String farmerId;
  final String farmerName;
  const _FarmerViolationHistoryDialog({required this.farmerId, required this.farmerName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FarmerViolationHistory>(
      future: _loadFarmerViolationHistory(farmerId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AlertDialog(
            content: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return AlertDialog(
            title: const Text('Something went wrong'),
            content: const Text('Could not load violation history. Please try again.'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
          );
        }
        final h = snap.data!;
        return AlertDialog(
          title: Text('$farmerName — Violation History'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Confirmed Violations', '${h.confirmedViolations}'),
                  _detailRow('Warnings Issued', '${h.warnings}'),
                  _detailRow('Suspensions', '${h.suspensions}'),
                  const SizedBox(height: 10),
                  _sectionLabel('Related Reports'),
                  if (h.relatedReports.isEmpty)
                    Text('No related reports.', style: TextStyle(color: Colors.grey[600], fontSize: 12.5))
                  else
                    ...h.relatedReports.map((r) {
                      final action = r.moderationAction != null ? _capitalize(r.moderationAction!) : 'No decision yet';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${_shortId(r.id)}  •  ${r.reason}  •  ${_reportStatusLabel(r)}  •  $action  •  ${_formatDate(r.createdAt)}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        );
      },
    );
  }
}

// ============================================================
// REPORT DETAIL DIALOG — the review + decision workflow
// ============================================================

class _ReportDetailDialog extends StatefulWidget {
  final String reportId;
  const _ReportDetailDialog({required this.reportId});

  @override
  State<_ReportDetailDialog> createState() => _ReportDetailDialogState();
}

class _ReportDetailDialogState extends State<_ReportDetailDialog> {
  bool _claimAttempted = false;
  bool _busy = false;

  /// "Admin opens report -> Under Review" (workflow spec): the first time
  /// this dialog sees a still-pending report, it claims it once. Guarded by
  /// _claimAttempted so a rebuild (e.g. the report doc's own stream ticking)
  /// never re-fires the write.
  void _claimIfPending(Map<String, dynamic> report) {
    if (_claimAttempted) return;
    _claimAttempted = true;
    if ((report['status'] ?? 'pending') != 'pending') return;
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final reportRef = FirebaseFirestore.instance.collection('reports').doc(widget.reportId);
    reportRef.update({
      'status': 'under_review',
      'reviewedBy': adminUid,
      'reviewedAt': FieldValue.serverTimestamp(),
    }).then((_) {
      reportRef.collection('history').add({
        'action': 'under_review',
        'adminId': adminUid,
        'reason': null,
        'notes': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }).catchError((_) {});
  }

  Future<void> _runAction({
    required Map<String, dynamic> report,
    required String action,
    required bool violationConfirmed,
    required String reason,
    required String notes,
    String? severity,
  }) async {
    if (_busy) return;
    if (!await _ensureOnline(context)) return;
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      final farmerId = (report['farmerId'] ?? report['reportedUserId'] ?? '').toString();
      final productId = report['productId']?.toString();

      final batch = FirebaseFirestore.instance.batch();
      final reportRef = FirebaseFirestore.instance.collection('reports').doc(widget.reportId);
      batch.update(reportRef, {
        'status': 'resolved',
        'moderationAction': action,
        'violationConfirmed': violationConfirmed,
        'violationSeverity': ?severity,
        'adminNotes': notes,
        'reviewedBy': adminUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // Hide/Remove both map to the existing isSuspended gate — already
      // respected by every buyer-facing query (marketplace listing, order
      // placement) — no new visibility field needed.
      if ((action == 'hidden' || action == 'removed') && productId != null && productId.isNotEmpty) {
        batch.update(FirebaseFirestore.instance.collection('products').doc(productId), {'isSuspended': true});
      }
      if (action == 'suspended' && farmerId.isNotEmpty) {
        batch.update(FirebaseFirestore.instance.collection('users').doc(farmerId), {
          'accountStatus': 'suspended',
          'suspensionReason': reason,
          'moderationUpdatedBy': adminUid,
          'moderationUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (action == 'banned' && farmerId.isNotEmpty) {
        batch.update(FirebaseFirestore.instance.collection('users').doc(farmerId), {
          'accountStatus': 'banned',
          'banReason': reason,
          'moderationUpdatedBy': adminUid,
          'moderationUpdatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      // Append-only audit trail — never overwrites a previous entry.
      await reportRef.collection('history').add({
        'action': action,
        'adminId': adminUid,
        'reason': reason,
        'notes': notes,
        'severity': ?severity,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final auditAction = _auditActionFor(action);
      if (auditAction != null) {
        final who = _firstNonEmpty([report['reportedUserName'], report['sellerName']]) ??
            (farmerId.isEmpty ? 'Unknown seller' : 'farmer $farmerId');
        final productName = report['productName']?.toString();
        final target = productName != null && productName.isNotEmpty ? '"$productName" ($who)' : who;
        AuditLogService.log(
          auditAction,
          '${_capitalize(action)}: $target.${reason.isNotEmpty ? ' Reason: $reason' : ''}',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report updated: ${_capitalize(action)}.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _reactivateFarmer(String farmerId) async {
    if (_busy) return;
    if (!await _ensureOnline(context)) return;
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('users').doc(farmerId).update({
        'accountStatus': 'active',
        'suspensionReason': FieldValue.delete(),
        'suspendedUntil': FieldValue.delete(),
        'banReason': FieldValue.delete(),
        'moderationUpdatedBy': adminUid,
        'moderationUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Farmer account reactivated.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _openActionDialog({
    required Map<String, dynamic> report,
    required String title,
    required String actionLabel,
    required Color actionColor,
    required String action,
    required bool violationConfirmed,
    bool requireReason = true,
    List<String>? severityOptions,
    String? defaultSeverity,
  }) async {
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    String? severity = defaultSeverity;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: requireReason ? 'Reason (required)' : 'Reason (optional)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Admin notes (internal, optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (severityOptions != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: severity,
                      decoration: const InputDecoration(labelText: 'Violation severity', border: OutlineInputBorder()),
                      items: severityOptions
                          .map((s) => DropdownMenuItem(value: s, child: Text(_capitalize(s))))
                          .toList(),
                      onChanged: (v) => setDialogState(() => severity = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: actionColor, foregroundColor: Colors.white),
              onPressed: () {
                if (requireReason && reasonController.text.trim().isEmpty) return;
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    await _runAction(
      report: report,
      action: action,
      violationConfirmed: violationConfirmed,
      reason: reasonController.text.trim(),
      notes: notesController.text.trim(),
      severity: severity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('reports').doc(widget.reportId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return AlertDialog(
            title: const Text('Something went wrong'),
            content: const Text('Could not load this report. Please try again.'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
          );
        }
        if (!snap.hasData) {
          return const AlertDialog(
            content: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          );
        }
        final report = snap.data!.data();
        if (report == null) {
          return AlertDialog(
            title: const Text('Report Not Found'),
            content: const Text('This report could not be found. It may have been removed.'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => _claimIfPending(report));

        final hasProduct = (report['productId']?.toString().trim().isNotEmpty ?? false);
        final targetType = (report['targetType'] ?? (hasProduct ? 'listing' : 'farmer')).toString();
        final farmerId = (report['farmerId'] ?? report['reportedUserId'] ?? '').toString();
        final productId = report['productId']?.toString();
        final rawStatus = (report['status'] ?? 'pending').toString();
        final bucketStatus = rawStatus == 'dismissed' ? 'resolved' : rawStatus;
        final isResolved = bucketStatus == 'resolved';
        final reason = (report['issueType'] ?? report['reason'] ?? 'General Report').toString();
        final description = (report['description'] ?? '').toString();
        final createdAt = report['createdAt'] as Timestamp?;
        final reporterName = (report['reporterName'] ?? 'Unknown user').toString();
        final reporterId = (report['reporterId'] ?? '—').toString();
        final moderationAction = (report['moderationAction'] ?? report['action'])?.toString();
        final adminNotes = (report['adminNotes'] ?? '').toString();
        final violationConfirmed = report['violationConfirmed'] == true;

        return AlertDialog(
          title: const Text('Moderation Review'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Report Information'),
                  _detailRow('Report ID', _shortId(widget.reportId)),
                  _detailRow('Target Type', _capitalize(targetType)),
                  _detailRow('Date Reported', _formatDate(createdAt)),
                  _detailRow('Reason', reason),
                  if (description.isNotEmpty) _detailRow('Description', description),
                  _detailRow('Current Status',
                      violationConfirmed ? 'Violation Confirmed' : _capitalize(bucketStatus)),
                  if (moderationAction != null) _detailRow('Admin Action Taken', _capitalize(moderationAction)),
                  if (adminNotes.isNotEmpty) _detailRow('Admin Notes', adminNotes),
                  const SizedBox(height: 10),

                  _sectionLabel('Reporter Information'),
                  _detailRow('Reporter Name', reporterName),
                  _detailRow('Reporter ID', _shortId(reporterId)),
                  const SizedBox(height: 10),

                  _sectionLabel('Reported Farmer'),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future:
                        farmerId.isEmpty ? null : FirebaseFirestore.instance.collection('users').doc(farmerId).get(),
                    builder: (context, farmerSnap) {
                      if (farmerId.isEmpty) {
                        return Text('No farmer on record for this report.',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12.5));
                      }
                      if (farmerSnap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      final farmer = farmerSnap.data?.data();
                      if (farmer == null) {
                        return Text('Farmer account not found.',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12.5));
                      }
                      final name = _firstNonEmpty([farmer['fullName'], farmer['name']]) ?? 'Unknown Farmer';
                      final barangay = _firstNonEmpty([farmer['barangay']]) ?? '—';
                      final approvalStatus = (farmer['approvalStatus'] ?? '—').toString();
                      final accountStatus = (farmer['accountStatus'] ?? 'active').toString();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('Farmer Name', name),
                          _detailRow('Farmer ID', _shortId(farmerId)),
                          _detailRow('Barangay', barangay),
                          _detailRow('Approval Status', approvalStatus.isEmpty ? '—' : _capitalize(approvalStatus)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: Text('Account Status',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                ),
                                _accountStatusBadge(AdminThemeScope.of(context).palette, accountStatus),
                              ],
                            ),
                          ),
                          if (accountStatus != 'active') ...[
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.restart_alt, size: 16),
                              label: const Text('Reactivate Account'),
                              onPressed: _busy ? null : () => _reactivateFarmer(farmerId),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  if (targetType == 'listing') ...[
                    _sectionLabel('Reported Listing'),
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: (productId == null || productId.isEmpty)
                          ? null
                          : FirebaseFirestore.instance.collection('products').doc(productId).get(),
                      builder: (context, productSnap) {
                        if (productId == null || productId.isEmpty) {
                          return Text('No listing on record for this report.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12.5));
                        }
                        if (productSnap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final product = productSnap.data?.data();
                        if (product == null) {
                          return Text('This listing no longer exists.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12.5));
                        }
                        final name = (product['name'] ?? '—').toString();
                        final category = (product['category'] ?? '—').toString();
                        final desc = (product['description'] ?? '—').toString();
                        final price = product['price'];
                        final qty = product['quantity'];
                        final imageUrls = product['imageUrls'];
                        final imageUrl = _firstNonEmpty([
                          product['imageUrl'],
                          (imageUrls is List && imageUrls.isNotEmpty) ? imageUrls.first?.toString() : null,
                        ]);
                        final isArchived = product['isArchived'] == true;
                        final isSuspended = product['isSuspended'] == true;
                        final listingStatus = isSuspended ? 'Suspended' : (isArchived ? 'Archived' : 'Active');

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (imageUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  width: 120,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            _detailRow('Product Name', name),
                            _detailRow('Category', category),
                            _detailRow('Description', desc),
                            _detailRow('Price',
                                price != null ? formatPeso(price is num ? price : num.tryParse('$price') ?? 0) : '—'),
                            _detailRow('Quantity', qty?.toString() ?? '—'),
                            _detailRow('Listing Status', listingStatus),
                            _detailRow('Listing Owner', _shortId(farmerId)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  _sectionLabel('Violation History'),
                  FutureBuilder<_FarmerViolationHistory>(
                    future: _loadFarmerViolationHistory(farmerId),
                    builder: (context, histSnap) {
                      if (histSnap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (histSnap.hasError || !histSnap.hasData) {
                        return Text('Could not load violation history.',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12.5));
                      }
                      final h = histSnap.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('Previous Confirmed Violations', '${h.confirmedViolations}'),
                          _detailRow('Previous Warnings', '${h.warnings}'),
                          _detailRow('Previous Suspensions', '${h.suspensions}'),
                          _detailRow('Related Reports', '${h.relatedReports.length}'),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: isResolved
              ? [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))]
              : [
                  TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _openActionDialog(
                              report: report,
                              title: 'Dismiss this report?',
                              actionLabel: 'Dismiss',
                              actionColor: Colors.grey,
                              action: 'dismissed',
                              violationConfirmed: false,
                              requireReason: false,
                            ),
                    child: const Text('Dismiss Report'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    onPressed: _busy
                        ? null
                        : () => _openActionDialog(
                              report: report,
                              title: 'Issue a warning?',
                              actionLabel: 'Issue Warning',
                              actionColor: Colors.orange,
                              action: 'warning',
                              violationConfirmed: true,
                              severityOptions: const ['minor', 'moderate'],
                              defaultSeverity: 'minor',
                            ),
                    child: const Text('Issue Warning'),
                  ),
                  if (targetType == 'listing') ...[
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.blueGrey),
                      onPressed: _busy
                          ? null
                          : () => _openActionDialog(
                                report: report,
                                title: 'Hide this listing?',
                                actionLabel: 'Hide Listing',
                                actionColor: Colors.blueGrey,
                                action: 'hidden',
                                violationConfirmed: true,
                                severityOptions: const ['minor', 'moderate'],
                                defaultSeverity: 'minor',
                              ),
                      child: const Text('Hide Listing'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: _busy
                          ? null
                          : () => _openActionDialog(
                                report: report,
                                title: 'Remove this listing?',
                                actionLabel: 'Remove Listing',
                                actionColor: Colors.red,
                                action: 'removed',
                                violationConfirmed: true,
                                severityOptions: const ['moderate', 'serious'],
                                defaultSeverity: 'moderate',
                              ),
                      child: const Text('Remove Listing'),
                    ),
                  ] else ...[
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrange),
                      onPressed: _busy
                          ? null
                          : () => _openActionDialog(
                                report: report,
                                title: 'Temporarily suspend this Farmer?',
                                actionLabel: 'Suspend',
                                actionColor: Colors.deepOrange,
                                action: 'suspended',
                                violationConfirmed: true,
                                severityOptions: const ['serious'],
                                defaultSeverity: 'serious',
                              ),
                      child: const Text('Temporary Suspension'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: _busy
                          ? null
                          : () => _openActionDialog(
                                report: report,
                                title: 'Permanently deactivate this Farmer account?',
                                actionLabel: 'Ban / Deactivate',
                                actionColor: Colors.red,
                                action: 'banned',
                                violationConfirmed: true,
                                severityOptions: const ['critical'],
                                defaultSeverity: 'critical',
                              ),
                      child: const Text('Permanent Ban / Deactivate'),
                    ),
                  ],
                ],
        );
      },
    );
  }
}
