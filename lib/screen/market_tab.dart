import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/farmer_revenue_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/shimmer.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/retry_message.dart';
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
  DateTime? _selectedSalesMonth;
  @override
  void initState() {
    super.initState();
  }

  Widget _salesPerformanceLineCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return _salesCardMessage('Log in to view your sales performance.');
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Shimmer(child: SalesPerformanceCardSkeleton());
        }
        if (userSnapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load your verification date. Check your connection and retry.',
            onRetry: () => setState(() {}),
          );
        }

        final user = userSnapshot.data?.data() ?? const <String, dynamic>{};
        if ((user['approvalStatus'] ?? 'approved').toString().toLowerCase() !=
            'approved') {
          return _salesCardMessage(
            'Sales performance will be available once your farmer account is verified.',
          );
        }
        final now = DateTime.now();
        final storedVerifiedAt =
            _parseDateTime(user['verifiedAt']) ??
            _parseDateTime(user['reviewedAt']) ??
            _parseDateTime(user['createdAt']) ??
            now;
        final verifiedAt = storedVerifiedAt.isAfter(now)
            ? now
            : storedVerifiedAt;
        final firstMonth = DateTime(verifiedAt.year, verifiedAt.month);
        final currentMonth = DateTime(now.year, now.month);
        final months = <DateTime>[];
        for (
          var cursor = currentMonth;
          !cursor.isBefore(firstMonth);
          cursor = DateTime(cursor.year, cursor.month - 1)
        ) {
          months.add(cursor);
        }
        final selectedMonth = months.firstWhere(
          (month) =>
              month.year == _selectedSalesMonth?.year &&
              month.month == _selectedSalesMonth?.month,
          orElse: () => months.first,
        );

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: OrderService().farmerOrdersStream(),
          builder: (context, ordersSnapshot) {
            if (ordersSnapshot.connectionState == ConnectionState.waiting) {
              return const Shimmer(child: SalesPerformanceCardSkeleton());
            }
            if (ordersSnapshot.hasError) {
              return RetryMessage(
                message:
                    'Could not load completed orders. Check your connection and retry.',
                onRetry: () => setState(() {}),
              );
            }
            final orders =
                (ordersSnapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .map((doc) => doc.data())
                    .toList();
            final days = FarmerRevenueService.dailyRevenueForMonth(
              orders: orders,
              month: selectedMonth,
              verifiedAt: verifiedAt,
            );
            final total = FarmerRevenueService.totalRevenueForDays(days);
            final spots = [
              for (var i = 0; i < days.length; i++)
                FlSpot(i.toDouble(), days[i].revenue),
            ];
            final maxRevenue = days.fold<double>(
              0,
              (max, day) => day.revenue > max ? day.revenue : max,
            );
            final chartMax = maxRevenue <= 0 ? 100.0 : maxRevenue * 1.2;
            final firstEligibleDate = DateTime(
              selectedMonth.year,
              selectedMonth.month,
              selectedMonth.year == verifiedAt.year &&
                      selectedMonth.month == verifiedAt.month
                  ? verifiedAt.day
                  : 1,
            );
            final periodLabel = firstEligibleDate.day == 1
                ? 'From ${MaterialLocalizations.of(context).formatShortDate(firstEligibleDate)}'
                : 'Starts on your verification date · ${MaterialLocalizations.of(context).formatShortDate(firstEligibleDate)}';

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7EFE4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
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
                            SizedBox(height: 3),
                            Text(
                              'Completed-order revenue',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (months.length > 1)
                        DropdownButton<DateTime>(
                          value: selectedMonth,
                          underline: const SizedBox.shrink(),
                          borderRadius: BorderRadius.circular(12),
                          items: [
                            for (final month in months)
                              DropdownMenuItem(
                                value: month,
                                child: Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMonthYear(month),
                                ),
                              ),
                          ],
                          onChanged: (month) {
                            if (month != null)
                              setState(() => _selectedSalesMonth = month);
                          },
                        )
                      else
                        _monthPill(
                          MaterialLocalizations.of(
                            context,
                          ).formatMonthYear(selectedMonth),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatCurrency(total),
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    periodLabel,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 175,
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (days.length - 1).clamp(1, 31).toDouble(),
                        minY: 0,
                        maxY: chartMax,
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: chartMax / 3,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: Color(0xFFE9EEE6),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              getTitlesWidget: (value, meta) => Text(
                                '₱${value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: days.length > 10 ? 5 : 1,
                              getTitlesWidget: (value, meta) {
                                final index = value.round();
                                if (index < 0 || index >= days.length)
                                  return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${days[index].date.day}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: _dark,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: _dark.withValues(alpha: 0.10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total > 0
                        ? 'Revenue is based on orders marked completed.'
                        : 'No completed sales recorded for this month yet.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _monthPill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F7EC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _dark,
      ),
    ),
  );

  Widget _salesCardMessage(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE7EFE4)),
    ),
    child: Text(
      message,
      style: TextStyle(color: Colors.grey[700], fontSize: 12),
    ),
  );

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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ProductService().myProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MarketTabSkeleton();
        }
        if (snapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load your products. Check your connection and try again.',
            onRetry: () => setState(() {}),
          );
        }
        final productCount = snapshot.data?.docs.length ?? 0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            _welcomeHeader(name, productCount),
            const SizedBox(height: 16),
            _statRow(productCount),
            const SizedBox(height: 16),
            _salesPerformanceLineCard(),
            const SizedBox(height: 16),
            _bestSellingProductsCard(),
          ],
        );
      },
    );
  }

  Widget _welcomeHeader(String name, int productCount) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final imageProvider = photoUrl != null && photoUrl.isNotEmpty
        ? NetworkImage(photoUrl)
        : null;

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
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? const Icon(Icons.person, color: _dark, size: 28)
                    : null,
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
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: _dark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'List your first product',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddProductScreen()),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Your First Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
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
        if (userSnapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load sales data. Check your connection and retry.',
            onRetry: () => setState(() {}),
          );
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
            if (ordersSnapshot.hasError) {
              return RetryMessage(
                message:
                    'Could not load sales data. Check your connection and retry.',
                onRetry: () => setState(() {}),
              );
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

  // Top marketplace products by quantity in anonymized completed sales.
  Widget _bestSellingProductsCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('market_sales').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Shimmer(child: MarketObjectiveCardSkeleton());
        }
        if (snapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load marketplace sales. Check your connection and retry.',
            onRetry: () => setState(() {}),
          );
        }

        final sales =
            (snapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .map((doc) => doc.data())
                .toList();
        final bestSellers = FarmerRevenueService.topMarketplaceProducts(
          sales: sales,
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
              const Row(
                children: [
                  Icon(Icons.emoji_events_outlined, size: 18, color: _dark),
                  SizedBox(width: 8),
                  Text(
                    'Best-Selling Products',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Most bought all-time across AgriTrade+',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              if (bestSellers.isEmpty)
                Text(
                  'No completed purchases yet. Popular products will appear here as buyers complete orders.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey[500],
                    height: 1.4,
                  ),
                )
              else
                ...List.generate(bestSellers.length, (i) {
                  final p = bestSellers[i];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: i == bestSellers.length - 1 ? 0 : 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _dark,
                            ),
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '${formatStock(p.quantity, p.unit)} bought · ${p.orderCount} orders',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
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

  Widget _marketObjectivesCard() {
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
        if (productsSnapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load marketplace listings. Check your connection and retry.',
            onRetry: () => setState(() {}),
          );
        }

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
            if (ordersSnapshot.hasError) {
              return RetryMessage(
                message:
                    'Could not load completed market sales. Check your connection and retry.',
                onRetry: () => setState(() {}),
              );
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
            final avgCommodity = insight['marketAverageCommodity']?.toString();
            final avgUnit = insight['marketAverageUnit']?.toString();
            final seasonPick = insight['seasonalPick']?.toString();
            final marketPick = insight['marketPick']?.toString();

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7EFE4)),
                boxShadow: [
                  BoxShadow(
                    color: _dark.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4E7),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.insights_rounded,
                          color: _dark,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Simple Market Guide',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'A quick look at what buyers are choosing',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    avgPrice != null && avgCommodity != null && avgUnit != null
                        ? 'Other farmers list $avgCommodity for about ${formatPriceWithUnit(avgPrice, avgUnit)} on AgriTrade+. Use this as a guide and choose a price that works for your farm.'
                        : 'There are not enough active listings to show a price guide yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(
                        Icons.shopping_basket_outlined,
                        color: _dark,
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Products buyers bought',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: _demandTile(
                          icon: Icons.wb_sunny_outlined,
                          title: 'This season',
                          product: seasonPick,
                          caption: 'Most bought this season across AgriTrade+',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _demandTile(
                          icon: Icons.local_fire_department_outlined,
                          title: 'Last 30 days',
                          product: marketPick,
                          caption:
                              'Most bought in the last 30 days across AgriTrade+',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF1F8ED), Color(0xFFFAFCF8)],
                      ),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFDCEAD5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lightbulb_outline_rounded,
                          color: _dark,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            marketPick != null
                                ? 'If you grow $marketPick, consider listing it. Buyers bought it most in the last 30 days on AgriTrade+.'
                                : seasonPick != null
                                ? 'If you grow $seasonPick, consider listing it. Buyers bought it most this season on AgriTrade+.'
                                : 'There is not enough completed-sale data yet. Check back as more buyers complete orders.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey[800],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
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

  Widget _demandTile({
    required IconData icon,
    required String title,
    required String? product,
    required String caption,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE8EDE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _dark, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product ?? 'Collecting sales data',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _dark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            product == null ? 'More completed orders are needed.' : caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              color: Colors.grey[600],
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
