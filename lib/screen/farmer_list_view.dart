import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

import '../services/audit_log_service.dart';
import '../services/dashboard_analytics_service.dart';
import '../services/market_price_helpers.dart';
import '../services/pdf_report_service.dart';
import 'admin_dashboard_screen.dart'
    show
        AdminPalette,
        AdminThemeScope,
        AdminStatCard,
        AdminStatusBadge,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminStreamError,
        AdminQuickActionButton;

/// Farmer List — a physically separate screen from Verification Queue.
/// It does not import or reuse Verification Queue's dialog, data loaders,
/// or approve/reject actions; it only shares the common Admin Dashboard
/// design-system pieces (AdminStatCard, AdminStatusBadge, etc.) that every
/// admin page is built from.
///
/// Shows role == 'farmer' && approvalStatus == 'approved' only — no
/// pending, no rejected, no buyers, no admins.
enum _SortOption { nameAsc, nameDesc, newestApproved, oldestApproved, mostActiveListings, mostOrders }

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

  String get fullName => (data['fullName'] ?? data['name'] ?? 'Unknown Farmer').toString();
  String get email => (data['email'] ?? '—').toString();
  String get barangay =>
      (data['barangay']?.toString().trim().isNotEmpty == true) ? data['barangay'].toString() : '—';
  String get municipality =>
      (data['municipality']?.toString().trim().isNotEmpty == true) ? data['municipality'].toString() : '—';
  Timestamp? get reviewedAt => data['reviewedAt'] as Timestamp?;
}

