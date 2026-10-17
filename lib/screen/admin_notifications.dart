import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/admin_session_service.dart';
import '../services/audit_log_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/rsba_number.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, AdminThemeScope;
import 'admin_filter_controls.dart';

// The Admin Portal's notifications: a feed of what has happened on the
// marketplace (orders, registrations, approvals, reports, announcements),
// read from the records the portal already loads — nothing is stored
// separately for it — plus the announcements the Admin sends to users.

/// The page a notification (or a header search result) opens when
/// clicked.
enum AdminNotificationTarget {
  heatmap,
  verification,
  farmers,
  moderation,
  auditLog,
}

/// Set to ask the portal to open a page; the shell clears it once done.
final ValueNotifier<AdminNotificationTarget?> adminOpenPageRequest =
    ValueNotifier<AdminNotificationTarget?>(null);

/// One thing that happened, as the bell lists it.
class AdminNotificationItem {
  final IconData icon;
  final String title;
  final String detail;
  final DateTime at;
  final AdminNotificationTarget? target;

  const AdminNotificationItem({
    required this.icon,
    required this.title,
    required this.detail,
    required this.at,
    this.target,
  });
}

/// A Firestore document as the feed reads it: its id and fields.
typedef AdminRecord = ({String id, Map<String, dynamic> data});

DateTime? _time(dynamic value) => value is Timestamp ? value.toDate() : null;

String _text(dynamic value, String fallback) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

/// Everything that happened in the last [days] days, newest first. Pure,
/// so it can be tested without Firestore.
///
/// An order's Confirmed and Shipped steps are read from its current status
/// and last update, the only record of them an order keeps; once it moves
/// on, the feed shows the later step instead.
List<AdminNotificationItem> buildAdminNotifications({
  required Iterable<AdminRecord> orders,
  required Iterable<AdminRecord> users,
  required Iterable<AdminRecord> reports,
  required Iterable<AdminRecord> announcements,
  // This Admin's own sign-ins to the portal (adminSessions history).
  Iterable<AdminRecord> signIns = const [],
  required DateTime now,
  int days = 30,
  int limit = 60,
}) {
  final since = now.subtract(Duration(days: days));
  final items = <AdminNotificationItem>[];
  void add(
    DateTime? at,
    IconData icon,
    String title,
    String detail, [
    AdminNotificationTarget? target,
  ]) {
    if (at == null || at.isBefore(since) || at.isAfter(now)) return;
    items.add(
      AdminNotificationItem(
        icon: icon,
        title: title,
        detail: detail,
        at: at,
        target: target,
      ),
    );
  }

  for (final order in orders) {
    final data = order.data;
    final buyer = _text(data['buyerName'], 'A buyer');
    final seller = _text(data['sellerName'], 'a farmer');
    final product = _text(data['productName'], 'a product');
    final status = _text(data['status'], 'pending').toLowerCase();
    // Orders have no page of their own in the portal: shown, not opened.
    const AdminNotificationTarget? target = null;
    add(
      _time(data['createdAt']),
      Icons.shopping_bag_outlined,
      'New order',
      '$buyer ordered $product from $seller',
      target,
    );
    add(
      _time(data['completedAt']),
      Icons.task_alt_rounded,
      'Order completed',
      '$product · $buyer and $seller',
      target,
    );
    add(
      _time(data['cancelledAt']),
      Icons.cancel_outlined,
      'Order cancelled',
      '$product · $buyer and $seller',
      target,
    );
    final step = switch (status) {
      'confirmed' => (Icons.thumb_up_alt_outlined, 'Order confirmed'),
      'shipped' => (Icons.local_shipping_outlined, 'Order shipped'),
      'rejected' => (Icons.block_outlined, 'Order rejected'),
      _ => null,
    };
    if (step != null) {
      add(
        _time(data['updatedAt']),
        step.$1,
        step.$2,
        '$product · $buyer and $seller',
        target,
      );
    }
  }

  for (final user in users) {
    final data = user.data;
    final role = _text(data['role'], '').toLowerCase();
    if (role != 'farmer' && role != 'buyer') continue;
    final name = _text(data['fullName'] ?? data['name'], 'Unnamed account');
    if (role == 'buyer') {
      add(
        _time(data['createdAt']),
        Icons.person_add_alt_1_outlined,
        'New buyer account',
        name,
      );
      continue;
    }
    add(
      _time(data['createdAt']),
      Icons.assignment_ind_outlined,
      'New farmer application',
      '$name · RSBA No.: ${farmerIdOf(data) ?? kNoFarmerId}',
      AdminNotificationTarget.verification,
    );
    final approval = _text(data['approvalStatus'], '').toLowerCase();
    if (approval == 'approved' || approval == 'rejected') {
      add(
        _time(data['reviewedAt']),
        approval == 'approved'
            ? Icons.verified_outlined
            : Icons.person_off_outlined,
        approval == 'approved'
            ? 'Farmer approved'
            : 'Farmer application rejected',
        name,
        AdminNotificationTarget.verification,
      );
    }
  }

  for (final report in reports) {
    final data = report.data;
    add(
      _time(data['createdAt']),
      Icons.flag_outlined,
      'New report',
      '${_text(data['issueType'] ?? data['reason'], 'General report')} · '
          'reported by ${_text(data['reporterName'], 'a user')}',
      AdminNotificationTarget.moderation,
    );
  }

  // Security: each sign-in to this Admin account, as its email alert says.
  for (final signIn in signIns) {
    final data = signIn.data;
    // A session picked up again is not a sign-in.
    if (data['announced'] == false) continue;
    final at = _time(data['startedAt']);
    final device = _text(data['deviceName'], 'an unrecognized device');
    add(
      at,
      Icons.shield_outlined,
      'New Admin login detected',
      data['newDevice'] == true
          ? 'Your account was logged in from a new device · $device'
          : 'Your account was logged in · $device',
      AdminNotificationTarget.auditLog,
    );
  }

  for (final announcement in announcements) {
    final data = announcement.data;
    final maintenance = data['kind'] == 'maintenance';
    add(
      _time(data['createdAt']),
      maintenance ? Icons.build_circle_outlined : Icons.campaign_outlined,
      maintenance ? 'Maintenance notice sent' : 'Announcement sent',
      _text(data['title'], 'Untitled'),
    );
  }

  items.sort((a, b) => b.at.compareTo(a.at));
  return items.length > limit ? items.sublist(0, limit) : items;
}

