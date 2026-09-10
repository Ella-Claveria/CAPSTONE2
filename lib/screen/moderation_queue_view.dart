import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/connectivity_service.dart';

class ModerationQueueView extends StatefulWidget {
  const ModerationQueueView({super.key});

  @override
  State<ModerationQueueView> createState() => _ModerationQueueViewState();
}

class _ModerationQueueViewState extends State<ModerationQueueView> {
  String _selectedFilter = 'All Issues';
  final List<String> _filters = ['All Issues', 'Price Gouging', 'Counterfeit Goods', 'Quality Issues'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Moderation Queue', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green[800])),
          Text('Review flagged listings, anomalous pricing alerts, and user reports.', style: TextStyle(color: Colors.grey[700])),
          SizedBox(height: 24),
          
          // Filter Tabs
          Row(
            children: _filters.map((filter) {
              final isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  selectedColor: Colors.green[100],
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.green[900] : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedFilter = filter);
                  },
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 16),

          // Queue List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Querying a hypothetical 'reports' collection
              stream: _getFilteredStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: Colors.green[800]));
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading moderation queue.'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('No flagged items at this time.', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final reportId = docs[index].id;
                    final issueType = data['issueType'] ?? 'General Report';
                    final description = data['description'] ?? 'No details provided.';
                    final reporterName = data['reporterName'] ?? 'Unknown user';

                    // Reports come from two flows: a product listing (has
                    // productId/productName/sellerName — e.g. reported from a
                    // product page) or a chat/user report (has reportedUserId
                    // /reportedUserName instead — see ChatScreen). Showing
                    // "Unknown Product / Unknown Seller" on a chat report would
                    // be misleading, so branch on which fields actually exist.
                    final productId = data['productId']?.toString();
                    final hasProduct = productId != null && productId.isNotEmpty;
                    final productName = data['productName'] ?? 'Unknown Product';
                    final sellerName = data['sellerName'] ?? 'Unknown Seller';
                    final reportedUserName = data['reportedUserName'] ?? 'Unknown user';

                    return Card(
                      margin: EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.red.shade100, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(issueType, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800])),
                                      SizedBox(width: 8),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(4)),
                                        child: Text('High Priority', style: TextStyle(fontSize: 12, color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    hasProduct ? productName : 'Reported user: $reportedUserName',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    hasProduct
                                        ? 'Seller: $sellerName | Product ID: $productId'
                                        : 'Reported account, not a product listing',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  ),
                                  Text('Reported by: $reporterName', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                  SizedBox(height: 8),
                                  Text(description, style: TextStyle(color: Colors.black87)),
                                ],
                              ),
                            ),
                            // Action Buttons
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (hasProduct)
                                  ElevatedButton.icon(
                                    icon: Icon(Icons.gavel, size: 18),
                                    label: Text('Suspend Listing'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    onPressed: () => _suspendListing(context, reportId, productId),
                                  ),
                                if (hasProduct) SizedBox(height: 8),
                                OutlinedButton.icon(
                                  icon: Icon(Icons.warning, size: 18, color: Colors.orange),
                                  label: Text(hasProduct ? 'Warn Seller' : 'Warn User', style: TextStyle(color: Colors.orange)),
                                  onPressed: () => _warnSeller(context, reportId),
                                ),
                                SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => _dismissReport(context, reportId),
                                  child: Text('Dismiss', style: TextStyle(color: Colors.grey)),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
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

  Stream<QuerySnapshot> _getFilteredStream() {
    Query query = FirebaseFirestore.instance.collection('reports').where('status', isEqualTo: 'pending');
    
    if (_selectedFilter != 'All Issues') {
      query = query.where('issueType', isEqualTo: _selectedFilter);
    }
    
    return query.snapshots();
  }

  // ---- Admin moderation actions ----

  /// Every action below changes marketplace/report state, so none of them
  /// may run while offline — Firestore would otherwise silently queue the
  /// write and report success before it's actually reached the server.
  Future<bool> _ensureOnline(BuildContext context) async {
    if (await ConnectivityService.instance.checkNow()) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
    }
    return false;
  }

  Future<void> _suspendListing(BuildContext context, String reportId, String productId) async {
    if (!await _ensureOnline(context)) return;
    try {
      // 1. Mark report as resolved
      await FirebaseFirestore.instance.collection('reports').doc(reportId).update({'status': 'resolved', 'action': 'suspended'});
      // 2. Suspend the actual product in the products collection
      await FirebaseFirestore.instance.collection('products').doc(productId).update({'isSuspended': true});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Listing suspended successfully.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error suspending listing: $e')));
    }
  }

  Future<void> _warnSeller(BuildContext context, String reportId) async {
    if (!await _ensureOnline(context)) return;
    try {
      await FirebaseFirestore.instance.collection('reports').doc(reportId).update({'status': 'resolved', 'action': 'warned'});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Warning sent to seller.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _dismissReport(BuildContext context, String reportId) async {
    if (!await _ensureOnline(context)) return;
    try {
      await FirebaseFirestore.instance.collection('reports').doc(reportId).update({'status': 'dismissed'});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report dismissed.')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}