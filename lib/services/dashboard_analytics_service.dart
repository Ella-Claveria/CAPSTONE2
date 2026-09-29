import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';

import '../data/laurel_barangays.dart';
import 'farmer_revenue_service.dart';

/// A buyer's location, resolved for demand analytics — the buyer's own
/// saved pin (MyLocationField, anywhere in the Philippines — see
/// register_screen.dart's "the location of the buyer is the one they
/// entered in registration"), never the farmer's, product's, or seller's.
///
/// A legacy account (registered before the free map pin existed) only has
/// a Laurel barangay name instead of coordinates. Either way this resolves
/// to one real, plottable point plus a human-readable "Barangay,
/// Municipality" label:
/// - within Laurel (isWithinLaurel): the nearest Laurel barangay, "name,
///   Laurel" — cheap and always available offline, no geocoding needed.
/// - outside Laurel, with barangay/municipality/province already on the
///   user doc (a legacy account, or one GeocodingService has already
///   resolved and cached — see admin_dashboard_screen.dart): that real
///   saved area, verbatim. Never a generic "Outside Laurel" bucket — a
///   buyer in Tanauan reads as Tanauan, one in Lipa reads as Lipa.
/// - outside Laurel with a pin but nothing resolved yet: an honest
///   coordinate-based placeholder (never a guess) until the background
///   reverse-geocode lands and this resolves to a real place name.
/// A buyer with no pin and no legacy barangay resolves to null — excluded,
/// never padded with a guess.
({String area, double lat, double lng})? _resolveBuyerArea(Map<String, dynamic>? user) {
  if (user == null) return null;
  final lat = (user['latitude'] as num?)?.toDouble();
  final lng = (user['longitude'] as num?)?.toDouble();

  if (lat != null && lng != null) {
    if (isWithinLaurel(lat, lng)) {
      return (area: '${nearestLaurelBarangay(lat, lng).name}, Laurel', lat: lat, lng: lng);
    }
    final barangay = (user['barangay'] ?? '').toString().trim();
    final municipality = (user['municipality'] ?? '').toString().trim();
    final province = (user['province'] ?? '').toString().trim();
    final label = [barangay, municipality.isNotEmpty ? municipality : province]
        .where((s) => s.isNotEmpty)
        .join(', ');
    if (label.isNotEmpty) return (area: label, lat: lat, lng: lng);
    return (
      area: 'Unresolved area (${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)})',
      lat: lat,
      lng: lng,
    );
  }

  final barangay = (user['barangay'] ?? '').toString().trim();
  if (barangay.isEmpty) return null;
  final loc = laurelBarangayLocationFor(barangay);
  if (loc == null) return null;
  final municipality = (user['municipality'] ?? '').toString().trim();
  return (area: '$barangay, ${municipality.isNotEmpty ? municipality : 'Laurel'}', lat: loc.lat, lng: loc.lng);
}

/// Single source of truth for every number the Analytics Dashboard shows.
///
/// The live dashboard calls these with no [DateTimeRange] — which
/// reproduces today's exact behavior (the same fixed windows: last 8
/// weeks, last 30 days, last 6 months, all-time) — while the Export
/// Report flow calls them with an explicit range. Keeping both callers on
/// the same functions is what guarantees an export can never show a
/// different number than what's on screen for "the same" data.
///
/// Where reproducing the live dashboard's exact fixed-window arithmetic
/// mattered, the no-range branch below is left as a literal copy of the
/// original logic rather than folded into one "clever" range-aware
/// formula — safer than risking an off-by-one-day drift from unifying two
/// slightly different reference points (now vs. a range boundary).
class DashboardAnalyticsService {
  const DashboardAnalyticsService._();

  static DateTime? _timestampToDate(dynamic value) => value is Timestamp ? value.toDate() : null;

