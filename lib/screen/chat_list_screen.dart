import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../services/conversation_prefs_service.dart';
import '../services/message_service.dart';
import '../widgets/page_header.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/online_dot.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/report_user_dialog.dart';
import 'archived_conversations_screen.dart';
import 'message_management_screens.dart';
import 'chat_navigation.dart';
import 'message_search_screen.dart';
import '../widgets/agri_empty_state.dart';

/// Which conversations a [ChatListScreen] shows.
enum ChatListMode {
  /// The Messages tab: everything not archived, with header/search/filters.
  inbox,

  /// The Archived folder (see ArchivedConversationsScreen).
  archived,

  /// Every muted conversation, archived or not (see MutedConversationsScreen).
  muted,
}

/// The "Messages" tab: a live list of the current user's conversations,
/// sorted by most recent activity — same idea as a Messenger inbox.
///
/// The same list in [ChatListMode.archived]/[ChatListMode.muted] is the
/// Archived and Muted folders: only those chats, no header, search or
/// filters. Conversations with a blocked user are hidden in every mode
/// (they're managed from the Blocked Users screen).
class ChatListScreen extends StatefulWidget {
  final ChatListMode mode;

  const ChatListScreen({super.key, this.mode = ChatListMode.inbox});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const Color _dark = AppTheme.dark;

  final MessageService _messageService = MessageService();
  String _filter = 'all';
  final ConversationPrefs _prefs = ConversationPrefs.instance;

  // Streams are created once (per user, for the row profiles), never in
  // build(): this list stays alive under an open chat, so a rebuild — e.g.
  // the keyboard opening in that chat — would otherwise re-subscribe every
  // one of them and drop back to the loading state.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _conversationsStream =
      _messageService.myConversationsStream();
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
  _profileStreams = {};
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _ownUserStream;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream(String uid) =>
      _profileStreams.putIfAbsent(
        uid,
        () => FirebaseFirestore.instance
            .collection('publicProfiles')
            .doc(uid)
            .snapshots(),
      );

  bool get _inboxMode => widget.mode == ChatListMode.inbox;

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _prefs.load(FirebaseAuth.instance.currentUser?.uid);
    if (_inboxMode) _syncOwnProfilePhoto();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onActivityResolved() {
    if (mounted) setState(() {});
  }

