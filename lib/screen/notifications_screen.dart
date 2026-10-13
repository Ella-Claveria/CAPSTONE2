import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/notification_permission_prompt.dart';
import '../services/push_notification_service.dart';
import '../widgets/permission_rationale_dialog.dart';
import '../widgets/notification_card.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_empty_state.dart';

/// Reads notifications/{uid}/items — written by Cloud Functions
/// (functions/index.js) whenever a new message, new order, order status
/// change, verification decision or moderation notice happens. One screen
/// for both roles: buyers and farmers see the same layout (filters, date
/// groups, NotificationCard), just their own notifications. Requires that function to be
/// deployed; until then this stream is simply empty.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _bg = Color(0xFFFAFBFA);
  static const Color _text = Color(0xFF1B1B1B);

  // Created once, not in build(), so switching filter doesn't resubscribe.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _items;
  NotificationFilter _filter = NotificationFilter.all;
  // Decides only whether the Reports filter is offered; buyer until known.
  bool _isFarmer = false;

  CollectionReference<Map<String, dynamic>>? _itemsRef;
  AuthorizationStatus? _permissionStatus;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _itemsRef = FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .collection('items');
      _items = _itemsRef!
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();
      FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
        if (mounted && doc.data()?['role'] == 'farmer') {
          setState(() => _isFarmer = true);
        }
      }, onError: (_) {});
    }
    // Refreshes the token only when OS permission is already granted. This
    // call never opens a permission prompt.
    PushNotificationService().setupFCM().catchError((_) {});
    _checkPermission();
  }

  // Surfaces WHY push notifications might not be arriving — a denied OS
  // permission is otherwise invisible: the app never re-prompts for it,
  // and every failure downstream of it (no token saved, so
  // notifyUser skips the push) is silent by design so it never blocks
  // anything else. This is the one place that actually tells the user.
  Future<void> _checkPermission() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (!mounted) return;
      setState(() => _permissionStatus = settings.authorizationStatus);
    } catch (_) {}
  }

  // Marking a notification read is itself a write, so — same as the rest of
  // AgriTrade+'s online-only actions — it must not appear to succeed while
  // actually offline (it would otherwise silently queue in Firestore's
  // local cache instead of being confirmed).
  Future<void> _markRead(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (doc.data()['read'] == true) return;
    if (!await ConnectivityService.instance.checkNow()) return;
    try {
      await doc.reference.update({'read': true});
    } catch (_) {
      // Non-fatal — the notification just stays visually unread; the next
      // successful read (or "Mark all as read") will catch it up.
    }
  }

  Future<void> _markAllRead(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final unread = docs.where((d) => d.data()['read'] != true).toList();
    if (unread.isEmpty) return;

    if (!await ConnectivityService.instance.checkNow()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      return;
    }

    // Each item lives under notifications/{currentUid}/items, so this batch
    // can only ever touch the signed-in user's own notifications.
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread) {
      batch.update(doc.reference, {'read': true});
    }
    try {
      await batch.commit();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not mark all as read. Please try again.'),
        ),
      );
    }
  }

  void _openNotification(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    _markRead(doc);
    final data = doc.data();
    final type = (data['type'] ?? '').toString();
    final payload = Map<String, dynamic>.from(data['data'] ?? {});
    NotificationNavigationService.open(type: type, data: payload);
  }

  @override
  Widget build(BuildContext context) {
    final itemsRef = _itemsRef;
    if (itemsRef == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to see notifications.')),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _items,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final hasUnread = docs.any((d) => d.data()['read'] != true);

        return Scaffold(
          backgroundColor: _bg,
          appBar: AgriAppBar(
            title: 'Notifications',
            actions: [
              if (hasUnread)
                TextButton(
                  onPressed: () => _markAllRead(docs),
                  style: TextButton.styleFrom(foregroundColor: _dark),
                  child: const Text(
                    'Mark All as Read',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              _filterRow(),
              _permissionBanner(),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _dark),
                      );
                    }
                    if (snapshot.hasError) {
                      return RetryMessage(
                        message:
                            'Could not load notifications. Check your connection and try again.',
                        onRetry: () => setState(() {}),
                      );
                    }

                    final shown = _filter == NotificationFilter.all
                        ? docs
                        : docs
                              .where(
                                (d) =>
                                    notificationCategory(
                                      (d.data()['type'] ?? '').toString(),
                                      isFarmer: _isFarmer,
                                    ) ==
                                    _filter,
                              )
                              .toList();

                    if (shown.isEmpty) return _emptyState(docs.isEmpty);
                    return _groupedList(shown);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- All / Messages / Orders / Updates (+ Reports for farmers) ----
  Widget _filterRow() {
    final filters = notificationFiltersFor(isFarmer: _isFarmer);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = filter == _filter;
          return Center(
            child: Material(
              color: selected ? _dark : Colors.white,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected ? _dark : _dark.withValues(alpha: 0.25),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _filter = filter),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _dark,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Newest first, under Today / Yesterday / the date.
  Widget _groupedList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final rows = <Widget>[];
    String? currentGroup;
    for (final doc in docs) {
      final createdAt = (doc.data()['createdAt'] as Timestamp?)?.toDate();
      // Not stamped by the server yet = just now.
      final group = notificationGroupLabel(createdAt ?? DateTime.now());
      if (group != currentGroup) {
        currentGroup = group;
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, rows.isEmpty ? 4 : 14, 4, 8),
            child: Text(
              group,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
          ),
        );
      } else {
        rows.add(const SizedBox(height: 8));
      }
      final data = doc.data();
      rows.add(
        NotificationCard(
          type: (data['type'] ?? '').toString(),
          title: data['title']?.toString() ?? 'Notification',
          body: data['body']?.toString() ?? '',
          createdAt: createdAt,
          isRead: data['read'] == true,
          onTap: () => _openNotification(doc),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: rows,
    );
  }

  Widget _emptyState(bool noNotificationsAtAll) {
    return Center(
      child: AgriEmptyState(
        icon: Icons.notifications_none_rounded,
        title: noNotificationsAtAll
            ? 'No notifications yet'
            : 'No ${_filter.label.toLowerCase()} notifications',
        subtitle: noNotificationsAtAll
            ? 'Messages, orders, and important updates will appear here.'
            : 'Notifications of this kind will appear here.',
        padding: const EdgeInsets.all(32),
      ),
    );
  }

  Widget _permissionBanner() {
    final status = _permissionStatus;
    if (status == null || status == AuthorizationStatus.authorized) {
      return const SizedBox.shrink();
    }

    // notDetermined: the OS has never actually asked yet (rare — usually
    // resolved before landing here), so a fresh request still shows the
    // real permission dialog. denied: Android never re-prompts once
    // denied, so the only path back is the phone's own Settings.
    final canPromptAgain = status == AuthorizationStatus.notDetermined;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            color: Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canPromptAgain
                      ? "Push notifications aren't turned on yet, so you won't be alerted "
                            "about new messages or orders while the app is closed."
                      : "Push notifications are off for AgriTrade+, so you won't be alerted "
                            "about new messages or orders while the app is closed. To turn them "
                            "on: phone Settings → Apps → AgriTrade+ → Notifications.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.red.shade900,
                    height: 1.4,
                  ),
                ),
                if (canPromptAgain) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () async {
                        final proceed = await showPermissionRationale(
                          context,
                          icon: Icons.notifications_active_outlined,
                          title: kNotificationRationaleTitle,
                          message: kNotificationRationaleMessage,
                          denyLabel: 'Not Now',
                          allowLabel: 'Allow Notifications',
                        );
                        if (proceed) {
                          await PushNotificationService().setupFCM(
                            requestPermission: true,
                          );
                        }
                        _checkPermission();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade900,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text(
                        'Enable Notifications',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
