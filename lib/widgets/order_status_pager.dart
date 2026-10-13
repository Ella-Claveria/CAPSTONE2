import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/order_seen_service.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import 'agri_refresh_indicator.dart';
import 'retry_message.dart';
import 'agri_empty_state.dart';

// The Orders body shared by the Farmer and Buyer sides (see OrdersView):
// plain text status tabs with a green underline, a red corner badge for
// unseen activity only, one swipeable page per status, no skeleton
// placeholders, status-specific empty states, and a one-time swipe tutorial
// for new users.

typedef OrderDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// One status tab.
class OrderStatusTab {
  final String value;
  final String label;
  final IconData emptyIcon;

  const OrderStatusTab(this.value, this.label, this.emptyIcon);

  String get emptyTitle => 'No ${label.toLowerCase()} orders yet';
}

const kPendingTab = OrderStatusTab(
  'pending',
  'Pending',
  Icons.pending_actions_outlined, // clipboard with clock
);
const kConfirmedTab = OrderStatusTab(
  'confirmed',
  'Confirmed',
  Icons.assignment_turned_in_outlined, // order with check
);
const kShippedTab = OrderStatusTab(
  'shipped',
  'Shipped',
  Icons.local_shipping_outlined,
);
const kCompletedTab = OrderStatusTab(
  'completed',
  'Completed',
  Icons.task_alt_rounded,
);
const kRejectedTab = OrderStatusTab(
  'rejected',
  'Rejected',
  Icons.cancel_outlined,
);

const kOrderStatusTabs = [
  kPendingTab,
  kConfirmedTab,
  kShippedTab,
  kCompletedTab,
];

/// The order status of [doc] in lowercase ('pending' when missing).
String orderStatusOf(OrderDoc doc) =>
    switch ((doc.data()['status'] ?? 'pending').toString().toLowerCase()) {
      // A cancelled order is listed with the rejected ones: both ended
      // without a sale.
      'cancelled' => 'rejected',
      final status => status,
    };

/// Prefs key remembering that this account has seen the swipe tutorial.
String ordersSwipeTutorialKey() {
  String uid;
  try {
    uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  } catch (_) {
    uid = 'unknown';
  }
  return 'orders_swipe_tutorial_seen_$uid';
}

/// Whether the signed-in account is new enough for first-use tutorials
/// (registered within the last 30 days), so long-time users updating the
/// app aren't shown them.
bool isRecentlyRegisteredUser() {
  try {
    final created = FirebaseAuth.instance.currentUser?.metadata.creationTime;
    return created != null &&
        DateTime.now().difference(created) <= const Duration(days: 30);
  } catch (_) {
    return false;
  }
}

class OrderStatusPager extends StatefulWidget {
  /// Creates the orders stream. Called once, and again only on Retry after
  /// an error — never on rebuilds.
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function() streamFactory;
  final List<OrderStatusTab> tabs;

  /// The cards for one status page, given every order the stream returned.
  /// [isNew] tells whether an order has activity this user hasn't seen yet.
  final List<Widget> Function(
    OrderStatusTab tab,
    List<OrderDoc> all,
    bool Function(OrderDoc doc) isNew,
  )
  itemsBuilder;

  /// Optional widgets above the cards of a page (e.g. a banner).
  final List<Widget> Function(OrderStatusTab tab, List<OrderDoc> all)?
  headerBuilder;
  final Future<void> Function() onRefresh;
  final String Function(OrderStatusTab tab) emptySubtitle;
  final Widget? emptyAction;
  final String errorMessage;

  /// Prefs key for the one-time swipe tutorial; null disables it.
  final String? tutorialPrefsKey;

  /// Whether this user should get the tutorial at all (new users only).
  final bool Function() tutorialEligible;

  /// When (ms since epoch) the other party last changed this order, or 0
  /// if its current state is this user's own doing. Drives the tab badges;
  /// null turns badges off.
  final int Function(OrderDoc doc)? activityOf;

  /// Where this user's "seen up to" times are kept. Null turns badges off.
  final OrderSeenStore? seenStore;

  const OrderStatusPager({
    super.key,
    required this.streamFactory,
    required this.itemsBuilder,
    required this.onRefresh,
    required this.emptySubtitle,
    required this.errorMessage,
    this.tabs = kOrderStatusTabs,
    this.headerBuilder,
    this.emptyAction,
    this.tutorialPrefsKey,
    this.tutorialEligible = isRecentlyRegisteredUser,
    this.activityOf,
    this.seenStore,
  });

  @override
  State<OrderStatusPager> createState() => _OrderStatusPagerState();
}

