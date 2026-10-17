import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../services/admin_perf.dart';
import '../services/rsba_number.dart';
import 'admin_filter_controls.dart';
import '../services/audit_log_service.dart';
import '../services/dashboard_analytics_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/market_price_helpers.dart';
import '../services/pdf_report_service.dart';
import 'admin_dashboard_screen.dart'
    show
        AdminPalette,
        AdminThemeScope,
        AdminStatusBadge,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminStreamError,
        AdminQuickActionButton;

/// Farmer List — a physically separate screen from Verification Queue.
/// It does not import or reuse Verification Queue's dialog, data loaders,
/// or approve/reject actions; it only shares the common Admin Dashboard
/// design-system pieces (AdminStatusBadge, AdminEmptyState, etc.) that every
/// admin page is built from.
///
/// Shows role == 'farmer' && approvalStatus == 'approved' only — no
/// pending, no rejected, no buyers, no admins.
enum _SortOption {
  nameAsc,
  nameDesc,
  newestApproved,
  oldestApproved,
  mostActiveListings,
  mostOrders,
}

class _FarmerListRow {
  final String uid;
  final Map<String, dynamic> data;
  final int activeListings;
  final int archivedProducts;
  final int completedOrders;
  const _FarmerListRow({
    required this.uid,
    required this.data,
    required this.activeListings,
    required this.archivedProducts,
    required this.completedOrders,
  });

  String get fullName =>
      (data['fullName'] ?? data['name'] ?? 'Unknown Farmer').toString();
  String get email => (data['email'] ?? '—').toString();
  String get barangay =>
      (data['barangay']?.toString().trim().isNotEmpty == true)
      ? data['barangay'].toString()
      : '—';
  String get municipality =>
      (data['municipality']?.toString().trim().isNotEmpty == true)
      ? data['municipality'].toString()
      : '—';
  Timestamp? get reviewedAt => data['reviewedAt'] as Timestamp?;

  /// The farmer's RSBA number (see farmerIdOf), or "Not provided".
  String get farmerId => farmerIdOf(data) ?? kNoFarmerId;
}

/// Joins approved-farmer docs with their products/orders — shared by the
/// live StreamBuilder view and the one-time fetch behind Export Report, so
/// the two can never drift apart on how a count is computed.
List<_FarmerListRow> _computeFarmerRows(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> farmerDocs,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
) {
  final productsByFarmer =
      <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final p in productDocs) {
    final fid = (p.data()['farmerId'] ?? '').toString();
    if (fid.isEmpty) continue;
    productsByFarmer.putIfAbsent(fid, () => []).add(p);
  }
  final ordersByFarmer =
      <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final o in orderDocs) {
    final sid = (o.data()['sellerId'] ?? '').toString();
    if (sid.isEmpty) continue;
    ordersByFarmer.putIfAbsent(sid, () => []).add(o);
  }

  return farmerDocs.map((doc) {
    final uid = doc.id;
    final products = productsByFarmer[uid] ?? const [];
    final active = products
        .where((p) => (p.data()['isArchived'] ?? false) != true)
        .length;
    final archived = products.length - active;
    final orders = ordersByFarmer[uid] ?? const [];
    final completed = orders
        .where(
          (o) =>
              (o.data()['status'] ?? '').toString().toLowerCase() ==
              'completed',
        )
        .length;
    return _FarmerListRow(
      uid: uid,
      data: doc.data(),
      activeListings: active,
      archivedProducts: archived,
      completedOrders: completed,
    );
  }).toList();
}

class FarmerListView extends StatefulWidget {
  const FarmerListView({super.key});

  @override
  State<FarmerListView> createState() => _FarmerListViewState();
}

class _FarmerListViewState extends State<FarmerListView> with AdminPageSearch {
  // Typed in the header's search box.
  String get _search => pageSearch;
  String _barangayFilter = 'All';
  _SortOption _sort = _SortOption.newestApproved;
  bool _exporting = false;

