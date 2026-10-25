import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../data/laurel_barangays.dart';
import 'rsba_number.dart';

/// A buyer's location, resolved for demand analytics — the buyer's own
/// saved location (anywhere in the Philippines, set via BuyerLocationField
/// when placing an order — see place_order_screen.dart), never the
/// farmer's, product's, or seller's.
///
/// A legacy account (registered before buyers could pick a readable
/// address, or that simply hasn't placed an order yet) only has a Laurel
/// barangay name instead of coordinates, or nothing at all. Either way
/// this resolves to one general, plottable point (a pin is rounded to
/// about 1.1km, never plotted exactly) plus a human-readable
/// "Barangay, Municipality" label:
/// - within Laurel (isWithinLaurel): the barangay saved on the buyer's own
///   account, or failing that the nearest Laurel reference barangay, "name,
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
({String area, double? lat, double? lng})? _resolveBuyerProfileArea(
  Map<String, dynamic>? user,
) {
  if (user == null) return null;
  final lat = (user['latitude'] as num?)?.toDouble();
  final lng = (user['longitude'] as num?)?.toDouble();

  if (lat != null && lng != null) {
    // Round the buyer's real pin to ~1.1km before it ever reaches an
    // analytics consumer — every caller of this function is heatmap/ranked-
    // list analytics (never the buyer's own distance calc, which reads live
    // GPS directly), so a buyer's exact home coordinate must never be the
    // thing plotted, even for an admin-only view. Inside Laurel as well as
    // outside it: kLaurelBarangayLocations are only reference points laid
    // out around the town centre, not surveyed barangay positions, so they
    // name an area but must not be used to place heat on a real map.
    final roundedLat = double.parse(lat.toStringAsFixed(2));
    final roundedLng = double.parse(lng.toStringAsFixed(2));
    final barangay = (user['barangay'] ?? '').toString().trim();
    final municipality = (user['municipality'] ?? '').toString().trim();
    if (isWithinLaurel(lat, lng)) {
      // The barangay the buyer saved themselves when there is one; the
      // nearest reference barangay only as a fallback.
      final area = barangay.isNotEmpty
          ? '$barangay, ${municipality.isNotEmpty ? municipality : 'Laurel'}'
          : '${nearestLaurelBarangay(lat, lng).name}, Laurel';
      return (area: area, lat: roundedLat, lng: roundedLng);
    }
    final province = (user['province'] ?? '').toString().trim();
    final label = [
      barangay,
      municipality.isNotEmpty ? municipality : province,
    ].where((s) => s.isNotEmpty).join(', ');
    if (label.isNotEmpty) {
      return (area: label, lat: roundedLat, lng: roundedLng);
    }
    return (
      area:
          'Unresolved area (${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)})',
      lat: roundedLat,
      lng: roundedLng,
    );
  }

  // No pin — the buyer chose their address from the list and no coordinate
  // came with it. The area they saved is still where the purchase came
  // from: it counts, under that name, and is located by the caller (see
  // demandByBuyerAreaForMonth's areaCoordinates) rather than dropped.
  final barangay = (user['barangay'] ?? '').toString().trim();
  final municipality = (user['municipality'] ?? '').toString().trim();
  final province = (user['province'] ?? '').toString().trim();
  final label = [
    barangay,
    municipality.isNotEmpty ? municipality : province,
  ].where((s) => s.isNotEmpty).join(', ');
  if (label.isEmpty) return null;
  return (area: label, lat: null, lng: null);
}

// Parts of a typed address that are finer than a barangay — a purok, a
// street, a house or lot number. Dropped before an address is used as an
// area, so an analytics view never shows them.
final RegExp _addressDetail = RegExp(
  r'^(#|\d)|\b(purok|prk|sitio|zone|blk|block|lot|phase|unit|bldg|building|'
  r'st|street|ave|avenue|road|rd|hwy|highway|km)\b\.?',
  caseSensitive: false,
);

/// The general area — "Barangay, City" at most — named by an order's own
/// address text ([buyerAddress]), or null when it names none.
///
///   "Ihubok I, Basco, Batanes"            -> "Ihubok I, Basco"
///   "Purok 2, Poblacion, Batangas City"   -> "Poblacion, Batangas City"
///   "Talisay, Batangas"                   -> "Talisay, Batangas"
///   "San Gabriel" (a Laurel barangay)     -> "San Gabriel, Laurel"
///   "csegege"                             -> null
///
/// The address a buyer gave for an order is the last resort for where the
/// purchase came from, used only when their account has no saved location
/// (or no longer exists). Free text is never guessed at: a single word is
/// accepted only when it is one of Laurel's own barangays.
String? areaFromOrderAddress(String? address) {
  final parts = [
    for (final part in (address ?? '').split(','))
      if (part.trim().isNotEmpty && !_addressDetail.hasMatch(part.trim()))
        part.trim(),
  ];
  if (parts.isEmpty) return null;
  if (parts.length == 1) {
    for (final barangay in kLaurelBarangays) {
      if (barangay.toLowerCase() == parts.single.toLowerCase()) {
        return '$barangay, Laurel';
      }
    }
    return null;
  }
  // "…, Barangay, City, Province" -> Barangay, City. With only two parts
  // there is no telling which level they are: both are kept.
  return parts.length == 2
      ? parts.join(', ')
      : '${parts[parts.length - 3]}, ${parts[parts.length - 2]}';
}