/// "5m ago", "3h ago", "Oct 8".
String adminNotificationTime(DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'Just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 7) return '${gap.inDays}d ago';
  return DateFormat('MMM d').format(at);
}

/// The button beside the bell that opens the announcement form.
class AdminAnnounceButton extends StatelessWidget {
  const AdminAnnounceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Tooltip(
      message: 'Send an announcement',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showAdminAnnouncementDialog(context),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surfaceAlt,
          ),
          child: Icon(
            Icons.campaign_outlined,
            color: c.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// The bell in the portal's header: unread count and the feed.
class AdminNotificationBell extends StatefulWidget {
  const AdminNotificationBell({super.key});

  @override
  State<AdminNotificationBell> createState() => _AdminNotificationBellState();
}

class _AdminNotificationBellState extends State<AdminNotificationBell> {
  // Created once — not on every rebuild of the header.
  final Stream<QuerySnapshot<Map<String, dynamic>>> _announcements =
      FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots();

  // This Admin's recent sign-ins; empty while signed out.
  final Stream<QuerySnapshot<Map<String, dynamic>>>? _signIns = () {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : AdminSessionService.recentSessions(uid);
  }();

  // When this Admin last opened the bell, kept on this browser. Anything
  // newer is unread.
  DateTime _seen = DateTime.fromMillisecondsSinceEpoch(0);

  String get _seenKey =>
      'admin_notifications_seen_${FirebaseAuth.instance.currentUser?.uid ?? ''}';

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_seenKey);
      if (saved == null || !mounted) return;
      setState(() => _seen = DateTime.fromMillisecondsSinceEpoch(saved));
    } catch (_) {
      // Without it everything simply counts as unread until opened.
    }
  }

  Future<void> _markSeen() async {
    final now = DateTime.now();
    setState(() => _seen = now);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seenKey, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static List<AdminRecord> _records(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
  ) => [
    for (final doc
        in docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
      (id: doc.id, data: doc.data()),
  ];

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final data = DashboardDataService.instance;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) => StreamBuilder(
        stream: data.usersStream,
        builder: (context, users) => StreamBuilder(
          stream: data.allReportsStream,
          builder: (context, reports) => StreamBuilder(
            stream: _announcements,
            builder: (context, announcements) => StreamBuilder(
              stream: _signIns,
              builder: (context, signIns) {
                final items = buildAdminNotifications(
                  orders: _records(data.allOrders),
                  users: _records(users.data?.docs),
                  reports: _records(reports.data?.docs),
                  announcements: _records(announcements.data?.docs),
                  signIns: _records(signIns.data?.docs),
                  now: DateTime.now(),
                );
                final unread = items.where((i) => i.at.isAfter(_seen)).length;
                return _bell(c, items, unread);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _bell(AdminPalette c, List<AdminNotificationItem> items, int unread) {
    // What was unread when the bell was opened, so those rows stay marked
    // while the panel is up.
    final seenAtOpen = _seen;
    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      offset: const Offset(0, 44),
      onOpened: _markSeen,
      itemBuilder: (menuContext) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Divider(height: 1, color: c.border),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 30,
                      horizontal: 24,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 30,
                          color: c.textMuted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No notifications yet',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Orders, farmer applications, approvals, reports '
                          'and announcements from the last 30 days appear '
                          'here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: c.border),
                      itemBuilder: (_, index) => _row(
                        c,
                        menuContext,
                        items[index],
                        isNew: items[index].at.isAfter(seenAtOpen),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.surfaceAlt),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.notifications_outlined,
              color: c.textSecondary,
              size: 22,
            ),
            if (unread > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: c.red,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.surfaceAlt, width: 1.5),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    AdminPalette c,
    BuildContext menuContext,
    AdminNotificationItem item, {
    required bool isNew,
  }) {
    return InkWell(
      onTap: item.target == null
          ? null
          : () {
              Navigator.of(menuContext).pop();
              adminOpenPageRequest.value = item.target;
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: c.greenBg,
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, size: 16, color: c.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: isNew ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  adminNotificationTime(item.at, DateTime.now()),
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
                if (isNew) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ANNOUNCEMENTS — a message from the Admin to farmers (or to everyone,
// for a maintenance notice). Saved to `announcements`; the sendAnnouncement
// Cloud Function delivers it to each recipient's Notifications and phone.
// ============================================================

const int kAnnouncementTitleMax = 80;
const int kAnnouncementBodyMax = 600;

/// The message a maintenance notice carries, built from its schedule so
/// every notice reads the same way.
String maintenanceNoticeBody(DateTime start, DateTime end, String note) {
  final day = DateFormat('MMM d, y');
  final time = DateFormat('h:mm a');
  final sameDay = DateUtils.isSameDay(start, end);
  final window = sameDay
      ? '${day.format(start)}, ${time.format(start)} to ${time.format(end)}'
      : '${day.format(start)}, ${time.format(start)} to '
            '${day.format(end)}, ${time.format(end)}';
  final extra = note.trim();
  return 'AgriTrade+ will be under maintenance on $window. The app may be '
      'unavailable or slow during this time.'
      '${extra.isEmpty ? '' : ' $extra'}';
}

/// The header's megaphone: an announcement to farmers, or to farmers and
/// buyers.
Future<void> showAdminAnnouncementDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AnnouncementDialog(),
  );
}

/// Admin menu → System Maintenance: a scheduled maintenance notice to
/// everyone. Kept apart from ordinary announcements.
Future<void> showAdminMaintenanceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AnnouncementDialog(maintenance: true),
  );
}

class _AnnouncementDialog extends StatefulWidget {
  /// A maintenance notice instead of an announcement.
  final bool maintenance;
  const _AnnouncementDialog({this.maintenance = false});

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  bool get _maintenance => widget.maintenance;
  bool _everyone = false;
  DateTime? _start;
  DateTime? _end;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _start : _end) ?? _start ?? now;
    final day = await showAdminDatePicker(
      context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 365)),
      title: start ? 'Starts' : 'Ends',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  String? _problem() {
    if (_maintenance) {
      if (_start == null || _end == null) {
        return 'Choose when the maintenance starts and ends.';
      }
      if (!_end!.isAfter(_start!)) {
        return 'The end must be after the start.';
      }
      if (_end!.isBefore(DateTime.now())) {
        return 'That maintenance window has already passed.';
      }
      return null;
    }
    if (_title.text.trim().isEmpty) return 'Enter a title.';
    if (_message.text.trim().isEmpty) return 'Enter the message.';
    return null;
  }

  Future<void> _send() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final title = _maintenance
        ? 'Scheduled System Maintenance'
        : _title.text.trim();
    final body = _maintenance
        ? maintenanceNoticeBody(_start!, _end!, _message.text)
        : _message.text.trim();
    if (body.length > kAnnouncementBodyMax) {
      setState(() => _error = 'The message is too long.');
      return;
    }
    // A maintenance notice concerns everyone who uses the app.
    final audience = _maintenance || _everyone ? 'all' : 'farmers';
    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await FirebaseFirestore.instance.collection('announcements').add({
        'title': title,
        'body': body,
        'kind': _maintenance ? 'maintenance' : 'announcement',
        'audience': audience,
        if (_maintenance) 'startsAt': Timestamp.fromDate(_start!),
        if (_maintenance) 'endsAt': Timestamp.fromDate(_end!),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      AuditLogService.log(
        AuditAction.sendAnnouncement,
        '${_maintenance ? 'Maintenance notice' : 'Announcement'} to '
        '${audience == 'all' ? 'farmers and buyers' : 'farmers'}: $title',
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            audience == 'all'
                ? 'Sent to farmers and buyers.'
                : 'Sent to farmers.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send it. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.62);
    final when = DateFormat('MMM d, y · h:mm a');
    // The same green as the dialog's main button.
    final buttonStyle = Theme.of(context).filledButtonTheme.style;
    final action =
        buttonStyle?.backgroundColor?.resolve(const {}) ?? scheme.primary;
    final onAction =
        buttonStyle?.foregroundColor?.resolve(const {}) ?? scheme.surface;

    Widget choice(String label, bool selected, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _sending ? null : onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? action : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? onAction : muted,
            ),
          ),
        ),
      ),
    );
    Widget toggle(List<Widget> choices) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(children: choices),
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
    );
    Widget schedule(String hint, DateTime? value, bool start) => Expanded(
      child: OutlinedButton.icon(
        onPressed: _sending ? null : () => _pick(start: start),
        icon: const Icon(Icons.event_outlined, size: 16),
        label: Text(
          value == null ? hint : when.format(value),
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          textStyle: const TextStyle(fontSize: 12.5),
        ),
      ),
    );

    return AlertDialog(
      title: Text(_maintenance ? 'System maintenance' : 'New announcement'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_maintenance) ...[
                label('Maintenance schedule'),
                Row(
                  children: [
                    schedule('Starts', _start, true),
                    const SizedBox(width: 10),
                    schedule('Ends', _end, false),
                  ],
                ),
                label('Extra note (optional)'),
                AdminField(
                  controller: _message,
                  enabled: !_sending,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: adminMultilineDecoration(
                    context,
                    hintText: 'Anything users should know or do beforehand',
                  ),
                ),
                Text(
                  'Sent to farmers and buyers.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ] else ...[
                label('Send to'),
                toggle([
                  choice(
                    'Farmers',
                    !_everyone,
                    () => setState(() => _everyone = false),
                  ),
                  choice(
                    'Farmers and buyers',
                    _everyone,
                    () => setState(() => _everyone = true),
                  ),
                ]),
                label('Title'),
                AdminField(
                  controller: _title,
                  enabled: !_sending,
                  maxLength: kAnnouncementTitleMax,
                  decoration: const InputDecoration(
                    hintText: 'What the announcement is about',
                  ),
                ),
                label('Message'),
                AdminField(
                  controller: _message,
                  enabled: !_sending,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: kAnnouncementBodyMax,
                  decoration: adminMultilineDecoration(
                    context,
                    hintText: 'The message farmers will read',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(_sending ? 'Sending…' : 'Send'),
        ),
      ],
    );
  }
}
