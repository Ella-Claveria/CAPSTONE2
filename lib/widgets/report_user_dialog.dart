import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'agri_dialog.dart';

/// "Report this user" from a chat — asks for a description and files it to
/// the `reports` collection for the Admin Moderation Queue. Shared by the
/// chat screen's report button and the Messages long-press menu, so both
/// file exactly the same report.
///
/// [otherUserName] must be the real account name — it's what the report
/// records for the admin. [displayName] (e.g. a conversation nickname) only
/// changes the dialog's title.
Future<void> showReportUserDialog(
  BuildContext context, {
  required String otherUserId,
  required String otherUserName,
  required String conversationId,
  String? displayName,
}) async {
  final reportController = TextEditingController();
  final shouldSend = await showAgriDialog<bool>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.flag_outlined,
      tone: AgriTone.warning,
      title: Text('Report ${displayName ?? otherUserName}'),
      content: TextField(
        controller: reportController,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Explain the issue...'),
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(dialogContext, false),
        ),
        AgriDialogButton(
          label: 'Send',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
  final description = reportController.text.trim();
  reportController.dispose();
  if (shouldSend != true || description.isEmpty || !context.mounted) return;

  try {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('reports').add({
      'issueType': 'Chat Report',
      'description': description,
      'reporterId': user?.uid ?? '',
      'reporterName': user?.displayName ?? 'User',
      'reportedUserId': otherUserId,
      'reportedUserName': otherUserName,
      // The Moderation Queue's report-target model: a chat report always
      // concerns the other participant's account/behavior, not a specific
      // listing, so targetType is 'farmer' and farmerId is that participant.
      'targetType': 'farmer',
      'farmerId': otherUserId,
      'conversationId': conversationId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report sent for review.')));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not send report.')));
  }
}
