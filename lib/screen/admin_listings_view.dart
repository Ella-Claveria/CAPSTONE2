import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/audit_log_service.dart';
import '../services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_data_service.dart';
import '../services/market_price_helpers.dart';
import 'admin_dashboard_screen.dart'
    show
        AdminThemeScope,
        AdminPalette,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminStatusBadge,
        AdminStreamError;
import 'admin_filter_controls.dart';

/// Where a listing stands on the marketplace.
enum ListingStatus { active, soldOut, archived, suspended }

extension ListingStatusLabel on ListingStatus {
  String get label => switch (this) {
    ListingStatus.active => 'Active',
    ListingStatus.soldOut => 'Sold Out',
    ListingStatus.archived => 'Archived by Farmer',
    ListingStatus.suspended => 'Hidden by Admin',
  };
}

/// One product listing, as the Product Listings table shows it.
class AdminListingRow {
  final String id;
  final String name;
  final String category;
  final String farmer;
  final double? price;
  final double? wholesalePrice;
  final double stock;
  final String unit;
  final ListingStatus status;
  final DateTime? posted;

  const AdminListingRow({
    required this.id,
    required this.name,
    required this.category,
    required this.farmer,
    required this.price,
    required this.wholesalePrice,
    required this.stock,
    required this.unit,
    required this.status,
    required this.posted,
  });

  static double? _positive(dynamic raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value > 0 ? value : null;
  }

  factory AdminListingRow.fromProduct(String id, Map<String, dynamic> data) {
    final stock = _positive(data['quantity']) ?? 0;
    final wholesaleOn =
        data['wholesaleEnabled'] == true ||
        (data['wholesaleEnabled'] == null &&
            _positive(data['wholesalePrice']) != null);
    final created = data['createdAt'];
    return AdminListingRow(
      id: id,
      name: (data['name'] ?? '').toString().trim(),
      category: (data['category'] ?? '').toString().trim(),
      farmer: (data['farmerName'] ?? '').toString().trim(),
      price: _positive(data['retailPrice'] ?? data['price']),
      wholesalePrice: wholesaleOn ? _positive(data['wholesalePrice']) : null,
      stock: stock,
      unit: (data['unit'] ?? '').toString().trim(),
      // Hidden by an Admin outranks the farmer's own archive; a listing
      // with no stock left is not on sale either way. An Admin never
      // deletes a listing: one marked "removed" by an earlier decision is
      // hidden like any other, and can be restored.
      status: data['isSuspended'] == true
          ? ListingStatus.suspended
          : data['isArchived'] == true
          ? ListingStatus.archived
          : stock <= 0
          ? ListingStatus.soldOut
          : ListingStatus.active,
      posted: created is Timestamp ? created.toDate() : null,
    );
  }

  /// Whether [query] is in the product, farmer, category or listing ID.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        farmer.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        id.toLowerCase().contains(q);
  }
}

/// Every listing as a row, newest first; one with no posting date last.
List<AdminListingRow> buildListingRows(
  Iterable<({String id, Map<String, dynamic> data})> products,
) =>
    [
      for (final product in products)
        AdminListingRow.fromProduct(product.id, product.data),
    ]..sort((a, b) {
      final ad = a.posted, bd = b.posted;
      if (ad == null || bd == null) {
        return ad == bd ? 0 : (ad == null ? 1 : -1);
      }
      return bd.compareTo(ad);
    });

/// Admin Portal → Product Listings: every listing on AgriTrade+ with its
/// farmer, price, stock and status, searchable and filterable. Live from
/// the portal's shared products listener (DashboardDataService). View
/// listings can be restored here; Hide/Remove decisions start in Moderation.
class AdminListingsView extends StatefulWidget {
  const AdminListingsView({super.key});

  @override
  State<AdminListingsView> createState() => _AdminListingsViewState();
}

