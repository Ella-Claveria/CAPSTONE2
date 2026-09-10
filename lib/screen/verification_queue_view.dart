import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // Added to decode Base64 images

import '../services/connectivity_service.dart';

class VerificationQueueView extends StatelessWidget {
  const VerificationQueueView({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verification Queue',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
            ),
          ),
          Text(
            'Review and approve agricultural credentials for new farmers.',
            style: TextStyle(color: Colors.grey[700]),
          ),
          SizedBox(height: 24),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('verificationDocs')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error loading queue.'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No pending verifications at this time.',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['status'] == null || data['status'] == 'pending';
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No pending verifications at this time.',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final docId = docs[index].id;

                    // Handling missing fields gracefully
                    final storedUserId =
                        data['userId']?.toString().trim() ?? '';
                    final userId = storedUserId.isNotEmpty
                        ? storedUserId
                        : docId;
                    final storedName =
                        data['fullName']?.toString().trim() ?? '';
                    // A real, stable identifier (the account's own uid) rather
                    // than a synthetic row number that would shuffle as the
                    // list re-sorts on every update.
                    final farmerId = userId.length > 8 ? userId.substring(0, 8) : userId;
                    final document = data['document']?.toString() ?? '';

                    return _farmerApplicationCard(
                      context,
                      data,
                      docId,
                      userId.toString(),
                      storedName,
                      farmerId,
                      document,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _farmerApplicationCard(
    BuildContext context,
    Map<String, dynamic> data,
    String docId,
    String userId,
    String storedName,
    String farmerId,
    String document,
  ) {
    // Always listen to the user profile (not just when the name is
    // missing) — the farmer's barangay only lives on `users/{uid}`, never
    // on the verification doc itself.
    final profileStream = userId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(userId).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileStream,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final fullName = storedName.isNotEmpty
            ? storedName
            : profile?['fullName']?.toString().trim().isNotEmpty == true
            ? profile!['fullName'].toString().trim()
            : profile?['name']?.toString().trim().isNotEmpty == true
            ? profile!['name'].toString().trim()
            : 'Unknown Farmer';
        final rawBarangay = profile?['barangay']?.toString().trim();
        final barangay = (rawBarangay == null || rawBarangay.isEmpty) ? '—' : rawBarangay;
        final submittedAt = data['submittedAt'] as Timestamp?;
        final dateSubmitted =
            submittedAt != null ? DateFormat('MMM d, y').format(submittedAt.toDate()) : '—';
        final rawStatus = (data['status'] ?? 'pending').toString();
        final statusLabel =
            rawStatus.isEmpty ? 'Pending' : '${rawStatus[0].toUpperCase()}${rawStatus.substring(1)}';

        return Card(
          margin: EdgeInsets.only(bottom: 16),
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Colors.green[100],
              child: Icon(Icons.person, color: Colors.green[800]),
            ),
            title: Text(
              fullName,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            isThreeLine: true,
            subtitle: Text(
              'ID: $farmerId  •  Barangay: $barangay\nSubmitted: $dateSubmitted  •  Status: $statusLabel',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'View full verification details',
                  icon: Icon(Icons.visibility_outlined, color: Colors.grey[700]),
                  onPressed: () => showFarmerVerificationDetails(context, uid: userId),
                ),
                OutlinedButton.icon(
                  icon: Icon(Icons.image_search, color: Colors.blue),
                  label: Text('View Doc'),
                  onPressed: () => _showDocumentDialog(context, document),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: Icon(Icons.check),
                  label: Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => approveFarmerAccount(context, docId, userId),
                ),
                SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: Icon(Icons.close, color: Colors.red),
                  label: Text('Reject', style: TextStyle(color: Colors.red)),
                  onPressed: () => rejectFarmerAccount(context, docId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}

// Updated to display Base64 images instead of URLs
void _showDocumentDialog(BuildContext context, String document) {
  Widget imageWidget;

  try {
    if (document.startsWith('http://') || document.startsWith('https://')) {
      imageWidget = Image.network(
        document,
        width: 400,
        height: 400,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Text('Failed to load document image.'),
      );
    } else if (document.isNotEmpty) {
      // Clean up the string in case it has metadata like "data:image/jpeg;base64,"
      final cleanBase64 = document.contains(',') ? document.split(',').last : document;

      imageWidget = Image.memory(
        base64Decode(cleanBase64),
        width: 400,
        height: 400,
        fit: BoxFit.contain,
      );
    } else {
      imageWidget = const Text('No document image provided.');
    }
  } catch (e) {
    imageWidget = const Text('Failed to load image format.');
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Agricultural Certification'),
      content: imageWidget,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Approve a farmer application. `verificationDocId` and `userId` are
/// always the same value in practice (the verification doc's own id is
/// the farmer's Firebase Auth uid — see AuthService.saveVerificationDocument
/// / createPendingVerificationApplication), but both are threaded through
/// explicitly since the verification doc is the canonical record of *what*
/// was submitted and reviewed.
Future<void> approveFarmerAccount(
  BuildContext context,
  String verificationDocId,
  String userId,
) async {
  if (!await ConnectivityService.instance.checkNow()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
    }
    return;
  }
  try {
    await FirebaseFirestore.instance
        .collection('verificationDocs')
        .doc(verificationDocId)
        .update({'status': 'approved'});
    if (userId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'isVerified': true, 'approvalStatus': 'approved'});
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Farmer approved successfully!')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error approving farmer: $e')));
  }
}

Future<void> rejectFarmerAccount(BuildContext context, String verificationDocId) async {
  if (!await ConnectivityService.instance.checkNow()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
    }
    return;
  }
  try {
    await FirebaseFirestore.instance
        .collection('verificationDocs')
        .doc(verificationDocId)
        .update({'status': 'rejected'});
    await FirebaseFirestore.instance
        .collection('users')
        .doc(verificationDocId)
        .update({'approvalStatus': 'rejected'});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application rejected.')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error rejecting application: $e')));
  }
}

