import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'dashboard_analytics_service.dart';
import 'dashboard_data_service.dart';

/// One Overview card's state: still loading, loaded with a [value], or
/// failed with an [error]. Each card has its own, so a slow or failing
/// metric never holds the other three back.
class OverviewMetric<T> {
  final T? value;
  final Object? error;

  const OverviewMetric.loading() : value = null, error = null;
  const OverviewMetric.loaded(T this.value) : error = null;
  const OverviewMetric.failed(Object this.error) : value = null;

  bool get isLoading => value == null && error == null;
  bool get hasError => error != null;
}

/// The Analytics Dashboard's four Overview cards — Total Users, Pending
/// Verifications, Flagged Reports, Total Transaction Value.
///
/// Uses Firestore aggregate queries (count / sum) so no documents are
/// downloaded at all: the server returns just the numbers. The definitions
/// are the same ones DashboardAnalyticsService applies to full document
/// lists (farmerCount / buyerCount / pendingVerifications /
/// unresolvedReports / platformTransactionTotal) — see each metric below.
///
/// All four run in parallel for a fast first paint, and are then kept
/// current live (see _startLive) — a Refresh is never needed, and a
/// widget rebuild or a page switch never re-runs a query.
class DashboardOverviewService extends ChangeNotifier {
  DashboardOverviewService._();
  static final DashboardOverviewService instance = DashboardOverviewService._();

  OverviewMetric<({int farmers, int buyers})> totalUsers =
      const OverviewMetric.loading();
  OverviewMetric<int> pendingVerifications = const OverviewMetric.loading();
  OverviewMetric<int> flaggedReports = const OverviewMetric.loading();
  OverviewMetric<num> totalTransactionValue = const OverviewMetric.loading();

  bool _startedOnce = false;
  Future<void>? _inFlight;

  /// Loads the metrics the first time it's called; a no-op afterwards.
  /// Safe to call from build().
  Future<void> ensureLoaded() {
    if (_startedOnce) return _inFlight ?? Future.value();
    return refresh();
  }

  /// Re-fetches all four (deduped against a fetch already in flight).
  Future<void> refresh() {
    _startedOnce = true;
    return _inFlight ??= _loadAll().whenComplete(() {
      _inFlight = null;
      _startLive();
    });
  }

  // ---- Live updates ----
  // The aggregate queries below give the four figures quickly on first
  // paint. From then on they are kept current by the portal's shared live
  // listeners (users, reports, orders — see DashboardDataService), run
  // through the same DashboardAnalyticsService definitions: a new
  // registration, a report being resolved or an order completing updates
  // its card by itself, with nothing to refresh.
  final List<StreamSubscription<dynamic>> _liveSubscriptions = [];
  bool _liveStarted = false;

  void _startLive() {
    if (_liveStarted) return;
    _liveStarted = true;
    final data = DashboardDataService.instance;

    void stopped(Object _) {
      // A listener that fails is finished: let the next refresh reopen it.
      for (final subscription in _liveSubscriptions) {
        subscription.cancel();
      }
      _liveSubscriptions.clear();
      data.removeListener(_onOrdersChanged);
      _liveStarted = false;
    }

    _liveSubscriptions
      ..add(
        data.usersStream.listen((snapshot) {
          totalUsers = OverviewMetric.loaded((
            farmers: DashboardAnalyticsService.farmerCount(snapshot.docs),
            buyers: DashboardAnalyticsService.buyerCount(snapshot.docs),
          ));
          pendingVerifications = OverviewMetric.loaded(
            DashboardAnalyticsService.pendingVerifications(snapshot.docs),
          );
          notifyListeners();
        }, onError: stopped),
      )
      ..add(
        data.allReportsStream.listen((snapshot) {
          flaggedReports = OverviewMetric.loaded(
            DashboardAnalyticsService.unresolvedReports(snapshot.docs),
          );
          notifyListeners();
        }, onError: stopped),
      );
    data.addListener(_onOrdersChanged);
    data.ensureLoaded();
  }

  void _onOrdersChanged() {
    final data = DashboardDataService.instance;
    if (!data.ordersReady) return;
    final total = DashboardAnalyticsService.platformTransactionTotal(
      data.orders,
    );
    if (totalTransactionValue.value == total) return;
    totalTransactionValue = OverviewMetric.loaded(total);
    notifyListeners();
  }

  static final _users = FirebaseFirestore.instance.collection('users');
  static final _reports = FirebaseFirestore.instance.collection('reports');
  static final _orders = FirebaseFirestore.instance.collection('orders');

  static Future<int> _count(Query<Map<String, dynamic>> query) async =>
      (await query.count().get()).count ?? 0;

  // An aggregate query that hasn't answered by now is treated as failed,
  // so its card moves on to the fallback instead of sitting on a skeleton.
  static const _aggregateTimeout = Duration(seconds: 10);

