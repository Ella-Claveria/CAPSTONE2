import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'admin_perf.dart';

/// Shared, LIVE source for the Admin Portal's "analytics" data —
/// completed orders, products, and market_prices — feeding the charts and
/// KPIs (Sales Performance, Sales by Category, Price Trend, Top-Selling
/// Products, the Demand Heatmap, Price Management, Market Forecasts).
///
/// Instead of every admin page opening its own `.snapshots()` listener on
/// the same collections, they all read from this one singleton: ONE
/// listener per collection for the whole portal, opened the first time a
/// page asks and kept for the session. A change in the database reaches
/// every open page by itself — the admin never has to refresh.
///
/// The other collections the portal watches live (users, verification
/// documents, reports) are shared the same way: see [usersStream],
/// [verificationDocsStream] and [allReportsStream] below.
class DashboardDataService extends ChangeNotifier {
  DashboardDataService._();
  static final DashboardDataService instance = DashboardDataService._();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allOrders = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _orders = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _products = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _marketPrices = const [];
  DateTime? _lastFetchedAt;
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
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get marketPrices =>
      _marketPrices;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get hasLoadedOnce => _lastFetchedAt != null;
  Object? get lastError => _lastError;

  // ---- Live: orders, products and market_prices ----
  // Each is one Firestore listener, opened the first time an Admin page
  // asks for the data and kept for the session. A change in the database —
  // an order completing, a new listing, a price update — reaches every
  // open page by itself: nothing has to be refreshed.
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _subscriptions = {};
  Completer<void>? _firstLoad;

  // Which of the three have arrived at least once. A section that only
  // needs orders is drawn as soon as orders are in — it does not wait for
  // the product or price lists (see [ordersReady] and its siblings).
  bool _ordersReady = false;
  bool _productsReady = false;
  bool _marketPricesReady = false;

  bool get ordersReady => _ordersReady;
  bool get productsReady => _productsReady;
  bool get marketPricesReady => _marketPricesReady;

  /// Starts the live listeners if they are not running (or one has failed)
  /// — safe to call on every build()/initState(). Completes once all three
  /// collections have arrived.
  Future<void> ensureLoaded() => _listen();

  /// Kept for the Refresh buttons and the write paths that call it: the
  /// data is already live, so this only restarts a listener that failed,
  /// and completes once everything is in. [force] is accepted for
  /// compatibility and has no effect.
  Future<void> refresh({bool force = true}) => _listen();

  Future<void> _listen() {
    final firestore = FirebaseFirestore.instance;
    _open('orders', firestore.collection('orders'), (docs) {
      _allOrders = docs;
      _orders = docs
          .where(
            (d) =>
                (d.data()['status'] ?? '').toString().toLowerCase() ==
                'completed',
          )
          .toList();
      _ordersReady = true;
    });
    _open('products', firestore.collection('products'), (docs) {
      _products = docs;
      _productsReady = true;
    });
    _open(
      'market_prices',
      firestore.collection('market_prices').orderBy('name'),
      (docs) {
        _marketPrices = docs;
        _marketPricesReady = true;
      },
    );
    if (hasLoadedOnce) return Future.value();
    return (_firstLoad ??= Completer<void>()).future;
  }

