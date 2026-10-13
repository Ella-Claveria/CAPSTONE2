import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/report_reasons.dart';
import 'agri_dialog.dart';

/// "Report this user" from a chat — asks for a reason and a description and
/// files it to the `reports` collection for the Admin Moderation Queue.
/// Shared by the chat screen's report button and the Messages long-press
/// menu, so both file exactly the same report.
///
/// The reasons offered depend on who is reporting (see report_reasons.dart):
/// a buyer reports a farmer, a farmer reports a buyer. The chosen reason is
/// saved as the report's `issueType`.
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
  final user = FirebaseAuth.instance.currentUser;

  // The reporter's own role decides which reasons apply. Anything other
  // than a confirmed farmer gets the buyer's list.
  var reporterRole = 'buyer';
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user?.uid)
        .get();
    if (doc.data()?['role'] == 'farmer') reporterRole = 'farmer';
  } catch (_) {}
  if (!context.mounted) return;

  final report = await showAgriDialog<({String reason, String description})>(
    context: context,
    builder: (_) => _ReportUserForm(
      title: 'Report ${displayName ?? otherUserName}',
      reasons: reportReasonsFor(reporterRole),
    ),
  );
  if (report == null || !context.mounted) return;

  try {
    await FirebaseFirestore.instance.collection('reports').add({
      'issueType': report.reason,
      'description': report.description,
      'reporterId': user?.uid ?? '',
      'reporterName': user?.displayName ?? 'User',
      'reportedUserId': otherUserId,
      'reportedUserName': otherUserName,
      // The Moderation Queue's report-target model: a chat report always
      // concerns the other participant's account/behavior, not a specific
      // listing — a farmer when a buyer reports, a buyer when a farmer
      // does. farmerId is that participant either way.
      'targetType': reportTargetTypeFor(reporterRole),
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

/// The dialog's form: a reason, then the details. "Send" stays disabled
/// until both are filled in.
class _ReportUserForm extends StatefulWidget {
  final String title;
  final List<String> reasons;

  const _ReportUserForm({required this.title, required this.reasons});

  @override
  State<_ReportUserForm> createState() => _ReportUserFormState();
}

class _ReportUserFormState extends State<_ReportUserForm> {
  final _description = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final description = _description.text.trim();
    final canSend = _reason != null && description.isNotEmpty;

    return AgriDialog(
      icon: Icons.flag_outlined,
      tone: AgriTone.warning,
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            hint: const Text('Select a reason'),
            items: [
              for (final reason in widget.reasons)
                DropdownMenuItem(
                  value: reason,
                  child: Text(reason, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _reason = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'Explain the issue...'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AgriDialogButton(
          label: 'Send',
          kind: AgriButtonKind.primary,
          onPressed: canSend
              ? () => Navigator.pop(context, (
                  reason: _reason!,
                  description: description,
                ))
              : null,
        ),
      ],
    );
  }
}
