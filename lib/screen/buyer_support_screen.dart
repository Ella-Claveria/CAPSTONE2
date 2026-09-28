import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/support_request_service.dart';

/// Lets a buyer send a support request and see the ones they've already
/// sent (with status). There's no admin review screen for these yet —
/// they land in Firestore for now — but submitting and tracking your own
/// requests is fully real, not a placeholder.
class BuyerSupportScreen extends StatefulWidget {
  const BuyerSupportScreen({super.key});

  @override
  State<BuyerSupportScreen> createState() => _BuyerSupportScreenState();
}

class _BuyerSupportScreenState extends State<BuyerSupportScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  const Text('New Support Request',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'How can we help?',
                      border: OutlineInputBorder(),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        centerTitle: true,
        title: const Text('Help & Support',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87)),
      ),
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
          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          )..sort((a, b) {
              final at = a.data()['createdAt'] as Timestamp?;
              final bt = b.data()['createdAt'] as Timestamp?;
              return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
            });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                    child: const Icon(Icons.support_agent_outlined, size: 48, color: _dark),
                  ),
                  const SizedBox(height: 18),
                  const Text('No support requests yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 6),
                  Text('Tap "New Request" if you need help with anything.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
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
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(subject,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                        _statusBadge(status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(message, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
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