class _AdminListingsViewState extends State<AdminListingsView>
    with AdminPageSearch {
  @override
  void onPageSearchChanged() => _shown = _pageSize;

  final Set<String> _restoring = {};

  Future<void> _restore(AdminListingRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore listing?'),
        content: Text(
          'Clear the admin restriction on "${row.name}"? The farmer account, stock and archive status still determine marketplace availability.',
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
    if (confirmed != true || !mounted || _restoring.contains(row.id)) return;
    setState(() => _restoring.add(row.id));
    try {
      if (!await ConnectivityService.instance.checkNow()) {
        throw StateError(kNoInternetActionMessage);
      }
      final ref = FirebaseFirestore.instance.collection('products').doc(row.id);
      await FirebaseFirestore.instance.runTransaction<void>((tx) async {
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
          'moderatedBy': FirebaseAuth.instance.currentUser?.uid,
          'moderatedAt': FieldValue.serverTimestamp(),
        });
      });
      AuditLogService.log(
        AuditAction.restoreListing,
        'Restored listing ${row.id}: ${row.name}.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin restriction cleared.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _restoring.remove(row.id));
    }
  }

  // Hiding or restoring the ticked listings.
  bool _working = false;

  // The ticked listings and what applies to them: Hide for those still on
  // the farmer's side, Restore for those an Admin has hidden.
  Widget _selectionBar(AdminPalette c, List<AdminListingRow> selected) {
    if (selected.isEmpty) return const SizedBox.shrink();
    final hidden = [
      for (final row in selected)
        if (row.status == ListingStatus.suspended) row,
    ];
    final shown = [
      for (final row in selected)
        if (row.status != ListingStatus.suspended) row,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminSelectionNote(
          count: selected.length,
          onClear: () => setState(_ticked.clear),
        ),
        if (hidden.isNotEmpty) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _working ? null : () => _setHidden(hidden, hide: false),
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: Text('Restore (${hidden.length})'),
          ),
        ],
        if (shown.isNotEmpty) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _working ? null : () => _setHidden(shown, hide: true),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.visibility_off_outlined, size: 16),
            label: Text('Hide (${shown.length})'),
          ),
        ],
      ],
    );
  }

  // Hides the listings from the marketplace (with the reason, which is
  // kept on each listing), or clears that again. A listing is never
  // deleted: the farmer keeps it, and an Admin can restore it.
  Future<void> _setHidden(
    List<AdminListingRow> rows, {
    required bool hide,
  }) async {
    final one = rows.length == 1;
    final label = one ? '"${rows.single.name}"' : '${rows.length} listings';
    final reasonController = TextEditingController();
    var missingReason = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(hide ? 'Hide $label?' : 'Restore $label?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hide
                      ? 'Buyers will no longer see or order '
                            '${one ? 'it' : 'them'}. Nothing is deleted: the '
                            'farmer keeps the listing, and you can restore '
                            'it from Hidden by Admin.'
                      : 'The admin restriction is cleared. The farmer '
                            'account, stock and archive status still decide '
                            'whether buyers see ${one ? 'it' : 'them'}.',
                ),
                if (hide) ...[
                  const SizedBox(height: 14),
                  AdminField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: adminMultilineDecoration(
                      dialogContext,
                      labelText: 'Reason (required)',
                      hintText: 'e.g. Wrong product photo',
                    ),
                  ),
                  if (missingReason)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text(
                        'Give the reason: it is kept on the listing.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (hide && reasonController.text.trim().isEmpty) {
                  setDialogState(() => missingReason = true);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(hide ? 'Hide' : 'Restore'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    if (confirmed != true || !mounted || _working) return;
    setState(() => _working = true);
    try {
      if (!await ConnectivityService.instance.checkNow()) {
        throw StateError(kNoInternetActionMessage);
      }
      final firestore = FirebaseFirestore.instance;
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      // Firestore takes at most 500 writes in a batch.
      for (var i = 0; i < rows.length; i += 400) {
        final batch = firestore.batch();
        for (final row in rows.skip(i).take(400)) {
          batch.update(firestore.collection('products').doc(row.id), {
            'isSuspended': hide,
            'moderationStatus': hide ? 'hidden' : 'restored',
            'moderationReason': hide ? reason : FieldValue.delete(),
            'moderatedBy': adminUid,
            'moderatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      final what = one ? 'listing' : '${rows.length} listings';
      final names = rows.map((row) => row.name).join(', ');
      AuditLogService.log(
        hide ? AuditAction.suspendListing : AuditAction.restoreListing,
        hide ? 'Hid $what: $names. Reason: $reason' : 'Restored $what: $names.',
      );
      if (!mounted) return;
      setState(() => _ticked.removeAll(rows.map((row) => row.id)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hide
                ? 'Hidden $label. Find ${one ? 'it' : 'them'} under '
                      'Hidden by Admin.'
                : 'Restored $label.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not ${hide ? 'hide' : 'restore'} $label: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // Typed in the header's search box.
  String get _search => pageSearch;
  ListingStatus? _status;
  String _category = 'All';

  // Rows whose box is ticked, by listing id.
  final Set<String> _ticked = {};

  static IconData _statusIcon(ListingStatus status) => switch (status) {
    ListingStatus.active => Icons.storefront_outlined,
    ListingStatus.soldOut => Icons.remove_shopping_cart_outlined,
    ListingStatus.archived => Icons.archive_outlined,
    ListingStatus.suspended => Icons.visibility_off_outlined,
  };

  static const int _pageSize = 50;
  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return ListenableBuilder(
      listenable: DashboardDataService.instance,
      builder: (context, _) {
        final data = DashboardDataService.instance;
        if (!data.productsReady) {
          return data.lastError != null
              ? const AdminStreamError(source: 'products')
              : const AdminLoadingSpinner();
        }
        final all = buildListingRows([
          for (final doc in data.products) (id: doc.id, data: doc.data()),
        ]);
        final categories = {
          for (final row in all)
            if (row.category.isNotEmpty) row.category,
        }.toList()..sort();
        final category = categories.contains(_category) ? _category : 'All';
        // The category narrows every tab; the tabs then split by status.
        final inCategory = [
          for (final row in all)
            if (category == 'All' || row.category == category) row,
        ];
        final filtered = [
          for (final row in inCategory)
            if ((_status == null || row.status == _status) &&
                row.matches(_search))
              row,
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The title is in the utility bar above.
              _filters(c, categories, category),
              const SizedBox(height: 16),
              AdminTabbedTable<ListingStatus?>(
                selected: _status,
                onSelected: (tab) => setState(() {
                  _status = tab;
                  _shown = _pageSize;
                  _ticked.clear();
                }),
                tabs: [
                  (
                    value: null,
                    label: 'All listings',
                    count: inCategory.length,
                    icon: Icons.inventory_2_outlined,
                  ),
                  for (final status in ListingStatus.values)
                    (
                      value: status,
                      label: status.label,
                      count: inCategory.where((r) => r.status == status).length,
                      icon: _statusIcon(status),
                    ),
                ],
                // How many rows are ticked, what can be done with them,
                // and Clear: level with the tabs, so it is in view without
                // scrolling to the table's end.
                trailing: _selectionBar(c, [
                  for (final row in all)
                    if (_ticked.contains(row.id)) row,
                ]),
                child: _table(c, filtered, all.isEmpty),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filters(AdminPalette c, List<String> categories, String category) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AdminPillDropdown<String>(
          value: category,
          icon: Icons.category_outlined,
          items: [
            const DropdownMenuItem(value: 'All', child: Text('All categories')),
            for (final name in categories)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) => setState(() {
            _category = value;
            _shown = _pageSize;
          }),
        ),
      ],
    );
  }

  Widget _table(AdminPalette c, List<AdminListingRow> rows, bool none) {
    final box = adminTableCard(c, tabbed: true);
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: box,
        child: AdminEmptyState(
          icon: Icons.inventory_2_outlined,
          title: none ? 'No listings yet' : 'No listings match these filters',
          subtitle: none
              ? 'Listings appear here as soon as farmers post them.'
              : 'Try a different search, category or status.',
        ),
      );
    }
    final visible = rows.take(_shown).toList();
    final secondary = TextStyle(color: c.textSecondary);
    return Container(
      width: double.infinity,
      decoration: adminTableCard(c, tabbed: true),
      padding: kAdminTablePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                DataColumn(label: Text('Posted')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Farmer')),
                DataColumn(label: Text('Retail Price')),
                DataColumn(label: Text('Wholesale Price')),
                DataColumn(label: Text('Available Stock')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Action')),
              ],
              rows: [
                for (final row in visible)
                  DataRow(
                    selected: _ticked.contains(row.id),
                    onSelectChanged: (ticked) => setState(() {
                      if (ticked ?? false) {
                        _ticked.add(row.id);
                      } else {
                        _ticked.remove(row.id);
                      }
                    }),
                    cells: [
                      DataCell(
                        Text(
                          row.posted == null
                              ? '—'
                              : DateFormat('MMM d, y').format(row.posted!),
                          style: secondary,
                        ),
                      ),
                      DataCell(
                        Text(
                          row.name.isEmpty ? '—' : row.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(
                        Text(
                          row.category.isEmpty ? '—' : row.category,
                          style: secondary,
                        ),
                      ),
                      DataCell(Text(row.farmer.isEmpty ? '—' : row.farmer)),
                      DataCell(
                        Text(
                          row.price == null
                              ? '—'
                              : formatPriceWithUnit(row.price!, row.unit),
                        ),
                      ),
                      DataCell(
                        Text(
                          row.wholesalePrice == null
                              ? '—'
                              : formatPriceWithUnit(
                                  row.wholesalePrice!,
                                  row.unit,
                                ),
                          style: secondary,
                        ),
                      ),
                      DataCell(Text(formatStock(row.stock, row.unit))),
                      DataCell(_statusBadge(c, row.status)),
                      DataCell(
                        row.status == ListingStatus.suspended
                            ? TextButton(
                                onPressed: _restoring.contains(row.id)
                                    ? null
                                    : () => _restore(row),
                                child: const Text('Restore'),
                              )
                            : const Text('—'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${visible.length} of ${rows.length} '
                    '${rows.length == 1 ? 'listing' : 'listings'}',
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ),
                if (rows.length > visible.length)
                  TextButton(
                    onPressed: () => setState(() => _shown += _pageSize),
                    child: const Text('Show more'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(AdminPalette c, ListingStatus status) {
    final (color, bg) = switch (status) {
      ListingStatus.active => (c.green, c.greenBg),
      ListingStatus.soldOut => (c.amber, c.amberBg),
      ListingStatus.archived => (c.blue, c.blueBg),
      ListingStatus.suspended => (c.red, c.redBg),
    };
    return AdminStatusBadge(text: status.label, color: color, bg: bg);
  }
}
