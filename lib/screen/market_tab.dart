import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/farmer_revenue_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
//
// onNavigateToTab lets this tab jump to another bottom-nav tab in the
// parent Scaffold (tapping "Welcome back" goes to Profile). Wire it up
// in FarmerHomeScreen:
//   MarketTab(onNavigateToTab: (i) => setState(() => _selectedIndex = i))
// Index assumption, matching the rest of this build: 3=Profile — adjust
// the number below if your order differs.
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
  FarmerRevenueView _selectedRevenueView = FarmerRevenueView.weekly;

  Future<void> _refreshMarket() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
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
          return const Center(child: CircularProgressIndicator(color: _dark));
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              _welcomeHeader(name, docs.length),
              const SizedBox(height: 16),
              _statRow(docs.length),
              const SizedBox(height: 16),
              _salesPerformanceCard(),
              const SizedBox(height: 16),
              _marketObjectivesCard(),
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

        return Row(
          children: [
            Expanded(child: _statCard('TOTAL ORDERS', '$totalOrdersToday')),
            const SizedBox(width: 12),
            Expanded(child: _statCard('TOTAL\nPRODUCTS', '$productCount')),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
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
    );
  }

  Widget _salesPerformanceCard() {
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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() ?? const <String, dynamic>{};
        final registeredAt = _parseDateTime(userData['createdAt']);
        final now = DateTime.now();
        if (registeredAt == null ||
            FarmerRevenueService.isBeginner(
              registeredAt: registeredAt,
              now: now,
            )) {
          return _newFarmerSalesCard();
        }

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
                    'Revenue updates as completed orders come in.',
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
            'Add your products and start accepting orders. Your weekly sales will appear here after your first week.',
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

  Widget _marketObjectivesCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, productsSnapshot) {
        final products =
            (productsSnapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .map((doc) => Map<String, dynamic>.from(doc.data()))
                .toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('status', isEqualTo: 'completed')
              .snapshots(),
          builder: (context, ordersSnapshot) {
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

            final avgPrice =
                (insight['marketAverage'] as num?)?.toDouble() ?? 0.0;
            final seasonPick =
                insight['seasonalPick']?.toString() ?? 'Vegetables';
            final marketPick =
                insight['marketPick']?.toString() ?? 'Vegetables';
            final seasonLabel = insight['season']?.toString() ?? 'Season';

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
                    value: '₱${avgPrice.toStringAsFixed(0)}/kg',
                    subtitle: 'Average price across listed products',
                  ),
                  const SizedBox(height: 10),
                  _objectiveRow(
                    title: 'Best this $seasonLabel',
                    value: seasonPick,
                    subtitle: 'Top product by seasonal buyer demand',
                  ),
                  const SizedBox(height: 10),
                  _objectiveRow(
                    title: 'Marketplace demand',
                    value: marketPick,
                    subtitle:
                        'Most bought product by buyers in the marketplace',
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
                      'Suggested focus: sell more $marketPick during the $seasonLabel to match buyer demand and improve turnover.',
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
