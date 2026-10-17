import 'package:cloud_firestore/cloud_firestore.dart';
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

/// One order, as the Transactions table shows it.
class AdminTransactionRow {
  final String id;
  final DateTime? date;
  final String buyer;
  final String seller;
  final String product;
  final String quantity;
  final num total;
  final String status;
  final String fulfillment;

  const AdminTransactionRow({
    required this.id,
    required this.date,
    required this.buyer,
    required this.seller,
    required this.product,
    required this.quantity,
    required this.total,
    required this.status,
    required this.fulfillment,
  });

  static DateTime? _date(dynamic value) =>
      value is Timestamp ? value.toDate() : null;

  factory AdminTransactionRow.fromOrder(String id, Map<String, dynamic> data) {
    final total = data['grandTotal'] ?? data['total'];
    final quantity = data['quantity'];
    return AdminTransactionRow(
      id: id,
      date: _date(data['createdAt']),
      buyer: (data['buyerName'] ?? '').toString().trim(),
      seller: (data['sellerName'] ?? '').toString().trim(),
      product: (data['productName'] ?? '').toString().trim(),
      quantity: (data['quantityLabel'] ?? '').toString().trim().isNotEmpty
          ? data['quantityLabel'].toString().trim()
          : (quantity is num
                ? formatStock(quantity, data['unit']?.toString())
                : ''),
      total: total is num ? total : num.tryParse('${total ?? ''}') ?? 0,
      status: (data['status'] ?? 'pending').toString().trim().toLowerCase(),
      fulfillment: (data['deliveryMethod'] ?? '').toString().trim(),
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isClosedWithoutSale => status == 'cancelled' || status == 'rejected';
  bool get isInProgress => !isCompleted && !isClosedWithoutSale;

  String get statusLabel => status.isEmpty
      ? 'Pending'
      : status
            .split(RegExp(r'[_\s]+'))
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return id.toLowerCase().contains(q) ||
        buyer.toLowerCase().contains(q) ||
        seller.toLowerCase().contains(q) ||
        product.toLowerCase().contains(q);
  }
}

/// Every order on the platform, newest first — each transaction the Admin
/// can monitor, where the dashboard shows only totals. Rows built from raw
/// order documents; pure, so it can be tested without Firestore.
List<AdminTransactionRow> buildTransactionRows(
  Iterable<({String id, Map<String, dynamic> data})> orders,
) {
  final rows = [
    for (final order in orders)
      AdminTransactionRow.fromOrder(order.id, order.data),
  ];
  rows.sort((a, b) {
    final at = a.date?.millisecondsSinceEpoch ?? 0;
    final bt = b.date?.millisecondsSinceEpoch ?? 0;
    return bt.compareTo(at);
  });
  return rows;
}

/// Admin Portal → Transactions: every order with who bought, who sold,
/// what, how much and its current status. Live — it reads the portal's
/// shared orders listener (DashboardDataService), so a new order or a
/// status change appears by itself. View only: orders are changed by the
/// buyer and farmer, never from here.
class AdminTransactionsView extends StatefulWidget {
  const AdminTransactionsView({super.key});