/// Opens the full verification detail dialog for one farmer — used both by
/// the queue's own eye icon and by the Home dashboard's "Recent Verification
/// Requests" table, so both stay backed by the same live data and the same
/// approve/reject actions.
Future<void> showFarmerVerificationDetails(BuildContext context, {required String uid}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FarmerVerificationDetailDialog(uid: uid),
  );
}

class _FarmerVerificationDetailDialog extends StatelessWidget {
  final String uid;
  const _FarmerVerificationDetailDialog({required this.uid});

  String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('verificationDocs').doc(uid).snapshots(),
          builder: (context, verifSnap) {
            if (userSnap.hasError || verifSnap.hasError) {
              return AlertDialog(
                title: const Text('Something went wrong'),
                content: const Text('Could not load this farmer\'s details. Please try again.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              );
            }
            if (!userSnap.hasData || !verifSnap.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final user = userSnap.data!.data();
            if (user == null) {
              return AlertDialog(
                title: const Text('Account Not Found'),
                content: const Text('This farmer\'s account could not be found. It may have been removed.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ],
              );
            }
            final verif = verifSnap.data!.data();

            final fullName = _firstNonEmpty([verif?['fullName'], user['fullName'], user['name']]) ??
                'Unknown Farmer';
            final barangay = _firstNonEmpty([user['barangay']]);
            final municipality = _firstNonEmpty([user['municipality']]);
            final province = _firstNonEmpty([user['province']]);
            final location =
                [barangay, municipality, province].whereType<String>().join(', ');
            final approvalStatus = (user['approvalStatus'] ?? verif?['status'] ?? 'pending').toString();
            final statusLabel = approvalStatus.isEmpty
                ? 'Pending'
                : '${approvalStatus[0].toUpperCase()}${approvalStatus.substring(1)}';
            final submittedAt = verif?['submittedAt'] as Timestamp?;
            final dateSubmitted =
                submittedAt != null ? DateFormat('MMM d, y – h:mm a').format(submittedAt.toDate()) : '—';
            final document = (verif?['document'] ?? '').toString();

            return AlertDialog(
              title: Text(fullName),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Farmer ID', uid),
                      _detailRow('Barangay', location.isEmpty ? '—' : location),
                      _detailRow('Date Submitted', dateSubmitted),
                      _detailRow('Approval Status', statusLabel),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.image_search, color: Colors.blue),
                        label: const Text('View Submitted Document'),
                        onPressed: document.isEmpty ? null : () => _showDocumentDialog(context, document),
                      ),
                      if (document.isEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'No verification document was submitted for this account.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                if (approvalStatus == 'pending') ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await rejectFarmerAccount(context, uid);
                    },
                    child: const Text('Reject'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await approveFarmerAccount(context, uid, uid);
                    },
                    child: const Text('Approve'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
