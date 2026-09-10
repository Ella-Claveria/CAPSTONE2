import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// The existing notification bell icon, unchanged, plus a small unread-count
/// badge in its corner — reused by Farmer Home and Buyer Marketplace so the
/// badge logic lives in exactly one place. Reads
/// notifications/{uid}/items where read == false; never a hardcoded count.
class NotificationBell extends StatelessWidget {
  final VoidCallback onPressed;
  final Color color;

  const NotificationBell({super.key, required this.onPressed, this.color = const Color(0xFF1B5E20)});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(Icons.notifications_none_rounded, color: color, size: 22),
        ),
        if (uid != null)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .doc(uid)
                    .collection('items')
                    .where('read', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  final label = count > 99 ? '99+' : '$count';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1.2),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
