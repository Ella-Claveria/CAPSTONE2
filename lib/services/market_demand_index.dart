import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/commodity_master_list.dart';
import 'market_demand_service.dart';

/// This month's Best-Selling Products, by commodity, for the Buyer's
/// product cards (see DemandBadge) — worked out exactly as the Farmer's
/// Market tab card does ([MarketDemandService.bestSellers]), so the two
/// always agree.
///
/// One `market_sales` subscription for the whole app, started by the first
/// card that asks; a card never opens its own.
class MarketDemandIndex extends ChangeNotifier {
  MarketDemandIndex._();
  static final MarketDemandIndex instance = MarketDemandIndex._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _sales = const [];
  Map<String, BestSeller> _byCommodity = const {};
  bool _watchingRegistry = false;

  /// The Best-Selling entry for [productName]'s commodity, or null when it
  /// isn't on this month's list (or the sales have not loaded yet).
  BestSeller? forProduct(String productName) {
    _listen();
    final commodity = matchSupportedCommodity(productName) ?? productName;
    return _byCommodity[commodity.trim().toLowerCase()];
  }

  void _listen() {
    if (_sub != null) return;
    try {
      _sub = FirebaseFirestore.instance
          .collection('market_sales')
          .snapshots()
          .listen(
            (snap) {
              _sales = [for (final doc in snap.docs) doc.data()];
              _rebuild();
            },
            // Signed out (or offline before anything loaded): stop, and
            // start again the next time a card asks.
            onError: (_) {
              _sub?.cancel();
              _sub = null;
            },
          );
    } catch (_) {
      return; // Firebase not set up (e.g. in tests): no badges.
    }
    if (!_watchingRegistry) {
      // Names and categories come from the Admin-managed list.
      _watchingRegistry = true;
      CommodityRegistry.instance.addListener(_rebuild);
    }
  }

  /// Uses [sales] as the `market_sales` records, without Firestore.
  @visibleForTesting
  void debugSetSales(List<Map<String, dynamic>> sales) {
    _sales = sales;
    _rebuild();
  }

  void _rebuild() {
    final bestSellers = MarketDemandService.bestSellers(
      sales: _sales,
      month: DateTime.now(),
    );
    _byCommodity = {
      for (final item in bestSellers) item.commodity.toLowerCase(): item,
    };
    notifyListeners();
  }
}
