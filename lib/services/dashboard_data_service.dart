import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Shared cache for the Admin Analytics Dashboard's "analytics" data —
/// completed orders, products, and market_prices. These feed charts/KPIs
/// that don't need millisecond freshness (Sales Overview, Sales by
/// Category, Transaction Breakdown, Price Trend, Top-Selling Products,
/// Live Commodity Prices), so instead of every admin page opening its own
/// live `.snapshots()` listener on the same collections (admin_dashboard_
/// screen.dart's Analytics Dashboard, Demand Heatmap, and Price Management
/// previously each did), they all read from this one singleton: a single
/// one-shot fetch, cached for [cacheTtl], manually refreshable.
///
/// Operational data that genuinely needs to stay live (Pending
/// Verifications, Flagged Reports — see admin_dashboard_screen.dart) is
/// NOT part of this cache; see [usersStream]/[verificationDocsStream]/
/// [pendingReportsStream] below for the shared *live* tier instead — those
/// stay real Firestore listeners, just one shared instance instead of one
/// per consuming page.
///
/// Modeled on ConnectivityService's TTL-cache + in-flight-dedupe shape
/// (see connectivity_service.dart) — the same pattern, applied to Firestore
/// reads instead of a connectivity probe.
class DashboardDataService extends ChangeNotifier {
  DashboardDataService._();
  static final DashboardDataService instance = DashboardDataService._();

  static const Duration cacheTtl = Duration(minutes: 5);

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allOrders = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _orders = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _products = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _marketPrices = const [];
  DateTime? _lastFetchedAt;
  Future<void>? _inFlight;
  Object? _lastError;

  /// Completed orders only — see class doc. Every consumer of this getter
  /// (Analytics Dashboard, Demand Heatmap) was already written against
  /// "completed orders only" and some of their helper functions (e.g.
  /// DashboardAnalyticsService.demandByBuyerAreaForMonth) trust that and do
  /// NOT re-check status themselves, so this must never silently become
  /// "all orders" — use [allOrders] instead where every status is needed.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get orders => _orders;

  /// Every order regardless of status — for screens like Farmer List that
  /// need active/pending/completed counts, not just completed revenue.
  /// Fetched in the same request as [orders] (one query, filtered down to
  /// the completed subset in Dart) rather than two separate reads of the
  /// same collection.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get allOrders => _allOrders;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get products => _products;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get marketPrices => _marketPrices;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get hasLoadedOnce => _lastFetchedAt != null;
  Object? get lastError => _lastError;

  /// Fetches only if nothing has been loaded yet or the cache is past
  /// [cacheTtl] — safe to call on every build()/initState(), same as
  /// ConnectivityService.checkNow().
  Future<void> ensureLoaded() => _load(force: false);

  /// Always re-fetches (deduped against an already-in-flight fetch) —
  /// what the dashboard's Refresh button and Price Management's write
  /// paths call.
  Future<void> refresh({bool force = true}) => _load(force: force);

  Future<void> _load({required bool force}) {
    if (!force && _lastFetchedAt != null && DateTime.now().difference(_lastFetchedAt!) < cacheTtl) {
      return Future.value();
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('orders').get(),
        FirebaseFirestore.instance.collection('products').get(),
        FirebaseFirestore.instance.collection('market_prices').orderBy('name').get(),
      ]);
      _allOrders = results[0].docs;
      _orders = _allOrders
          .where((d) => (d.data()['status'] ?? '').toString().toLowerCase() == 'completed')
          .toList();
      _products = results[1].docs;
      _marketPrices = results[2].docs;
      _lastError = null;
      _lastFetchedAt = DateTime.now();
    } catch (e) {
      // Keep whatever was already cached visible rather than blanking the
      // dashboard on a transient error.
      _lastError = e;
    } finally {
      notifyListeners();
    }
  }

  // ---- Shared live tier ----
  // Firestore's .snapshots() Stream is broadcast-safe, but only if every
  // consumer shares the SAME Stream instance — calling .collection(...).
  // snapshots() again elsewhere opens a second, independent listener. These
  // late final fields are created once per app session (unlike a page's own
  // State, which admin_dashboard_screen.dart's AnimatedSwitcher tears down
  // on every tab switch) so every page referencing them really does share
  // one Firestore listener each.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> usersStream =
      FirebaseFirestore.instance.collection('users').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> verificationDocsStream =
      FirebaseFirestore.instance.collection('verificationDocs').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> pendingReportsStream =
      FirebaseFirestore.instance.collection('reports').where('status', isEqualTo: 'pending').snapshots();

  /// Every report regardless of status — for the Moderation Queue, which
  /// needs all of Pending/Under Review/Resolved/Violations, not just the
  /// pending count [pendingReportsStream] covers.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> allReportsStream =
      FirebaseFirestore.instance.collection('reports').snapshots();
}
