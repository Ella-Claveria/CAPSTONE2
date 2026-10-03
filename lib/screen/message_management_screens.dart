import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/conversation_prefs_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/profile_avatar.dart';
import 'chat_list_screen.dart';

// The message-management sections opened from the Messages menu (the ☰ in
// the Messages header): Muted, Reported and Blocked Users. Archived lives in
// archived_conversations_screen.dart. Same screens for Farmer and Buyer.

/// Shared white app bar + body for the message-management screens.
class MessageFolderScaffold extends StatelessWidget {
  final String title;
  final Widget body;

  const MessageFolderScaffold({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppTheme.dark),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Every muted conversation. Long-press (or swipe) a chat to unmute it.
class MutedConversationsScreen extends StatelessWidget {
  const MutedConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MessageFolderScaffold(
      title: 'Muted',
      body: ChatListScreen(mode: ChatListMode.muted),
    );
  }
}

/// The users this account has reported from Messages, with the review
/// status. The user's own view of what they filed — not the Admin
/// Moderation Queue, and it never shows the admin's notes or decision.
class ReportedUsersScreen extends StatefulWidget {
  const ReportedUsersScreen({super.key});

  @override
  State<ReportedUsersScreen> createState() => _ReportedUsersScreenState();
}

class _ReportedUsersScreenState extends State<ReportedUsersScreen> {
  // Firestore rules only let a user read reports they filed themselves, so
  // the query must filter on reporterId.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reports =
      FirebaseFirestore.instance
          .collection('reports')
          .where(
            'reporterId',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
          )
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return MessageFolderScaffold(
      title: 'Reported',
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reports,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load your reports',
              subtitle: 'Check your connection and try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.dark),
            );
          }
          final docs = [...snapshot.data!.docs]
            ..sort((a, b) {
              final at = a.data()['createdAt'];
              final bt = b.data()['createdAt'];
              return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0)
                  .compareTo(at is Timestamp ? at.millisecondsSinceEpoch : 0);
            });
          if (docs.isEmpty) {
            return const _EmptyState(
              icon: Icons.flag_outlined,
              title: 'No reports yet',
              subtitle: 'Users you report from Messages will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) => _reportTile(docs[i].data()),
          );
        },
      ),
    );
  }

  // Only the broad stage is shown to the reporter — never the outcome.
  (String, Color) _statusLabel(String status) => switch (status) {
    'under_review' => ('Under review', Colors.blue.shade700),
    'resolved' || 'dismissed' => ('Reviewed', AppTheme.dark),
    _ => ('Submitted', Colors.orange.shade800),
  };

  Widget _reportTile(Map<String, dynamic> report) {
    final userId = (report['reportedUserId'] ?? '').toString();
    final fallbackName = (report['reportedUserName'] ?? 'User').toString();
    final reason = (report['issueType'] ?? 'Report').toString();
    final description = (report['description'] ?? '').toString();
    final createdAt = report['createdAt'];
    final date = createdAt is Timestamp
        ? MaterialLocalizations.of(context).formatMediumDate(createdAt.toDate())
        : '';
    final (statusText, statusColor) = _statusLabel(
      (report['status'] ?? 'pending').toString(),
    );

    return _UserCard(
      userId: userId,
      fallbackName: fallbackName,
      subtitle: [reason, date].where((s) => s.isNotEmpty).join(' · '),
      detail: description,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          statusText,
          style: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        ),
      ),
    );
  }
}

/// Everyone this account has blocked, with an Unblock action.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final ConversationPrefs _prefs = ConversationPrefs.instance;

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _prefs.load(FirebaseAuth.instance.currentUser?.uid);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  Future<void> _confirmUnblock(String userId, String name) async {
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.lock_open_outlined,
      title: 'Unblock $name?',
      message: 'Your conversations with $name will appear in Messages again.',
      confirmLabel: 'Unblock',
    );
    if (confirmed) _prefs.unblock(userId);
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _prefs.blockedUserIds;
    return MessageFolderScaffold(
      title: 'Blocked Users',
      body: blocked.isEmpty
          ? const _EmptyState(
              icon: Icons.block,
              title: 'No blocked users',
              subtitle: 'Users you block from Messages will appear here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: blocked.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final userId = blocked[i];
                return _UserCard(
                  userId: userId,
                  fallbackName: 'User',
                  subtitle: 'Blocked',
                  trailingBuilder: (name) => OutlinedButton(
                    onPressed: () => _confirmUnblock(userId, name),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.dark,
                      side: const BorderSide(color: AppTheme.dark),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Unblock',
                      style: GoogleFonts.montserrat(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// A user row (live photo + name from publicProfiles) for the Reported and
/// Blocked lists.
class _UserCard extends StatelessWidget {
  final String userId;
  final String fallbackName;
  final String subtitle;
  final String detail;
  final Widget? trailing;

  /// Builds the trailing widget once the user's display name is known.
  final Widget Function(String name)? trailingBuilder;

  const _UserCard({
    required this.userId,
    required this.fallbackName,
    required this.subtitle,
    this.detail = '',
    this.trailing,
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userId.isEmpty
          ? null
          : FirebaseFirestore.instance
                .collection('publicProfiles')
                .doc(userId)
                .snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final profileName = profile?['name']?.toString().trim();
        final name = profileName != null && profileName.isNotEmpty
            ? profileName
            : fallbackName;
        return Container(
          padding: const EdgeInsets.all(12),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                photoUrl: profile?['photoUrl']?.toString(),
                name: name,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ?(trailingBuilder != null ? trailingBuilder!(name) : trailing),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
