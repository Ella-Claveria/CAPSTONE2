import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// The filters above the notification list. Buyers and farmers get the
/// same ones, plus Reports for farmers (listing/account moderation notices,
/// which only farmers receive as a category of their own).
enum NotificationFilter { all, messages, orders, updates, reports }

extension NotificationFilterLabel on NotificationFilter {
  String get label => switch (this) {
    NotificationFilter.all => 'All',
    NotificationFilter.messages => 'Messages',
    NotificationFilter.orders => 'Orders',
    NotificationFilter.updates => 'Updates',
    NotificationFilter.reports => 'Reports',
  };
}

List<NotificationFilter> notificationFiltersFor({required bool isFarmer}) => [
  NotificationFilter.all,
  NotificationFilter.messages,
  NotificationFilter.orders,
  NotificationFilter.updates,
  if (isFarmer) NotificationFilter.reports,
];

/// Which filter a notification `type` (as written by Cloud Functions —
/// see functions/index.js) belongs under. Anything that isn't a message or
/// an order is an update; for a farmer, moderation notices get their own
/// Reports filter instead.
NotificationFilter notificationCategory(String type, {required bool isFarmer}) {
  switch (type) {
    case 'chat_message':
      return NotificationFilter.messages;
    case 'new_order':
    case 'order_status':
      return NotificationFilter.orders;
    case 'moderation_warning':
      return isFarmer ? NotificationFilter.reports : NotificationFilter.updates;
    default:
      return NotificationFilter.updates;
  }
}

/// Whether tapping a notification of this type opens something (see
/// NotificationNavigationService) — only those get a chevron.
bool notificationOpensScreen(String type) => const {
  'chat_message',
  'new_order',
  'order_status',
  'verification_status',
  'moderation_warning',
}.contains(type);

IconData notificationIcon(String type) {
  switch (type) {
    case 'chat_message':
      return Icons.chat_bubble_outline_rounded;
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

/// The date heading a notification is listed under: Today, Yesterday, or
/// the date itself for anything older.
String notificationGroupLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return DateFormat(
    date.year == today.year ? 'MMMM d' : 'MMMM d, y',
  ).format(date);
}

/// One notification: type icon, title, message, time, an unread dot, and a
/// chevron when tapping it opens something. Unread cards sit on a very
/// light green; read ones on white. All text is dark enough to read on
/// either — nothing important is drawn in light grey.
class NotificationCard extends StatelessWidget {
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final VoidCallback? onTap;

  const NotificationCard({
    super.key,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.onTap,
  });

  static const Color _dark = AppTheme.dark;
  static const Color _unreadBackground = AppTheme.tint;
  static const Color _unreadDot = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final warning = type == 'moderation_warning';

    // A flat, full-width row (the list puts a divider between rows); an
    // unread one is tinted green.
    return Material(
      color: isRead ? Colors.white : _unreadBackground,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: warning
                    ? const Color(0xFFFFF3E0)
                    : const Color(0xFFDCEDC8),
                child: Icon(
                  notificationIcon(type),
                  size: 19,
                  color: warning ? const Color(0xFFE65100) : _dark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.25,
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              color: const Color(0xFF1B1B1B),
                            ),
                          ),
                        ),
                        if (!isRead) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: _unreadDot,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Color(0xFF424242),
                        ),
                      ),
                    ],
                    if (createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('h:mm a').format(createdAt!),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF616161),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (notificationOpensScreen(type))
                const Padding(
                  padding: EdgeInsets.only(left: 2, top: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFF757575),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
