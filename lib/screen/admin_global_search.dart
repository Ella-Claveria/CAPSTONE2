import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_data_service.dart';
import '../services/rsba_number.dart';
import 'admin_dashboard_screen.dart' show AdminThemeScope;
import 'admin_filter_controls.dart';
import 'admin_listings_view.dart';
import 'admin_notifications.dart';
import 'admin_transactions_view.dart';

/// One match of the header search: what it is, and the page it is on.
class AdminSearchHit {
  final IconData icon;
  final String group;
  final String title;
  final String detail;
  final AdminNotificationTarget target;

  const AdminSearchHit({
    required this.icon,
    required this.group,
    required this.title,
    required this.detail,
    required this.target,
  });
}

/// Farmers, listings and transactions matching [query] — a few of each, in
/// that order. Pure, so it can be tested without Firestore.
List<AdminSearchHit> searchAdminRecords(
  String query, {
  required Iterable<AdminRecord> users,
  required Iterable<AdminRecord> products,
  required Iterable<AdminRecord> orders,
  int perGroup = 4,
}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final hits = <AdminSearchHit>[];

  var found = 0;
  for (final user in users) {
    final data = user.data;
    if (data['role'] != 'farmer' || data['approvalStatus'] != 'approved') {
      continue;
    }
    final name = (data['fullName'] ?? data['name'] ?? '').toString().trim();
    final farmerId = farmerIdOf(data) ?? '';
    final barangay = (data['barangay'] ?? '').toString().trim();
    if (![name, farmerId, barangay].any((v) => v.toLowerCase().contains(q))) {
      continue;
    }
    hits.add(
      AdminSearchHit(
        icon: Icons.agriculture_outlined,
        group: 'Farmer',
        title: name.isEmpty ? 'Unnamed farmer' : name,
        detail: [
          if (farmerId.isNotEmpty) 'RSBA No. $farmerId',
          if (barangay.isNotEmpty) barangay,
        ].join(' · '),
        target: AdminNotificationTarget.farmers,
      ),
    );
    if (++found == perGroup) break;
  }

  for (final row in buildListingRows(
    products,
  ).where((r) => r.matches(q)).take(perGroup)) {
    hits.add(
      AdminSearchHit(
        icon: Icons.inventory_2_outlined,
        group: 'Listing',
        title: row.name.isEmpty ? 'Unnamed listing' : row.name,
        detail: [
          if (row.category.isNotEmpty) row.category,
          if (row.farmer.isNotEmpty) row.farmer,
        ].join(' · '),
        target: AdminNotificationTarget.listings,
      ),
    );
  }

  for (final row in buildTransactionRows(
    orders,
  ).where((r) => r.matches(q)).take(perGroup)) {
    hits.add(
      AdminSearchHit(
        icon: Icons.receipt_long_outlined,
        group: 'Transaction',
        title: row.product.isEmpty ? 'Order' : row.product,
        detail: [
          if (row.buyer.isNotEmpty) row.buyer,
          if (row.seller.isNotEmpty) row.seller,
          row.statusLabel,
        ].join(' · '),
        target: AdminNotificationTarget.transactions,
      ),
    );
  }
  return hits;
}

/// What the header's search does on each page, by the page's place in
/// the sidebar: on a page with a table it filters that table (the hint
/// says what by); anywhere else it finds farmers, listings and
/// transactions and opens the page of the one picked.
const Map<int, String> kAdminPageSearchHints = {
  2: 'Search name, email or area…',
  3: 'Search name, email, RSBA No. or barangay…',
  5: 'Search order ID, buyer, farmer or product…',
  6: 'Search product, farmer or category…',
  7: 'Search farmer, listing, report ID or reporter…',
  9: 'Search loaded entries…',
};

/// The one search box of the portal, in its header.
class AdminGlobalSearch extends StatefulWidget {
  /// The open page, by its place in the sidebar.
  final int page;
  const AdminGlobalSearch({super.key, required this.page});

  @override
  State<AdminGlobalSearch> createState() => _AdminGlobalSearchState();
}

class _AdminGlobalSearchState extends State<AdminGlobalSearch> {
  List<AdminRecord> _users = const [];
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool get _filtersPage => kAdminPageSearchHints.containsKey(widget.page);

  static List<AdminRecord> _records(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) => [for (final doc in docs) (id: doc.id, data: doc.data())];

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
    _text.addListener(_typed);
    adminPageSearch.addListener(_clearedElsewhere);
  }

  @override
  void dispose() {
    _typing?.cancel();
    adminPageSearch.removeListener(_clearedElsewhere);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  // The open page reads what is typed from adminPageSearch — once typing
  // pauses, so the page's table is filtered and redrawn per pause, not per
  // letter. Clearing the box takes effect at once.
  Timer? _typing;
  static const Duration _typingPause = Duration(milliseconds: 300);

  void _typed() {
    final query = _filtersPage ? _text.text : '';
    _typing?.cancel();
    if (adminPageSearch.value == query) return;
    if (query.isEmpty) {
      adminPageSearch.value = '';
      return;
    }
    _typing = Timer(_typingPause, () {
      if (mounted && adminPageSearch.value != query) {
        adminPageSearch.value = query;
      }
    });
  }

  // A page's own "Clear" emptied the search: empty the box with it.
  void _clearedElsewhere() {
    if (adminPageSearch.value.isEmpty &&
        _filtersPage &&
        _text.text.isNotEmpty) {
      _text.clear();
    }
  }

  @override
  void didUpdateWidget(AdminGlobalSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page == widget.page) return;
    // Another page: start its search empty. After this frame, since pages
    // rebuild when the search changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _text.clear();
      adminPageSearch.value = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final data = DashboardDataService.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: data.usersStream,
      builder: (context, users) {
        if (users.hasData) _users = _records(users.data!.docs);
        return LayoutBuilder(
          builder: (context, constraints) => RawAutocomplete<AdminSearchHit>(
            textEditingController: _text,
            focusNode: _focus,
            displayStringForOption: (hit) => hit.title,
            // On a page with a table the text filters that table; there
            // is no list of results to pick from.
            optionsBuilder: (value) => _filtersPage
                ? const <AdminSearchHit>[]
                : searchAdminRecords(
                    value.text,
                    users: _users,
                    products: _records(data.products),
                    orders: _records(data.allOrders),
                  ),
            onSelected: (hit) {
              adminOpenPageRequest.value = hit.target;
              FocusManager.instance.primaryFocus?.unfocus();
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: adminPillDecoration(
                    c,
                    hint:
                        kAdminPageSearchHints[widget.page] ??
                        'Search farmers, listings, transactions…',
                    icon: Icons.search,
                  ),
                  onSubmitted: (_) => onSubmitted(),
                ),
            optionsViewBuilder: (context, onSelected, hits) => Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Material(
                  color: c.surface,
                  elevation: 10,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kAdminPopupRadius),
                    side: BorderSide(color: c.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth,
                      maxHeight: 380,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: hits.length,
                      itemBuilder: (context, index) {
                        final hit = hits.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(hit),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Icon(hit.icon, size: 18, color: c.green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hit.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (hit.detail.isNotEmpty)
                                        Text(
                                          hit.detail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: c.textSecondary,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  hit.group,
                                  style: TextStyle(
                                    color: c.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