  /// When an order actually became 'completed' — its own completedAt when
  /// present (stamped by OrderService.updateStatus going forward), falling
  /// back to updatedAt (the last status write, which for an order that has
  /// never been touched again since really did complete it) for orders
  /// completed before completedAt existed, then createdAt as a last
  /// resort. Never null for a real order.
  static DateTime? _completionDate(Map<String, dynamic> data) =>
      _timestampToDate(data['completedAt']) ??
      _timestampToDate(data['updatedAt']) ??
      _timestampToDate(data['createdAt']);

  static bool _inRange(DateTime? date, DateTimeRange? range) {
    if (range == null) return true;
    if (date == null) return false;
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
    return !date.isBefore(start) && !date.isAfter(end);
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static String _statusLabel(dynamic raw) {
    final status = (raw ?? 'pending').toString();
    if (status.isEmpty) return 'Pending';
    return status[0].toUpperCase() + status.substring(1);
  }

  // ============================================================
  // SNAPSHOT COUNTS — always current, never date-filtered. A user's role
  // or a commodity's live price isn't an event with a date, so "as of
  // [date range]" doesn't apply to these the way it does to activity
  // (orders, registrations, submissions) below.
  // ============================================================

  static int farmerCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> users) =>
      users.where((d) => d.data()['role'] == 'farmer' && d.data()['approvalStatus'] == 'approved').length;