/// Where a completed purchase came from, for demand analytics: the buyer's
/// own saved location ([_resolveBuyerProfileArea]) and, only when their
/// account has none, the area named by the order's own address
/// ([areaFromOrderAddress]) — located by name, never by a coordinate.
///
/// Only a purchase by a registered account counts. An order whose buyer is
/// not in `users` — sample or test records written straight into `orders`
/// by a script, with a made-up buyer id — is not real buyer demand and
/// resolves to null, whatever address it carries.
({String area, double? lat, double? lng})? _resolveBuyerArea(
  Map<String, dynamic>? user, [
  Map<String, dynamic>? order,
]) {
  if (user == null) return null;
  // The area frozen on the order at checkout comes first: it is where
  // this purchase was made, whatever the buyer's profile says now.
  final frozenBarangay = (order?['buyerBarangay'] ?? '').toString().trim();
  final frozenCity = (order?['buyerMunicipality'] ?? '').toString().trim();
  if (frozenCity.isNotEmpty) {
    return (
      area: frozenBarangay.isEmpty
          ? frozenCity
          : '$frozenBarangay, $frozenCity',
      lat: null,
      lng: null,
    );
  }
  final saved = _resolveBuyerProfileArea(user);
  if (saved != null) return saved;
  final area = areaFromOrderAddress(order?['buyerAddress']?.toString());
  return area == null ? null : (area: area, lat: null, lng: null);
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
///
/// ================================================================
/// CANONICAL METRIC DEFINITIONS — every number the app calls an
/// "analytics" figure means exactly this, everywhere it's shown. A
/// metric not on this list, or a screen showing one of these under a
/// different formula, is a bug — fix the formula or the label, not both
/// independently. Some of these live in other files (noted below) rather
/// than here, since the underlying data (product listings, farmer-scoped
/// revenue, price-trend statistics) is already owned elsewhere — but the
/// DEFINITION is still centralized here.
///
/// - **TOTAL TRANSACTION VALUE** = sum of completed orders' `total`
///   (`status == 'completed'`, any pricingType). See [platformTransactionTotal]
///   — also reused as-is for a single farmer's own total (see
///   farmer_list_view.dart / verification_queue_view.dart).
/// - **SALES OVERVIEW** = revenue from completed orders within the
///   selected period. Live dashboard + farmer Market tab:
///   FarmerRevenueService.totalRevenueForRange/revenueBars. Export flow:
///   [salesBarsForRange]. Deliberately two implementations (see class doc
///   above) — both must independently satisfy this same definition.
/// - **SALES BY CATEGORY** = completed-order revenue grouped by product
///   category. See [categoryRevenue].
/// - **TOP-SELLING PRODUCTS** = products ranked by completed-order
///   revenue, quantity sold retained as a secondary value. See
///   [topSellingProducts] (platform-wide) and
///   FarmerRevenueService.bestSellingProducts (farmer-scoped — the
///   function platform-wide delegates to).
/// - **CURRENT MARKET AVERAGE** = average ACTIVE LISTING price for the
///   same commodity, unit, and pricing type — never the Admin Reference
///   Price (`market_prices.baselinePrice`). See
///   market_price_helpers.dart's computeLiveAverage/
///   computeWholesaleLiveAverage. The "Live Commodity Prices" card on
///   this dashboard ([commodityPrices], below) intentionally shows the
///   Admin Reference Price instead — a different, admin-set figure — and
///   must never be captioned "Current Market Average".
/// - **DEMAND HEATMAP** = buyer demand from completed purchases only, by
///   the BUYER's own location (never the farmer's/seller's). See
///   [demandByBuyerBarangay], [demandByBuyerAreaForMonth],
///   [buyerDemandPoints], [buyerDemandPointsForMonth].
/// - **SEARCH DEMAND** = buyer search-query activity (`searchEvents`),
///   kept entirely separate from completed-purchase demand above — never
///   blended into one number on this dashboard. See
///   [topSearchQueriesForMonth].
/// - **PRICE MOVEMENT** = historical COMPLETED-TRANSACTION prices
///   (`orders.unitPrice`, not listing prices) for the same commodity,
///   unit, and pricing type. See [weeklyAveragePrice].
/// - **Retail / Wholesale breakdown**: [pricingTypeSummary] — a compact
///   Orders/Revenue split by `pricingType`, not a duplicate dashboard.
///   Legacy orders with no `pricingType` field default to Retail, never
///   Wholesale, never excluded.
///
/// Every completed-order metric prefers [_completionDate] (`completedAt`,
/// falling back to `updatedAt` then `createdAt`) over a bare `createdAt`
/// read, and every one independently re-checks `status == 'completed'`
/// rather than trusting the caller's Firestore query to have already
/// filtered it — so a metric never silently counts a pending/confirmed/
/// shipped/rejected order just because some future caller forgets to
/// filter before calling it.
/// ================================================================
class DashboardAnalyticsService {
  const DashboardAnalyticsService._();

  static DateTime? _timestampToDate(dynamic value) =>
      value is Timestamp ? value.toDate() : null;

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
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
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

  // TOTAL USERS / farmer count = Buyers + APPROVED Farmers only — a
  // pending or rejected application is never an active marketplace seller,
  // regardless of how long ago they registered. approvalStatus is the
  // single source-of-truth field for this everywhere in the app
  // (verification queue, Farmer List, marketplace access, here) — never
  // read isVerified for this purpose, it's a separate, narrower-scoped
  // field (see verification_queue_view.dart's _setFarmerApproval).
  static int farmerCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) => users
      .where(
        (d) =>
            d.data()['role'] == 'farmer' &&
            d.data()['approvalStatus'] == 'approved',
      )
      .length;

  static int buyerCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) => users.where((d) => d.data()['role'] == 'buyer').length;

  // A missing approvalStatus (a legacy farmer account predating the field)
  // counts as pending, not as silently excluded — same "missing defaults
  // to pending" convention as AuthRoutingService/PendingApprovalScreen/
  // getPendingFarmers, so this KPI never quietly undercounts legacy
  // accounts that still need an admin decision.
  static int pendingVerifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) => users.where((d) {
    if (d.data()['role'] != 'farmer') return false;
    final status = d.data()['approvalStatus'];
    return status == null || status == 'pending';
  }).length;

  // FLAGGED REPORTS = every report an admin still has to act on: Pending
  // and Under Review. Resolved (and the legacy 'dismissed', which the
  // Moderation Queue also buckets as resolved) are excluded; a missing
  // status counts as pending, the same default the Moderation Queue uses.
  static int unresolvedReports(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reports,
  ) => reports.where((d) {
    final status = (d.data()['status'] ?? 'pending').toString();
    return status != 'resolved' && status != 'dismissed';
  }).length;

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
        case null:
          pending++;
      }
    }
    return (approved: approved, rejected: rejected, pending: pending);
  }

  static List<
    ({
      String name,
      double currentPrice,
      double? previousPrice,
      double? changePct,
      DateTime? updatedAt,
    })
  >
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

  // TOTAL TRANSACTION VALUE = sum of completed orders' `total`. Works for
  // any order list passed in — the platform-wide KPI tile, the Export
  // flow, and a single farmer's own "Total Sales" figure (see
  // farmer_list_view.dart / verification_queue_view.dart) all call this
  // same function rather than each re-summing independently.
  static num platformTransactionTotal(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, {
    DateTimeRange? range,
  }) {
    num total = 0;
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      if (!_inRange(_completionDate(data), range)) continue;
      final raw = data['total'];
      total += raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
    }
    return total;
  }

  // How many orders platformTransactionTotal counts: completed, and
  // completed within [range].
  static int completedOrderCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, {
    DateTimeRange? range,
  }) {
    var count = 0;
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      if (_inRange(_completionDate(data), range)) count++;
    }
    return count;
  }

  // Compact Retail/Wholesale breakdown (Orders + Revenue) — see class doc.
  // Not a second dashboard: this backs one small summary row alongside
  // Total Transaction Value / Sales Overview, not a duplicate set of
  // charts.
  static ({
    int retailOrders,
    int wholesaleOrders,
    num retailRevenue,
    num wholesaleRevenue,
  })
  pricingTypeSummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, {
    DateTimeRange? range,
  }) {
    var retailOrders = 0;
    var wholesaleOrders = 0;
    num retailRevenue = 0;
    num wholesaleRevenue = 0;

    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      if (!_inRange(_completionDate(data), range)) continue;

      final type = (data['pricingType'] ?? 'retail').toString().toLowerCase();
      final raw = data['subtotal'] ?? data['total'];
      final value = raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;

      if (type == 'wholesale') {
        wholesaleOrders++;
        wholesaleRevenue += value;
      } else {
        // Legacy orders pre-dating pricingType are classified as retail.
        retailOrders++;
        retailRevenue += value;
      }
    }

    return (
      retailOrders: retailOrders,
      wholesaleOrders: wholesaleOrders,
      retailRevenue: retailRevenue,
      wholesaleRevenue: wholesaleRevenue,
    );
  }

  /// The categories Sales by Category reports under, spelled as shown.
  static const List<String> salesCategories = [
    'Grains',
    'Root Crops',
    'Vegetables',
    'Spices',
    'Fruits',
    'Livestock',
  ];

  // [raw] as one of the commodity list's categories however it was typed
  // ("root crops", " Vegetables "); null for anything that is not one.
  static String? _knownCategory(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final key = text.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ' ');
    for (final name in [
      ...salesCategories,
      ...CommodityRegistry.instance.categories,
    ]) {
      if (name.toLowerCase() == key) return name;
    }
    return null;
  }

  /// The category a completed order was sold under — always one of the
  /// commodity list's own categories, most direct source first:
  ///  1. the category frozen on the order at checkout;
  ///  2. the category on the product listing it was bought from;
  ///  3. the category of the supported commodity the order or listing is
  ///     for ("Yellow Corn" is Corn, so Grains).
  /// Null for a product that is not on the commodity list at all.
  static String? orderCategory(
    Map<String, dynamic> order,
    Map<String, dynamic>? product,
  ) {
    final recorded =
        _knownCategory(order['category']) ??
        _knownCategory(product?['category']);
    if (recorded != null) return recorded;
    for (final name in [
      order['commodity'],
      product?['commodity'],
      order['productName'],
      product?['name'],
    ]) {
      final text = (name ?? '').toString().trim();
      if (text.isEmpty) continue;
      final category =
          categoryOfCommodity(text) ??
          categoryOfCommodity(matchSupportedCommodity(text) ?? '');
      if (category != null) return _knownCategory(category) ?? category;
    }
    return null;
  }

  // Orders already reported as having no category, so a live dashboard
  // doesn't repeat the same line on every update.
  static final Set<String> _loggedNoCategory = {};

  // SALES BY CATEGORY = completed-order revenue grouped by product
  // category (see [orderCategory]). Re-checks status itself (never just
  // trusts the caller's Firestore query already filtered it) — see class
  // doc. An order for a product outside the commodity list has no
  // category: it is left out, and its ID is logged.
  static Map<String, num> categoryRevenue(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products, {
    DateTimeRange? range,
  }) {
    final productById = <String, Map<String, dynamic>>{
      for (final p in products) p.id: p.data(),
    };
    final revenue = <String, num>{};
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      if (!_inRange(_completionDate(data), range)) continue;
      final productId = (data['productId'] ?? '').toString();
      final category = orderCategory(data, productById[productId]);
      if (category == null) {
        if (_loggedNoCategory.add(doc.id)) {
          debugPrint(
            '[SalesByCategory] order ${doc.id} has no category '
            '(productId: ${productId.isEmpty ? 'none' : productId}, '
            'product: ${data['productName'] ?? 'unnamed'})',
          );
        }
        continue;
      }
      final total = data['total'];
      final value = total is num
          ? total
          : num.tryParse(total?.toString() ?? '') ?? 0;
      revenue[category] = (revenue[category] ?? 0) + value;
    }
    return revenue;
  }

  /// The dashboard's "Last N Months" period: the [months] calendar months
  /// ending with [now]'s own month, from the 1st of the earliest one.
  static DateTimeRange lastMonthsRange(DateTime now, int months) =>
      DateTimeRange(
        start: DateTime(now.year, now.month - (months - 1), 1),
        end: now,
      );

  /// SALES PERFORMANCE = completed-order revenue per calendar month, for
  /// the [months] months ending with [now]'s, oldest first. Completed
  /// orders only, dated by when they completed (see [_completionDate]).
  /// A month with no completed order is still listed, at zero — never
  /// filled in or estimated.
  static List<({DateTime month, double revenue, int orders})>
  monthlyCompletedSales(
    Iterable<Map<String, dynamic>> orders, {
    required DateTime now,
    int months = 6,
  }) {
    final first = DateTime(now.year, now.month - (months - 1), 1);
    final revenue = List<double>.filled(months, 0);
    final counts = List<int>.filled(months, 0);
    for (final data in orders) {
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final date = _completionDate(data);
      if (date == null) continue;
      final index = (date.year - first.year) * 12 + (date.month - first.month);
      if (index < 0 || index >= months) continue;
      final total = data['total'];
      revenue[index] += total is num
          ? total.toDouble()
          : double.tryParse(total?.toString() ?? '') ?? 0;
      counts[index]++;
    }
    return [
      for (var i = 0; i < months; i++)
        (
          month: DateTime(first.year, first.month + i, 1),
          revenue: revenue[i],
          orders: counts[i],
        ),
    ];
  }

  /// SALES PERFORMANCE by product: for each of the [months] calendar months
  /// ending this one, the revenue and number of completed orders of every
  /// product (its supported commodity, else the order's own product name)
  /// — the [limit] that sold the most over the whole
  /// period, highest first (ranked by revenue, as Top-Selling Products
  /// is). A month in which a product sold nothing is a real 0, so a line
  /// shows the drop.
  static List<({String name, List<double> revenue, List<int> orders})>
  monthlyProductSales(
    Iterable<Map<String, dynamic>> orders, {
    required DateTime now,
    int months = 6,
    int limit = 5,
  }) {
    final first = DateTime(now.year, now.month - (months - 1), 1);
    final revenue = <String, List<double>>{};
    final counts = <String, List<int>>{};
    for (final data in orders) {
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      // A product not on the commodity list still has its sales charted,
      // under its own name.
      final productName = (data['productName'] ?? '').toString().trim();
      final name =
          orderCommodity(data) ?? (productName.isEmpty ? null : productName);
      final date = _completionDate(data);
      if (name == null || date == null) continue;
      final index = (date.year - first.year) * 12 + (date.month - first.month);
      if (index < 0 || index >= months) continue;
      final total = data['total'];
      revenue.putIfAbsent(
        name,
        () => List<double>.filled(months, 0),
      )[index] += total is num
          ? total.toDouble()
          : double.tryParse(total?.toString() ?? '') ?? 0;
      counts.putIfAbsent(name, () => List<int>.filled(months, 0))[index]++;
    }
    double sum(List<double> values) => values.fold(0, (a, b) => a + b);
    final ranked = revenue.keys.toList()
      ..sort((a, b) {
        final byRevenue = sum(revenue[b]!).compareTo(sum(revenue[a]!));
        return byRevenue != 0 ? byRevenue : a.compareTo(b);
      });
    return [
      for (final name in ranked.take(limit))
        (name: name, revenue: revenue[name]!, orders: counts[name]!),
    ];
  }

  /// SALES PERFORMANCE for one [product]: its demand in each of the
  /// [months] calendar months ending this one — the quantity sold in
  /// completed orders (in the product's own unit), their revenue and how
  /// many there were — so the months it sells best, and where it drops,
  /// show. A month with no sale is a real 0.
  static List<({DateTime month, double quantity, double revenue, int orders})>
  monthlyDemandFor(
    Iterable<Map<String, dynamic>> orders, {
    required String product,
    required DateTime now,
    int months = 6,
  }) {
    final first = DateTime(now.year, now.month - (months - 1), 1);
    final target = product.trim().toLowerCase();
    final unit = unitForCommodity(product).toLowerCase();
    final quantity = List<double>.filled(months, 0);
    final revenue = List<double>.filled(months, 0);
    final counts = List<int>.filled(months, 0);
    for (final data in orders) {
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final productName = (data['productName'] ?? '').toString().trim();
      final name = orderCommodity(data) ?? productName;
      if (name.toLowerCase() != target) continue;
      final date = _completionDate(data);
      if (date == null) continue;
      final index = (date.year - first.year) * 12 + (date.month - first.month);
      if (index < 0 || index >= months) continue;
      final total = data['total'];
      revenue[index] += total is num
          ? total.toDouble()
          : double.tryParse(total?.toString() ?? '') ?? 0;
      counts[index]++;
      // Quantities only add up in one unit (never kg with heads).
      final orderUnit = (data['unit'] ?? '').toString().trim().toLowerCase();
      final q = data['quantity'];
      if ((orderUnit.isEmpty || orderUnit == unit) && q is num) {
        quantity[index] += q.toDouble();
      }
    }
    return [
      for (var i = 0; i < months; i++)
        (
          month: DateTime(first.year, first.month + i, 1),
          quantity: quantity[i],
          revenue: revenue[i],
          orders: counts[i],
        ),
    ];
  }

  /// The supported commodity a completed order was for: the commodity
  /// frozen on the order, or the one its product name refers to ("Native
  /// Chicken" is Chicken). Null for a product that is not on the Admin's
  /// commodity list.
  static String? orderCommodity(Map<String, dynamic> order) {
    final frozen = (order['commodity'] ?? '').toString().trim();
    final known = CommodityRegistry.instance.find(frozen)?.name;
    if (known != null) return known;
    return matchSupportedCommodity((order['productName'] ?? '').toString());
  }

  /// TOP-SELLING PRODUCTS = the supported commodities ranked by the revenue
  /// of their completed orders, every listing of a commodity counted
  /// together. An order for something that is not on the commodity list is
  /// not ranked.
  static List<({String name, num revenue, num quantity})> topSellingProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, {
    int limit = 5,
    DateTimeRange? range,
  }) {
    final revenue = <String, num>{};
    final quantity = <String, num>{};
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      if (!_inRange(_completionDate(data), range)) continue;
      final commodity = orderCommodity(data);
      if (commodity == null) continue;
      num number(dynamic raw) =>
          raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
      revenue[commodity] = (revenue[commodity] ?? 0) + number(data['total']);
      quantity[commodity] =
          (quantity[commodity] ?? 0) + number(data['quantity']);
    }
    final ranked = revenue.keys.toList()
      ..sort((a, b) => revenue[b]!.compareTo(revenue[a]!));
    return [
      for (final name in ranked.take(limit))
        (name: name, revenue: revenue[name]!, quantity: quantity[name]!),
    ];
  }

  // Whether a completed order was for [commodityName] — by the same rule
  // as Top-Selling Products ([orderCommodity]) when it is a supported
  // commodity, so the two cards always count the same orders. For a price
  // record that is not a supported commodity yet, by its name.
  static bool _orderMatchesCommodity(
    Map<String, dynamic> order,
    String commodityName,
  ) {
    final c = commodityName.toLowerCase().trim();
    if (c.isEmpty) return false;
    if (CommodityRegistry.instance.find(commodityName) != null) {
      return orderCommodity(order)?.toLowerCase() == c;
    }
    return (order['productName'] ?? '').toString().toLowerCase().contains(c);
  }

  /// PRICE MOVEMENT: weekly average of completed-order transaction prices
  /// (`unitPrice`, not a listing price), oldest-first, for one commodity
  /// AND one [pricingType] — never blending retail and wholesale prices
  /// into the same weekly figure, since they aren't comparable numbers.
  /// Legacy orders with no `pricingType` field are treated as Retail (see
  /// class doc), matching every other pricingType read in the app. With
  /// no [range]: exactly today's live-dashboard behavior — [weeks] windows
  /// counting back from [now]. With a [range]: buckets by week across the
  /// range instead.
  static List<double?> weeklyAveragePrice(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    String commodityName, {
    required DateTime now,
    int weeks = 8,
    DateTimeRange? range,
    String pricingType = 'retail',
  }) {
    bool matchesPricingType(Map<String, dynamic> data) {
      final type = (data['pricingType'] ?? 'retail').toString().toLowerCase();
      return type == pricingType;
    }

    if (range == null) {
      final buckets = List<List<double>>.generate(weeks, (_) => []);
      final windowStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 7 * weeks));
      for (final doc in orders) {
        final data = doc.data();
        if (!_orderMatchesCommodity(data, commodityName)) continue;
        if (!matchesPricingType(data)) continue;
        final date = _completionDate(data);
        if (date == null || date.isBefore(windowStart)) continue;
        final daysAgo = now.difference(date).inDays;
        final weekIndex = weeks - 1 - (daysAgo ~/ 7);
        if (weekIndex < 0 || weekIndex >= weeks) continue;
        final price = data['unitPrice'];
        final value = price is num
            ? price.toDouble()
            : double.tryParse(price?.toString() ?? '');
        if (value != null) buckets[weekIndex].add(value);
      }
      return buckets
          .map((b) => b.isEmpty ? null : b.reduce((a, b2) => a + b2) / b.length)
          .toList();
    }

    final windowStart = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final windowEnd = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
    final bucketCount = ((windowEnd.difference(windowStart).inDays + 1) / 7)
        .ceil()
        .clamp(1, 104);
    final buckets = List<List<double>>.generate(bucketCount, (_) => []);
    for (final doc in orders) {
      final data = doc.data();
      if (!_orderMatchesCommodity(data, commodityName)) continue;
      if (!matchesPricingType(data)) continue;
      final date = _completionDate(data);
      if (date == null ||
          date.isBefore(windowStart) ||
          date.isAfter(windowEnd)) {
        continue;
      }
      final daysFromStart = date.difference(windowStart).inDays;
      final bucketIndex = (daysFromStart / 7).floor().clamp(0, bucketCount - 1);
      final price = data['unitPrice'];
      final value = price is num
          ? price.toDouble()
          : double.tryParse(price?.toString() ?? '');
      if (value != null) buckets[bucketIndex].add(value);
    }
    return buckets
        .map((b) => b.isEmpty ? null : b.reduce((a, b2) => a + b2) / b.length)
        .toList();
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
  static List<({String barangay, int orderCount, num revenue})>
  demandByBuyerBarangay(
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
        windowStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 30));
      } else {
        windowStart = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        windowEnd = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
          999,
        );
      }
    }

    final counts = <String, int>{};
    final revenue = <String, num>{};
    for (final doc in orders) {
      final data = doc.data();
      if (!allTime) {
        final date = _completionDate(data);
        if (date == null || date.isBefore(windowStart!)) continue;
        if (windowEnd != null && date.isAfter(windowEnd)) continue;
      }

      final buyerId = (data['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId], doc.data());
      if (resolved == null) continue;
      final area = resolved.area;

      counts[area] = (counts[area] ?? 0) + 1;
      final total = data['total'];
      final value = total is num
          ? total
          : num.tryParse(total?.toString() ?? '') ?? 0;
      revenue[area] = (revenue[area] ?? 0) + value;
    }

    final entries =
        counts.entries
            .map(
              (e) => (
                barangay: e.key,
                orderCount: e.value,
                revenue: revenue[e.key] ?? 0,
              ),
            )
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
      final resolved = _resolveBuyerArea(usersByUid[buyerId], doc.data());
      if (resolved == null) continue;
      // An area with no coordinate of its own cannot be a point here.
      final lat = resolved.lat;
      final lng = resolved.lng;
      if (lat == null || lng == null) continue;
      points.add((lat: lat, lng: lng));
    }
    return points;
  }

  /// The first-of-month boundaries [month]/[year] resolves to: `start`
  /// (inclusive) and `end` (exclusive, the first day of the *next* month)
  /// — the exact `completedAt >= start && completedAt < end` window the
  /// admin Demand Heatmap's Month/Year filter uses everywhere below.
  static ({DateTime start, DateTime end}) monthWindow(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
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

  // The middle of an area's located buyers, or failing any, [lookedUp].
  static double? _areaCoordinate(
    String area,
    Map<String, double> sums,
    Map<String, int> located,
    double? lookedUp,
  ) {
    final count = located[area] ?? 0;
    return count > 0 ? sums[area]! / count : lookedUp;
  }

  /// Buyer demand per area for one calendar month — the admin Demand
  /// Heatmap's "Highest Demand Areas" list. Unlike [demandByBuyerBarangay]
  /// (createdAt-windowed, used by the Analytics Dashboard's own 30-day
  /// trend card), this filters by *completion* date
  /// (_completionDate/completedAt) for exactly the selected month/year, per
  /// area (see _resolveBuyerArea) — every completed purchase counts, not
  /// just one per unique buyer, so an area with a few repeat buyers
  /// correctly outranks one with many one-time buyers.
  ///
  /// An area is placed at the middle of its buyers' general locations. One
  /// whose buyers saved an address without a map pin has none: it is still
  /// counted and listed, with null coordinates unless [areaCoordinates]
  /// (area name -> looked-up location) supplies one.
  static List<
    ({String area, int orderCount, num revenue, double? lat, double? lng})
  >
  demandByBuyerAreaForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
    Map<String, Map<String, dynamic>> usersByUid, {
    required int year,
    required int month,
    Map<String, ({double lat, double lng})>? areaCoordinates,
  }) {
    final window = monthWindow(year, month);

    final counts = <String, int>{};
    final revenue = <String, num>{};
    // Where each area is drawn: the middle of its buyers' general (already
    // rounded) locations, weighted by their purchases — one point per area.
    final latSum = <String, double>{};
    final lngSum = <String, double>{};
    final located = <String, int>{};
    for (final doc in completedOrders) {
      final data = doc.data();
      final date = _completionDate(data);
      if (date == null ||
          date.isBefore(window.start) ||
          !date.isBefore(window.end)) {
        continue;
      }

      final buyerId = (data['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId], doc.data());
      if (resolved == null) continue;

      counts[resolved.area] = (counts[resolved.area] ?? 0) + 1;
      final total = data['total'];
      final value = total is num
          ? total
          : num.tryParse(total?.toString() ?? '') ?? 0;
      revenue[resolved.area] = (revenue[resolved.area] ?? 0) + value;
      final lat = resolved.lat;
      final lng = resolved.lng;
      if (lat != null && lng != null) {
        located[resolved.area] = (located[resolved.area] ?? 0) + 1;
        latSum[resolved.area] = (latSum[resolved.area] ?? 0) + lat;
        lngSum[resolved.area] = (lngSum[resolved.area] ?? 0) + lng;
      }
    }

    final entries =
        counts.entries
            .map(
              (e) => (
                area: e.key,
                orderCount: e.value,
                revenue: revenue[e.key] ?? 0,
                lat: _areaCoordinate(
                  e.key,
                  latSum,
                  located,
                  areaCoordinates?[e.key]?.lat,
                ),
                lng: _areaCoordinate(
                  e.key,
                  lngSum,
                  located,
                  areaCoordinates?[e.key]?.lng,
                ),
              ),
            )
            .toList()
          ..sort((a, b) => b.orderCount.compareTo(a.orderCount));
    return entries;
  }

  /// MOST PURCHASED PRODUCTS BY AREA = within each buyer area (see
  /// _resolveBuyerArea — the same areas as [demandByBuyerAreaForMonth]),
  /// the commodities bought in completed orders in [year]/[month], ranked
  /// by total quantity purchased (then by number of orders). Completed
  /// orders only; a listing's own name is matched to its commodity, so
  /// "Fresh Native Chicken" and "Chicken" count together. Aggregated per
  /// area: no buyer is identified.
  static Map<
    String,
    List<
      ({
        String product,
        String category,
        double quantity,
        String unit,
        int orders,
      })
    >
  >
  productsByBuyerAreaForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
    Map<String, Map<String, dynamic>> usersByUid, {
    required int year,
    required int month,
  }) {
    final window = monthWindow(year, month);
    // area -> "commodity|unit" -> running totals
    final byArea =
        <
          String,
          Map<
            String,
            ({
              String product,
              String category,
              double quantity,
              String unit,
              int orders,
            })
          >
        >{};
    for (final doc in completedOrders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final date = _completionDate(data);
      if (date == null ||
          date.isBefore(window.start) ||
          !date.isBefore(window.end)) {
        continue;
      }
      final resolved = _resolveBuyerArea(
        usersByUid[(data['buyerId'] ?? '').toString()],
        data,
      );
      if (resolved == null) continue;

      final name = (data['productName'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final product = matchSupportedCommodity(name) ?? name;
      final category =
          categoryOfCommodity(product) ??
          (data['category'] ?? '').toString().trim();
      final savedUnit = (data['unit'] ?? '').toString().trim();
      final unit = savedUnit.isNotEmpty ? savedUnit : unitForCommodity(product);
      final rawQuantity = data['quantity'];
      final quantity = rawQuantity is num
          ? rawQuantity.toDouble()
          : double.tryParse(rawQuantity?.toString() ?? '') ?? 0;

      final products = byArea.putIfAbsent(resolved.area, () => {});
      final key = '${product.toLowerCase()}|${unit.toLowerCase()}';
      final current = products[key];
      products[key] = (
        product: product,
        category: category,
        quantity: (current?.quantity ?? 0) + quantity,
        unit: unit,
        orders: (current?.orders ?? 0) + 1,
      );
    }
    return {
      for (final entry in byArea.entries)
        entry.key: entry.value.values.toList()
          ..sort((a, b) {
            final byQuantity = b.quantity.compareTo(a.quantity);
            if (byQuantity != 0) return byQuantity;
            final byOrders = b.orders.compareTo(a.orders);
            return byOrders != 0 ? byOrders : a.product.compareTo(b.product);
          }),
    };
  }

  /// How many orders completed in [year]/[month] in total — including the
  /// ones [demandByBuyerAreaForMonth] cannot place because their buyer has
  /// no saved location. The difference between the two is what the Demand
  /// Heatmap reports as not mapped, instead of silently dropping it.
  static int completedOrderCountForMonth(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders, {
    required int year,
    required int month,
  }) {
    final window = monthWindow(year, month);
    var count = 0;
    for (final doc in completedOrders) {
      final date = _completionDate(doc.data());
      if (date == null ||
          date.isBefore(window.start) ||
          !date.isBefore(window.end)) {
        continue;
      }
      count++;
    }
    return count;
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
      if (date == null ||
          date.isBefore(window.start) ||
          !date.isBefore(window.end)) {
        continue;
      }
      final buyerId = (data['buyerId'] ?? '').toString();
      final resolved = _resolveBuyerArea(usersByUid[buyerId], doc.data());
      if (resolved == null) continue;
      // An area with no coordinate of its own cannot be a point here.
      final lat = resolved.lat;
      final lng = resolved.lng;
      if (lat == null || lng == null) continue;
      points.add((lat: lat, lng: lng));
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    if (range == null) {
      final months = List.generate(
        6,
        (i) => DateTime(now.year, now.month - (5 - i), 1),
      );
      final farmerCounts = List.filled(6, 0);
      final buyerCounts = List.filled(6, 0);
      for (final doc in users) {
        final data = doc.data();
        final role = data['role'];
        if (role != 'farmer' && role != 'buyer') continue;
        final date = _timestampToDate(data['createdAt']);
        if (date == null) continue;
        final idx = months.indexWhere(
          (m) => m.year == date.year && m.month == date.month,
        );
        if (idx == -1) continue;
        if (role == 'farmer') {
          farmerCounts[idx]++;
        } else {
          buyerCounts[idx]++;
        }
      }
      return List.generate(
        6,
        (i) => (
          label: monthNames[months[i].month - 1],
          farmers: farmerCounts[i],
          buyers: buyerCounts[i],
        ),
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
      final idx = months.indexWhere(
        (m) => m.year == date.year && m.month == date.month,
      );
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
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final totalDays = end.difference(start).inDays + 1;

    num totalFor(bool Function(DateTime) matches) {
      num total = 0;
      for (final doc in orders) {
        final data = doc.data();
        if ((data['status'] ?? '').toString().toLowerCase() != 'completed') {
          continue;
        }
        final date = _completionDate(data);
        if (date == null || !matches(date)) continue;
        final raw = data['total'];
        total += raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
      }
      return total;
    }

    if (totalDays <= 31) {
      return List.generate(totalDays, (i) {
        final day = start.add(Duration(days: i));
        final value = totalFor(
          (d) => d.year == day.year && d.month == day.month && d.day == day.day,
        );
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

  /// SEARCH DEMAND BY AREA = buyer searches logged in [year]/[month]
  /// (searchEvents.createdAt), counted by the area the searching buyer has
  /// saved on their account — where buyers are LOOKING, kept apart from
  /// where they bought ([demandByBuyerAreaForMonth]); the two are never
  /// added together.
  ///
  /// A search record holds who searched and what, not where, so the area
  /// is the searcher's saved one. A search by a buyer with no saved
  /// location, or by an account that no longer exists, cannot be placed
  /// and is left out. [terms] gives, per area, what was searched for there,
  /// most searched first.
  static ({
    List<({String area, int searches, double? lat, double? lng})> areas,
    Map<String, List<({String term, int searches})>> terms,
  })
  searchesByBuyerAreaForMonth(
    Iterable<Map<String, dynamic>> searchEvents,
    Map<String, Map<String, dynamic>> usersByUid, {
    required int year,
    required int month,
    Map<String, ({double lat, double lng})>? areaCoordinates,
  }) {
    final window = monthWindow(year, month);
    final counts = <String, int>{};
    final latSum = <String, double>{};
    final lngSum = <String, double>{};
    final located = <String, int>{};
    final termCounts = <String, Map<String, int>>{};
    for (final data in searchEvents) {
      final date = _timestampToDate(data['createdAt']);
      if (date == null ||
          date.isBefore(window.start) ||
          !date.isBefore(window.end)) {
        continue;
      }
      final term = (data['query'] ?? '').toString().trim().toLowerCase();
      if (term.isEmpty) continue;
      final resolved = _resolveBuyerProfileArea(
        usersByUid[(data['userId'] ?? '').toString()],
      );
      if (resolved == null) continue;

      final area = resolved.area;
      counts[area] = (counts[area] ?? 0) + 1;
      final lat = resolved.lat;
      final lng = resolved.lng;
      if (lat != null && lng != null) {
        located[area] = (located[area] ?? 0) + 1;
        latSum[area] = (latSum[area] ?? 0) + lat;
        lngSum[area] = (lngSum[area] ?? 0) + lng;
      }
      final terms = termCounts.putIfAbsent(area, () => {});
      terms[term] = (terms[term] ?? 0) + 1;
    }

    final areas =
        [
          for (final entry in counts.entries)
            (
              area: entry.key,
              searches: entry.value,
              lat: _areaCoordinate(
                entry.key,
                latSum,
                located,
                areaCoordinates?[entry.key]?.lat,
              ),
              lng: _areaCoordinate(
                entry.key,
                lngSum,
                located,
                areaCoordinates?[entry.key]?.lng,
              ),
            ),
        ]..sort((a, b) {
          final bySearches = b.searches.compareTo(a.searches);
          return bySearches != 0 ? bySearches : a.area.compareTo(b.area);
        });
    return (
      areas: areas,
      terms: {
        for (final entry in termCounts.entries)
          entry.key:
              [
                for (final term in entry.value.entries)
                  (term: term.key, searches: term.value),
              ]..sort((a, b) {
                final bySearches = b.searches.compareTo(a.searches);
                return bySearches != 0 ? bySearches : a.term.compareTo(b.term);
              }),
      },
    );
  }

  /// How much a completed purchase and a buyer search each add to an
  /// area's demand on the Demand Heatmap: buying shows stronger demand
  /// than looking, so a purchase counts twice a search.
  static const int purchaseDemandPoints = 2;
  static const int searchDemandPoints = 1;

  /// One Demand Heatmap: each buyer area's completed purchases and buyer
  /// searches for the month together, as a demand score (purchases ×
  /// [purchaseDemandPoints] + searches × [searchDemandPoints]) that sets
  /// the heat. Highest score first; an area keeps the location of
  /// whichever side has one.
  static List<
    ({
      String area,
      int purchases,
      int searches,
      int score,
      num revenue,
      double? lat,
      double? lng,
    })
  >
  combinedDemandByArea(
    List<({String area, int orderCount, num revenue, double? lat, double? lng})>
    purchases,
    List<({String area, int searches, double? lat, double? lng})> searches,
  ) {
    final byArea =
        <
          String,
          ({int purchases, int searches, num revenue, double? lat, double? lng})
        >{};
    for (final p in purchases) {
      byArea[p.area] = (
        purchases: p.orderCount,
        searches: 0,
        revenue: p.revenue,
        lat: p.lat,
        lng: p.lng,
      );
    }
    for (final q in searches) {
      final had = byArea[q.area];
      byArea[q.area] = (
        purchases: had?.purchases ?? 0,
        searches: q.searches,
        revenue: had?.revenue ?? 0,
        lat: had?.lat ?? q.lat,
        lng: had?.lng ?? q.lng,
      );
    }
    final list = [
      for (final e in byArea.entries)
        (
          area: e.key,
          purchases: e.value.purchases,
          searches: e.value.searches,
          score:
              e.value.purchases * purchaseDemandPoints +
              e.value.searches * searchDemandPoints,
          revenue: e.value.revenue,
          lat: e.value.lat,
          lng: e.value.lng,
        ),
    ];
    list.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byPurchases = b.purchases.compareTo(a.purchases);
      if (byPurchases != 0) return byPurchases;
      return a.area.compareTo(b.area);
    });
    return list;
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
      if (date == null ||
          date.isBefore(window.start) ||
          !date.isBefore(window.end)) {
        continue;
      }
      final query = (data['query'] ?? '').toString().trim().toLowerCase();
      if (query.isEmpty) continue;
      counts[query] = (counts[query] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
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
    })
  >
  recentVerifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> verifDocs,
    Map<String, Map<String, dynamic>> usersByUid, {
    DateTimeRange? range,
    int? limit = 5,
  }) {
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs = verifDocs;
    if (range != null) {
      docs = docs.where(
        (d) => _inRange(_timestampToDate(d.data()['submittedAt']), range),
      );
    }
    final sorted = [...docs]
      ..sort((a, b) {
        final at = a.data()['submittedAt'] as Timestamp?;
        final bt = b.data()['submittedAt'] as Timestamp?;
        return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
          at?.millisecondsSinceEpoch ?? 0,
        );
      });
    final limited = limit == null ? sorted : sorted.take(limit);

    return limited.map((doc) {
      final data = doc.data();
      final userId = (data['userId'] ?? doc.id).toString();
      final userDoc = usersByUid[userId];
      final fullName =
          _firstNonEmpty([
            data['fullName'],
            userDoc?['fullName'],
            userDoc?['name'],
          ]) ??
          'Unknown Farmer';
      final barangay = _firstNonEmpty([userDoc?['barangay']]) ?? '—';
      final submittedAt = data['submittedAt'] as Timestamp?;
      final dateSubmitted = submittedAt != null
          ? DateFormat('MMM d, y').format(submittedAt.toDate())
          : '—';
      return (
        uid: userId,
        farmerId: farmerIdOf(userDoc, data) ?? kNoFarmerId,
        fullName: fullName,
        barangay: barangay,
        dateSubmitted: dateSubmitted,
        status: _statusLabel(data['status']),
      );
    }).toList();
  }
}