/// Joins approved-farmer docs with their products/orders — shared by the
/// live StreamBuilder view and the one-time fetch behind Export Report, so
/// the two can never drift apart on how a count is computed.
List<_FarmerListRow> _computeFarmerRows(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> farmerDocs,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
) {
  final productsByFarmer = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final p in productDocs) {
    final fid = (p.data()['farmerId'] ?? '').toString();
    if (fid.isEmpty) continue;
    productsByFarmer.putIfAbsent(fid, () => []).add(p);
  }
  final ordersByFarmer = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final o in orderDocs) {
    final sid = (o.data()['sellerId'] ?? '').toString();
    if (sid.isEmpty) continue;
    ordersByFarmer.putIfAbsent(sid, () => []).add(o);
  }

  return farmerDocs.map((doc) {
    final uid = doc.id;
    final products = productsByFarmer[uid] ?? const [];
    final active = products.where((p) => (p.data()['isArchived'] ?? false) != true).length;
    final archived = products.length - active;
    final orders = ordersByFarmer[uid] ?? const [];
    final completed =
        orders.where((o) => (o.data()['status'] ?? '').toString().toLowerCase() == 'completed').length;
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

class _FarmerListViewState extends State<FarmerListView> {
  String _search = '';
  String _barangayFilter = 'All';
  String _municipalityFilter = 'All';
  _SortOption _sort = _SortOption.newestApproved;
  bool _exporting = false;

  // Same filter + sort the live table applies — factored out so Export
  // Report can reuse it exactly instead of re-implementing it.
  List<_FarmerListRow> _filterAndSort(List<_FarmerListRow> allRows) {
    var rows = allRows.where((r) {
      if (_barangayFilter != 'All' && r.barangay != _barangayFilter) return false;
      if (_municipalityFilter != 'All' && r.municipality != _municipalityFilter) return false;
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return r.fullName.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.barangay.toLowerCase().contains(q) ||
          r.municipality.toLowerCase().contains(q) ||
          r.uid.toLowerCase().contains(q);
    }).toList();

    rows.sort((a, b) {
      switch (_sort) {
        case _SortOption.nameAsc:
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case _SortOption.nameDesc:
          return b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase());
        case _SortOption.newestApproved:
          return (b.reviewedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.reviewedAt?.millisecondsSinceEpoch ?? 0);
        case _SortOption.oldestApproved:
          return (a.reviewedAt?.millisecondsSinceEpoch ?? 0).compareTo(b.reviewedAt?.millisecondsSinceEpoch ?? 0);
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
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'farmer')
            .where('approvalStatus', isEqualTo: 'approved')
            .get(),
        FirebaseFirestore.instance.collection('products').get(),
        FirebaseFirestore.instance.collection('orders').get(),
      ]);
      final allRows = _computeFarmerRows(results[0].docs, results[1].docs, results[2].docs);
      final rows = _filterAndSort(allRows);

      final bytes = await PdfReportService.buildFarmerListReport(
        totalFarmers: allRows.length,
        activeListingsTotal: allRows.fold<int>(0, (t, r) => t + r.activeListings),
        completedOrdersTotal: allRows.fold<int>(0, (t, r) => t + r.completedOrders),
        rows: rows
            .map((r) => (
                  farmerId: r.uid.length > 8 ? r.uid.substring(0, 8) : r.uid,
                  fullName: r.fullName,
                  email: r.email,
                  barangay: r.barangay,
                  municipality: r.municipality,
                  dateApproved: r.reviewedAt != null ? DateFormat('MMM d, y').format(r.reviewedAt!.toDate()) : '—',
                  activeListings: r.activeListings,
                  completedOrders: r.completedOrders,
                ))
            .toList(),
      );
      if (!mounted) return;
      await PdfReportService.share(bytes, 'agritrade_farmer_list.pdf');
      AuditLogService.log(
        AuditAction.exportReport,
        'Exported the Farmer List report (${rows.length} of ${allRows.length} farmers shown).',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Farmer List report exported.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Farmer List',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.textPrimary)),
                  Text('View and manage approved farmer accounts registered in AgriTrade+.',
                      style: TextStyle(color: c.textSecondary)),
                ],
              ),
              AdminQuickActionButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Export Report',
                onPressed: _exporting ? () {} : _export,
              ),
            ],
          ),
          const SizedBox(height: 20),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'farmer')
                  .where('approvalStatus', isEqualTo: 'approved')
                  .snapshots(),
              builder: (context, farmerSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('products').snapshots(),
                  builder: (context, productSnap) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
                      builder: (context, orderSnap) {
                        final snapshots = [farmerSnap, productSnap, orderSnap];
                        if (snapshots.any((s) => s.hasError)) {
                          return const AdminStreamError();
                        }
                        if (snapshots.any((s) => !s.hasData)) {
                          return const AdminLoadingSpinner();
                        }

                        final allRows = _computeFarmerRows(
                          farmerSnap.data!.docs,
                          productSnap.data!.docs,
                          orderSnap.data!.docs,
                        );

                        final totalFarmers = allRows.length;
                        final activeListingsTotal =
                            allRows.fold<int>(0, (total, r) => total + r.activeListings);
                        final completedOrdersTotal =
                            allRows.fold<int>(0, (total, r) => total + r.completedOrders);

                        final barangayOptions = {
                          'All',
                          ...allRows.map((r) => r.barangay).where((b) => b != '—'),
                        }.toList()
                          ..sort();
                        final municipalityOptions = {
                          'All',
                          ...allRows.map((r) => r.municipality).where((m) => m != '—'),
                        }.toList()
                          ..sort();

                        final rows = _filterAndSort(allRows);

                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(builder: (context, constraints) {
                                // A Wrap (not a fixed-childAspectRatio
                                // GridView) so each card sizes to its own
                                // content height — it can't overflow at any
                                // width — while the column count still
                                // reflows continuously with the available
                                // space (see the same fix on the Dashboard
                                // Overview's KPI row).
                                const spacing = 16.0;
                                final width = constraints.maxWidth;
                                final columns = width >= 760 ? 3 : (width >= 480 ? 2 : 1);
                                final cardWidth = (width - spacing * (columns - 1)) / columns;
                                final cards = [
                                  AdminStatCard(
                                    label: 'Total Farmers',
                                    value: '$totalFarmers',
                                    delta: 'Approved & active on AgriTrade+',
                                    icon: Icons.groups_outlined,
                                    iconColor: (c) => c.green,
                                    iconBg: (c) => c.greenBg,
                                    isEmpty: totalFarmers == 0,
                                  ),
                                  AdminStatCard(
                                    label: 'Active Listings',
                                    value: '$activeListingsTotal',
                                    delta: 'From approved farmers',
                                    icon: Icons.inventory_2_outlined,
                                    iconColor: (c) => c.blue,
                                    iconBg: (c) => c.blueBg,
                                    isEmpty: activeListingsTotal == 0,
                                  ),
                                  AdminStatCard(
                                    label: 'Completed Orders',
                                    value: '$completedOrdersTotal',
                                    delta: 'From approved farmers',
                                    icon: Icons.local_shipping_outlined,
                                    iconColor: (c) => c.amber,
                                    iconBg: (c) => c.amberBg,
                                    isEmpty: completedOrdersTotal == 0,
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

                              _FarmerListFilterBar(
                                c: c,
                                search: _search,
                                onSearchChanged: (v) => setState(() => _search = v),
                                barangayOptions: barangayOptions,
                                barangayFilter: _barangayFilter,
                                onBarangayChanged: (v) => setState(() => _barangayFilter = v),
                                municipalityOptions: municipalityOptions,
                                municipalityFilter: _municipalityFilter,
                                onMunicipalityChanged: (v) => setState(() => _municipalityFilter = v),
                                sort: _sort,
                                onSortChanged: (v) => setState(() => _sort = v),
                              ),
                              const SizedBox(height: 16),

                              if (allRows.isEmpty)
                                const AdminEmptyState(
                                  icon: Icons.groups_outlined,
                                  title: 'No verified farmers yet.',
                                  subtitle: 'Approved Farmer accounts will appear here.',
                                )
                              else if (rows.isEmpty)
                                AdminEmptyState(
                                  icon: Icons.search_off,
                                  title: 'No matches for the current search/filters.',
                                  subtitle: 'Try clearing the search or filters above.',
                                )
                              else
                                _FarmerListTable(c: c, rows: rows),
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
}

class _FarmerListFilterBar extends StatelessWidget {
  final AdminPalette c;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final List<String> barangayOptions;
  final String barangayFilter;
  final ValueChanged<String> onBarangayChanged;
  final List<String> municipalityOptions;
  final String municipalityFilter;
  final ValueChanged<String> onMunicipalityChanged;
  final _SortOption sort;
  final ValueChanged<_SortOption> onSortChanged;

  const _FarmerListFilterBar({
    required this.c,
    required this.search,
    required this.onSearchChanged,
    required this.barangayOptions,
    required this.barangayFilter,
    required this.onBarangayChanged,
    required this.municipalityOptions,
    required this.municipalityFilter,
    required this.onMunicipalityChanged,
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

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            style: fieldStyle,
            decoration:
                _fieldDecoration('Search name, email, Farmer ID, barangay, municipality…', Icons.search),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            initialValue: barangayFilter,
            style: fieldStyle,
            dropdownColor: c.surface,
            isExpanded: true,
            decoration: _fieldDecoration('Barangay', Icons.place_outlined),
            items: barangayOptions
                .map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => v != null ? onBarangayChanged(v) : null,
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            initialValue: municipalityFilter,
            style: fieldStyle,
            dropdownColor: c.surface,
            isExpanded: true,
            decoration: _fieldDecoration('Municipality', Icons.location_city_outlined),
            items: municipalityOptions
                .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => v != null ? onMunicipalityChanged(v) : null,
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<_SortOption>(
            initialValue: sort,
            style: fieldStyle,
            dropdownColor: c.surface,
            isExpanded: true,
            decoration: _fieldDecoration('Sort by', Icons.sort),
            items: _sortLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => v != null ? onSortChanged(v) : null,
          ),
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
            final farmerId = r.uid.length > 8 ? r.uid.substring(0, 8) : r.uid;
            final dateApproved =
                r.reviewedAt != null ? DateFormat('MMM d, y').format(r.reviewedAt!.toDate()) : '—';

            return DataRow(cells: [
              DataCell(Text(farmerId)),
              DataCell(Text(r.fullName)),
              DataCell(Text(r.email)),
              DataCell(Text(r.barangay)),
              DataCell(Text(r.municipality)),
              DataCell(Text(dateApproved)),
              DataCell(Text('${r.activeListings}')),
              DataCell(Text('${r.completedOrders}')),
              DataCell(AdminStatusBadge(text: 'Approved', color: c.green, bg: c.greenBg)),
              DataCell(IconButton(
                tooltip: 'View Farmer details',
                icon: Icon(Icons.visibility_outlined, size: 18, color: c.textSecondary),
                onPressed: () => _showFarmerListDetails(context, uid: r.uid),
              )),
            ]);
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

Future<void> _showFarmerListDetails(BuildContext context, {required String uid}) {
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

Future<_FarmerMarketplaceActivity> _loadFarmerMarketplaceActivity(String uid) async {
  final products =
      await FirebaseFirestore.instance.collection('products').where('farmerId', isEqualTo: uid).get();
  var active = 0, archived = 0;
  for (final p in products.docs) {
    if ((p.data()['isArchived'] ?? false) == true) {
      archived++;
    } else {
      active++;
    }
  }

  final orders =
      await FirebaseFirestore.instance.collection('orders').where('sellerId', isEqualTo: uid).get();
  final completedCount = orders.docs
      .where((o) => (o.data()['status'] ?? '').toString().toLowerCase() == 'completed')
      .length;
  // TOTAL TRANSACTION VALUE — same definition/formula as the platform-
  // wide KPI tile (DashboardAnalyticsService.platformTransactionTotal),
  // just scoped to this one farmer's own orders.
  final totalSales = DashboardAnalyticsService.platformTransactionTotal(orders.docs);

  return _FarmerMarketplaceActivity(
    activeListings: active,
    archivedProducts: archived,
    completedOrders: completedCount,
    totalSales: totalSales,
  );
}

class _FarmerListDetailDialog extends StatelessWidget {
  final String uid;
  const _FarmerListDetailDialog({required this.uid});

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
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('verificationDocs').doc(uid).snapshots(),
          builder: (context, verifSnap) {
            if (userSnap.hasError || verifSnap.hasError) {
              return AlertDialog(
                title: const Text('Something went wrong'),
                content: const Text('Could not load this farmer\'s details. Please try again.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              );
            }
            if (!userSnap.hasData || !verifSnap.hasData) {
              return const AlertDialog(
                content: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              );
            }

            final user = userSnap.data!.data();
            if (user == null) {
              return AlertDialog(
                title: const Text('Account Not Found'),
                content: const Text('This farmer\'s account could not be found. It may have been removed.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              );
            }
            final verif = verifSnap.data!.data();

            final fullName =
                _firstNonEmpty([verif?['fullName'], user['fullName'], user['name']]) ?? 'Unknown Farmer';
            final email = (user['email'] ?? '—').toString();
            final phone = _firstNonEmpty([user['phone']]) ?? '—';
            final barangay = _firstNonEmpty([user['barangay']]) ?? '—';
            final municipality = _firstNonEmpty([user['municipality']]) ?? '—';
            final createdAt = user['createdAt'] as Timestamp?;
            final dateRegistered =
                createdAt != null ? DateFormat('MMM d, y – h:mm a').format(createdAt.toDate()) : '—';

            final approvalStatus = (user['approvalStatus'] ?? '—').toString();
            final statusLabel = approvalStatus.isEmpty
                ? '—'
                : '${approvalStatus[0].toUpperCase()}${approvalStatus.substring(1)}';
            final submittedAt = verif?['submittedAt'] as Timestamp?;
            final dateSubmitted =
                submittedAt != null ? DateFormat('MMM d, y – h:mm a').format(submittedAt.toDate()) : '—';
            final reviewedAt = user['reviewedAt'] as Timestamp?;
            final dateApproved =
                reviewedAt != null ? DateFormat('MMM d, y – h:mm a').format(reviewedAt.toDate()) : '—';
            final reviewedByUid = _firstNonEmpty([user['reviewedBy']]);
            final reviewedBy = reviewedByUid == null
                ? '—'
                : (reviewedByUid.length > 8 ? reviewedByUid.substring(0, 8) : reviewedByUid);
            final document = (verif?['document'] ?? '').toString();

            return AlertDialog(
              title: Text(fullName),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Profile'),
                      _detailRow('Full Name', fullName),
                      _detailRow('Email', email),
                      _detailRow('Phone Number', phone),
                      _detailRow('Barangay', barangay),
                      _detailRow('Municipality', municipality),
                      _detailRow('Date Registered', dateRegistered),
                      const SizedBox(height: 10),
                      _sectionLabel('Verification'),
                      _detailRow('Approval Status', statusLabel),
                      _detailRow('Date Submitted', dateSubmitted),
                      _detailRow('Date Approved', dateApproved),
                      _detailRow('Reviewed By', reviewedBy),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.image_search, color: Colors.blue),
                        label: const Text('View Verification Document'),
                        onPressed:
                            document.isEmpty ? null : () => _showFarmerListDocument(context, document),
                      ),
                      if (document.isEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'No verification document was submitted for this account.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FutureBuilder<_FarmerMarketplaceActivity>(
                        future: _loadFarmerMarketplaceActivity(uid),
                        builder: (context, activitySnap) {
                          if (activitySnap.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          if (activitySnap.hasError || !activitySnap.hasData) {
                            return Text(
                              'Could not load marketplace activity.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            );
                          }
                          final a = activitySnap.data!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('Marketplace Activity'),
                              _detailRow('Active Listings', '${a.activeListings}'),
                              _detailRow('Archived Products', '${a.archivedProducts}'),
                              _detailRow('Completed Orders', '${a.completedOrders}'),
                              _detailRow('Total Sales / Transaction Value', formatPeso(a.totalSales)),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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
}

void _showFarmerListDocument(BuildContext context, String document) {
  Widget imageWidget;

  try {
    if (document.startsWith('http://') || document.startsWith('https://')) {
      imageWidget = Image.network(
        document,
        width: 400,
        height: 400,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Text('Failed to load document image.'),
      );
    } else if (document.isNotEmpty) {
      final cleanBase64 = document.contains(',') ? document.split(',').last : document;
      imageWidget = Image.memory(
        base64Decode(cleanBase64),
        width: 400,
        height: 400,
        fit: BoxFit.contain,
      );
    } else {
      imageWidget = const Text('No document image provided.');
    }
  } catch (e) {
    imageWidget = const Text('Failed to load image format.');
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Agricultural Certification'),
      content: imageWidget,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