  static int buyerCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> users) =>
      users.where((d) => d.data()['role'] == 'buyer').length;

  static int pendingVerifications(List<QueryDocumentSnapshot<Map<String, dynamic>>> users) => users
      .where((d) => d.data()['role'] == 'farmer' && d.data()['approvalStatus'] == 'pending')
      .length;

  static ({int approved, int rejected, int pending}) verificationStatusCounts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) {
    var approved = 0;
    var rejected = 0;
    var pending = 0;
    for (final doc in users) {
      final data = doc.data();
      if (data['role'] != 'farmer') continue;
      switch (data['approvalStatus']) {
        case 'approved':
          approved++;
        case 'rejected':
          rejected++;
        case 'pending':
          pending++;
      }
    }
    return (approved: approved, rejected: rejected, pending: pending);
  }

  static List<({String name, double currentPrice, double? previousPrice, double? changePct, DateTime? updatedAt})>
      commodityPrices(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.map((doc) {
      final data = doc.data();
      final current = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
      final previous = (data['previousBaselinePrice'] as num?)?.toDouble();
      final hasPrevious = previous != null && previous > 0;
      return (
        name: (data['name'] ?? doc.id).toString(),
        currentPrice: current,
        previousPrice: previous,
        changePct: hasPrevious ? ((current - previous) / previous) * 100 : null,
        updatedAt: _timestampToDate(data['updatedAt']),
      );
    }).toList();
  }

  // ============================================================
  // DATE-RANGE-AWARE ACTIVITY METRICS
  // ============================================================

  static num platformTransactionTotal(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, {
    DateTimeRange? range,
  }) {
    num total = 0;
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') continue;
      if (!_inRange(_timestampToDate(data['createdAt']), range)) continue;
      final raw = data['total'];
      total += raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
    }
    return total;
  }

  static Map<String, num> categoryRevenue(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products, {
    DateTimeRange? range,
  }) {
    final categoryByProductId = <String, String>{
      for (final p in products) p.id: (p.data()['category'] ?? '').toString(),
    };
    final revenue = <String, num>{};
    for (final doc in orders) {
      final data = doc.data();
      if (!_inRange(_timestampToDate(data['createdAt']), range)) continue;
      var category = (data['category'] ?? '').toString().trim();
      if (category.isEmpty) {
        final productId = (data['productId'] ?? '').toString();
        category = categoryByProductId[productId] ?? '';
      }
      if (category.isEmpty) category = 'Uncategorized';
      final total = data['total'];
      final value = total is num ? total : num.tryParse(total?.toString() ?? '') ?? 0;
      revenue[category] = (revenue[category] ?? 0) + value;
    }
    return revenue;
  }

  static List<({String name, num revenue, num quantity})> topSellingProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, {
    int limit = 5,
    DateTimeRange? range,
  }) {
    final filtered = range == null
        ? orders
        : orders.where((d) => _inRange(_timestampToDate(d.data()['createdAt']), range));
    return FarmerRevenueService.bestSellingProducts(
      orders: filtered.map((d) => d.data()).toList(),
      limit: limit,
    );
  }

  static bool _orderMatchesCommodity(String productName, String commodityName) {
    final p = productName.toLowerCase();
    final c = commodityName.toLowerCase().trim();
    return c.isNotEmpty && p.contains(c);
  }

  /// Weekly average price, oldest-first. With no [range]: exactly today's
  /// live-dashboard behavior — [weeks] windows counting back from [now].
  /// With a [range]: buckets by week across the range instead.
  static List<double?> weeklyAveragePrice(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    String commodityName, {
    required DateTime now,
    int weeks = 8,
    DateTimeRange? range,
  }) {
    if (range == null) {
      final buckets = List<List<double>>.generate(weeks, (_) => []);
      final windowStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: 7 * weeks));
      for (final doc in orders) {
        final data = doc.data();
        final name = (data['productName'] ?? '').toString();
        if (!_orderMatchesCommodity(name, commodityName)) continue;
        final date = _timestampToDate(data['createdAt']);
        if (date == null || date.isBefore(windowStart)) continue;
        final daysAgo = now.difference(date).inDays;
        final weekIndex = weeks - 1 - (daysAgo ~/ 7);
        if (weekIndex < 0 || weekIndex >= weeks) continue;
        final price = data['unitPrice'];
        final value = price is num ? price.toDouble() : double.tryParse(price?.toString() ?? '');
        if (value != null) buckets[weekIndex].add(value);
      }
      return buckets.map((b) => b.isEmpty ? null : b.reduce((a, b2) => a + b2) / b.length).toList();
    }

    final windowStart = DateTime(range.start.year, range.start.month, range.start.day);
    final windowEnd = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
    final bucketCount = ((windowEnd.difference(windowStart).inDays + 1) / 7).ceil().clamp(1, 104);
    final buckets = List<List<double>>.generate(bucketCount, (_) => []);
    for (final doc in orders) {
      final data = doc.data();
      final name = (data['productName'] ?? '').toString();
      if (!_orderMatchesCommodity(name, commodityName)) continue;
      final date = _timestampToDate(data['createdAt']);
      if (date == null || date.isBefore(windowStart) || date.isAfter(windowEnd)) continue;
      final daysFromStart = date.difference(windowStart).inDays;
      final bucketIndex = (daysFromStart / 7).floor().clamp(0, bucketCount - 1);
      final price = data['unitPrice'];
      final value = price is num ? price.toDouble() : double.tryParse(price?.toString() ?? '');
      if (value != null) buckets[bucketIndex].add(value);
    }
    return buckets.map((b) => b.isEmpty ? null : b.reduce((a, b2) => a + b2) / b.length).toList();
  }

  /// Buyer demand per area — measures the *buyer's* location, not the
  /// selling farmer's (see _resolveBuyerArea). No [range] reproduces the
  /// live dashboard's fixed last-30-days window (with no upper bound,
  /// exactly as today); a [range] applies both bounds explicitly.
  /// [allTime] skips date filtering altogether (ignoring [range]) — used
  /// by the Demand Heatmap, which shows the accumulated geography of
  /// demand rather than a 30-day trend, so it stays consistent with its
  /// own map layer (DashboardAnalyticsService.buyerDemandPoints, also
  /// unwindowed).
  static List<({String barangay, int orderCount, num revenue})> demandByBuyerBarangay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    Map<String, Map<String, dynamic>> usersByUid,
    DateTime now, {
    DateTimeRange? range,
    bool allTime = false,
  }) {
    DateTime? windowStart;
    DateTime? windowEnd;
    if (!allTime) {
      if (range == null) {
        windowStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      } else {
        windowStart = DateTime(range.start.year, range.start.month, range.start.day);
        windowEnd = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
      }
    }

    final counts = <String, int>{};
    final revenue = <String, num>{};
    for (final doc in orders) {
      final data = doc.data();
      if (!allTime) {
        final date = _timestampToDate(data['createdAt']);
        if (date == null || date.isBefore(windowStart!)) continue;
        if (windowEnd != null && date.isAfter(windowEnd)) continue;
      }

      final buyerId = (data['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId]);
      if (resolved == null) continue;
      final area = resolved.area;

      counts[area] = (counts[area] ?? 0) + 1;
      final total = data['total'];
      final value = total is num ? total : num.tryParse(total?.toString() ?? '') ?? 0;
      revenue[area] = (revenue[area] ?? 0) + value;
    }

    final entries = counts.entries
        .map((e) => (barangay: e.key, orderCount: e.value, revenue: revenue[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return entries;
  }

  /// One point per completed order, at the buyer's real resolved location
  /// (see _resolveBuyerArea) — used by the Demand Heatmap's map layer.
  /// Unlike [demandByBuyerBarangay] (grouped/counted for the ranked list),
  /// this keeps every order as its own point, so several nearby-but-
  /// distinct buyers each contribute their own bit of heat instead of
  /// being merged into one area-wide blob. All-time (completed orders are
  /// naturally scoped by whatever query the caller passed in), not
  /// windowed to 30 days — a heatmap of "current demand geography" reads
  /// oddly if it resets every month.
  static List<({double lat, double lng})> buyerDemandPoints(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
    Map<String, Map<String, dynamic>> usersByUid,
  ) {
    final points = <({double lat, double lng})>[];
    for (final doc in completedOrders) {
      final buyerId = (doc.data()['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId]);
      if (resolved == null) continue;
      points.add((lat: resolved.lat, lng: resolved.lng));
    }
    return points;
  }

  /// The first-of-month boundaries [month]/[year] resolves to: `start`
  /// (inclusive) and `end` (exclusive, the first day of the *next* month)
  /// — the exact `completedAt >= start && completedAt < end` window the
  /// admin Demand Heatmap's Month/Year filter uses everywhere below.
  static ({DateTime start, DateTime end}) monthWindow(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return (start: start, end: end);
  }

  /// Every calendar year with at least one completed order, plus [now]'s
  /// year (so a brand-new platform with zero completed orders yet still
  /// has a selectable current year) — the Demand Heatmap's Year filter
  /// options. Real data only, no padded range of arbitrary past years.
  static List<int> yearsWithCompletedOrders(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
    DateTime now,
  ) {
    final years = <int>{now.year};
    for (final doc in completedOrders) {
      final date = _completionDate(doc.data());
      if (date != null) years.add(date.year);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Buyer demand per area for one calendar month — the admin Demand
  /// Heatmap's "Highest Demand Areas" list. Unlike [demandByBuyerBarangay]
  /// (createdAt-windowed, used by the Analytics Dashboard's own 30-day
  /// trend card), this filters by *completion* date
  /// (_completionDate/completedAt) for exactly the selected month/year, per
  /// area (see _resolveBuyerArea) — every completed purchase counts, not
  /// just one per unique buyer, so an area with a few repeat buyers
  /// correctly outranks one with many one-time buyers.
  static List<({String area, int orderCount, num revenue, double lat, double lng})> demandByBuyerAreaForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
    Map<String, Map<String, dynamic>> usersByUid, {
    required int year,
    required int month,
  }) {
    final window = monthWindow(year, month);

    final counts = <String, int>{};
    final revenue = <String, num>{};
    final anchor = <String, ({double lat, double lng})>{};
    for (final doc in completedOrders) {
      final data = doc.data();
      final date = _completionDate(data);
      if (date == null || date.isBefore(window.start) || !date.isBefore(window.end)) continue;

      final buyerId = (data['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId]);
      if (resolved == null) continue;

      counts[resolved.area] = (counts[resolved.area] ?? 0) + 1;
      final total = data['total'];
      final value = total is num ? total : num.tryParse(total?.toString() ?? '') ?? 0;
      revenue[resolved.area] = (revenue[resolved.area] ?? 0) + value;
      anchor[resolved.area] = (lat: resolved.lat, lng: resolved.lng);
    }

    final entries = counts.entries
        .map((e) => (
              area: e.key,
              orderCount: e.value,
              revenue: revenue[e.key] ?? 0,
              lat: anchor[e.key]!.lat,
              lng: anchor[e.key]!.lng,
            ))
        .toList()
      ..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return entries;
  }

  /// One point per completed order in [year]/[month], at the buyer's real
  /// resolved location (see _resolveBuyerArea) — the Demand Heatmap map
  /// layer's month/year-filtered counterpart to [buyerDemandPoints]. Every
  /// completed order contributes its own point (never deduplicated per
  /// buyer), so several purchases from the same or nearby buyers correctly
  /// blend into stronger heat than a single distant one.
  static List<({double lat, double lng})> buyerDemandPointsForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
    Map<String, Map<String, dynamic>> usersByUid, {
    required int year,
    required int month,
  }) {
    final window = monthWindow(year, month);
    final points = <({double lat, double lng})>[];
    for (final doc in completedOrders) {
      final data = doc.data();
      final date = _completionDate(data);
      if (date == null || date.isBefore(window.start) || !date.isBefore(window.end)) continue;
      final buyerId = (data['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId]);
      if (resolved == null) continue;
      points.add((lat: resolved.lat, lng: resolved.lng));
    }
    return points;
  }

  /// New farmer/buyer registrations per month, oldest-first. No [range]
  /// reproduces the live dashboard's fixed last-6-months window exactly
  /// (month-only labels, matching today); a [range] generates the actual
  /// calendar months it spans instead (labeled with year, since a custom
  /// range can cross a year boundary or run longer than 6 months).
  static List<({String label, int farmers, int buyers})> registrationsByMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    DateTime now, {
    DateTimeRange? range,
  }) {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    if (range == null) {
      final months = List.generate(6, (i) => DateTime(now.year, now.month - (5 - i), 1));
      final farmerCounts = List.filled(6, 0);
      final buyerCounts = List.filled(6, 0);
      for (final doc in users) {
        final data = doc.data();
        final role = data['role'];
        if (role != 'farmer' && role != 'buyer') continue;
        final date = _timestampToDate(data['createdAt']);
        if (date == null) continue;
        final idx = months.indexWhere((m) => m.year == date.year && m.month == date.month);
        if (idx == -1) continue;
        if (role == 'farmer') {
          farmerCounts[idx]++;
        } else {
          buyerCounts[idx]++;
        }
      }
      return List.generate(
        6,
        (i) => (label: monthNames[months[i].month - 1], farmers: farmerCounts[i], buyers: buyerCounts[i]),
      );
    }

    final months = <DateTime>[];
    var cursor = DateTime(range.start.year, range.start.month, 1);
    final endMonth = DateTime(range.end.year, range.end.month, 1);
    while (!cursor.isAfter(endMonth)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    final farmerCounts = List.filled(months.length, 0);
    final buyerCounts = List.filled(months.length, 0);
    for (final doc in users) {
      final data = doc.data();
      final role = data['role'];
      if (role != 'farmer' && role != 'buyer') continue;
      final date = _timestampToDate(data['createdAt']);
      if (date == null) continue;
      final idx = months.indexWhere((m) => m.year == date.year && m.month == date.month);
      if (idx == -1) continue;
      if (role == 'farmer') {
        farmerCounts[idx]++;
      } else {
        buyerCounts[idx]++;
      }
    }
    return List.generate(
      months.length,
      (i) => (
        label: '${monthNames[months[i].month - 1]} ${months[i].year}',
        farmers: farmerCounts[i],
        buyers: buyerCounts[i],
      ),
    );
  }

  /// Revenue per calendar day (ranges up to 31 days) or per calendar month
  /// (longer ranges) across [range] — the Export flow's version of the
  /// Sales Overview chart. The live dashboard keeps its own Week/Month
  /// toggle (FarmerRevenueService.revenueBars) completely separate and
  /// unaffected by this.
  static List<({String label, num value})> salesBarsForRange(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange range,
  ) {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final totalDays = end.difference(start).inDays + 1;

    num totalFor(bool Function(DateTime) matches) {
      num total = 0;
      for (final doc in orders) {
        final data = doc.data();
        if ((data['status'] ?? '').toString().toLowerCase() != 'completed') continue;
        final date = _timestampToDate(data['createdAt']);
        if (date == null || !matches(date)) continue;
        final raw = data['total'];
        total += raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
      }
      return total;
    }

    if (totalDays <= 31) {
      return List.generate(totalDays, (i) {
        final day = start.add(Duration(days: i));
        final value = totalFor((d) => d.year == day.year && d.month == day.month && d.day == day.day);
        return (label: DateFormat('MMM d').format(day), value: value);
      });
    }

    final months = <DateTime>[];
    var cursor = DateTime(start.year, start.month, 1);
    final endMonth = DateTime(end.year, end.month, 1);
    while (!cursor.isAfter(endMonth)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months.map((m) {
      final value = totalFor((d) => d.year == m.year && d.month == m.month);
      return (label: DateFormat('MMM y').format(m), value: value);
    }).toList();
  }

  /// Top buyer search terms logged in [year]/[month] (searchEvents.createdAt)
  /// — the Demand Heatmap's "Top Buyer Searches" panel, refreshed on the
  /// same Month/Year filter as the rest of the page (a search record with
  /// no createdAt, which shouldn't happen going forward, is excluded
  /// rather than guessed into a month).
  static List<MapEntry<String, int>> topSearchQueriesForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> searchDocs, {
    required int year,
    required int month,
    int limit = 8,
  }) {
    final window = monthWindow(year, month);
    final counts = <String, int>{};
    for (final doc in searchDocs) {
      final data = doc.data();
      final date = _timestampToDate(data['createdAt']);
      if (date == null || date.isBefore(window.start) || !date.isBefore(window.end)) continue;
      final query = (data['query'] ?? '').toString().trim().toLowerCase();
      if (query.isEmpty) continue;
      counts[query] = (counts[query] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Most recent verification requests. No [range]/default [limit] of 5
  /// reproduces the live dashboard's "glance" widget exactly. Pass `limit:
  /// null` (as the Export flow does) to get every request in [range]
  /// instead of just the latest 5 — a export should list everything in
  /// the chosen window, not just a preview.
  static List<
      ({
        String uid,
        String farmerId,
        String fullName,
        String barangay,
        String dateSubmitted,
        String status,
      })> recentVerifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> verifDocs,
    Map<String, Map<String, dynamic>> usersByUid, {
    DateTimeRange? range,
    int? limit = 5,
  }) {
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs = verifDocs;
    if (range != null) {
      docs = docs.where((d) => _inRange(_timestampToDate(d.data()['submittedAt']), range));
    }
    final sorted = [...docs]..sort((a, b) {
        final at = a.data()['submittedAt'] as Timestamp?;
        final bt = b.data()['submittedAt'] as Timestamp?;
        return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
      });
    final limited = limit == null ? sorted : sorted.take(limit);

    return limited.map((doc) {
      final data = doc.data();
      final userId = (data['userId'] ?? doc.id).toString();
      final userDoc = usersByUid[userId];
      final fullName =
          _firstNonEmpty([data['fullName'], userDoc?['fullName'], userDoc?['name']]) ?? 'Unknown Farmer';
      final barangay = _firstNonEmpty([userDoc?['barangay']]) ?? '—';
      final submittedAt = data['submittedAt'] as Timestamp?;
      final dateSubmitted =
          submittedAt != null ? DateFormat('MMM d, y').format(submittedAt.toDate()) : '—';
      return (
        uid: userId,
        farmerId: userId.length > 8 ? userId.substring(0, 8) : userId,
        fullName: fullName,
        barangay: barangay,
        dateSubmitted: dateSubmitted,
        status: _statusLabel(data['status']),
      );
    }).toList();
  }
}
