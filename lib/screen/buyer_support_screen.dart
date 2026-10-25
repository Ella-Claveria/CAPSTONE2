import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../widgets/agri_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/support_request_service.dart';
import '../widgets/agri_empty_state.dart';

/// Lets a farmer or buyer send a support request and see the ones they've
/// already sent, with live status updates and replies from the admin
/// portal. Opened from Help & Support (help_support_screen.dart).
class BuyerSupportScreen extends StatefulWidget {
  const BuyerSupportScreen({super.key});

  @override
  State<BuyerSupportScreen> createState() => _BuyerSupportScreenState();
}

class _BuyerSupportScreenState extends State<BuyerSupportScreen> {
  static const Color _dark = AppTheme.dark;

  final _service = SupportRequestService();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text(message),
      ),
    );
  }

  Future<void> _openNewRequestSheet() async {
    _subjectController.clear();
    _messageController.clear();
    await showAgriPanelSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'New Support Request',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(labelText: 'Subject'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'How can we help?',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            setSheetState(() => _sending = true);
                            final err = await _service.submit(
                              subject: _subjectController.text,
                              message: _messageController.text,
                            );
                            setSheetState(() => _sending = false);
                            if (!sheetContext.mounted) return;
                            if (err != null) {
                              _snack(err);
                              return;
                            }
                            Navigator.pop(sheetContext);
                            _snack('Request sent — we\'ll get back to you.');
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: const StadiumBorder(),
                    ),
                    child: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send Request'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    final resolved = status == 'resolved';
    final c = resolved ? _dark : const Color(0xFFB8860B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AgriAppBar(title: 'Support Requests'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewRequestSheet,
        backgroundColor: _dark,
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.myRequestsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _dark));
          }
          final docs =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              )..sort((a, b) {
                final at = a.data()['createdAt'] as Timestamp?;
                final bt = b.data()['createdAt'] as Timestamp?;
                return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                  at?.millisecondsSinceEpoch ?? 0,
                );
              });

          if (docs.isEmpty) {
            return const Center(
              child: AgriEmptyState(
                icon: Icons.support_agent_outlined,
                title: 'No support requests yet',
                subtitle: 'Tap "New Request" if you need help with anything.',
                padding: EdgeInsets.all(32),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final subject = d['subject']?.toString() ?? '';
              final message = d['message']?.toString() ?? '';
              final status = d['status']?.toString() ?? 'open';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subject,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _statusBadge(status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    if ((d['adminReply']?.toString().trim() ?? '')
                        .isNotEmpty) ...[
                      const Divider(),
                      const Text(
                        'Admin reply',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(d['adminReply'].toString()),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
