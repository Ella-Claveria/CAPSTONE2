import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/farmer_revenue_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../widgets/shimmer.dart';
import '../widgets/skeleton_loaders.dart';
import 'add_product_screen.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
//
// onNavigateToTab lets this tab jump to another bottom-nav tab in the
// parent Scaffold (tapping "Welcome back" or the Total Products card goes
// to Profile; the Total Orders card goes to Orders). Wire it up in
// FarmerHomeScreen:
//   MarketTab(onNavigateToTab: (i) => setState(() => _selectedIndex = i))
// Index assumption, matching the rest of this build: 2=Orders, 3=Profile —
// adjust _ordersTabIndex/_profileTabIndex below if your order differs.
class MarketTab extends StatefulWidget {
  final ValueChanged<int>? onNavigateToTab;

  const MarketTab({super.key, this.onNavigateToTab});

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  static const int _profileTabIndex = 3;
  static const int _ordersTabIndex = 2;
  FarmerRevenueView _selectedRevenueView = FarmerRevenueView.weekly;
  bool _isRefreshing = false;

  Future<void> _refreshMarket() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isRefreshing = false);
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _formatCurrency(num value) {
    final whole = value.round();
    final s = whole.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final indexFromEnd = s.length - i;
      if (i > 0 && indexFromEnd % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(s[i]);
    }
    return '₱$buffer';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Farmer';
    final productService = ProductService();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: productService.myProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MarketTabSkeleton();
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Something went wrong loading products.'),
          );
        }
        final docs = snapshot.data?.docs ?? [];

        return RefreshIndicator(
          color: _dark,
          onRefresh: _refreshMarket,
          child: _isRefreshing
              ? const MarketTabSkeleton()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    _welcomeHeader(name, docs.length),
                    const SizedBox(height: 16),
                    _statRow(docs.length),
                    if (docs.isEmpty) ...[
                      const SizedBox(height: 16),
                      _addFirstProductCard(context),
                    ],
                    const SizedBox(height: 16),
                    _salesPerformanceCard(docs.isNotEmpty),
                    const SizedBox(height: 16),
                    _bestSellingProductsCard(docs.isNotEmpty),
                    const SizedBox(height: 16),
                    _marketObjectivesCard(docs.isNotEmpty),
                  ],
                ),
        );
      },
    );
  }

  // ---- Welcome header — tappable, opens Profile ----
  Widget _welcomeHeader(String name, int productCount) {
    final user = FirebaseAuth.instance.currentUser;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => widget.onNavigateToTab?.call(_profileTabIndex),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_dark, Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user?.uid ?? '')
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  final photoUrl =
                      data?['photoUrl']?.toString() ?? user?.photoURL;
                  final imageProvider =
                      (photoUrl != null && photoUrl.isNotEmpty)
                      ? NetworkImage(photoUrl)
                      : null;

                  return CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    backgroundImage: imageProvider,
                    child: imageProvider == null
                        ? const Icon(Icons.person, color: _dark, size: 28)
                        : null,
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome back,',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$productCount product${productCount == 1 ? '' : 's'} listed',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  // Shown only while this farmer has zero listings — a friendly nudge with
  // a direct path to their first product, instead of leaving the stat row
  // ("0 products listed") as the only clue something's missing.
  Widget _addFirstProductCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent, width: 1.4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                child: const Icon(Icons.add_a_photo_outlined, color: _dark, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'List your first product',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "You haven't posted anything yet — buyers can't find you until you do. It only takes a minute.",
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Your First Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(int productCount) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: OrderService().farmerOrdersStream(),
      builder: (context, snapshot) {
        final today = DateTime.now();
        final totalOrdersToday = (snapshot.data?.docs ?? const []).where((doc) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase();
          final createdAt = data['createdAt'];
          final date = createdAt is Timestamp ? createdAt.toDate() : null;
          return (status == 'pending' || status == 'confirmed') &&
              date != null &&
              date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
        }).length;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _statCard(
                  'TOTAL ORDERS',
                  '$totalOrdersToday',
                  onTap: () => widget.onNavigateToTab?.call(_ordersTabIndex),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  'TOTAL PRODUCTS',
                  '$productCount',
                  onTap: () => widget.onNavigateToTab?.call(_profileTabIndex),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.4,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _dark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _salesPerformanceCard(bool hasProducts) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Center(child: Text('Login to view sales performance.')),
      );
    }

    // A farmer with zero listings has nothing to sell yet — show the
    // friendly nudge without waiting on any Firestore round-trip.
    if (!hasProducts) {
      return _newFarmerSalesCard();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        // Wait for the farmer's profile doc before deciding what to show —
        // never fall through to a default state while this is still `waiting`.
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Shimmer(child: SalesPerformanceCardSkeleton());
        }

        final now = DateTime.now();
        final userData = userSnapshot.data?.data() ?? const <String, dynamic>{};
        // Missing createdAt (e.g. an older account) defaults to "now" —
        // restricts to the weekly view rather than crashing or guessing.
        final registeredAt = _parseDateTime(userData['createdAt']) ?? now;

        final canViewMonthly = FarmerRevenueService.canViewMonthly(
          registeredAt: registeredAt,
          now: now,
        );
        final effectiveView = canViewMonthly
            ? _selectedRevenueView
            : FarmerRevenueView.weekly;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: OrderService().farmerOrdersStream(),
          builder: (context, ordersSnapshot) {
            if (ordersSnapshot.connectionState == ConnectionState.waiting) {
              return const Shimmer(child: SalesPerformanceCardSkeleton());
            }

            final orders =
                (ordersSnapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .map(
                      (doc) =>
                          Map<String, dynamic>.from(doc.data())
                            ..['id'] = doc.id,
                    )
                    .toList();

            final bars = FarmerRevenueService.revenueBars(
              orders: orders,
              view: effectiveView,
              now: now,
            );
            final maxValue = bars.isEmpty
                ? 1.0
                : bars
                      .map((bar) => (bar['value'] as num).toDouble())
                      .reduce((a, b) => a > b ? a : b);
            final totalRevenue = FarmerRevenueService.totalRevenueForRange(
              orders: orders,
              view: effectiveView,
              now: now,
            );
            final hasCompletedSales = totalRevenue > 0;

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sales Performance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (canViewMonthly)
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              _viewToggleChip('Week', FarmerRevenueView.weekly),
                              _viewToggleChip(
                                'Month',
                                FarmerRevenueView.monthly,
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Week',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _dark,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    effectiveView == FarmerRevenueView.weekly
                        ? 'Weekly Revenue'
                        : 'Monthly Revenue',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    _formatCurrency(totalRevenue),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 108,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(bars.length, (i) {
                        final value = (bars[i]['value'] as num).toDouble();
                        final height = maxValue <= 0
                            ? 0.0
                            : ((value / maxValue) * 80.0).clamp(8.0, 80.0);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 18,
                              height: height,
                              decoration: BoxDecoration(
                                color: value > 0 ? _dark : _accent,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              bars[i]['label'].toString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasCompletedSales
                        ? 'Revenue updates as completed orders come in.'
                        : 'No completed sales in this period yet.',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Ranked by completed-order revenue, this farmer's listings only — the
  // per-farmer counterpart to the admin dashboard's platform-wide
  // "Best-Selling Product" card. Hidden entirely for a farmer with zero
  // listings (nothing to rank yet); once they have listings but no
  // completed sales, it shows an honest empty state instead of hiding.
  Widget _bestSellingProductsCard(bool hasProducts) {
    if (!hasProducts) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: OrderService().farmerOrdersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Shimmer(child: MarketObjectiveCardSkeleton());
        }

        final orders = (snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map((doc) => doc.data())
            .toList();
        final bestSellers = FarmerRevenueService.bestSellingProducts(orders: orders);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.emoji_events_outlined, size: 18, color: _dark),
                  SizedBox(width: 8),
                  Text(
                    'Best-Selling Products',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('By completed-order revenue', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 14),
              if (bestSellers.isEmpty)
                Text(
                  'No completed sales yet — your top products will appear here once orders complete.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[500], height: 1.4),
                )
              else
                ...List.generate(bestSellers.length, (i) {
                  final p = bestSellers[i];
                  return Padding(
                    padding: EdgeInsets.only(bottom: i == bestSellers.length - 1 ? 0 : 12),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _dark),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                              ),
                              Text(
                                '${p.quantity.toStringAsFixed(0)} sold',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatCurrency(p.revenue),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _dark),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _newFarmerSalesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sales Performance',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          Text(
            "Let's get your farm moving!",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _dark,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'List your first product and start accepting orders — your sales performance will appear here once you do.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _viewToggleChip(String label, FarmerRevenueView view) {
    final active = _selectedRevenueView == view;
    return GestureDetector(
      onTap: () => setState(() => _selectedRevenueView = view),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _dark : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : _dark,
          ),
        ),
      ),
    );
  }

  // hasProducts distinguishes "this farmer hasn't listed anything yet" from
  // "the marketplace itself has no data" — Current Market Average is a
  // marketplace-wide figure and stays real either way, but the
  // personalized rows (season pick, demand pick, suggestion) switch to
  // onboarding copy for a farmer with zero listings of their own.
  Widget _marketObjectivesCard(bool hasProducts) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, productsSnapshot) {
        if (productsSnapshot.connectionState == ConnectionState.waiting) {
          return const Shimmer(child: MarketObjectiveCardSkeleton());
        }
        final products =
            (productsSnapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .map((doc) => Map<String, dynamic>.from(doc.data()))
                .toList();

        // market_sales mirrors just {productName, quantity, createdAt} for
        // every completed order platform-wide, written by the
        // recordMarketSale Cloud Function — querying `orders` directly here
        // isn't possible, since Firestore rules only let a user read an
        // order where they're the buyer or seller (see firestore.rules).
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('market_sales')
              .snapshots(),
          builder: (context, ordersSnapshot) {
            if (ordersSnapshot.connectionState == ConnectionState.waiting) {
              return const Shimmer(child: MarketObjectiveCardSkeleton());
            }
            final orders =
                (ordersSnapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .map((doc) => Map<String, dynamic>.from(doc.data()))
                    .toList();

            final insight = FarmerRevenueService.marketObjective(
              products: products,
              orders: orders,
              now: DateTime.now(),
            );

            final avgPrice = (insight['marketAverage'] as num?)?.toDouble();
            final seasonLabel = insight['season']?.toString() ?? 'Season';
            // A farmer with no listings of their own gets onboarding copy
            // for these rows, even if the wider marketplace already has
            // real seasonal/demand data — only the market average above
            // is shown to everyone regardless of hasProducts.
            final seasonPick =
                hasProducts ? insight['seasonalPick']?.toString() : null;
            final marketPick =
                hasProducts ? insight['marketPick']?.toString() : null;
            final suggestion = hasProducts
                ? (insight['suggestion']?.toString() ??
                    'Suggested focus: Continue listing products while more market data is collected.')
                : 'Suggested focus: Start by listing your products to see current market prices and buyer demand.';

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Market Objective',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _objectiveRow(
                    title: 'Current market average',
                    value: avgPrice != null
                        ? '₱${avgPrice.toStringAsFixed(0)}/kg'
                        : 'No active listings yet',
                    subtitle: 'Average price across listed products',
                  ),
                  const SizedBox(height: 10),
                  _objectiveRow(
                    title: 'Best this $seasonLabel',
                    value: seasonPick ??
                        (hasProducts ? 'Not enough data yet' : 'No data yet'),
                    subtitle: seasonPick != null
                        ? 'Highest buyer demand this season.'
                        : (hasProducts
                            ? 'Not enough completed sales this season.'
                            : 'Add products to start receiving seasonal insights.'),
                  ),
                  const SizedBox(height: 10),
                  _objectiveRow(
                    title: 'Marketplace demand',
                    value: marketPick ??
                        (hasProducts ? 'Not enough data yet' : 'No data yet'),
                    subtitle: marketPick != null
                        ? 'Based on recent buyer purchases in the marketplace.'
                        : (hasProducts
                            ? 'Check back once more orders come in.'
                            : 'Demand insights will appear as buyers interact with products.'),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F9EE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accent),
                    ),
                    child: Text(
                      suggestion,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _objectiveRow({
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: const BoxDecoration(
              color: _dark,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