class _OrderStatusPagerState extends State<OrderStatusPager>
    with SingleTickerProviderStateMixin {
  // Narrower than this per tab and the row scrolls instead of squeezing.
  static const double _minTabWidth = 86;
  // How long a page must stay open before its new activity counts as seen.
  static const Duration _seenDelay = Duration(milliseconds: 1800);

  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream = widget
      .streamFactory();
  // Last orders received: kept on screen while refreshing or if the stream
  // briefly errors, so the list never blanks out.
  List<OrderDoc>? _docs;
  QuerySnapshot<Map<String, dynamic>>? _lastSnapshot;

  late final TabController _tabs = TabController(
    length: widget.tabs.length,
    vsync: this,
  )..addListener(_onTabChanged);
  int _index = 0;

  ValueListenable<TickerModeData>? _visible;
  bool _tutorialChecked = false;
  bool _showTutorial = false;

  // Newest activity already seen, per status. Null until loaded.
  Map<String, int>? _seen;
  bool _seenLoaded = false;
  Timer? _seenTimer;

  bool get _badgesOn => widget.activityOf != null && widget.seenStore != null;
  bool get _isVisible => _visible?.value.enabled ?? false;

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The home screens keep every tab alive in an IndexedStack; hidden tabs
    // have tickers off. Used to act only once Orders is actually open.
    final visible = TickerMode.getValuesNotifier(context);
    if (!identical(visible, _visible)) {
      _visible?.removeListener(_onVisibilityChanged);
      _visible = visible..addListener(_onVisibilityChanged);
    }
  }

  @override
  void dispose() {
    _visible?.removeListener(_onVisibilityChanged);
    _seenTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _onVisibilityChanged() {
    _maybeShowTutorial();
    _scheduleSeen();
  }

  // ---- Unseen activity ----

  Future<void> _loadSeen() async {
    if (!_badgesOn) return;
    final stored = await widget.seenStore!.load();
    if (!mounted) return;
    setState(() {
      _seen = stored;
      _seenLoaded = true;
    });
    _baselineSeen();
    _scheduleSeen();
  }

  int _newestActivity(String status) {
    var newest = 0;
    for (final doc in _docs ?? const <OrderDoc>[]) {
      if (orderStatusOf(doc) != status) continue;
      final at = widget.activityOf!(doc);
      if (at > newest) newest = at;
    }
    return newest;
  }

  // First time this account opens Orders on this device: treat what's
  // already there as seen, so old orders don't all show up as new.
  void _baselineSeen() {
    if (!_badgesOn || !_seenLoaded || _seen != null || _docs == null) return;
    final seen = {
      for (final t in widget.tabs) t.value: _newestActivity(t.value),
    };
    setState(() => _seen = seen);
    widget.seenStore!.save(seen);
  }

  bool _isNew(OrderDoc doc) {
    final seen = _seen;
    if (!_badgesOn || seen == null) return false;
    return widget.activityOf!(doc) > (seen[orderStatusOf(doc)] ?? 0);
  }

  // Once the open page has been on screen for a moment, its activity is
  // seen. One timer, one write — never on rebuilds.
  void _scheduleSeen() {
    _seenTimer?.cancel();
    _seenTimer = null;
    if (!_badgesOn || _seen == null || _docs == null || !_isVisible) return;
    final status = widget.tabs[_index].value;
    if (_newestActivity(status) <= (_seen![status] ?? 0)) return;
    _seenTimer = Timer(_seenDelay, () {
      _seenTimer = null;
      if (!mounted || !_isVisible || widget.tabs[_index].value != status) {
        return;
      }
      final newest = _newestActivity(status);
      final seen = _seen;
      if (seen == null || newest <= (seen[status] ?? 0)) return;
      setState(() => _seen = {...seen, status: newest});
      widget.seenStore!.save(_seen!);
    });
  }

  // ---- Tutorial ----

  Future<void> _maybeShowTutorial() async {
    final key = widget.tutorialPrefsKey;
    if (_tutorialChecked || key == null || _docs == null) return;
    if (!_isVisible) return;
    _tutorialChecked = true;
    if (!widget.tutorialEligible()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return;
    } catch (_) {
      return; // Can't remember "seen" — safer to skip than nag every time.
    }
    if (mounted) setState(() => _showTutorial = true);
  }

  Future<void> _dismissTutorial() async {
    if (!_showTutorial) return;
    setState(() => _showTutorial = false);
    final key = widget.tutorialPrefsKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {}
  }

  void _retry() {
    setState(() => _stream = widget.streamFactory());
  }

  // Fires for both taps and swipes, so tab and page can't drift apart.
  void _onTabChanged() {
    if (_tabs.index == _index) return;
    setState(() => _index = _tabs.index);
    // Changing status means they've got it.
    if (_showTutorial) _dismissTutorial();
    _scheduleSeen();
  }

  void _onData(List<OrderDoc> docs) {
    final firstLoad = _docs == null;
    _docs = docs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (firstLoad) {
        _maybeShowTutorial();
        _baselineSeen();
      }
      // New activity on the open page restarts the "seen" wait.
      if (_seenTimer == null) _scheduleSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasData && !identical(snapshot.data, _lastSnapshot)) {
          _lastSnapshot = snapshot.data;
          _onData(snapshot.data!.docs);
        }
        final docs = _docs;
        final unseen = <String, int>{};
        for (final doc in docs ?? const <OrderDoc>[]) {
          if (!_isNew(doc)) continue;
          final status = orderStatusOf(doc);
          unseen[status] = (unseen[status] ?? 0) + 1;
        }

        Widget body;
        if (docs != null) {
          body = Stack(
            children: [
              TabBarView(
                controller: _tabs,
                children: [
                  for (final tab in widget.tabs)
                    _KeepAlivePage(child: _page(tab, docs)),
                ],
              ),
              if (_showTutorial)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: _SwipeTutorialCard(onDismiss: _dismissTutorial),
                ),
            ],
          );
        } else if (snapshot.hasError) {
          body = RetryMessage(message: widget.errorMessage, onRetry: _retry);
        } else {
          // Very first load with nothing cached: just a thin bar.
          body = const _LoadingBar();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tabRow(unseen),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _tabRow(Map<String, int> unseen) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Evenly spread when they fit; otherwise the row scrolls.
        final scrollable =
            constraints.maxWidth < widget.tabs.length * _minTabWidth;
        return TabBar(
          controller: _tabs,
          isScrollable: scrollable,
          tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          labelPadding: EdgeInsets.symmetric(horizontal: scrollable ? 16 : 4),
          indicatorSize: TabBarIndicatorSize.label,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppTheme.dark, width: 2),
          ),
          dividerColor: Colors.grey.shade200,
          dividerHeight: 1,
          labelColor: AppTheme.dark,
          unselectedLabelColor: Colors.grey.shade700,
          labelStyle: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            for (final tab in widget.tabs)
              Tab(
                height: 42,
                child: _TabLabel(
                  label: tab.label,
                  unseen: unseen[tab.value] ?? 0,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _page(OrderStatusTab tab, List<OrderDoc> docs) {
    final header = widget.headerBuilder?.call(tab, docs) ?? const <Widget>[];
    final items = widget.itemsBuilder(tab, docs, _isNew);
    return AgriRefreshIndicator(
      color: AppTheme.dark,
      onRefresh: widget.onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          key: PageStorageKey<String>('orders-${tab.value}'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
          children: [
            ...header,
            if (items.isEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 140).clamp(
                    220.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: _EmptyState(
                    tab: tab,
                    subtitle: widget.emptySubtitle(tab),
                    action: widget.emptyAction,
                  ),
                ),
              )
            else
              ...items,
          ],
        ),
      ),
    );
  }
}