  @override
  State<AdminTransactionsView> createState() => _AdminTransactionsViewState();
}

class _AdminTransactionsViewState extends State<AdminTransactionsView>
    with AdminPageSearch {
  @override
  void onPageSearchChanged() => _shown = _pageSize;

  // Typed in the header's search box.
  String get _search => pageSearch;
  String _status = 'All';

  // Rows whose box is ticked, by order id.
  final Set<String> _ticked = {};

  static IconData _statusIcon(String status) => switch (status.toLowerCase()) {
    'pending' => Icons.hourglass_empty_rounded,
    'confirmed' => Icons.thumb_up_alt_outlined,
    'shipped' => Icons.local_shipping_outlined,
    'completed' => Icons.task_alt_rounded,
    'cancelled' || 'rejected' => Icons.cancel_outlined,
    _ => Icons.receipt_long_outlined,
  };

  // Rows are added to the table a page at a time, so a long history does
  // not build thousands of rows at once.
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
        if (!data.ordersReady) {
          return data.lastError != null
              ? const AdminStreamError(source: 'orders')
              : const AdminLoadingSpinner();
        }
        final all = buildTransactionRows([
          for (final doc in data.allOrders) (id: doc.id, data: doc.data()),
        ]);
        final statuses = {for (final row in all) row.statusLabel}.toList()
          ..sort();
        final status = statuses.contains(_status) ? _status : 'All';
        final filtered = [
          for (final row in all)
            if ((status == 'All' || row.statusLabel == status) &&
                row.matches(_search))
              row,
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The title is in the utility bar above.
              // One tab per status there are orders in.
              AdminTabbedTable<String>(
                selected: status,
                onSelected: (tab) => setState(() {
                  _status = tab;
                  _shown = _pageSize;
                  _ticked.clear();
                }),
                tabs: [
                  (
                    value: 'All',
                    label: 'All orders',
                    count: all.length,
                    icon: Icons.list_alt_rounded,
                  ),
                  for (final s in statuses)
                    (
                      value: s,
                      label: s,
                      count: all.where((r) => r.statusLabel == s).length,
                      icon: _statusIcon(s),
                    ),
                ],
                // How many rows are ticked, and Clear: level with the tabs,
                // so it is in view without scrolling to the table's end.
                trailing: AdminSelectionNote(
                  count: _ticked.length,
                  onClear: () => setState(_ticked.clear),
                ),
                child: _table(c, filtered, all.isEmpty),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _table(AdminPalette c, List<AdminTransactionRow> rows, bool noOrders) {
    final box = adminTableCard(c, tabbed: true);
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: box,
        child: AdminEmptyState(
          icon: Icons.receipt_long_outlined,
          title: noOrders ? 'No orders yet' : 'No orders match these filters',
          subtitle: noOrders
              ? 'Orders appear here as soon as buyers place them.'
              : 'Try a different search or status.',
        ),
      );
    }
    final visible = rows.take(_shown).toList();
    final secondary = TextStyle(color: c.textSecondary);
    return Container(
      width: double.infinity,
      decoration: adminTableCard(c, tabbed: true),
      // The header band follows the rounded corners.
      clipBehavior: Clip.antiAlias,
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
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Order ID')),
                DataColumn(label: Text('Buyer')),
                DataColumn(label: Text('Farmer')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Quantity')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('Fulfillment')),
                DataColumn(label: Text('Status')),
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
                          row.date == null
                              ? '—'
                              : DateFormat(
                                  'MMM d, y · h:mm a',
                                ).format(row.date!),
                          style: secondary,
                        ),
                      ),
                      DataCell(
                        Tooltip(
                          message: row.id,
                          child: Text(
                            row.id.length > 8 ? row.id.substring(0, 8) : row.id,
                            style: secondary,
                          ),
                        ),
                      ),
                      DataCell(Text(row.buyer.isEmpty ? '—' : row.buyer)),
                      DataCell(Text(row.seller.isEmpty ? '—' : row.seller)),
                      DataCell(
                        Text(
                          row.product.isEmpty ? '—' : row.product,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(Text(row.quantity.isEmpty ? '—' : row.quantity)),
                      DataCell(Text(formatPeso(row.total))),
                      DataCell(
                        Text(
                          row.fulfillment.isEmpty
                              ? '—'
                              : '${row.fulfillment[0].toUpperCase()}'
                                    '${row.fulfillment.substring(1)}',
                          style: secondary,
                        ),
                      ),
                      DataCell(_statusBadge(c, row)),
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
                    '${rows.length == 1 ? 'order' : 'orders'}',
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

  Widget _statusBadge(AdminPalette c, AdminTransactionRow row) {
    final (color, bg) = row.isCompleted
        ? (c.green, c.greenBg)
        : row.isClosedWithoutSale
        ? (c.red, c.redBg)
        : row.status == 'pending'
        ? (c.amber, c.amberBg)
        : (c.blue, c.blueBg);
    return AdminStatusBadge(text: row.statusLabel, color: color, bg: bg);
  }
}
