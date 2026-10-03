import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/presence_service.dart';

/// The green "active" dot on an avatar — drawn only while [userId] is
/// really online (see PresenceService), and nothing at all otherwise.
class OnlineDot extends StatefulWidget {
  final String userId;

  const OnlineDot({super.key, required this.userId});

  @override
  State<OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<OnlineDot> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _presence =
      FirebaseFirestore.instance
          .collection('presence')
          .doc(widget.userId)
          .snapshots();

  // Someone who loses their connection sends no "offline" update — their
  // last heartbeat just gets old. Re-checking on a timer is what turns the
  // dot off in that case.
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    _recheck = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _presence,
      builder: (context, snapshot) {
        if (!PresenceService.isOnline(snapshot.data?.data())) {
          return const SizedBox.shrink();
        }
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        );
      },
    );
  }
}