  Future<void> _loadAll() async {
    totalUsers = const OverviewMetric.loading();
    pendingVerifications = const OverviewMetric.loading();
    flaggedReports = const OverviewMetric.loading();
    totalTransactionValue = const OverviewMetric.loading();
    notifyListeners();

    final all = Stopwatch()..start();
    final farmers = _users.where('role', isEqualTo: 'farmer');
    // Needed by both Total Users and Pending Verifications — asked once.
    final approvedFarmers = _count(
      farmers.where('approvalStatus', isEqualTo: 'approved'),
    );
    // Its error is reported by the metrics that await it below.
    approvedFarmers.ignore();

    // Fallback data, fetched at most once per load and only if an aggregate
    // query actually failed: the plain document reads the cards used
    // before, run through the same DashboardAnalyticsService functions.
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? userDocs;
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> allUsers() =>
        userDocs ??= _users.get().then((s) => s.docs);

    await Future.wait([
      // TOTAL USERS = buyers + APPROVED farmers (pending and rejected
      // applications are not marketplace users).
      _run(
        'Total Users',
        () async {
          final counts = await Future.wait([
            approvedFarmers,
            _count(_users.where('role', isEqualTo: 'buyer')),
          ]);
          return (farmers: counts[0], buyers: counts[1]);
        },
        fallback: () async {
          final docs = await allUsers();
          return (
            farmers: DashboardAnalyticsService.farmerCount(docs),
            buyers: DashboardAnalyticsService.buyerCount(docs),
          );
        },
        store: (m) => totalUsers = m,
      ),

      // PENDING VERIFICATIONS = farmers that are neither approved nor
      // rejected. Counted by subtraction so a legacy farmer account with no
      // approvalStatus field at all still counts as pending (a query for
      // approvalStatus == 'pending' can never match a missing field).
      _run(
        'Pending Verifications',
        () async {
          final counts = await Future.wait([
            _count(farmers),
            approvedFarmers,
            _count(farmers.where('approvalStatus', isEqualTo: 'rejected')),
          ]);
          final pending = counts[0] - counts[1] - counts[2];
          return pending < 0 ? 0 : pending;
        },
        fallback: () async =>
            DashboardAnalyticsService.pendingVerifications(await allUsers()),
        store: (m) => pendingVerifications = m,
      ),

      // FLAGGED REPORTS = every report not yet resolved (Pending + Under
      // Review). Also by subtraction, so a report with no status field
      // counts as pending, like the Moderation Queue treats it.
      _run(
        'Flagged Reports',
        () async {
          final counts = await Future.wait([
            _count(_reports),
            _count(
              _reports.where('status', whereIn: ['resolved', 'dismissed']),
            ),
          ]);
          final open = counts[0] - counts[1];
          return open < 0 ? 0 : open;
        },
        fallback: () async => DashboardAnalyticsService.unresolvedReports(
          (await _reports.get()).docs,
        ),
        store: (m) => flaggedReports = m,
      ),

      // TOTAL TRANSACTION VALUE = sum of `total` over Completed orders
      // only, added up by Firestore itself. The fallback reuses the orders
      // the dashboard's charts already download (no second orders query).
      _run<num>(
        'Total Transaction Value',
        () async {
          final snapshot = await _orders
              .where('status', isEqualTo: 'completed')
              .aggregate(sum('total'))
              .get();
          return snapshot.getSum('total') ?? 0;
        },
        fallback: () async {
          final data = DashboardDataService.instance;
          await data.ensureLoaded();
          if (!data.hasLoadedOnce) {
            throw data.lastError ?? StateError('orders could not be loaded');
          }
          return DashboardAnalyticsService.platformTransactionTotal(
            data.orders,
          );
        },
        store: (m) => totalTransactionValue = m,
      ),
    ]);
    debugPrint(
      '[Overview] all 4 metrics settled in ${all.elapsedMilliseconds} ms',
    );
  }

  /// Runs one metric: the aggregate query first, and if that fails or
  /// times out, [fallback]. Stores the result (or, if both failed, the
  /// error) through [store], repaints its card straight away, and logs the
  /// value, the time taken and the exact error of anything that failed.
  /// Never throws, so one failure can't cancel the others in Future.wait.
  Future<void> _run<T>(
    String name,
    Future<T> Function() load, {
    required Future<T> Function() fallback,
    required void Function(OverviewMetric<T> metric) store,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final value = await load().timeout(_aggregateTimeout);
      store(OverviewMetric.loaded(value));
      debugPrint(
        '[Overview] $name = $value '
        '(aggregate query, ${watch.elapsedMilliseconds} ms)',
      );
    } catch (aggregateError) {
      debugPrint(
        '[Overview] $name aggregate query FAILED after '
        '${watch.elapsedMilliseconds} ms: $aggregateError — '
        'falling back to reading the documents',
      );
      try {
        final value = await fallback();
        store(OverviewMetric.loaded(value));
        debugPrint(
          '[Overview] $name = $value '
          '(fallback, ${watch.elapsedMilliseconds} ms total)',
        );
      } catch (fallbackError) {
        store(OverviewMetric.failed(fallbackError));
        debugPrint(
          '[Overview] $name FAILED — no value to show. '
          'Fallback error: $fallbackError',
        );
      }
    }
    notifyListeners();
  }
}
