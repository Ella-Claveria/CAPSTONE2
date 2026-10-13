import 'package:flutter/material.dart';
import '../widgets/agri_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/farmer_revenue_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../widgets/market_average_card.dart';
import '../widgets/market_demand_cards.dart';
import '../widgets/market_tab_guide.dart';
import '../widgets/page_header.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
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

  /// The notification bell in this tab's header.
  final VoidCallback? onNotificationsPressed;

  const MarketTab({
    super.key,
    this.onNavigateToTab,
    this.onNotificationsPressed,
  });

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {
  static const Color _dark = AppTheme.dark;

  static const int _profileTabIndex = 3;
  static const int _ordersTabIndex = 2;
  DateTime? _selectedSalesMonth;

  // The month every dashboard analytics card shows: the one picked on
  // Sales Performance, or the current month until one is picked.
  DateTime get _analyticsMonth {
    final month = _selectedSalesMonth ?? DateTime.now();
    return DateTime(month.year, month.month);
  }

  int _lastProductCount = 0;
  // Until the product list has loaded, a count of 0 means "unknown", not
  // "no products".
  bool _productsLoaded = false;
  @override
  void initState() {
    super.initState();
    // A first-time farmer is told which cards are their own sales and
    // which are the whole marketplace, once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMarketTabGuideOnce(context);
    });
  }

  Widget _salesPerformanceLineCard(int productCount) {
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
        if (userSnapshot.connectionState == ConnectionState.waiting &&
            !userSnapshot.hasData) {
          return _salesLoadingCard();
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
            if (ordersSnapshot.connectionState == ConnectionState.waiting &&
                !ordersSnapshot.hasData) {
              return _salesLoadingCard();
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
                            _SectionTitle('Sales Performance'),
                            SizedBox(height: 3),
                            Text(
                              'Completed-order revenue',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.normal,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _monthPill(
                        MaterialLocalizations.of(
                          context,
                        ).formatMonthYear(selectedMonth),
                        onTap: () async {
                          final picked = await _showMonthYearPicker(
                            context,
                            selectedMonth: selectedMonth,
                            firstMonth: firstMonth,
                            currentMonth: currentMonth,
                          );
                          if (picked != null && mounted) {
                            setState(() => _selectedSalesMonth = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // No completed sales in the selected month: say so, with
                  // the next step, instead of a flat empty chart.
                  if (total <= 0)
                    _salesEmptyState(
                      newFarmer:
                          _productsLoaded &&
                          productCount == 0 &&
                          !orders.any(
                            (order) =>
                                (order['status'] ?? '')
                                    .toString()
                                    .toLowerCase() ==
                                'completed',
                          ),
                    )
                  else ...[
                    Text(
                      _formatCurrency(total),
                      style: GoogleFonts.montserrat(
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
                                  if (index < 0 || index >= days.length) {
                                    return const SizedBox.shrink();
                                  }
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
                      'Revenue is based on orders marked completed.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // What Sales Performance shows in place of the chart when the selected
  // month has no completed sales. A farmer with no products and no sales
  // ever is pointed at Add Product; one who already has products (or has
  // sold before) is pointed at their product list instead.
  Widget _salesEmptyState({required bool newFarmer}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            newFarmer ? Icons.storefront_outlined : Icons.show_chart_rounded,
            size: 30,
            color: _dark,
          ),
          const SizedBox(height: 8),
          Text(
            newFarmer ? 'No sales yet' : 'No completed sales yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            newFarmer
                ? 'Start by listing your first product to begin tracking your sales performance.'
                : 'Your sales performance will appear here once buyers complete their orders.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (newFarmer)
            ElevatedButton.icon(
              // The same Add Product screen the + button opens.
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddProductScreen()),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                textStyle: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            OutlinedButton(
              // The farmer's product list lives on the Profile tab.
              onPressed: () => widget.onNavigateToTab?.call(_profileTabIndex),
              style: OutlinedButton.styleFrom(
                foregroundColor: _dark,
                side: const BorderSide(color: _dark),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                textStyle: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('View My Products'),
            ),
        ],
      ),
    );
  }

  Widget _monthPill(String label, {required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9DF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.normal,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Colors.black54,
          ),
        ],
      ),
    ),
  );

  Future<DateTime?> _showMonthYearPicker(
    BuildContext context, {
    required DateTime selectedMonth,
    required DateTime firstMonth,
    required DateTime currentMonth,
  }) {
    final minimumYear = firstMonth.year;
    final maximumYear = currentMonth.year;
    var pickerYear = selectedMonth.year;
    var draftMonth = selectedMonth;

    return showAgriPanelSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final canGoPrevious = pickerYear > minimumYear;
          final canGoNext = pickerYear < maximumYear;

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE5DB),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Month',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _yearArrow(
                      icon: Icons.chevron_left_rounded,
                      enabled: canGoPrevious,
                      onTap: () => setSheetState(() => pickerYear--),
                    ),
                    Text(
                      '$pickerYear',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    _yearArrow(
                      icon: Icons.chevron_right_rounded,
                      enabled: canGoNext,
                      onTap: () => setSheetState(() => pickerYear++),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent: 42,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final month = DateTime(pickerYear, index + 1);
                    final isValid =
                        !month.isBefore(firstMonth) &&
                        !month.isAfter(currentMonth);
                    final isSelected =
                        month.year == draftMonth.year &&
                        month.month == draftMonth.month;
                    return InkWell(
                      onTap: isValid
                          ? () => setSheetState(() => draftMonth = month)
                          : null,
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _dark
                              : isValid
                              ? const Color(0xFFF4F8F2)
                              : const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: isSelected ? _dark : const Color(0xFFE8EEE6),
                          ),
                        ),
                        child: Text(
                          DateFormat.MMMM().format(month),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : isValid
                                ? Colors.black87
                                : Colors.black26,
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _legendDot(_dark),
                    const SizedBox(width: 5),
                    const Text(
                      'Selectable month',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                    const SizedBox(width: 16),
                    _legendDot(const Color(0xFFD8DDD9)),
                    const SizedBox(width: 5),
                    const Text(
                      'Not available',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F8EF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: _dark,
                        size: 16,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Available from ${DateFormat('MMMM yyyy').format(firstMonth)}, based on your verification date. Future months cannot be selected.',
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.35,
                            color: Color(0xFF52614F),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _dark,
                          side: const BorderSide(color: Color(0xFFDDE5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, draftMonth),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.dark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _yearArrow({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFEAF4E7) : const Color(0xFFF3F4F3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: enabled ? _dark : Colors.black26),
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

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

  Widget _salesLoadingCard() => Container(
    width: double.infinity,
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
    child: const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle('Sales Performance'),
              SizedBox(height: 3),
              Text(
                'Completed-order revenue',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
        AgriLogoLoader(),
      ],
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

  // Pull to refresh: asks the server for the latest of everything this tab
  // shows. The cards are fed by live listeners, so they take the new data
  // in place — nothing is cleared or swapped for a loading state meanwhile.
  Future<void> _refresh() async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    const fromServer = GetOptions(source: Source.server);
    try {
      await Future.wait([
        // Long enough for the pull to register as having done something.
        Future<void>.delayed(const Duration(milliseconds: 600)),
        db.collection('market_sales').get(fromServer),
        db.collection('products').get(fromServer),
        if (uid != null) ...[
          db.collection('users').doc(uid).get(fromServer),
          db
              .collection('orders')
              .where('sellerId', isEqualTo: uid)
              .get(fromServer),
        ],
      ]).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline or slow: the listeners keep showing what they have.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ProductService().myProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load your products. Check your connection and try again.',
            onRetry: () => setState(() {}),
          );
        }
        if (snapshot.hasData) {
          _lastProductCount = snapshot.data!.docs.length;
          _productsLoaded = true;
        }
        final productCount = snapshot.hasData
            ? snapshot.data!.docs.length
            : _lastProductCount;

        return AgriRefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              // Same title row as Messages, Orders and Profile.
              PageHeader(
                title: 'Market',
                trailing: widget.onNotificationsPressed == null
                    ? null
                    : NotificationBell(
                        onPressed: widget.onNotificationsPressed!,
                        color: AppTheme.dark,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _welcomeHeader(productCount),
                    const SizedBox(height: 16),
                    _statRow(productCount),
                    const SizedBox(height: 16),
                    _salesPerformanceLineCard(productCount),
                    const SizedBox(height: 16),
                    // What supported products are selling for right now.
                    const MarketAverageCard(),
                    const SizedBox(height: 16),
                    // Same month as the Sales Performance card above.
                    MarketDemandCards(month: _analyticsMonth),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _welcomeHeader(int productCount) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name =
            (data['name'] ?? data['fullName'] ?? user.displayName ?? 'Farmer')
                .toString();
        final photoUrl = data['photoUrl']?.toString() ?? '';
        final imageProvider = photoUrl.isNotEmpty
            ? NetworkImage(photoUrl)
            : null;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onNavigateToTab?.call(_profileTabIndex),
            child: Container(
              height: 106,
              padding: const EdgeInsets.fromLTRB(30, 14, 22, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/images/market_farmer.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Color(0xFF52614F),
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            color: const Color(0xFF173D21),
                            fontSize: 22,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$productCount product${productCount == 1 ? '' : 's'} listed',
                          style: const TextStyle(
                            color: Color(0xFF52614F),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: Colors.white,
                    backgroundImage: imageProvider,
                    child: imageProvider == null
                        ? const Icon(Icons.person, color: _dark, size: 30)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                  fontWeight: FontWeight.normal,
                  color: Colors.grey[600],
                  letterSpacing: 0.4,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: GoogleFonts.montserrat(
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
}

/// A dashboard section title ("Sales Performance", "Best-Selling
/// Products"): Montserrat SemiBold. Built with GoogleFonts so the real
/// semibold face is used — a plain TextStyle(fontWeight: bold) only gets a
/// synthesized bold of the regular face, which reads noticeably weaker.
class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.montserrat(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    ),
  );
}