  // One listener per collection. The three are independent: one being
  // slow or failing neither delays nor discards the other two, and
  // listeners are told as each one lands. The first snapshot of each is
  // timed ([AdminPerf]).
  void _open(
    String name,
    Query<Map<String, dynamic>> query,
    void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) store,
  ) {
    if (_subscriptions.containsKey(name)) return;
    _subscriptions[name] =
        AdminPerf.firstEvent(
          'dashboard data: $name (live)',
          query.snapshots(),
          describe: (s) => '${s.docs.length} docs',
        ).listen(
          (snapshot) {
            store(snapshot.docs);
            _lastError = null;
            if (_ordersReady && _productsReady && _marketPricesReady) {
              _lastFetchedAt = DateTime.now();
              _firstLoad?.complete();
              _firstLoad = null;
            }
            notifyListeners();
          },
          onError: (Object error) {
            // Keep whatever was already loaded visible rather than blanking
            // the dashboard, and drop the dead listener so the next
            // ensureLoaded() opens a fresh one.
            _lastError = error;
            _subscriptions.remove(name)?.cancel();
            _firstLoad?.complete();
            _firstLoad = null;
            notifyListeners();
          },
        );
  }

  // ---- Shared live tier ----
  // One Firestore listener per collection for the whole Admin Portal,
  // shared by every page that references these fields (they are created
  // once per app session, unlike a page's own State, which
  // admin_dashboard_screen.dart's AnimatedSwitcher tears down on every tab
  // switch).
  //
  // They go through [_shareReplayingLatest] rather than exposing
  // .snapshots() directly: a Firestore snapshots() stream is a plain
  // broadcast stream, which does NOT replay — a StreamBuilder that
  // subscribes while another one is already listening (the previous page
  // is still mounted for the AnimatedSwitcher's fade, or two pages use the
  // same stream) would never receive the current snapshot and sit on its
  // loading spinner until the collection next changed. That is what made
  // the Analytics Dashboard's Overview cards vanish after visiting another
  // page and coming back.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> usersStream =
      _shareReplayingLatest(
        "users",
        () => FirebaseFirestore.instance.collection('users').snapshots(),
      );
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  verificationDocsStream = _shareReplayingLatest(
    "verificationDocs",
    () => FirebaseFirestore.instance.collection('verificationDocs').snapshots(),
  );

  /// Every report regardless of status — for the Moderation Queue's tabs.
  /// (The Overview's Flagged Reports card no longer reads this: it uses a
  /// count query, see DashboardOverviewService.)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> allReportsStream =
      _shareReplayingLatest(
        "reports",
        () => FirebaseFirestore.instance.collection('reports').snapshots(),
      );

  /// Wraps [source] so that all listeners share ONE upstream subscription
  /// and every new listener is immediately handed the latest value. The
  /// upstream is opened by the first listener and closed (and the cached
  /// value dropped) when the last one leaves, so nothing stale is ever
  /// replayed and nothing stays open while no page is showing it.
  static Stream<T> _shareReplayingLatest<T>(
    String name,
    Stream<T> Function() source,
  ) {
    final listeners = <MultiStreamController<T>>{};
    StreamSubscription<T>? upstream;
    T? latest;
    var hasLatest = false;

    void closeUpstream() {
      upstream?.cancel();
      upstream = null;
      latest = null;
      hasLatest = false;
    }

    return Stream<T>.multi((controller) {
      listeners.add(controller);
      // More than one listener per open page here means something is
      // subscribing twice; a new Firestore listener is only ever opened
      // on the "opening Firestore listener" line.
      debugPrint(
        "[AdminData] $name stream: listener added → ${listeners.length} listening"
        "${upstream == null ? " (opening Firestore listener)" : " (sharing the open one)"}",
      );
      if (hasLatest) controller.add(latest as T);
      upstream ??=
          AdminPerf.firstEvent<T>(
            '$name stream',
            source(),
            describe: (value) =>
                value is QuerySnapshot ? '${value.docs.length} docs' : '',
          ).listen(
            (value) {
              latest = value;
              hasLatest = true;
              for (final listener in listeners.toList()) {
                listener.add(value);
              }
            },
            onError: (Object error, StackTrace stack) {
              for (final listener in listeners.toList()) {
                listener.addError(error, stack);
              }
              // A Firestore listener is finished once it errors — drop it so
              // the next subscriber opens a fresh one instead of waiting on a
              // dead stream.
              closeUpstream();
            },
          );
      controller.onCancel = () {
        listeners.remove(controller);
        debugPrint(
          "[AdminData] $name stream: listener removed → ${listeners.length} listening",
        );
        if (listeners.isEmpty) closeUpstream();
      };
    }, isBroadcast: true);
  }
}
