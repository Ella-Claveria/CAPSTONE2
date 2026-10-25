import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/order_format.dart';
import '../services/order_seen_service.dart';
import '../services/order_service.dart';
import 'order_status_pager.dart';
import 'unread_messages_dot.dart';

/// Wraps the farmer's Orders nav-bar icon with the red dot while any order
/// has buyer activity the farmer hasn't seen yet — a new order above all.
/// Uses the same rule and the same [OrderSeenStore] as the red badges on
/// the Orders status tabs, so the dot clears once those do.
class UnseenOrdersDot extends StatefulWidget {
  final Widget child;

  const UnseenOrdersDot({super.key, required this.child});

  @override
  State<UnseenOrdersDot> createState() => _UnseenOrdersDotState();
}

class _UnseenOrdersDotState extends State<UnseenOrdersDot> {
  static const _role = OrderRole.farmer;
  static final _statuses = {
    for (final tab in [...kOrderStatusTabs, kRejectedTab]) tab.value,
  };

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final OrderSeenStore _seenStore = OrderSeenStore(
    uid: _uid ?? 'unknown',
    role: _role.name,
  );
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _orders =
      OrderService().farmerOrdersStream();

  Map<String, int>? _seen;
  bool _seenLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSeen();
    OrderSeenStore.saved.addListener(_loadSeen);
  }

  @override
  void dispose() {
    OrderSeenStore.saved.removeListener(_loadSeen);
    super.dispose();
  }

  Future<void> _loadSeen() async {
    final seen = await _seenStore.load();
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _seenLoaded = true;
    });
  }

  bool _hasUnseen(List<OrderDoc> docs) {
    if (!_seenLoaded) return false;
    final seen = _seen;
    for (final doc in docs) {
      final status = orderStatusOf(doc);
      if (!_statuses.contains(status)) continue;
      final at = OrderInfo.fromDoc(doc).unseenActivityMs(_role);
      if (at == 0) continue;
      // Orders never opened on this phone: any waiting order is new.
      if (seen == null ? status == 'pending' : at > (seen[status] ?? 0)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return widget.child;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _orders,
      builder: (context, snapshot) => NavRedDot(
        show: _hasUnseen(snapshot.data?.docs ?? const []),
        child: widget.child,
      ),
    );
  }
}
