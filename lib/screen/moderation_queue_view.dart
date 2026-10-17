import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../data/report_reasons.dart';
import 'admin_sub_nav.dart';
import '../services/admin_perf.dart';
import '../services/rsba_number.dart';
import 'admin_filter_controls.dart';
import '../services/audit_log_service.dart';
import '../services/connectivity_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/market_price_helpers.dart';
import '../services/moderation_model.dart';
import 'admin_account_dialog.dart';
import 'admin_user_accounts_view.dart' show maskEmail;
import 'admin_dashboard_screen.dart'
    show
        AdminPalette,
        AdminThemeScope,
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

String? _firstNonEmpty(List<dynamic> candidates) {
  for (final c in candidates) {
    final s = c?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

String _capitalize(String s) => s.isEmpty
    ? s
    : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Maps a moderation decision (report['moderationAction'] values) to its
/// Audit Log action. Suspending or banning a farmer keeps its own action;
/// the same decision on a buyer is logged as an account action.
String? _auditActionFor(String moderationAction, {required bool farmer}) {
  switch (moderationAction) {
    case 'warning':
      return AuditAction.warnSeller;
    case 'hidden':
      return AuditAction.suspendListing;
    case 'removed':
      return AuditAction.removeListing;
    case 'suspended':
      return farmer ? AuditAction.suspendFarmer : AuditAction.suspendAccount;
    case 'banned':
      return farmer ? AuditAction.banFarmer : AuditAction.banAccount;
    case 'review_removed':
      return AuditAction.removeReview;
    case 'dismissed':
      return AuditAction.dismissReport;
    case 'no_violation':
      return AuditAction.resolveReport;
    case 'violation_recorded':
      return AuditAction.confirmViolation;
    default:
      return null;
  }
}

/// Opens a report for review — from the queue, and from a user's
/// moderation history (a violation's source report).
Future<void> showAdminReportDialog(
  BuildContext context, {
  required AdminPalette palette,
  required String reportId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReportDetailDialog(reportId: reportId, palette: palette),
  );
}

String _formatDate(Timestamp? t) =>
    t != null ? DateFormat('MMM d, y – h:mm a').format(t.toDate()) : '—';

Future<bool> _ensureOnline(BuildContext context) async {
  if (await ConnectivityService.instance.checkNow()) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
  }
  return false;
}

Widget _sectionLabel(String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12.5,
        color: Colors.grey[600],
        letterSpacing: 0.4,
      ),
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
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
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

  /// The farmer's Farmer ID as the portal shows it: their RSBA number.
  final String farmerRsba;
  final String farmerName;
  final String farmerBarangay;
  final String farmerApprovalStatus;
  final String farmerAccountStatus;

  const _ReportRow({
    required this.id,
    required this.data,
    required this.farmerId,
    required this.farmerRsba,
    required this.farmerName,
    required this.farmerBarangay,
    required this.farmerApprovalStatus,
    required this.farmerAccountStatus,
  });

  bool get hasProduct =>
      (data['productId']?.toString().trim().isNotEmpty ?? false);
  String get targetType =>
      (data['targetType'] ?? (hasProduct ? 'listing' : 'farmer')).toString();
  String get targetLabel =>
      hasProduct ? (data['productName'] ?? 'Listing').toString() : farmerName;
  String get reason =>
      (data['issueType'] ?? data['reason'] ?? 'General Report').toString();
  String get description => (data['description'] ?? '').toString();
  String get reporterName =>
      (data['reporterName'] ?? 'Unknown user').toString();
  String get rawStatus => (data['status'] ?? 'pending').toString();
  // 'dismissed' is the legacy value the old admin stub wrote — treated as a
  // resolved outcome for tab/bucket purposes, never rewritten.
  String get bucketStatus => rawStatus == 'dismissed' ? 'resolved' : rawStatus;
  String? get moderationAction =>
      (data['moderationAction'] ?? data['action'])?.toString();
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
  /// The Violations page — accounts with a confirmed violation, and price
  /// flags — instead of the queue of reports. It reads the same reports,
  /// so it is the same view with other tabs.
  final bool violations;

  const ModerationQueueView({super.key, this.violations = false});

  @override
  State<ModerationQueueView> createState() => _ModerationQueueViewState();
}

