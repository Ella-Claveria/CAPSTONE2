import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/conversation_prefs_service.dart';
import '../services/presence_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/report_user_dialog.dart';
import 'add_product_screen.dart';
import 'conversation_tools_screens.dart';
import 'farmer_storefront_screen.dart';
import 'product_detail_screen.dart';

/// Conversation Info, a full-screen page opened from the (i) in a chat's
/// header — same for Farmer and Buyer. Shows who the other person is
/// (photo, display name/nickname, role, whether they're active, and only
/// their general area — never an exact location), then:
///  - tools: Nickname, Search conversation, View all photos
///  - the linked product, if any
///  - Pin / Mute / Archive
///  - Report / Block (only here — not in the chat header)
///  - location privacy
///
/// Pops with a message id when the user picks a search result, so the chat
/// can jump to that message.
class ConversationInfoScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final String? productId;
  final String? productName;

  const ConversationInfoScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
    this.productId,
    this.productName,
  });

  @override
  State<ConversationInfoScreen> createState() => _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<ConversationInfoScreen> {
  final ConversationPrefs _prefs = ConversationPrefs.instance;
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(widget.otherUserId)
          .snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _presence =
      FirebaseFirestore.instance
          .collection('presence')
          .doc(widget.otherUserId)
          .snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _conversation =
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .snapshots();

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _prefs.load(_myUid);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  int _lastMessageMs(Map<String, dynamic>? data) {
    final t = data?['lastMessageTime'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  bool _isArchived(Map<String, dynamic>? data) {
    final lastSender = data?['lastSenderId']?.toString() ?? '';
    return _prefs.isArchived(
      widget.conversationId,
      lastMessageMs: _lastMessageMs(data),
      lastFromOther: lastSender.isNotEmpty && lastSender != _myUid,
    );
  }

  Future<void> _block(String name) async {
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.block,
      tone: AgriTone.destructive,
      title: 'Block $name?',
      message:
          'Your conversations with $name will be hidden from Messages. You '
          'can unblock them anytime from Blocked Users.',
      confirmLabel: 'Block',
    );
    if (!confirmed || !mounted) return;
    _prefs.block(widget.otherUserId);
    // Close only this screen. The chat sees the block when it regains
    // focus and closes itself (the conversation is now hidden).
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppTheme.dark),
        title: const Text(
          'Conversation Info',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, profileSnap) {
          final profile = profileSnap.data?.data();
          final liveName = profile?['name']?.toString().trim() ?? '';
          final realName = liveName.isNotEmpty
              ? liveName
              : widget.otherUserName;
          // In this conversation only, a nickname replaces the real name
          // (which is then not shown here at all).
          final name = _prefs.displayName(widget.conversationId, realName);
          final role = profile?['role']?.toString();
          final area = [
            profile?['barangay'],
            profile?['municipality'],
            profile?['province'],
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

          final nickname = _prefs.nicknameFor(widget.conversationId);
          final hasProduct =
              widget.productId != null && widget.productId!.isNotEmpty;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              _header(profile, profileSnap.hasData, name, role, area),
              const SizedBox(height: 18),

              _sectionTitle('Conversation tools'),
              _section(
                children: [
                  _actionRow(
                    icon: Icons.badge_outlined,
                    label: 'Nickname',
                    subtitle: nickname ?? 'Only you see it, only in this chat',
                    onTap: () => _editNickname(nickname),
                  ),
                  _actionRow(
                    icon: Icons.search_rounded,
                    label: 'Search conversation',
                    onTap: () => _openSearch(name),
                  ),
                  _actionRow(
                    icon: Icons.photo_library_outlined,
                    label: 'View all photos',
                    onTap: () => _openPhotos(name),
                  ),
                ],
              ),

              if (hasProduct) ...[
                const SizedBox(height: 14),
                _sectionTitle('Product context'),
                _section(
                  children: [
                    _actionRow(
                      icon: Icons.shopping_basket_outlined,
                      label: (widget.productName ?? '').isNotEmpty
                          ? widget.productName!
                          : 'View product',
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black38,
                      ),
                      onTap: _openProduct,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),
              _sectionTitle('Conversation'),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _conversation,
                builder: (context, convSnap) =>
                    _management(convSnap.data?.data()),
              ),

              const SizedBox(height: 14),
              _sectionTitle('Safety'),
              _section(
                children: [
                  _actionRow(
                    icon: Icons.report_problem_outlined,
                    label: 'Report $name',
                    destructive: true,
                    // The report itself records the real name, for the
                    // admin; the nickname is only the label here.
                    onTap: () => showReportUserDialog(
                      context,
                      otherUserId: widget.otherUserId,
                      otherUserName: realName,
                      displayName: name,
                      conversationId: widget.conversationId,
                    ),
                  ),
                  _actionRow(
                    icon: Icons.block,
                    label: 'Block $name',
                    destructive: true,
                    onTap: () => _block(name),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              _sectionTitle('Location privacy'),
              _section(
                children: [
                  _infoRow(
                    Icons.lock_outline,
                    'Only a general area is public',
                    'Profiles show only a general location (barangay, '
                        'municipality/city, province).',
                  ),
                  _infoRow(
                    Icons.location_on_outlined,
                    'Exact location only when you choose',
                    'An exact location is shared only when someone '
                        'intentionally uses Share Location in this chat.',
                  ),
                  _infoRow(
                    Icons.local_shipping_outlined,
                    'For delivery or pick-up',
                    'A shared exact location may be used to coordinate '
                        'delivery or pick-up.',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    Map<String, dynamic>? profile,
    bool loaded,
    String name,
    String? role,
    String area,
  ) {
    final livePhotoUrl = profile?['photoUrl']?.toString();
    return Column(
      children: [
        ProfileAvatar(
          photoUrl: loaded ? livePhotoUrl : widget.otherUserPhotoUrl,
          name: name,
          radius: 42,
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _presence,
          builder: (context, snap) {
            final online = PresenceService.isOnline(snap.data?.data());
            final roleLabel = role == 'farmer'
                ? 'Farmer'
                : role == 'buyer'
                ? 'Buyer'
                : null;
            final parts = [?roleLabel, if (online) 'Active now'];
            if (parts.isEmpty) return const SizedBox.shrink();
            return Text(
              parts.join(' · '),
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: online ? const Color(0xFF16A34A) : Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
        if (area.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.place_outlined, size: 15, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  area,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ],
        if (role == 'farmer') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FarmerStorefrontScreen(farmerId: widget.otherUserId),
              ),
            ),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('View Storefront'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.dark,
              side: const BorderSide(color: AppTheme.dark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Pin / Mute / Archive — the same saved state the Messages list uses.
  Widget _management(Map<String, dynamic>? conversation) {
    final id = widget.conversationId;
    final pinned = _prefs.isPinned(id);
    final muted = _prefs.isMuted(id);
    final archived = _isArchived(conversation);
    return _section(
      children: [
        _actionRow(
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: pinned ? 'Unpin conversation' : 'Pin conversation',
          onTap: () => _prefs.togglePinned(id),
        ),
        _actionRow(
          icon: muted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: muted ? 'Unmute notifications' : 'Mute notifications',
          onTap: () => _prefs.toggleMuted(id),
        ),
        _actionRow(
          icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          label: archived ? 'Unarchive conversation' : 'Archive conversation',
          onTap: () => archived
              ? _prefs.unarchive(id)
              : _prefs.archive(id, lastMessageMs: _lastMessageMs(conversation)),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 6),
    child: Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
        letterSpacing: 0.2,
      ),
    ),
  );

  // Search returns the message to jump to; this screen then closes with it
  // so the chat can scroll there.
  Future<void> _openSearch(String name) async {
    final messageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationSearchScreen(
          conversationId: widget.conversationId,
          otherDisplayName: name,
        ),
      ),
    );
    if (messageId != null && mounted) Navigator.pop(context, messageId);
  }

  void _openPhotos(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationPhotosScreen(
          conversationId: widget.conversationId,
          otherDisplayName: name,
        ),
      ),
    );
  }

  // The listing this chat is about: the farmer who owns it gets their own
  // listing editor, anyone else the product page.
  Future<void> _openProduct() async {
    final productId = widget.productId;
    if (productId == null || productId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();
      final data = snap.data();
      if (!mounted) return;
      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This listing is no longer available.')),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => data['farmerId'] == _myUid
              ? AddProductScreen(productId: productId, existingData: data)
              : ProductDetailScreen(productId: productId, data: data),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the listing. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  Widget _section({required List<Widget> children}) {
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.dark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
    bool destructive = false,
  }) {
    final color = destructive ? Colors.red.shade700 : AppTheme.dark;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: destructive ? color : Colors.black87,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  // Set, change or remove this conversation's nickname. Saving an empty
  // name, or Remove, brings back the real account name.
  Future<void> _editNickname(String? current) async {
    final result = await showAgriDialog<String>(
      context: context,
      builder: (_) => _NicknameDialog(current: current),
    );
    if (result == null || !mounted) return;
    // The chat listens to ConversationPrefs, so its header and placeholder
    // update by themselves — nothing to hand back through Navigator.pop.
    _prefs.setNickname(widget.conversationId, result);
  }
}

/// The nickname editor. Pops with the new nickname, '' to remove it, or
/// null when cancelled. Owns (and disposes) its own text controller.
class _NicknameDialog extends StatefulWidget {
  final String? current;

  const _NicknameDialog({required this.current});

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgriDialog(
      icon: Icons.badge_outlined,
      title: Text(widget.current == null ? 'Set nickname' : 'Edit nickname'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: ConversationPrefs.nicknameMaxLength,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Nickname'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          Text(
            'Only you see this nickname, and only in this conversation. '
            'Their real name stays the same everywhere else.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
      actions: [
        if (widget.current != null)
          AgriDialogButton(
            label: 'Remove',
            kind: AgriButtonKind.destructive,
            onPressed: () => Navigator.pop(context, ''),
          )
        else
          AgriDialogButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context),
          ),
        AgriDialogButton(
          label: 'Save',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(context, _controller.text),
        ),
      ],
    );
  }
}
