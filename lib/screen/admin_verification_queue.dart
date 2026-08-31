import 'package:flutter/material.dart';

class VerificationQueueView extends StatefulWidget {
  const VerificationQueueView({super.key});

  @override
  State<VerificationQueueView> createState() => _VerificationQueueViewState();
}

class _VerificationQueueViewState extends State<VerificationQueueView> {
  // 3 Sample Data Entries
  final List<Map<String, dynamic>> _pendingFarmers = [
    {
      'id': 'F-1001',
      'name': 'Juan Santos',
      'email': 'juan.santos@gmail.com',
      'date': '2 days ago',
      'status': 'Pending',
    },
    {
      'id': 'F-1002',
      'name': 'Maria Makiling',
      'email': 'maria.farm@yahoo.com',
      'date': '1 day ago',
      'status': 'Pending',
    },
    {
      'id': 'F-1003',
      'name': 'Crisostomo Ibarra',
      'email': 'cris.ibarra@gmail.com',
      'date': '5 hours ago',
      'status': 'Pending',
    },
  ];

  void _approveFarmer(int index) {
    // Logic: In a real app, update Firestore status to 'Approved' 
    // and trigger Firebase Auth to send the Verification Email here.
    setState(() {
      _pendingFarmers[index]['status'] = 'Approved';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Approved ${_pendingFarmers[index]['name']}. Verification email sent.'),
        backgroundColor: Colors.green[800],
      ),
    );
  }

  void _requestUpdate(int index) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Update requested for ${_pendingFarmers[index]['name']}.'),
        backgroundColor: Colors.orange[800],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verification Queue',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Review and approve submitted agricultural certifications.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _pendingFarmers.length,
              itemBuilder: (context, index) {
                final farmer = _pendingFarmers[index];
                final isApproved = farmer['status'] == 'Approved';

                return Card(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.green[50],
                          child: Icon(Icons.person, color: Colors.green[800]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                farmer['name'],
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                '${farmer['id']} • Submitted ${farmer['date']}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        // View Certificate Button
                        OutlinedButton.icon(
                          onPressed: () {
                            // Logic to view image modal
                          },
                          icon: const Icon(Icons.badge_outlined, size: 18),
                          label: const Text('View Cert'),
                        ),
                        const SizedBox(width: 16),
                        // Action Buttons
                        isApproved
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Approved - Email Sent',
                                  style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w600),
                                ),
                              )
                            : Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _requestUpdate(index),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange[800],
                                      side: BorderSide(color: Colors.orange.shade200),
                                    ),
                                    child: const Text('Request Update'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () => _approveFarmer(index),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[800],
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Approve'),
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}