import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/order_format.dart';
import '../services/order_seen_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../widgets/order_card.dart';
import '../widgets/order_status_pager.dart';
import '../widgets/page_header.dart';
import 'inventory_screen.dart';
import 'order_actions.dart';
import '../l10n/tr.dart';

/// The Orders screen body for both the Farmer and the Buyer: same header,
/// tabs, swipe, badges, cards, loading and empty states. [role] only
/// changes the wording, whose name a card shows, and which actions exist.
///
/// Body-only — it renders inside the Farmer/Buyer home Scaffold, which
/// already provides the app bar and bottom navigation.
class OrdersView extends StatefulWidget {
  final OrderRole role;

  /// Buyer only: jumps to the marketplace from an empty state.
  final VoidCallback? onBrowseMarketplace;

  /// A status tab to open on request (see OrderStatusPager.showStatus).
  final ValueListenable<String?>? showStatus;

  const OrdersView({
    super.key,
    required this.role,
    this.onBrowseMarketplace,
    this.showStatus,
  });

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  // The four workflow statuses, plus declined orders so they stay findable.
  static const _tabs = [...kOrderStatusTabs, kRejectedTab];

  final OrderService _orderService = OrderService();
  late final OrderSeenStore _seenStore = OrderSeenStore(
    uid: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
    role: widget.role.name,
  );

  OrderRole get _role => widget.role;
  bool get _isFarmer => _role == OrderRole.farmer;

  // The list is a live Firestore stream and is already current; this only
  // gives the pull gesture its feedback.
  Future<void> _refresh() => Future.delayed(const Duration(milliseconds: 700));

  String _emptySubtitle(OrderStatusTab tab) => switch (tab.value) {
    'pending' =>
      _isFarmer
          ? 'New buyer orders will appear here.'
          : 'Orders waiting for farmer confirmation will appear here.',
    'confirmed' =>
      _isFarmer
          ? 'Accepted buyer orders will appear here.'
          : 'Orders confirmed by farmers will appear here.',
    'shipped' =>
      _isFarmer
          ? 'Orders marked as shipped or in fulfillment will appear here.'
          : 'Orders being fulfilled or delivered will appear here.',
    'completed' =>
      _isFarmer
          ? 'Completed transactions will appear here.'
          : 'Your completed purchases will appear here.',
    _ =>
      _isFarmer
          ? 'Orders you decline will appear here.'
          : 'Orders declined by farmers will appear here.',
  };

  // A farmer's pending orders: due soonest first ("needed by"). Everything
  // else: latest activity first.
  List<Widget> _cardsFor(
    OrderStatusTab tab,
    List<OrderDoc> all,
    bool Function(OrderDoc) isNew,
  ) {
    final docs = all.where((d) => orderStatusOf(d) == tab.value).toList();
    final info = {for (final d in docs) d.id: OrderInfo.fromDoc(d)};
    docs.sort((a, b) {
      final ao = info[a.id]!;
      final bo = info[b.id]!;
      if (_isFarmer && tab.value == 'pending') {
        final aNeed = ao.neededBy;
        final bNeed = bo.neededBy;
        if (aNeed != null || bNeed != null) {
          if (aNeed == null) return 1;
          if (bNeed == null) return -1;
          final due = aNeed.compareTo(bNeed);
          if (due != 0) return due;
        }
      }
      final aAt = (ao.statusChangedAt ?? ao.createdAt)?.millisecondsSinceEpoch;
      final bAt = (bo.statusChangedAt ?? bo.createdAt)?.millisecondsSinceEpoch;
      return (bAt ?? 0).compareTo(aAt ?? 0);
    });

    return [
      for (final doc in docs)
        Builder(
          key: ValueKey(doc.id),
          builder: (context) {
            final order = info[doc.id]!;
            return OrderCard(
              order: order,
              role: _role,
              isNew: isNew(doc),
              // Messaging and the order's actions are in its details.
              onDetails: () => OrderActions.openDetails(context, order, _role),
            );
          },
        ),
    ];
  }

  // Buyer, Completed tab: a nudge to review finished purchases.
  List<Widget> _header(OrderStatusTab tab, List<OrderDoc> all) {
    if (_isFarmer || tab.value != 'completed') return const [];
    final unreviewed = all.where((doc) {
      final data = doc.data();
      return orderStatusOf(doc) == 'completed' && data['reviewedAt'] == null;
    }).length;
    if (unreviewed == 0) return const [];
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Review your completed orders to earn the Trusted Buyer badge. '
          '$unreviewed order${unreviewed == 1 ? '' : 's'} still need${unreviewed == 1 ? 's' : ''} a review.',
          style: GoogleFonts.montserrat(
            color: AppTheme.dark,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final browse = widget.onBrowseMarketplace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: tr(context).navOrders,
          // Farmers only: stock of their own listings. A compact solid
          // dark green button on the title's own row, ending on the
          // page's 16px edge.
          titleTrailing: _isFarmer
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InventoryScreen(),
                      ),
                    ),
                    // Solid dark green pill, white label only, raised on a
                    // soft shadow that sinks when it is pressed.
                    style:
                        FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: AppTheme.dark,
                          shadowColor: AppTheme.dark,
                          shape: const StadiumBorder(),
                          minimumSize: Size.zero,
                          fixedSize: const Size.fromHeight(36),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.standard,
                          textStyle: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ).copyWith(
                          elevation: WidgetStateProperty.resolveWith(
                            (states) =>
                                states.contains(WidgetState.pressed) ? 1 : 5,
                          ),
                        ),
                    child: Text(tr(context).inventory),
                  ),
                )
              : null,
        ),
        Expanded(
          child: OrderStatusPager(
            streamFactory: _isFarmer
                ? _orderService.farmerOrdersStream
                : _orderService.buyerOrdersStream,
            tabs: _tabs,
            showStatus: widget.showStatus,
            itemsBuilder: _cardsFor,
            headerBuilder: _header,
            onRefresh: _refresh,
            emptySubtitle: _emptySubtitle,
            emptyAction: browse == null
                ? null
                : TextButton.icon(
                    onPressed: browse,
                    icon: const Icon(Icons.storefront_outlined, size: 17),
                    label: const Text('Browse Marketplace'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.dark,
                      textStyle: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
            errorMessage:
                'Could not load your orders. Check your connection and try again.',
            tutorialPrefsKey: ordersSwipeTutorialKey(),
            activityOf: (doc) => OrderInfo.fromDoc(doc).unseenActivityMs(_role),
            seenStore: _seenStore,
          ),
        ),
      ],
    );
  }
}