/// A status tab's text, with the unseen-activity badge on its upper-right
/// corner. No badge at all when there is nothing new.
class _TabLabel extends StatelessWidget {
  final String label;
  final int unseen;

  const _TabLabel({required this.label, required this.unseen});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: unseen > 0 ? '$label, $unseen new' : label,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Text(label, maxLines: 1, softWrap: false),
          if (unseen > 0)
            Positioned(
              top: -8,
              right: -13,
              child: IgnorePointer(
                child: Container(
                  key: ValueKey('order-tab-badge-$label'),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unseen > 99 ? '99+' : '$unseen',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final OrderStatusTab tab;
  final String subtitle;
  final Widget? action;

  const _EmptyState({required this.tab, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    // The app-wide empty state; Orders is where its look comes from.
    return AgriEmptyState(
      icon: tab.emptyIcon,
      title: tab.emptyTitle,
      subtitle: subtitle,
      action: action,
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(48, 14, 48, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          minHeight: 2.5,
          color: AppTheme.dark.withValues(alpha: 0.55),
          backgroundColor: AppTheme.dark.withValues(alpha: 0.08),
        ),
      ),
    ),
  );
}

/// Keeps each status page (scroll position, etc.) alive while swiping.
class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// One-time hint card floating over the orders (it doesn't block them).
class _SwipeTutorialCard extends StatefulWidget {
  final VoidCallback onDismiss;

  const _SwipeTutorialCard({required this.onDismiss});

  @override
  State<_SwipeTutorialCard> createState() => _SwipeTutorialCardState();
}

class _SwipeTutorialCardState extends State<_SwipeTutorialCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: AgriFrostedCard(
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _nudge,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        8 * (Curves.easeInOut.transform(_nudge.value) - 0.5),
                        0,
                      ),
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFF6E8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.swipe_rounded,
                        color: AppTheme.dark,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Swipe between order statuses',
                          style: GoogleFonts.montserrat(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.dark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Swipe left or right to quickly move between '
                          'Pending, Confirmed, Shipped, and Completed orders.',
                          style: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black54,
                    ),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.montserrat(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: widget.onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppTheme.dark,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Got it',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