class _ModerationQueueViewState extends State<ModerationQueueView>
    with AdminPageSearch {
  // The open tab lives in AdminSubNav, shared with the sidebar's submenu.
  ModerationSection get _tab => AdminSubNav.moderation.value;
  ViolationSection get _violationsTab => AdminSubNav.violations.value;

  // This page's own tabs.
  Listenable get _tabs =>
      widget.violations ? AdminSubNav.violations : AdminSubNav.moderation;

  void _onTabChanged() {
    if (mounted) setState(_ticked.clear);
  }

  // The rows whose box is ticked in the open tab: report ids, or farmer
  // ids in Violations.
  final Set<String> _ticked = {};

  void _tick(String id, bool? ticked) => setState(() {
    if (ticked ?? false) {
      _ticked.add(id);
    } else {
      _ticked.remove(id);
    }
  });

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    super.dispose();
  }

  // Typed in the header's search box.
  String get _search => pageSearch;
  String _targetTypeFilter = 'All';
  String _reasonFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title is in the utility bar above.

          // Two live streams — every report, every user — combined and
          // aggregated client-side, same real-time pattern used across the
          // rest of this dashboard (Verified Farmers/Farmer List, Analytics).
          // Both are DashboardDataService's shared, app-session-lifetime
          // Stream instances (see its class doc) rather than opened fresh
          // here — previously these were created inline in build(), so every
          // setState from the tab/search/filter controls below tore down and
          // resubscribed both live listeners on every keystroke.
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: DashboardDataService.instance.allReportsStream,
              builder: (context, reportsSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: DashboardDataService.instance.usersStream,
                  builder: (context, usersSnap) {
                    final snapshots = [reportsSnap, usersSnap];
                    if (snapshots.any((s) => s.hasError)) {
                      return const AdminStreamError();
                    }
                    if (snapshots.any((s) => !s.hasData)) {
                      return const AdminLoadingSpinner();
                    }

                    final usersByUid = <String, Map<String, dynamic>>{
                      for (final d in usersSnap.data!.docs) d.id: d.data(),
                    };

                    final allRows = reportsSnap.data!.docs.map((doc) {
                      final data = doc.data();
                      // The reported account, by its uid (see
                      // reportedUserIdOf): the same user as in User
                      // Accounts, whether a farmer or a buyer.
                      final farmerId = reportedUserIdOf(data);
                      final farmerUser = usersByUid[farmerId];
                      final farmerName =
                          _firstNonEmpty([
                            farmerUser?['fullName'],
                            farmerUser?['name'],
                            data['reportedUserName'],
                            data['sellerName'],
                          ]) ??
                          'Unknown user';
                      final farmerBarangay =
                          _firstNonEmpty([farmerUser?['barangay']]) ?? '—';
                      final farmerApprovalStatus =
                          (farmerUser?['approvalStatus'] ?? '—').toString();
                      final farmerAccountStatus =
                          (farmerUser?['accountStatus'] ?? 'active').toString();
                      return _ReportRow(
                        id: doc.id,
                        data: data,
                        farmerId: farmerId,
                        // Only a farmer has an RSBA number.
                        farmerRsba: farmerUser?['role'] == 'farmer'
                            ? (farmerIdOf(farmerUser) ?? kNoFarmerId)
                            : '—',
                        farmerName: farmerName,
                        farmerBarangay: farmerBarangay,
                        farmerApprovalStatus: farmerApprovalStatus,
                        farmerAccountStatus: farmerAccountStatus,
                      );
                    }).toList();

                    final pendingCount = allRows
                        .where((r) => r.bucketStatus == 'pending')
                        .length;
                    final underReviewCount = allRows
                        .where((r) => r.bucketStatus == 'under_review')
                        .length;
                    final resolvedCount = allRows
                        .where((r) => r.bucketStatus == 'resolved')
                        .length;
                    final violationsCount = allRows
                        .where((r) => r.violationConfirmed)
                        .length;

                    final reasonOptions = {
                      'All',
                      ...allRows.map((r) => r.reason),
                    }.toList()..sort();

                    List<_ReportRow> bucketRows;
                    switch (_tab) {
                      case ModerationSection.pending:
                        bucketRows = allRows
                            .where((r) => r.bucketStatus == 'pending')
                            .toList();
                        break;
                      case ModerationSection.underReview:
                        bucketRows = allRows
                            .where((r) => r.bucketStatus == 'under_review')
                            .toList();
                        break;
                      case ModerationSection.resolved:
                        bucketRows = allRows
                            .where((r) => r.bucketStatus == 'resolved')
                            .toList();
                        break;
                    }

                    final rows =
                        bucketRows.where((r) {
                          if (_targetTypeFilter != 'All' &&
                              r.targetType != _targetTypeFilter.toLowerCase()) {
                            return false;
                          }
                          if (_reasonFilter != 'All' &&
                              r.reason != _reasonFilter) {
                            return false;
                          }
                          final q = _search.trim().toLowerCase();
                          if (q.isEmpty) return true;
                          return r.farmerName.toLowerCase().contains(q) ||
                              r.targetLabel.toLowerCase().contains(q) ||
                              r.id.toLowerCase().contains(q) ||
                              r.reporterName.toLowerCase().contains(q);
                        }).toList()..sort(
                          (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
                              .compareTo(
                                a.createdAt?.millisecondsSinceEpoch ?? 0,
                              ),
                        );

                    // How many rows are ticked, and Clear: level with the
                    // tabs, in view without scrolling to the table's end.
                    final selectionNote = AdminSelectionNote(
                      count: _ticked.length,
                      onClear: () => setState(_ticked.clear),
                    );

                    // The Violations page: no report filters, its own tabs.
                    if (widget.violations) {
                      return SingleChildScrollView(
                        child: AdminTabbedTable<ViolationSection>(
                          selected: _violationsTab,
                          onSelected: (t) => AdminSubNav.violations.value = t,
                          trailing: selectionNote,
                          tabs: [
                            (
                              value: ViolationSection.violations,
                              label: 'Violations',
                              count: violationsCount,
                              icon: Icons.gavel_rounded,
                            ),
                            (
                              value: ViolationSection.priceFlags,
                              label: 'Price Flags',
                              // Counted by its own stream, inside the tab.
                              count: null,
                              icon: Icons.sell_outlined,
                            ),
                          ],
                          child: Container(
                            width: double.infinity,
                            decoration: adminTableCard(c, tabbed: true),
                            // The header band follows the rounded corners.
                            clipBehavior: Clip.antiAlias,
                            padding: kAdminTablePadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_violationsTab ==
                                    ViolationSection.priceFlags)
                                  const _PriceFlagsSection()
                                else
                                  _buildViolationsSection(c, allRows),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    final filters = _ReportFilterBar(
                      c: c,
                      targetTypeFilter: _targetTypeFilter,
                      onTargetTypeChanged: (v) =>
                          setState(() => _targetTypeFilter = v),
                      reasonOptions: reasonOptions,
                      reasonFilter: _reasonFilter,
                      onReasonChanged: (v) => setState(() => _reasonFilter = v),
                    );

                    return LayoutBuilder(
                      // On a window wide enough, the filters sit level with
                      // the tabs, at the right; otherwise on a row above.
                      builder: (context, constraints) {
                        final inline =
                            constraints.maxWidth >=
                            _ReportFilterBar.widthFor(reasonOptions) +
                                _tabsRoom;
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!inline) ...[
                                filters,
                                const SizedBox(height: 16),
                              ],
                              _reportTabs(
                                c,
                                trailing: inline
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          selectionNote,
                                          if (_ticked.isNotEmpty)
                                            const SizedBox(width: 12),
                                          filters.inline(),
                                        ],
                                      )
                                    : selectionNote,
                                pendingCount: pendingCount,
                                underReviewCount: underReviewCount,
                                resolvedCount: resolvedCount,
                                bucketRows: bucketRows,
                                rows: rows,
                              ),
                            ],
                          ),
                        );
                      },
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

  // Room the three tabs take at the left of their row, with a gap before
  // the filters beside them.
  static const double _tabsRoom = 560;

  Widget _reportTabs(
    AdminPalette c, {
    required Widget trailing,
    required int pendingCount,
    required int underReviewCount,
    required int resolvedCount,
    required List<_ReportRow> bucketRows,
    required List<_ReportRow> rows,
  }) {
    return AdminTabbedTable<ModerationSection>(
      selected: _tab,
      onSelected: (t) => AdminSubNav.moderation.value = t,
      trailing: trailing,
      tabs: [
        (
          value: ModerationSection.pending,
          label: 'Pending',
          count: pendingCount,
          icon: Icons.inbox_outlined,
        ),
        (
          value: ModerationSection.underReview,
          label: 'Under Review',
          count: underReviewCount,
          icon: Icons.manage_search_rounded,
        ),
        (
          value: ModerationSection.resolved,
          label: 'Resolved',
          count: resolvedCount,
          icon: Icons.task_alt_rounded,
        ),
      ],
      child: Container(
        width: double.infinity,
        decoration: adminTableCard(c, tabbed: true),
        // The header band follows the rounded corners.
        clipBehavior: Clip.antiAlias,
        padding: kAdminTablePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bucketRows.isEmpty)
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
              // 10 reports a page; back to the first on a new tab, filter
              // or search.
              AdminPaged<_ReportRow>(
                items: rows,
                resetKey: (_tab, _targetTypeFilter, _reasonFilter, pageSearch),
                builder: (context, page) => _ReportTable(
                  c: c,
                  rows: page,
                  ticked: _ticked,
                  onTicked: _tick,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _emptyTitleFor(ModerationSection tab) {
    switch (tab) {
      case ModerationSection.pending:
        return 'No pending reports.';
      case ModerationSection.underReview:
        return 'No reports under review.';
      case ModerationSection.resolved:
        return 'No resolved reports yet.';
    }
  }

  String _emptySubtitleFor(ModerationSection tab) {
    switch (tab) {
      case ModerationSection.pending:
        return 'New reports from Buyers/users will appear here.';
      case ModerationSection.underReview:
        return 'Reports an Admin has started investigating will appear here.';
      case ModerationSection.resolved:
        return 'Dismissed and completed reports will appear here.';
    }
  }

  Widget _buildViolationsSection(AdminPalette c, List<_ReportRow> allRows) {
    final confirmed = allRows.where((r) => r.violationConfirmed).toList();
    if (confirmed.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.verified_outlined,
        title: 'No confirmed violations.',
        subtitle:
            'Farmers/listings with an Admin-confirmed violation will appear here.',
      );
    }

    final byFarmer = <String, List<_ReportRow>>{};
    for (final r in confirmed) {
      if (r.farmerId.isEmpty) continue;
      byFarmer.putIfAbsent(r.farmerId, () => []).add(r);
    }

    final summaries =
        byFarmer.entries.map((e) {
          final reports = [...e.value]
            ..sort(
              (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
                a.createdAt?.millisecondsSinceEpoch ?? 0,
              ),
            );
          final latest = reports.first;
          return _ViolationSummary(
            farmerId: e.key,
            farmerRsba: latest.farmerRsba,
            farmerName: latest.farmerName,
            accountStatus: latest.farmerAccountStatus,
            confirmedCount: reports.length,
            lastViolation: latest.createdAt,
            lastAction: latest.moderationAction,
          );
        }).toList()..sort(
          (a, b) => (b.lastViolation?.millisecondsSinceEpoch ?? 0).compareTo(
            a.lastViolation?.millisecondsSinceEpoch ?? 0,
          ),
        );

    // 10 accounts a page.
    return AdminPaged<_ViolationSummary>(
      items: summaries,
      resetKey: pageSearch,
      builder: (context, page) =>
          _ViolationsTable(c: c, rows: page, ticked: _ticked, onTicked: _tick),
    );
  }
}

// ============================================================
// FILTER BAR
// ============================================================

class _ReportFilterBar extends StatelessWidget {
  final AdminPalette c;
  final String targetTypeFilter;
  final ValueChanged<String> onTargetTypeChanged;
  final List<String> reasonOptions;
  final String reasonFilter;
  final ValueChanged<String> onReasonChanged;

  /// On one line, level with the tabs, instead of wrapping on a row of
  /// its own.
  final bool oneLine;

  const _ReportFilterBar({
    required this.c,
    required this.targetTypeFilter,
    required this.onTargetTypeChanged,
    required this.reasonOptions,
    required this.reasonFilter,
    required this.onReasonChanged,
    this.oneLine = false,
  });

  /// The same filters, on one line.
  _ReportFilterBar inline() => _ReportFilterBar(
    c: c,
    targetTypeFilter: targetTypeFilter,
    onTargetTypeChanged: onTargetTypeChanged,
    reasonOptions: reasonOptions,
    reasonFilter: reasonFilter,
    onReasonChanged: onReasonChanged,
    oneLine: true,
  );

  static const double _targetWidth = 130;
  static const double _reasonWidth = 160;
  static const double _spacing = 12;

  // Reasons on record that neither reporter's list has: review reports,
  // older chat reports.
  static List<String> _otherReasons(List<String> reasonOptions) => [
    for (final r in reasonOptions)
      if (r != 'All' &&
          !kBuyerReportReasons.contains(r) &&
          !kFarmerReportReasons.contains(r))
        r,
  ];

  /// How wide the filters are on one line.
  static double widthFor(List<String> reasonOptions) {
    final reasons = _otherReasons(reasonOptions).isEmpty ? 2 : 3;
    return _targetWidth + reasons * (_reasonWidth + _spacing);
  }

  @override
  Widget build(BuildContext context) {
    // The reasons differ by who files the report (see report_reasons.dart),
    // so each kind of reporter has a dropdown of its own; a third appears
    // for any other reason actually on record (review reports, older chat
    // reports). One reason is filtered by at a time: choosing in one
    // dropdown puts the others back on their "all" line.
    final otherReasons = _otherReasons(reasonOptions);
    Widget reasonDropdown(String all, IconData icon, List<String> reasons) =>
        AdminPillDropdown<String>(
          value: reasons.contains(reasonFilter) ? reasonFilter : 'All',
          width: _reasonWidth,
          icon: icon,
          items: [
            DropdownMenuItem(value: 'All', child: Text(all)),
            for (final reason in reasons)
              DropdownMenuItem(value: reason, child: Text(reason)),
          ],
          onChanged: onReasonChanged,
        );

    final dropdowns = [
      AdminPillDropdown<String>(
        value: targetTypeFilter,
        width: _targetWidth,
        icon: Icons.category_outlined,
        items: const [
          DropdownMenuItem(value: 'All', child: Text('All')),
          DropdownMenuItem(value: 'Listing', child: Text('Listing')),
          DropdownMenuItem(value: 'Farmer', child: Text('Farmer')),
          DropdownMenuItem(value: 'Buyer', child: Text('Buyer')),
          DropdownMenuItem(value: 'Review', child: Text('Review')),
        ],
        onChanged: onTargetTypeChanged,
      ),
      reasonDropdown(
        'Buyer',
        Icons.shopping_basket_outlined,
        kBuyerReportReasons,
      ),
      reasonDropdown(
        'Farmer',
        Icons.agriculture_outlined,
        kFarmerReportReasons,
      ),
      if (otherReasons.isNotEmpty)
        reasonDropdown(
          'Other',
          Icons.report_gmailerrorred_outlined,
          otherReasons,
        ),
    ];

    if (oneLine) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < dropdowns.length; i++) ...[
            if (i > 0) const SizedBox(width: _spacing),
            dropdowns[i],
          ],
        ],
      );
    }
    return Wrap(
      spacing: _spacing,
      runSpacing: _spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: dropdowns,
    );
  }
}

