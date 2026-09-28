import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/push_notification_service.dart';

/// Reads notifications/{uid}/items — written by Cloud Functions
/// (functions/index.js) whenever a new message, new order, order status
/// change, or verification decision happens. Requires that function to be
/// deployed; until then this stream is simply empty.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  static const Color _bg = Colors.white;

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
    }
    // The permission explanation + request itself now happens on the user's
    // very first tap anywhere in the app (see NotificationPermissionPrompt),
    // so by the time they've navigated here it's already been decided —
    // this just keeps the FCM token fresh (a silent no-op otherwise).
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
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() => _permissionStatus = settings.authorizationStatus);
    } catch (_) {}
  }

  // Marking a notification read is itself a write, so — same as the rest of
  // AgriTrade+'s online-only actions — it must not appear to succeed while
  // actually offline (it would otherwise silently queue in Firestore's
  // local cache instead of being confirmed).
  Future<void> _markRead(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (doc.data()['read'] == true) return;
    if (!await ConnectivityService.instance.checkNow()) return;
    try {
      await doc.reference.update({'read': true});
    } catch (_) {
      // Non-fatal — the notification just stays visually unread; the next
      // successful read (or "Mark all as read") will catch it up.
    }
  }

  Future<void> _markAllRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final unread = docs.where((d) => d.data()['read'] != true).toList();
    if (unread.isEmpty) return;

    if (!await ConnectivityService.instance.checkNow()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kNoInternetActionMessage)),
      );
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
        const SnackBar(content: Text('Could not mark all as read. Please try again.')),
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

  IconData _iconFor(String type) {
    switch (type) {
      case 'chat_message':
        return Icons.mail_outline;
      case 'new_order':
        return Icons.shopping_bag_outlined;
      case 'order_status':
        return Icons.local_shipping_outlined;
      case 'verification_status':
        return Icons.verified_user_outlined;
      case 'moderation_warning':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final itemsRef = _itemsRef;
    if (itemsRef == null) {
      return const Scaffold(body: Center(child: Text('Please log in to see notifications.')));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: itemsRef.orderBy('createdAt', descending: true).limit(50).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final hasUnread = docs.any((d) => d.data()['read'] != true);

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            title: const Text('Notifications'),
            backgroundColor: Colors.white,
            foregroundColor: _dark,
            elevation: 1,
            actions: [
              if (hasUnread)
                TextButton(
                  onPressed: () => _markAllRead(docs),
                  child: const Text('Mark all read', style: TextStyle(color: _dark)),
                ),
            ],
          ),
          body: Column(
            children: [
              _permissionBanner(),
              Expanded(
                child: Builder(builder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _dark));
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading notifications. Please try again.'));
                  }

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.done_all, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('No notifications yet',
                              style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text('New messages, orders, and updates will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) => _notificationTile(docs[i]),
                  );
                }),
              ),
            ],
          ),
        );
      },
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
          Icon(Icons.notifications_off_outlined, color: Colors.red.shade700, size: 20),
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
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, height: 1.4),
                ),
                if (canPromptAgain) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () async {
                        await PushNotificationService().setupFCM();
                        _checkPermission();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade900,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Enable Notifications', style: TextStyle(fontSize: 12.5)),
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

  Widget _notificationTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = data['title']?.toString() ?? 'Notification';
    final body = data['body']?.toString() ?? '';
    final type = (data['type'] ?? '').toString();
    final isRead = data['read'] == true;
    final createdAt = data['createdAt'] as Timestamp?;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: isRead ? Colors.grey.shade200 : _accent, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openNotification(doc),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _accent,
                  child: Icon(_iconFor(type), color: _dark, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                  color: Colors.black87,
                                )),
                          ),
                          if (createdAt != null)
                            Text(_formatTime(createdAt.toDate()),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isRead ? Colors.grey[400] : Colors.red,
                                    fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ],
                    ],
                  ),
                ),
                if (!isRead) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