  // Same filter + sort the live table applies — factored out so Export
  // Report can reuse it exactly instead of re-implementing it.
  List<_FarmerListRow> _filterAndSort(List<_FarmerListRow> allRows) {
    var rows = allRows.where((r) {
      if (_barangayFilter != 'All' && r.barangay != _barangayFilter) {
        return false;
      }
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return r.fullName.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.barangay.toLowerCase().contains(q) ||
          r.municipality.toLowerCase().contains(q) ||
          r.farmerId.toLowerCase().contains(q);
    }).toList();

    rows.sort((a, b) {
      switch (_sort) {
        case _SortOption.nameAsc:
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case _SortOption.nameDesc:
          return b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase());
        case _SortOption.newestApproved:
          return (b.reviewedAt?.millisecondsSinceEpoch ?? 0).compareTo(
            a.reviewedAt?.millisecondsSinceEpoch ?? 0,
          );
        case _SortOption.oldestApproved:
          return (a.reviewedAt?.millisecondsSinceEpoch ?? 0).compareTo(
            b.reviewedAt?.millisecondsSinceEpoch ?? 0,
          );
        case _SortOption.mostActiveListings:
          return b.activeListings.compareTo(a.activeListings);
        case _SortOption.mostOrders:
          return b.completedOrders.compareTo(a.completedOrders);
      }
    });
    return rows;
  }

  // Real, freshly-fetched Firestore data (not whatever happens to be
  // loaded in the live StreamBuilder below) — the KPI totals reflect every
  // approved farmer (matching what the stat cards above show regardless of
  // filters), while the table matches exactly what's currently filtered/
  // sorted on screen, same as the audit log's "export what's visible".
  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      // The listings and orders are the live ones the page is already
      // showing (DashboardDataService) — not downloaded a second time.
      final data = DashboardDataService.instance;
      await data.ensureLoaded();
      final farmers = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'farmer')
          .where('approvalStatus', isEqualTo: 'approved')
          .get();
      final allRows = _computeFarmerRows(
        farmers.docs,
        data.products,
        data.allOrders,
      );
      final rows = _filterAndSort(allRows);

      final bytes = await PdfReportService.buildFarmerListReport(
        totalFarmers: allRows.length,
        activeListingsTotal: allRows.fold<int>(
          0,
          (t, r) => t + r.activeListings,
        ),
        completedOrdersTotal: allRows.fold<int>(
          0,
          (t, r) => t + r.completedOrders,
        ),
        rows: rows
            .map(
              (r) => (
                farmerId: r.farmerId,
                fullName: r.fullName,
                email: r.email,
                barangay: r.barangay,
                municipality: r.municipality,
                dateApproved: r.reviewedAt != null
                    ? DateFormat('MMM d, y').format(r.reviewedAt!.toDate())
                    : '—',
                activeListings: r.activeListings,
                completedOrders: r.completedOrders,
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      await PdfReportService.share(bytes, 'agritrade_farmer_list.pdf');
      AuditLogService.log(
        AuditAction.exportReport,
        'Exported the Farmer List report (${rows.length} of ${allRows.length} farmers shown).',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Farmer List report exported.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    DashboardDataService.instance.ensureLoaded();
    final c = AdminThemeScope.of(context).palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The title is in the utility bar above.
          Expanded(
            // users/products/orders are shared, app-session-lifetime reads
            // via DashboardDataService (see its class doc) instead of this
            // screen opening its own live listeners — previously those were
            // created fresh inline in build(), so every setState from the
            // search box / filter dropdowns below tore down and resubscribed
            // all three on every keystroke, re-reading the full products and
            // orders collections each time.
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: DashboardDataService.instance.usersStream,
              builder: (context, usersSnap) {
                return ListenableBuilder(
                  listenable: DashboardDataService.instance,
                  builder: (context, _) {
                    final svc = DashboardDataService.instance;
                    if (usersSnap.hasError || svc.lastError != null) {
                      return const AdminStreamError();
                    }
                    if (!usersSnap.hasData || !svc.hasLoadedOnce) {
                      return const AdminLoadingSpinner();
                    }

                    final farmerDocs = usersSnap.data!.docs
                        .where(
                          (d) =>
                              d.data()['role'] == 'farmer' &&
                              d.data()['approvalStatus'] == 'approved',
                        )
                        .toList();
                    final allRows = _computeFarmerRows(
                      farmerDocs,
                      svc.products,
                      svc.allOrders,
                    );

                    final barangayOptions = {
                      'All',
                      ...allRows.map((r) => r.barangay).where((b) => b != '—'),
                    }.toList()..sort();

                    final rows = _filterAndSort(allRows);

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The filters, and Export Report level with them.
                          Row(
                            children: [
                              Expanded(
                                child: _FarmerListFilterBar(
                                  c: c,
                                  barangayOptions: barangayOptions,
                                  barangayFilter: _barangayFilter,
                                  onBarangayChanged: (v) =>
                                      setState(() => _barangayFilter = v),
                                  sort: _sort,
                                  onSortChanged: (v) =>
                                      setState(() => _sort = v),
                                ),
                              ),
                              const SizedBox(width: 12),
                              AdminQuickActionButton(
                                icon: Icons.picture_as_pdf_outlined,
                                label: 'Export Report',
                                onPressed: _exporting ? () {} : _export,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (allRows.isEmpty)
                            const AdminEmptyState(
                              icon: Icons.groups_outlined,
                              title: 'No verified farmers yet.',
                              subtitle:
                                  'Approved Farmer accounts will appear here.',
                            )
                          else if (rows.isEmpty)
                            AdminEmptyState(
                              icon: Icons.search_off,
                              title:
                                  'No matches for the current search/filters.',
                              subtitle:
                                  'Try clearing the search or filters above.',
                            )
                          else
                            // 10 farmers a page; back to the first page on
                            // a new search, barangay or sort.
                            AdminPaged<_FarmerListRow>(
                              items: rows,
                              resetKey: (_barangayFilter, _sort, pageSearch),
                              builder: (context, page) =>
                                  _FarmerListTable(c: c, rows: page),
                            ),
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
}

class _FarmerListFilterBar extends StatelessWidget {
  final AdminPalette c;
  final List<String> barangayOptions;
  final String barangayFilter;
  final ValueChanged<String> onBarangayChanged;
  final _SortOption sort;
  final ValueChanged<_SortOption> onSortChanged;

  const _FarmerListFilterBar({
    required this.c,
    required this.barangayOptions,
    required this.barangayFilter,
    required this.onBarangayChanged,
    required this.sort,
    required this.onSortChanged,
  });

  static const _sortLabels = {
    _SortOption.nameAsc: 'Name A–Z',
    _SortOption.nameDesc: 'Name Z–A',
    _SortOption.newestApproved: 'Newest Approved',
    _SortOption.oldestApproved: 'Oldest Approved',
    _SortOption.mostActiveListings: 'Most Active Listings',
    _SortOption.mostOrders: 'Most Completed Orders',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AdminPillDropdown<String>(
          value: barangayFilter,
          width: 190,
          icon: Icons.place_outlined,
          items: [
            for (final b in barangayOptions)
              DropdownMenuItem(
                value: b,
                child: Text(b == 'All' ? 'All barangays' : b),
              ),
          ],
          onChanged: onBarangayChanged,
        ),
        AdminPillDropdown<_SortOption>(
          value: sort,
          width: 240,
          icon: Icons.sort,
          items: [
            for (final e in _sortLabels.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onSortChanged,
        ),
      ],
    );
  }
}

class _FarmerListTable extends StatelessWidget {
  final AdminPalette c;
  final List<_FarmerListRow> rows;
  const _FarmerListTable({required this.c, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: adminTableCard(c),
      // The header band follows the rounded corners.
      clipBehavior: Clip.antiAlias,
      padding: kAdminTablePadding,
      child: AdminTableFit(
        table: DataTable(
          headingRowColor: WidgetStateProperty.all(adminTableHeaderColor(c)),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
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
            DataColumn(label: Text('Full Name')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Barangay')),
            DataColumn(label: Text('Municipality')),
            DataColumn(label: Text('Date Approved')),
            DataColumn(label: Text('Active Listings'), numeric: true),
            DataColumn(label: Text('Completed Orders'), numeric: true),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: rows.map((r) {
            final dateApproved = r.reviewedAt != null
                ? DateFormat('MMM d, y').format(r.reviewedAt!.toDate())
                : '—';

            return DataRow(
              cells: [
                DataCell(Text(r.farmerId)),
                DataCell(
                  // The account's current photo, or its initials.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdminAvatar(
                        name: r.fullName,
                        photoUrl: r.data['photoUrl']?.toString(),
                        radius: 14,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        r.fullName.isEmpty ? '—' : r.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(r.email)),
                DataCell(Text(r.barangay)),
                DataCell(Text(r.municipality)),
                DataCell(Text(dateApproved)),
                DataCell(Text('${r.activeListings}')),
                DataCell(Text('${r.completedOrders}')),
                DataCell(
                  AdminStatusBadge(
                    text: 'Approved',
                    color: c.green,
                    bg: c.greenBg,
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: 'View Farmer details',
                    icon: Icon(
                      Icons.visibility_outlined,
                      size: 18,
                      color: c.textSecondary,
                    ),
                    onPressed: () =>
                        _showFarmerListDetails(context, uid: r.uid),
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
// FARMER DETAILS DIALOG — separate from Verification Queue's
// dialog. No Approve/Reject actions live here; farmers shown on
// this page are already approved.
// ============================================================

Future<void> _showFarmerListDetails(
  BuildContext context, {
  required String uid,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FarmerListDetailDialog(uid: uid),
  );
}

class _FarmerMarketplaceActivity {
  final int activeListings;
  final int archivedProducts;
  final int completedOrders;
  final num totalSales;
  const _FarmerMarketplaceActivity({
    required this.activeListings,
    required this.archivedProducts,
    required this.completedOrders,
    required this.totalSales,
  });
}

Future<_FarmerMarketplaceActivity> _loadFarmerMarketplaceActivity(
  String uid,
) async {
  // The two reads don't depend on each other: side by side, not in turn.
  final firestore = FirebaseFirestore.instance;
  final results = await AdminPerf.time(
    'farmer detail: listings + orders',
    () => Future.wait([
      firestore.collection('products').where('farmerId', isEqualTo: uid).get(),
      firestore.collection('orders').where('sellerId', isEqualTo: uid).get(),
    ]),
    describe: (r) => '${r[0].docs.length} products, ${r[1].docs.length} orders',
  );
  final products = results[0];
  final orders = results[1];
  var active = 0, archived = 0;
  for (final p in products.docs) {
    if ((p.data()['isArchived'] ?? false) == true) {
      archived++;
    } else {
      active++;
    }
  }

  final completedCount = orders.docs
      .where(
        (o) =>
            (o.data()['status'] ?? '').toString().toLowerCase() == 'completed',
      )
      .length;
  // TOTAL TRANSACTION VALUE — same definition/formula as the platform-
  // wide KPI tile (DashboardAnalyticsService.platformTransactionTotal),
  // just scoped to this one farmer's own orders.
  final totalSales = DashboardAnalyticsService.platformTransactionTotal(
    orders.docs,
  );

  return _FarmerMarketplaceActivity(
    activeListings: active,
    archivedProducts: archived,
    completedOrders: completedCount,
    totalSales: totalSales,
  );
}

class _FarmerListDetailDialog extends StatefulWidget {
  final String uid;
  const _FarmerListDetailDialog({required this.uid});

  @override
  State<_FarmerListDetailDialog> createState() =>
      _FarmerListDetailDialogState();
}

class _FarmerListDetailDialogState extends State<_FarmerListDetailDialog>
    with AdminReadOnce {
  String get uid => widget.uid;

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: watchOnce(
        'user',
        () =>
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      ),
      builder: (context, userSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: watchOnce(
            'verification',
            () => FirebaseFirestore.instance
                .collection('verificationDocs')
                .doc(uid)
                .snapshots(),
          ),
          builder: (context, verifSnap) {
            if (userSnap.hasError || verifSnap.hasError) {
              return AlertDialog(
                title: const Text('Something went wrong'),
                content: const Text(
                  'Could not load this farmer\'s details. Please try again.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            }
            if (!userSnap.hasData || !verifSnap.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 120,
                  child: Center(child: AdminLoadingBar()),
                ),
              );
            }

            final user = userSnap.data!.data();
            if (user == null) {
              return AlertDialog(
                title: const Text('Account Not Found'),
                content: const Text(
                  'This farmer\'s account could not be found. It may have been removed.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            }
            final verif = verifSnap.data!.data();

            final fullName =
                _firstNonEmpty([
                  verif?['fullName'],
                  user['fullName'],
                  user['name'],
                ]) ??
                'Unknown Farmer';
            final email = (user['email'] ?? '—').toString();
            // Registration saves it as mobileNumber; older accounts as phone.
            final phone =
                _firstNonEmpty([user['mobileNumber'], user['phone']]) ?? '—';
            final barangay = _firstNonEmpty([user['barangay']]) ?? '—';
            final municipality = _firstNonEmpty([user['municipality']]) ?? '—';
            final createdAt = user['createdAt'] as Timestamp?;
            final dateRegistered = createdAt != null
                ? DateFormat('MMM d, y – h:mm a').format(createdAt.toDate())
                : '—';

            final approvalStatus = (user['approvalStatus'] ?? '—').toString();
            final statusLabel = approvalStatus.isEmpty
                ? '—'
                : '${approvalStatus[0].toUpperCase()}${approvalStatus.substring(1)}';
            final submittedAt = verif?['submittedAt'] as Timestamp?;
            final dateSubmitted = submittedAt != null
                ? DateFormat('MMM d, y – h:mm a').format(submittedAt.toDate())
                : '—';
            final reviewedAt = user['reviewedAt'] as Timestamp?;
            final dateApproved = reviewedAt != null
                ? DateFormat('MMM d, y – h:mm a').format(reviewedAt.toDate())
                : '—';
            final reviewedByUid = _firstNonEmpty([user['reviewedBy']]);
            final farmerId = farmerIdOf(user, verif);
            final approved = approvalStatus == 'approved';

            final scheme = Theme.of(context).colorScheme;
            final muted = scheme.onSurface.withValues(alpha: 0.62);

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The farmer's current photo, or their initials.
                  AdminAvatar(
                    name: fullName,
                    photoUrl: user['photoUrl']?.toString(),
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'RSBA No. ${farmerId ?? kNoFarmerId}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            AdminStatusBadge(
                              text: statusLabel,
                              color: approved ? scheme.primary : muted,
                              bg: (approved ? scheme.primary : scheme.onSurface)
                                  .withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(
                        height: 1,
                        color: scheme.onSurface.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 16),
                      // What the farmer has done on the marketplace, as
                      // four figures side by side.
                      FutureBuilder<_FarmerMarketplaceActivity>(
                        future: readOnce(
                          'activity',
                          () => _loadFarmerMarketplaceActivity(uid),
                        ),
                        builder: (context, activitySnap) {
                          if (activitySnap.hasError) {
                            return Text(
                              'Could not load marketplace activity.',
                              style: TextStyle(color: muted, fontSize: 12.5),
                            );
                          }
                          final a = activitySnap.data;
                          String figure(
                            String Function(_FarmerMarketplaceActivity) of,
                          ) => a == null ? '…' : of(a);
                          return Row(
                            children: [
                              _stat(
                                context,
                                Icons.storefront_outlined,
                                'Active Listings',
                                figure((a) => '${a.activeListings}'),
                              ),
                              const SizedBox(width: 10),
                              _stat(
                                context,
                                Icons.archive_outlined,
                                'Archived Products',
                                figure((a) => '${a.archivedProducts}'),
                              ),
                              const SizedBox(width: 10),
                              _stat(
                                context,
                                Icons.task_alt_rounded,
                                'Completed Orders',
                                figure((a) => '${a.completedOrders}'),
                              ),
                              const SizedBox(width: 10),
                              _stat(
                                context,
                                Icons.payments_outlined,
                                'Total Sales',
                                figure((a) => formatPeso(a.totalSales)),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      _section(context, Icons.person_outline, 'Profile', [
                        _field(context, 'Email', email),
                        _field(context, 'Phone Number', phone),
                        _field(context, 'Barangay', barangay),
                        _field(context, 'Municipality', municipality),
                        _field(context, 'Date Registered', dateRegistered),
                      ]),
                      const SizedBox(height: 18),
                      _section(
                        context,
                        Icons.verified_user_outlined,
                        'Verification',
                        [
                          _field(context, 'Date Submitted', dateSubmitted),
                          _field(context, 'Date Approved', dateApproved),
                          // The officer's name, not their account code.
                          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            future: reviewedByUid == null
                                ? null
                                : readOnce(
                                    'officer/$reviewedByUid',
                                    () => FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(reviewedByUid)
                                        .get(),
                                  ),
                            builder: (context, officerSnap) {
                              final officer = officerSnap.data?.data();
                              return _field(
                                context,
                                'Reviewed By',
                                reviewedByUid == null
                                    ? '—'
                                    : _firstNonEmpty([
                                            officer?['fullName'],
                                            officer?['name'],
                                            officer?['email'],
                                          ]) ??
                                          (officerSnap.connectionState ==
                                                  ConnectionState.done
                                              ? 'Admin'
                                              : '…'),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // One figure of the farmer's marketplace activity: an icon, the number
  // and what it counts.
  Widget _stat(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // One titled group of details: its name with an icon, then its fields
  // two to a row.
  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    List<Widget> fields,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 16.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                children: [
                  for (final field in fields)
                    SizedBox(width: width, child: field),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // A detail: its name in small grey text, its value under it.
  Widget _field(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
