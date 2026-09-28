import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Wraps [child] (typically a nav-bar icon) with a small red dot in its
/// top-right corner whenever the signed-in user has at least one
/// conversation with an unread message — i.e. some
/// conversations/{id}.unreadCount[myUid] > 0. Reuses the same
/// `unreadCount` map ChatListScreen's per-conversation badges already read,
/// so this stays in sync with them automatically.
class UnreadMessagesDot extends StatelessWidget {
  final Widget child;
  const UnreadMessagesDot({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final hasUnread = snapshot.data?.docs.any((doc) {
              final unreadMap = Map<String, dynamic>.from(doc.data()['unreadCount'] ?? {});
              return ((unreadMap[uid] ?? 0) as num).toInt() > 0;
            }) ??
            false;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (hasUnread)
              Positioned(
                top: -1,
                right: -1,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
