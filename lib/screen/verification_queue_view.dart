import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert'; // Added to decode Base64 images

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
                    final applicationId = (index + 1).toString().padLeft(
                      5,
                      '0',
                    );
                    final document = data['document']?.toString() ?? '';

                    return _farmerApplicationCard(
                      context,
                      data,
                      docId,
                      userId.toString(),
                      storedName,
                      applicationId,
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
    String applicationId,
    String document,
  ) {
    final nameStream = storedName.isNotEmpty || userId.isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: nameStream,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final fullName = storedName.isNotEmpty
            ? storedName
            : profile?['fullName']?.toString().trim().isNotEmpty == true
            ? profile!['fullName'].toString().trim()
            : profile?['name']?.toString().trim().isNotEmpty == true
            ? profile!['name'].toString().trim()
            : 'Unknown Farmer';

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
            subtitle: Text('ID: $applicationId\nStatus: Pending Review'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [ 
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
                  onPressed: () => _approveFarmer(context, docId, userId),
                ),
                SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: Icon(Icons.close, color: Colors.red),
                  label: Text('Reject', style: TextStyle(color: Colors.red)),
                  onPressed: () => _rejectFarmer(context, docId),
                ),
              ],
            ),
          ),
        );
      },
    );
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
          errorBuilder: (_, _, _) =>
              const Text('Failed to load document image.'),
        );
      } else if (document.isNotEmpty) {
        // Clean up the string in case it has metadata like "data:image/jpeg;base64,"
        final cleanBase64 = document.contains(',')
            ? document.split(',').last
            : document;

        imageWidget = Image.memory(
          base64Decode(cleanBase64),
          width: 400,
          height: 400,
          fit: BoxFit.contain,
        );
      } else {
        imageWidget = Text('No document image provided.');
      }
    } catch (e) {
      imageWidget = Text('Failed to load image format.');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Agricultural Certification'),
        content: imageWidget,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _approveFarmer(
    BuildContext context,
    String verificationDocId,
    String userId,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('verificationDocs')
          .doc(verificationDocId)
          .update({'status': 'approved'});
      if (userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {'isVerified': true, 'approvalStatus': 'approved'},
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Farmer approved successfully!')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error approving farmer: $e')));
    }
  }

  Future<void> _rejectFarmer(
    BuildContext context,
    String verificationDocId,
  ) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Application rejected.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error rejecting application.')));
    }
  }
}