  int _lastMessageMs(Map<String, dynamic> data) =>
      (data['lastMessageTime'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

  // Archived, with nothing new from the other person since. A new incoming
  // message makes this false, which puts the chat back in the inbox.
  bool _isArchived(String id, Map<String, dynamic> data, String? myUid) {
    final lastSender = data['lastSenderId']?.toString() ?? '';
    return _prefs.isArchived(
      id,
      lastMessageMs: _lastMessageMs(data),
      lastFromOther: lastSender.isNotEmpty && lastSender != myUid,
    );
  }

  // The other side's Messages list reads photos from publicProfiles, which
  // mirrors users/{uid}.photoUrl. An account whose photo only exists on its
  // Firebase Auth profile (e.g. a Google photo) would never show up there,
  // so copy it across once.
  Future<void> _syncOwnProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    final authPhoto = user?.photoURL?.trim() ?? '';
    if (user == null || authPhoto.isEmpty) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await ref.get();
      if (!doc.exists) return;
      final saved = doc.data()?['photoUrl']?.toString().trim() ?? '';
      if (saved.isEmpty) await ref.update({'photoUrl': authPhoto});
    } catch (_) {
      // Best effort — the avatar just falls back to initials.
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        if (_inboxMode) ...[_header(), _searchBar(), _filterChips()],
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _conversationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _dark),
                );
              }
              if (snapshot.hasError) {
                return RetryMessage(
                  message:
                      'Could not load messages. Check your connection and try again.',
                  onRetry: () => setState(() {}),
                );
              }

              var docs =
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                    snapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                  )..sort((a, b) {
                    final at = a.data()['lastMessageTime'] as Timestamp?;
                    final bt = b.data()['lastMessageTime'] as Timestamp?;
                    final ams = at?.millisecondsSinceEpoch ?? 0;
                    final bms = bt?.millisecondsSinceEpoch ?? 0;
                    return bms.compareTo(ams);
                  });

              // Only threads with real content. A chat that was merely opened
              // — nothing sent — is not a conversation and is never listed
              // (see MessageService.hasMessageActivity).
              docs = docs
                  .where(
                    (doc) => _messageService.hasMessageActivity(
                      doc.id,
                      doc.data(),
                      onResolved: _onActivityResolved,
                    ),
                  )
                  .toList();

              // A chat that was archived but has since received a new
              // message is back in the inbox — drop its stale archive
              // entry so it stays there.
              final returned = docs
                  .where(
                    (doc) =>
                        _prefs.hasArchiveEntry(doc.id) &&
                        !_isArchived(doc.id, doc.data(), myUid),
                  )
                  .map((doc) => doc.id)
                  .toList();
              if (returned.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  returned.forEach(_prefs.unarchive);
                });
              }

              docs = docs.where((doc) {
                if (_prefs.isBlocked(_otherUid(doc.data(), myUid))) {
                  return false;
                }
                final isArchived = _isArchived(doc.id, doc.data(), myUid);
                switch (widget.mode) {
                  case ChatListMode.archived:
                    return isArchived;
                  case ChatListMode.muted:
                    return _prefs.isMuted(doc.id);
                  case ChatListMode.inbox:
                    break;
                }
                if (isArchived) return false;
                if (_filter != 'unread') return true;
                final unreadMap = Map<String, dynamic>.from(
                  doc.data()['unreadCount'] ?? {},
                );
                return ((unreadMap[myUid] ?? 0) as num).toInt() > 0;
              }).toList();

              docs.sort((a, b) {
                final aPinned = _prefs.isPinned(a.id);
                final bPinned = _prefs.isPinned(b.id);
                if (aPinned != bPinned) return aPinned ? -1 : 1;
                final at = a.data()['lastMessageTime'] as Timestamp?;
                final bt = b.data()['lastMessageTime'] as Timestamp?;
                return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                  at?.millisecondsSinceEpoch ?? 0,
                );
              });

              if (docs.isEmpty) {
                if (widget.mode == ChatListMode.archived) {
                  return _folderEmptyState(
                    Icons.archive_outlined,
                    'No archived conversations',
                    'Chats you archive will appear here.',
                  );
                }
                if (widget.mode == ChatListMode.muted) {
                  return _folderEmptyState(
                    Icons.notifications_off_outlined,
                    'No muted conversations',
                    'Chats you mute will appear here.',
                  );
                }
                return _filter == 'unread'
                    ? _noResultsState()
                    : _emptyState(myUid);
              }

              return AgriRefreshIndicator(
                color: _dark,
                onRefresh: _refreshData,
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    _inboxMode ? 4 : 12,
                    12,
                    _inboxMode ? 90 : 24,
                  ),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    return _conversationTile(context, doc.id, data, myUid);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _otherUid(Map<String, dynamic> data, String? myUid) {
    final participants = List<dynamic>.from(data['participants'] ?? []);
    return participants
        .firstWhere((id) => id != myUid, orElse: () => '')
        .toString();
  }

  // "Messages" title (same style as the Orders tab heading) with the
  // message-management menu on the right — same for Farmer and Buyer.
  Widget _header() {
    // The menu sits on the title's own row, opposite it.
    return PageHeader(title: 'Messages', titleTrailing: _menuButton());
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: _searchField(),
    );
  }

  Widget _searchField() {
    // Not an editable field — tapping it opens the dedicated search
    // screen (recent searches + results), same for Farmer and Buyer.
    return Semantics(
      button: true,
      label: 'Search conversations',
      child: AppSearchBar(
        hint: 'Search conversations...',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MessageSearchScreen()),
        ),
      ),
    );
  }

  Widget _filterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          _filterChip('All', 'all'),
          const SizedBox(width: 8),
          _filterChip('Unread', 'unread'),
        ],
      ),
    );
  }

  // Archived, Muted, Reported and Blocked Users are message-management
  // sections, not inbox filters — so they live behind this menu rather than
  // beside the All/Unread chips. A compact drop-down from the ☰ — bottom
  // sheets are kept for actions on one conversation (long-press).
  Widget _menuButton() {
    return Builder(
      builder: (buttonContext) => IconButton(
        tooltip: 'Manage messages',
        icon: const Icon(
          Icons.menu_rounded,
          size: 24,
          color: PageHeader.titleColor,
        ),
        onPressed: () => _openManageMenu(buttonContext),
      ),
    );
  }

  Future<void> _openManageMenu(BuildContext buttonContext) async {
    final Widget? screen = await showAgriPopupMenu<Widget>(
      anchorContext: buttonContext,
      items: const [
        AgriMenuItem(
          value: ArchivedConversationsScreen(),
          icon: Icons.archive_outlined,
          label: 'Archived',
        ),
        AgriMenuItem(
          value: MutedConversationsScreen(),
          icon: Icons.notifications_off_outlined,
          label: 'Muted',
        ),
        AgriMenuItem(
          value: ReportedUsersScreen(),
          icon: Icons.flag_outlined,
          label: 'Reported',
        ),
        AgriMenuItem(
          value: BlockedUsersScreen(),
          icon: Icons.block,
          label: 'Blocked Users',
        ),
      ],
    );
    if (screen == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _folderEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: AgriEmptyState(
        icon: icon,
        title: title,
        subtitle: subtitle,
        padding: const EdgeInsets.all(32),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _dark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _dark : const Color(0xFFE3E9DF)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _noResultsState() {
    return const Center(
      child: AgriEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'No unread messages',
        padding: EdgeInsets.all(32),
      ),
    );
  }

  String _profileLocation(Map<String, dynamic>? profile) {
    if (profile == null) return '';
    final values =
        [
              profile['barangay']?.toString(),
              profile['municipality']?.toString(),
              profile['province']?.toString(),
            ]
            .where((value) => value != null && value.trim().isNotEmpty)
            .map((value) => value!.trim());
    return values.join(', ');
  }

  // The prefs notify on every change, which rebuilds this list (and the
  // other Messages screen, if open) via _onPrefsChanged.
  void _togglePinned(String conversationId) =>
      _prefs.togglePinned(conversationId);

  void _toggleMuted(String conversationId) =>
      _prefs.toggleMuted(conversationId);

  // Archive or unarchive, depending on the conversation's current state.
  void _toggleArchived(
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
  ) {
    if (_isArchived(conversationId, data, myUid)) {
      _prefs.unarchive(conversationId);
    } else {
      _prefs.archive(conversationId, lastMessageMs: _lastMessageMs(data));
    }
  }

  Future<void> _confirmBlock(String otherUid, String otherName) async {
    if (otherUid.isEmpty) return;
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.block,
      tone: AgriTone.destructive,
      title: 'Block $otherName?',
      message:
          'Your conversations with $otherName will be hidden from Messages. '
          'You can unblock them anytime from Blocked Users in the menu.',
      confirmLabel: 'Block',
    );
    if (confirmed) _prefs.block(otherUid);
  }

  Widget _conversationTile(
    BuildContext context,
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
  ) {
    final participants = List<dynamic>.from(data['participants'] ?? []);
    final otherUid =
        participants.firstWhere((id) => id != myUid, orElse: () => '')
            as String;

    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherName = names[otherUid]?.toString() ?? 'User';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: otherUid.isEmpty ? null : _profileStream(otherUid),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final profileName = profile?['name']?.toString().trim();
        final resolvedName = profileName != null && profileName.isNotEmpty
            ? profileName
            : otherName;
        final photoUrl = profile?['photoUrl']?.toString();
        final location = _profileLocation(profile);
        return _conversationTileContent(
          context,
          conversationId,
          data,
          myUid,
          otherUid,
          resolvedName,
          photoUrl,
          location,
        );
      },
    );
  }

  Widget _conversationTileContent(
    BuildContext context,
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
    String otherUid,
    String otherName,
    String? otherPhotoUrl,
    String location,
  ) {
    final lastMessage = data['lastMessage']?.toString() ?? '';
    final lastSenderId = data['lastSenderId']?.toString() ?? '';
    final unreadMap = Map<String, dynamic>.from(data['unreadCount'] ?? {});
    final isPinned = _prefs.isPinned(conversationId);
    final isMuted = _prefs.isMuted(conversationId);
    final isArchived = _isArchived(conversationId, data, myUid);
    final unread = isMuted ? 0 : ((unreadMap[myUid] ?? 0) as num).toInt();

    final timestamp = data['lastMessageTime'] as Timestamp?;
    final timeLabel = _formatTime(timestamp?.toDate());

    final youSent = lastSenderId == myUid;
    final preview = lastMessage.isEmpty
        ? 'Say hello 👋'
        : '${youSent ? 'You: ' : ''}$lastMessage';

    return Slidable(
      key: ValueKey(conversationId),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _togglePinned(conversationId),
            backgroundColor: const Color(0xFFEAF4E7),
            foregroundColor: _dark,
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _toggleMuted(conversationId),
            backgroundColor: const Color(0xFFF1F4F1),
            foregroundColor: _dark,
            icon: isMuted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            label: isMuted ? 'Unmute' : 'Mute',
          ),
          if (isArchived)
            SlidableAction(
              onPressed: (_) => _toggleArchived(conversationId, data, myUid),
              backgroundColor: const Color(0xFFEAF4E7),
              foregroundColor: _dark,
              icon: Icons.unarchive_outlined,
              label: 'Unarchive',
            )
          else
            SlidableAction(
              onPressed: (_) => _toggleArchived(conversationId, data, myUid),
              backgroundColor: const Color(0xFFFFE8E6),
              foregroundColor: Colors.redAccent,
              icon: Icons.archive_outlined,
              label: 'Archive',
            ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: () => _showConversationActions(
          conversationId,
          data,
          myUid,
          otherUid,
          otherName,
        ),
        onTap: () => openConversation(
          context,
          conversationId: conversationId,
          data: data,
          myUid: myUid,
          otherUid: otherUid,
          otherName: otherName,
          otherPhotoUrl: otherPhotoUrl,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(photoUrl: otherPhotoUrl, name: otherName),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    // Shown only while the other person is really online.
                    child: OnlineDot(key: ValueKey(otherUid), userId: otherUid),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: unread > 0
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (timeLabel.isNotEmpty)
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: unread > 0 ? _dark : Colors.grey[500],
                              fontWeight: unread > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: unread > 0
                                  ? Colors.black87
                                  : Colors.grey[600],
                              fontWeight: unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: _dark,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 20),
                            child: Text(
                              unread > 9 ? '9+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Long-press menu for one conversation. Each action shows the opposite
  // of the conversation's current state (Pin/Unpin, Mute/Unmute,
  // Archive/Unarchive). Unblocking is done from the Blocked Users screen,
  // since a blocked user's chats aren't listed here.
  Future<void> _showConversationActions(
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
    String otherUid,
    String otherName,
  ) async {
    final isPinned = _prefs.isPinned(conversationId);
    final isMuted = _prefs.isMuted(conversationId);
    final isArchived = _isArchived(conversationId, data, myUid);
    final action = await showAgriSheet<String>(
      context: context,
      title: otherName,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AgriSheetAction(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin',
            onTap: () => Navigator.pop(sheetContext, 'pin'),
          ),
          AgriSheetAction(
            icon: isMuted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            label: isMuted ? 'Unmute' : 'Mute',
            onTap: () => Navigator.pop(sheetContext, 'mute'),
          ),
          AgriSheetAction(
            icon: isArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            label: isArchived ? 'Unarchive' : 'Archive',
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          AgriSheetAction(
            icon: Icons.flag_outlined,
            label: 'Report',
            onTap: () => Navigator.pop(sheetContext, 'report'),
          ),
          AgriSheetAction(
            icon: Icons.block,
            label: 'Block',
            destructive: true,
            onTap: () => Navigator.pop(sheetContext, 'block'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        _togglePinned(conversationId);
        break;
      case 'mute':
        _toggleMuted(conversationId);
        break;
      case 'archive':
        _toggleArchived(conversationId, data, myUid);
        break;
      case 'report':
        await showReportUserDialog(
          context,
          otherUserId: otherUid,
          otherUserName: otherName,
          conversationId: conversationId,
        );
        break;
      case 'block':
        await _confirmBlock(otherUid, otherName);
        break;
    }
  }

  Widget _emptyState(String? myUid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myUid == null
          ? null
          : _ownUserStream ??= FirebaseFirestore.instance
                .collection('users')
                .doc(myUid)
                .snapshots(),
      builder: (context, snapshot) {
        final isFarmer = snapshot.data?.data()?['role'] == 'farmer';
        return Center(
          child: AgriEmptyState(
            icon: Icons.mail_outline,
            title: 'No conversations yet',
            subtitle: isFarmer
                ? 'Messages from buyers will appear here.'
                : 'Messages from farmers will appear here.',
            padding: const EdgeInsets.all(32),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && now.day == dt.day) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $period';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.month}/${dt.day}/${dt.year % 100}';
    }
  }
}
