import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_mark.dart';

/// What each card on the Farmer's Market tab shows, and whose data it is,
/// in the order the cards come down the page. The first is the farmer's
/// own; the rest cover the whole marketplace, which is why they can already
/// have figures on a brand-new account.
const List<({String title, String message})> kMarketGuideItems = [
  (
    title: 'Sales Performance',
    message:
        'Your own sales: revenue from your completed orders. It stays '
        'empty until your first order is completed.',
  ),
  (
    title: 'Current Market Average',
    message:
        'Whole marketplace: what other farmers are asking right now for '
        'each product. Use it as a guide when setting your price.',
  ),
  (
    title: 'Best-Selling Products',
    message:
        'Whole marketplace: the products buyers purchased most across '
        'AgriTrade+ this month.',
  ),
  (
    title: 'Top Buyer Locations',
    message:
        'Whole marketplace: the areas where the most completed orders came '
        'from this month.',
  ),
];

/// The Market tab's first-time hints: no popup up front, but as the farmer
/// scrolls the tab, a small hint at each card when it comes into view —
/// one at a time and in order, the next only after the one before has gone
/// (tapped away, or scrolled past). Each is shown once per account on this
/// device; the place reached is remembered, so a farmer who stops halfway
/// carries on from there next time.
///
/// Put [keys] on the four cards, in [kMarketGuideItems]' order, and call
/// [onScroll] from the tab's scroll notifications.
class MarketTabHints {
  /// The signed-in account, whose progress is remembered.
  final String? Function() currentUid;

  MarketTabHints({this.currentUid = _signedInUid});

  static String? _signedInUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  final List<GlobalKey> keys = [for (final _ in kMarketGuideItems) GlobalKey()];

  // The next card to explain; null until read from storage.
  int? _next;
  bool _loading = false;
  bool _showing = false;
  // Only once the farmer has scrolled: the tab opening is not a reason to
  // show anything.
  bool _scrolled = false;

  static String _storageKey(String uid) => 'market_tab_hints_next_$uid';

  Future<void> _load() async {
    if (_next != null || _loading) return;
    _loading = true;
    final uid = currentUid();
    var next = kMarketGuideItems.length; // nothing to show without one
    if (uid != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        next = prefs.getInt(_storageKey(uid)) ?? 0;
      } catch (_) {}
    }
    _next = next;
    _loading = false;
  }

  Future<void> _save(int next) async {
    final uid = currentUid();
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey(uid), next);
    } catch (_) {}
  }

  /// From the tab's scroll view. [userScroll]: the farmer moved it (not a
  /// layout change or a refresh).
  void onScroll(BuildContext context, {required bool userScroll}) {
    if (userScroll) _scrolled = true;
    _check(context);
  }

  Future<void> _check(BuildContext context) async {
    if (!_scrolled || _showing) return;
    await _load();
    final index = _next!;
    if (index >= keys.length || _showing || !context.mounted) return;
    final top = sectionTopFraction(keys[index]);
    if (top == null ||
        top < kSectionHintBandTop ||
        top > kSectionHintBandBottom) {
      return;
    }

    _showing = true;
    final item = kMarketGuideItems[index];
    await showSectionHint(
      context: context,
      step: CoachMarkStep(
        targetKey: keys[index],
        title: item.title,
        message: item.message,
      ),
      progress: '${index + 1}/${keys.length}',
    );
    _next = index + 1;
    _showing = false;
    await _save(index + 1);
    // The next card may already be in place.
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _check(context);
      });
    }
  }
}