// ============================================================
// REPORT TABLE
// ============================================================

class _ReportTable extends StatelessWidget {
  final AdminPalette c;
  final List<_ReportRow> rows;
  final Set<String> ticked;
  final void Function(String id, bool? ticked) onTicked;
  const _ReportTable({
    required this.c,
    required this.rows,
    required this.ticked,
    required this.onTicked,
  });

  // Sits in the tabbed card the Moderation Queue builds around it.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: AdminTableFit(
        table: DataTable(
          headingRowColor: WidgetStateProperty.all(adminTableHeaderColor(c)),
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
            DataColumn(label: Text('Report ID')),
            DataColumn(label: Text('Reported Target')),
            DataColumn(label: Text('Target Type')),
            DataColumn(label: Text('Reported User')),
            DataColumn(label: Text('Reason')),
            DataColumn(label: Text('Reported By')),
            DataColumn(label: Text('Date Reported')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Action')),
          ],
          rows: rows.map((r) {
            return DataRow(
              selected: ticked.contains(r.id),
              onSelectChanged: (on) => onTicked(r.id, on),
              cells: [
                DataCell(Text(_shortId(r.id))),
                DataCell(Text(r.targetLabel)),
                DataCell(Text(_capitalize(r.targetType))),
                DataCell(Text(r.farmerName)),
                DataCell(Text(r.reason)),
                DataCell(Text(r.reporterName)),
                DataCell(Text(_formatDate(r.createdAt))),
                DataCell(
                  AdminStatusBadge(
                    text: _reportStatusLabel(r),
                    color: _reportStatusColor(c, r),
                    bg: _reportStatusBg(c, r),
                  ),
                ),
                DataCell(
                  TextButton.icon(
                    icon: Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: c.green,
                    ),
                    label: Text(
                      'View Report',
                      style: TextStyle(color: c.green, fontSize: 12.5),
                    ),
                    onPressed: () => showAdminReportDialog(
                      context,
                      palette: c,
                      reportId: r.id,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ============================================================
// PRICE FLAGS TAB — listings a farmer posted at a price far above the
// AI suggested range (the `priceFlag` field add_product_screen.dart saves
// on "Post Anyway"). Review-only: the flag is informational and never
// hides, suspends or penalises a listing by itself.
// ============================================================

class _PriceFlagsSection extends StatefulWidget {
  const _PriceFlagsSection();

  @override
  State<_PriceFlagsSection> createState() => _PriceFlagsSectionState();
}

class _PriceFlagsSectionState extends State<_PriceFlagsSection> {
  // Held in state so a parent rebuild doesn't resubscribe the listener.
  final Stream<QuerySnapshot<Map<String, dynamic>>> _flagged = FirebaseFirestore
      .instance
      .collection('products')
      .where('priceFlag.type', isEqualTo: 'high_price')
      .snapshots();

  // One key per flagged price: the listing and the row's place in it.
  final Set<String> _ticked = {};

  String _peso(dynamic value) =>
      value is num ? '₱${value.toStringAsFixed(2)}' : '—';

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _flagged,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const AdminStreamError();
        if (!snapshot.hasData) return const AdminLoadingSpinner();

        final docs = [...snapshot.data!.docs]
          ..sort((a, b) {
            final at = a.data()['priceFlag']?['flaggedAt'];
            final bt = b.data()['priceFlag']?['flaggedAt'];
            return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0).compareTo(
              at is Timestamp ? at.millisecondsSinceEpoch : 0,
            );
          });
        if (docs.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.price_check_outlined,
            title: 'No price flags.',
            subtitle:
                'Listings priced far above the AI suggested range will appear here.',
          );
        }

        final rows = <DataRow>[];
        for (final doc in docs) {
          final product = doc.data();
          final flag = Map<String, dynamic>.from(product['priceFlag'] as Map);
          final unit = (flag['unit'] ?? product['unit'] ?? '').toString();
          final flaggedAt = flag['flaggedAt'];
          for (final raw in (flag['items'] as List? ?? const [])) {
            final item = Map<String, dynamic>.from(raw as Map);
            final key = '${doc.id}#${rows.length}';
            rows.add(
              DataRow(
                selected: _ticked.contains(key),
                onSelectChanged: (on) => setState(() {
                  if (on ?? false) {
                    _ticked.add(key);
                  } else {
                    _ticked.remove(key);
                  }
                }),
                cells: [
                  DataCell(
                    Text(
                      (flag['productName'] ?? product['name'] ?? '—')
                          .toString(),
                    ),
                  ),
                  DataCell(Text((product['farmerName'] ?? '—').toString())),
                  DataCell(
                    Text(_capitalize((item['pricingType'] ?? '').toString())),
                  ),
                  DataCell(Text('${_peso(item['enteredPrice'])} / $unit')),
                  DataCell(
                    Text(
                      '${_peso(item['suggestedLowerPrice'])} – ${_peso(item['suggestedUpperPrice'])}',
                    ),
                  ),
                  DataCell(
                    AdminStatusBadge(
                      text: '${item['percentAbove'] ?? '—'}% above',
                      color: c.red,
                      bg: c.redBg,
                    ),
                  ),
                  DataCell(Text((item['dataAvailability'] ?? '—').toString())),
                  DataCell(
                    Text(
                      [
                        flag['label'],
                        flag['reason'],
                      ].whereType<String>().join(' — '),
                    ),
                  ),
                  DataCell(
                    AdminStatusBadge(
                      text: (flag['reviewStatus'] ?? 'Price Review Required')
                          .toString(),
                      color: c.amber,
                      bg: c.amberBg,
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatDate(flaggedAt is Timestamp ? flaggedAt : null),
                    ),
                  ),
                ],
              ),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Above the table, so it is in view without scrolling.
            AdminSelectionNote(
              count: _ticked.length,
              onClear: () => setState(_ticked.clear),
            ),
            // 10 flagged prices a page.
            AdminPaged<DataRow>(
              items: rows,
              builder: (context, page) => AdminTableFit(
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
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Farmer')),
                    DataColumn(label: Text('Price Type')),
                    DataColumn(label: Text('Entered Price')),
                    DataColumn(label: Text('Suggested Range')),
                    DataColumn(label: Text('Above Range')),
                    DataColumn(label: Text('Data Availability')),
                    DataColumn(label: Text('Reason')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Flagged')),
                  ],
                  rows: page,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// VIOLATIONS TAB
// ============================================================

class _ViolationSummary {
  final String farmerId;
  final String farmerRsba;
  final String farmerName;
  final String accountStatus;
  final int confirmedCount;
  final Timestamp? lastViolation;
  final String? lastAction;
  const _ViolationSummary({
    required this.farmerId,
    required this.farmerRsba,
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
  final Set<String> ticked;
  final void Function(String id, bool? ticked) onTicked;
  const _ViolationsTable({
    required this.c,
    required this.rows,
    required this.ticked,
    required this.onTicked,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: AdminTableFit(
        table: DataTable(
          headingRowColor: WidgetStateProperty.all(adminTableHeaderColor(c)),
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
            DataColumn(label: Text('RSBA No.')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Confirmed Violations'), numeric: true),
            DataColumn(label: Text('Last Violation')),
            DataColumn(label: Text('Current Account Status')),
            DataColumn(label: Text('Last Admin Action')),
            DataColumn(label: Text('View History')),
          ],
          rows: rows.map((r) {
            return DataRow(
              selected: ticked.contains(r.farmerId),
              onSelectChanged: (on) => onTicked(r.farmerId, on),
              cells: [
                DataCell(Text(r.farmerRsba)),
                DataCell(Text(r.farmerName)),
                DataCell(Text('${r.confirmedCount}')),
                DataCell(Text(_formatDate(r.lastViolation))),
                DataCell(_accountStatusBadge(c, r.accountStatus)),
                DataCell(
                  Text(r.lastAction != null ? _capitalize(r.lastAction!) : '—'),
                ),
                DataCell(
                  TextButton.icon(
                    icon: Icon(Icons.history, size: 16, color: c.green),
                    label: Text(
                      'View History',
                      style: TextStyle(color: c.green, fontSize: 12.5),
                    ),
                    // This account's reports and violations; each opens
                    // its source report.
                    onPressed: () => showAdminModerationHistory(
                      context,
                      palette: c,
                      uid: r.farmerId,
                      name: r.farmerName,
                    ),
                  ),
                ),
              ],
            );
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
Future<_FarmerViolationHistory> _loadFarmerViolationHistory(
  String farmerId,
) async {
  if (farmerId.isEmpty) {
    return const _FarmerViolationHistory(
      confirmedViolations: 0,
      warnings: 0,
      suspensions: 0,
      relatedReports: [],
    );
  }

  // The two reads don't depend on each other: side by side, not in turn.
  final reports = FirebaseFirestore.instance.collection('reports');
  final results = await AdminPerf.time(
    'moderation: farmer violation history',
    () => Future.wait([
      reports.where('farmerId', isEqualTo: farmerId).get(),
      reports.where('reportedUserId', isEqualTo: farmerId).get(),
    ]),
    describe: (r) => '${r[0].docs.length} + ${r[1].docs.length} reports',
  );
  final byFarmerId = results[0];
  final byReportedUserId = results[1];

  final seen = <String>{};
  final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final d in [...byFarmerId.docs, ...byReportedUserId.docs]) {
    // A review report names the farmer who filed it as farmerId: that one
    // is not about them.
    if (reportedUserIdOf(d.data()) != farmerId) continue;
    if (seen.add(d.id)) docs.add(d);
  }

  docs.sort((a, b) {
    final at = a.data()['createdAt'] as Timestamp?;
    final bt = b.data()['createdAt'] as Timestamp?;
    return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
      at?.millisecondsSinceEpoch ?? 0,
    );
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
        .map(
          (d) => _ReportRow(
            id: d.id,
            data: d.data(),
            farmerId: farmerId,
            farmerRsba: kNoFarmerId,
            farmerName: '',
            farmerBarangay: '—',
            farmerApprovalStatus: '—',
            farmerAccountStatus: '—',
          ),
        )
        .take(10)
        .toList(),
  );
}

// ============================================================
// REPORT DETAIL DIALOG — the review + decision workflow
// ============================================================

class _ReportDetailDialog extends StatefulWidget {
  final String reportId;

  /// The portal's colours: a popup is outside AdminThemeScope.
  final AdminPalette palette;
  const _ReportDetailDialog({required this.reportId, required this.palette});

  @override
  State<_ReportDetailDialog> createState() => _ReportDetailDialogState();
}

class _ReportDetailDialogState extends State<_ReportDetailDialog>
    with AdminReadOnce {
  bool _busy = false;

  // The reported account's own user record, read once per popup.
  Future<DocumentSnapshot<Map<String, dynamic>>> _reportedUser(String uid) =>
      readOnce(
        'user/$uid',
        () => FirebaseFirestore.instance.collection('users').doc(uid).get(),
      );

  /// Pending → Under Review, when the Admin chooses Start Review. A report
  /// is not moved on just by being opened.
  Future<void> _startReview(Map<String, dynamic> report) async {
    if (_busy) return;
    if (!await _ensureOnline(context)) return;
    setState(() => _busy = true);
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final reportRef = FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.reportId);
    final historyRef = reportRef.collection('history').doc();
    try {
      await FirebaseFirestore.instance.runTransaction<void>((
        transaction,
      ) async {
        final latest = await transaction.get(reportRef);
        if (!latest.exists ||
            (latest.data()?['status'] ?? 'pending') != 'pending') {
          return;
        }
        transaction.update(reportRef, {
          'status': 'under_review',
          'reviewedBy': adminUid,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(historyRef, {
          'action': 'under_review',
          'adminId': adminUid,
          'reason': null,
          'notes': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      AuditLogService.log(
        AuditAction.startReportReview,
        'Started review of report ${_shortId(widget.reportId)} about '
        '${_firstNonEmpty([report['reportedUserName']]) ?? 'a user'}.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start the review: $error')),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _runAction({
    required Map<String, dynamic> report,
    required String action,
    required bool violationConfirmed,
    required String reason,
    required String notes,
    String? severity,
    // Set when a violation is confirmed: what the Admin chose to do.
    ViolationAction? violation,
    String? reportedRole,
  }) async {
    if (_busy) return;
    if (!await _ensureOnline(context)) return;
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      // The reported account, by uid: the one a suspension or ban applies
      // to, and the one the violation is recorded against.
      final farmerId = reportedUserIdOf(report);
      final productId = report['productId']?.toString();
      final reviewId = report['reviewId']?.toString();

      final reportRef = FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.reportId);
      final historyRef = reportRef.collection('history').doc();
      await FirebaseFirestore.instance.runTransaction<void>((batch) async {
        final latest = await batch.get(reportRef);
        if (!latest.exists ||
            ![
              'pending',
              'under_review',
            ].contains(latest.data()?['status'] ?? 'pending')) {
          throw StateError(
            'This report has already been resolved or removed. Close it and refresh before taking another action.',
          );
        }
        batch.update(reportRef, {
          'status': 'resolved',
          'moderationAction': action,
          'violationConfirmed': violationConfirmed,
          'violationSeverity': ?severity,
          'adminNotes': notes,
          'reviewedBy': adminUid,
          'reviewedAt': FieldValue.serverTimestamp(),
        });

        // Both outcomes block marketplace visibility. Preserve the distinct
        // decision for the listings table and explicit admin restoration.
        if ((action == 'hidden' || action == 'removed') &&
            productId != null &&
            productId.isNotEmpty) {
          batch.update(
            FirebaseFirestore.instance.collection('products').doc(productId),
            {
              'isSuspended': true,
              'moderationStatus': action,
              'moderationReason': reason,
              'moderatedBy': adminUid,
              'moderatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
        if (action == 'review_removed' &&
            reviewId != null &&
            reviewId.isNotEmpty) {
          batch.update(
            FirebaseFirestore.instance
                .collection('productReviews')
                .doc(reviewId),
            {
              'moderationStatus': 'removed',
              'moderatedBy': adminUid,
              'moderatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
        if (action == 'suspended' && farmerId.isNotEmpty) {
          batch.update(
            FirebaseFirestore.instance.collection('users').doc(farmerId),
            {
              'accountStatus': 'suspended',
              'suspensionReason': reason,
              'moderationUpdatedBy': adminUid,
              'moderationUpdatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
        if (action == 'banned' && farmerId.isNotEmpty) {
          batch.update(
            FirebaseFirestore.instance.collection('users').doc(farmerId),
            {
              'accountStatus': 'banned',
              'banReason': reason,
              'moderationUpdatedBy': adminUid,
              'moderationUpdatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        // A confirmed violation gets a record of its own, tied to the
        // reported account by uid and to this report — its id is the
        // report's, so a report can never yield two.
        if (violation != null && farmerId.isNotEmpty) {
          batch.set(
            FirebaseFirestore.instance
                .collection('violations')
                .doc(widget.reportId),
            violationRecord(
              reportId: widget.reportId,
              report: report,
              reportedUserRole: reportedRole,
              action: violation,
              reason: reason,
              confirmedBy: adminUid,
              confirmedAt: FieldValue.serverTimestamp(),
            ),
          );
        }

        // Save the decision and its append-only history atomically.
        batch.set(historyRef, {
          'action': action,
          'adminId': adminUid,
          'reason': reason,
          'notes': notes,
          'severity': ?severity,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      final auditAction = _auditActionFor(
        action,
        farmer: reportedRole == 'farmer',
      );
      if (auditAction != null) {
        final who =
            _firstNonEmpty([
              report['reportedUserName'],
              report['sellerName'],
            ]) ??
            (farmerId.isEmpty ? 'Unknown user' : 'user $farmerId');
        final productName = report['productName']?.toString();
        final target = productName != null && productName.isNotEmpty
            ? '"$productName" ($who)'
            : who;
        AuditLogService.log(
          auditAction,
          '${violation != null ? 'Violation confirmed — ' : ''}'
          '${adminDecisionLabel(action)}: $target '
          '(report ${_shortId(widget.reportId)}).'
          '${reason.isNotEmpty ? ' Reason: $reason' : ''}',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${adminDecisionLabel(action)}.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _reactivateFarmer(String farmerId, {String? role}) async {
    if (_busy) return;
    if (!await _ensureOnline(context)) return;
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      final batch = FirebaseFirestore.instance.batch();
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(farmerId),
        {
          'accountStatus': 'active',
          'suspensionReason': FieldValue.delete(),
          'suspendedUntil': FieldValue.delete(),
          'banReason': FieldValue.delete(),
          'moderationUpdatedBy': adminUid,
          'moderationUpdatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.set(
        FirebaseFirestore.instance
            .collection('reports')
            .doc(widget.reportId)
            .collection('history')
            .doc(),
        {
          'action': 'reactivated',
          'adminId': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
      AuditLogService.log(
        role == 'farmer'
            ? AuditAction.reactivateFarmer
            : AuditAction.reactivateAccount,
        'Reactivated the account of user $farmerId '
        '(report ${_shortId(widget.reportId)}).',
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account reactivated.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Listings restored from this dialog: the listing above is read once, so
  // its status is shown from here after a restore.
  final Set<String> _restoredListings = {};

  /// Clears an Admin's hide on the reported listing — the only place a
  /// hidden listing is brought back. The same change the Listings page's
  /// Restore made: nothing else about the listing is touched, and the
  /// farmer account, stock and archive status still decide whether buyers
  /// see it.
  Future<void> _restoreListing(String productId, String name) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore "$name"?'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'The admin restriction is cleared. The farmer account, stock and '
            'archive status still decide whether buyers see it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await _ensureOnline(context)) return;
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      final firestore = FirebaseFirestore.instance;
      final ref = firestore.collection('products').doc(productId);
      await firestore.runTransaction<void>((tx) async {
        final current = await tx.get(ref);
        if (!current.exists || current.data()?['isSuspended'] != true) {
          throw StateError(
            'This listing has already been restored or deleted.',
          );
        }
        tx.update(ref, {
          'isSuspended': false,
          'moderationStatus': 'restored',
          'moderationReason': FieldValue.delete(),
          'moderatedBy': adminUid,
          'moderatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          firestore
              .collection('reports')
              .doc(widget.reportId)
              .collection('history')
              .doc(),
          {
            'action': 'listing_restored',
            'adminId': adminUid,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      });
      AuditLogService.log(
        AuditAction.restoreListing,
        'Restored listing $productId: $name '
        '(report ${_shortId(widget.reportId)}).',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _restoredListings.add(productId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Listing restored.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is StateError ? e.message : 'Error: $e')),
      );
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
                  AdminField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: adminMultilineDecoration(
                      dialogContext,
                      labelText: requireReason
                          ? 'Reason (required)'
                          : 'Reason (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdminField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: adminMultilineDecoration(
                      dialogContext,
                      labelText: 'Admin notes (internal, optional)',
                    ),
                  ),
                  if (severityOptions != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: severity,
                      borderRadius: BorderRadius.circular(kAdminPopupRadius),
                      decoration: const InputDecoration(
                        labelText: 'Violation severity',
                      ),
                      items: severityOptions
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(_capitalize(s)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => severity = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: actionColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (requireReason && reasonController.text.trim().isEmpty) {
                  return;
                }
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

  // Confirm Violation: the Admin picks what to do about it — only the
  // actions that apply to this report — and says why.
  Future<void> _openViolationDialog(Map<String, dynamic> report) async {
    final c = widget.palette;
    final options = violationActionsFor(report);
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    var chosen = options.first;
    var missingReason = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Confirm Violation'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This records a confirmed violation on the reported '
                    'account. Choose the action to take.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  for (final option in options)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setDialogState(() => chosen = option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              option == chosen
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: option == chosen
                                  ? adminActionColor(c)
                                  : c.textMuted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                option.label,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: option == chosen
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  AdminField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: adminMultilineDecoration(
                      dialogContext,
                      labelText: 'Reason (required)',
                    ),
                  ),
                  if (missingReason)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Give the reason for this decision.',
                        style: TextStyle(color: c.red, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  AdminField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: adminMultilineDecoration(
                      dialogContext,
                      labelText: 'Admin notes (internal, optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  setDialogState(() => missingReason = true);
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Confirm Violation'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    // Whose account it is decides how a suspension or ban is logged, and
    // is kept on the violation record.
    String? role;
    final uid = reportedUserIdOf(report);
    if (uid.isNotEmpty) {
      try {
        role = (await _reportedUser(uid)).data()?['role']?.toString();
      } catch (_) {}
    }
    await _runAction(
      report: report,
      action: chosen.code,
      violationConfirmed: true,
      reason: reasonController.text.trim(),
      notes: notesController.text.trim(),
      severity: chosen.severity,
      violation: chosen,
      reportedRole: role,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Each read below is started once (AdminReadOnce): the popup rebuilds
    // whenever the report changes or the Admin types, and must not fetch
    // the farmer, listing, review and history again each time.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: watchOnce(
        'report',
        () => FirebaseFirestore.instance
            .collection('reports')
            .doc(widget.reportId)
            .snapshots(),
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return AlertDialog(
            title: const Text('Something went wrong'),
            content: const Text(
              'Could not load this report. Please try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        }
        if (!snap.hasData) {
          return const AlertDialog(
            content: SizedBox(
              height: 120,
              child: Center(child: AdminLoadingBar()),
            ),
          );
        }
        final report = snap.data!.data();
        if (report == null) {
          return AlertDialog(
            title: const Text('Report Not Found'),
            content: const Text(
              'This report could not be found. It may have been removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        }

        final hasProduct =
            (report['productId']?.toString().trim().isNotEmpty ?? false);
        final targetType =
            (report['targetType'] ?? (hasProduct ? 'listing' : 'farmer'))
                .toString();
        // The reported account's uid: the key to its user record, its
        // history and any action taken on it.
        final farmerId = reportedUserIdOf(report);
        final c = widget.palette;
        final productId = report['productId']?.toString();
        final reviewId = report['reviewId']?.toString();
        final conversationId = (report['conversationId'] ?? '')
            .toString()
            .trim();
        final orderId = (report['relatedOrderId'] ?? report['orderId'] ?? '')
            .toString()
            .trim();
        final rawStatus = (report['status'] ?? 'pending').toString();
        final bucketStatus = rawStatus == 'dismissed' ? 'resolved' : rawStatus;
        final isResolved = bucketStatus == 'resolved';
        final reason =
            (report['issueType'] ?? report['reason'] ?? 'General Report')
                .toString();
        final description = (report['description'] ?? '').toString();
        final createdAt = report['createdAt'] as Timestamp?;
        final reporterName = (report['reporterName'] ?? 'Unknown user')
            .toString();
        final reporterId = (report['reporterId'] ?? '—').toString();
        final moderationAction =
            (report['moderationAction'] ?? report['action'])?.toString();
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
                  if (description.isNotEmpty)
                    _detailRow('Description', description),
                  _detailRow(
                    'Current Status',
                    violationConfirmed
                        ? 'Violation Confirmed'
                        : _capitalize(bucketStatus),
                  ),
                  if (moderationAction != null)
                    _detailRow(
                      'Admin Decision',
                      adminDecisionLabel(moderationAction),
                    ),
                  if (adminNotes.isNotEmpty)
                    _detailRow('Admin Notes', adminNotes),
                  const SizedBox(height: 10),

                  _sectionLabel('Reporter Information'),
                  _detailRow('Reporter Name', reporterName),
                  _detailRow('Reporter ID', _shortId(reporterId)),
                  const SizedBox(height: 10),

                  _sectionLabel('Reported User'),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: farmerId.isEmpty ? null : _reportedUser(farmerId),
                    builder: (context, farmerSnap) {
                      if (farmerId.isEmpty) {
                        return Text(
                          'No user is on record for this report.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12.5,
                          ),
                        );
                      }
                      if (farmerSnap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final farmer = farmerSnap.data?.data();
                      if (farmer == null) {
                        return Text(
                          'This user\'s account could not be found.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12.5,
                          ),
                        );
                      }
                      final name =
                          _firstNonEmpty([
                            farmer['fullName'],
                            farmer['name'],
                          ]) ??
                          'Unnamed account';
                      final role = (farmer['role'] ?? '').toString();
                      final isFarmer = role == 'farmer';
                      final email = (farmer['email'] ?? '').toString().trim();
                      final area = [
                        _firstNonEmpty([farmer['barangay']]),
                        _firstNonEmpty([
                          farmer['municipality'],
                          farmer['province'],
                        ]),
                      ].whereType<String>().join(', ');
                      final accountStatus = accountStatusOf(farmer);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The same account as in User Accounts: clicking
                          // the name opens it.
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => showAdminAccountDialog(
                              context,
                              palette: c,
                              uid: farmerId,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  adminUserAvatar(
                                    c,
                                    name: name,
                                    photoUrl: farmer['photoUrl']?.toString(),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            color: adminActionColor(c),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14.5,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        Text(
                                          '${isFarmer ? 'Farmer' : 'Buyer'} · '
                                          'View account',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _detailRow(
                            '${isFarmer ? 'Farmer' : 'Buyer'} ID',
                            _shortId(farmerId),
                          ),
                          if (isFarmer)
                            _detailRow(
                              'RSBA No.',
                              farmerIdOf(farmer) ?? kNoFarmerId,
                            ),
                          // A buyer's email is partly hidden, as it is
                          // everywhere in the portal.
                          _detailRow(
                            'Email',
                            email.isEmpty
                                ? '—'
                                : (isFarmer ? email : maskEmail(email)),
                          ),
                          _detailRow(
                            'General Area',
                            area.isEmpty ? 'Not saved' : area,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    'Account Status',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                adminAccountStatusBadge(c, accountStatus),
                              ],
                            ),
                          ),
                          if (accountStatus != 'active') ...[
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.restart_alt, size: 16),
                              label: const Text('Reactivate Account'),
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        _reactivateFarmer(farmerId, role: role),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // What the report is tied to, by id: each opens the page
                  // that record is on.
                  if ((productId != null && productId.isNotEmpty) ||
                      orderId.isNotEmpty ||
                      conversationId.isNotEmpty) ...[
                    _sectionLabel('Related Records'),
                    // A listing an Admin hid is brought back from here:
                    // the portal has no separate Listings page.
                    if (productId != null && productId.isNotEmpty)
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: readOnce(
                          'product/$productId',
                          () => FirebaseFirestore.instance
                              .collection('products')
                              .doc(productId)
                              .get(),
                        ),
                        builder: (context, productSnap) {
                          final product = productSnap.data?.data();
                          final name =
                              (product?['name'] ??
                                      report['productName'] ??
                                      _shortId(productId))
                                  .toString();
                          final hidden =
                              product?['isSuspended'] == true &&
                              !_restoredListings.contains(productId);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    'Related Listing',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    hidden ? '$name (hidden by Admin)' : name,
                                  ),
                                ),
                                if (hidden)
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                              _restoreListing(productId, name),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Restore listing'),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (orderId.isNotEmpty)
                      _detailRow('Related Order', _shortId(orderId)),
                    if (conversationId.isNotEmpty)
                      _detailRow(
                        'Related Conversation',
                        _shortId(conversationId),
                      ),
                    const SizedBox(height: 10),
                  ],

                  if (targetType == 'listing') ...[
                    _sectionLabel('Reported Listing'),
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: (productId == null || productId.isEmpty)
                          ? null
                          : readOnce(
                              'product/$productId',
                              () => FirebaseFirestore.instance
                                  .collection('products')
                                  .doc(productId)
                                  .get(),
                            ),
                      builder: (context, productSnap) {
                        if (productId == null || productId.isEmpty) {
                          return Text(
                            'No listing on record for this report.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                            ),
                          );
                        }
                        if (productSnap.connectionState !=
                            ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final product = productSnap.data?.data();
                        if (product == null) {
                          return Text(
                            'This listing no longer exists.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                            ),
                          );
                        }
                        final name = (product['name'] ?? '—').toString();
                        final category = (product['category'] ?? '—')
                            .toString();
                        final desc = (product['description'] ?? '—').toString();
                        final price = product['price'];
                        final qty = product['quantity'];
                        final imageUrls = product['imageUrls'];
                        final imageUrl = _firstNonEmpty([
                          product['imageUrl'],
                          (imageUrls is List && imageUrls.isNotEmpty)
                              ? imageUrls.first?.toString()
                              : null,
                        ]);
                        final isArchived = product['isArchived'] == true;
                        final isSuspended =
                            product['isSuspended'] == true &&
                            !_restoredListings.contains(productId);
                        final listingStatus = isSuspended
                            ? 'Hidden by Admin'
                            : (isArchived ? 'Archived' : 'Active');

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
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            _detailRow('Product Name', name),
                            _detailRow('Category', category),
                            _detailRow('Description', desc),
                            _detailRow(
                              'Price',
                              price != null
                                  ? formatPeso(
                                      price is num
                                          ? price
                                          : num.tryParse('$price') ?? 0,
                                    )
                                  : '—',
                            ),
                            _detailRow('Quantity', qty?.toString() ?? '—'),
                            _detailRow('Listing Status', listingStatus),
                            _detailRow(
                              'Listing Owner',
                              _shortId(
                                (product['farmerId'] ?? farmerId).toString(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (targetType == 'review') ...[
                    _sectionLabel('Reported Buyer Review'),
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: (reviewId == null || reviewId.isEmpty)
                          ? null
                          : readOnce(
                              'review/$reviewId',
                              () => FirebaseFirestore.instance
                                  .collection('productReviews')
                                  .doc(reviewId)
                                  .get(),
                            ),
                      builder: (context, reviewSnap) {
                        if (reviewId == null || reviewId.isEmpty) {
                          return Text(
                            'No review is attached to this report.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                            ),
                          );
                        }
                        if (reviewSnap.connectionState !=
                            ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final review = reviewSnap.data?.data();
                        if (review == null) {
                          return Text(
                            'This review is no longer available.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _detailRow(
                              'Product',
                              (review['productName'] ?? '—').toString(),
                            ),
                            _detailRow(
                              'Buyer',
                              (review['buyerName'] ?? 'Buyer').toString(),
                            ),
                            _detailRow(
                              'Rating',
                              '${review['rating'] ?? '—'} / 5',
                            ),
                            _detailRow(
                              'Review',
                              (review['comment'] ?? '').toString(),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                  _sectionLabel('Violation History'),
                  FutureBuilder<_FarmerViolationHistory>(
                    future: readOnce(
                      'history/$farmerId',
                      () => _loadFarmerViolationHistory(farmerId),
                    ),
                    builder: (context, histSnap) {
                      if (histSnap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (histSnap.hasError || !histSnap.hasData) {
                        return Text(
                          'Could not load violation history.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12.5,
                          ),
                        );
                      }
                      final h = histSnap.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(
                            'Previous Confirmed Violations',
                            '${h.confirmedViolations}',
                          ),
                          _detailRow('Previous Warnings', '${h.warnings}'),
                          _detailRow(
                            'Previous Suspensions',
                            '${h.suspensions}',
                          ),
                          _detailRow(
                            'Related Reports',
                            '${h.relatedReports.length}',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Pending → Start Review → one of three decisions. A report is
          // never treated as a violation until the Admin confirms one.
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (bucketStatus == 'pending')
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start Review'),
                onPressed: _busy ? null : () => _startReview(report),
              )
            else if (!isResolved) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _openActionDialog(
                        report: report,
                        title: 'Dismiss this report?',
                        actionLabel: 'Dismiss Report',
                        actionColor: Colors.grey,
                        action: 'dismissed',
                        violationConfirmed: false,
                        requireReason: false,
                      ),
                child: const Text('Dismiss Report'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _openActionDialog(
                        report: report,
                        title: 'Resolve with no violation?',
                        actionLabel: 'Resolve',
                        actionColor: adminActionColor(c),
                        action: 'no_violation',
                        violationConfirmed: false,
                        requireReason: false,
                      ),
                child: const Text('Resolve with No Violation'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : () => _openViolationDialog(report),
                child: const Text('Confirm Violation'),
              ),
            ],
          ],
        );
      },
    );
  }
}
