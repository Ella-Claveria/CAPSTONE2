import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/order_service.dart';
import 'add_review_screen.dart';

class BuyerOrdersScreen extends StatefulWidget {
  final VoidCallback? onBrowseMarketplace;

  const BuyerOrdersScreen({super.key, this.onBrowseMarketplace});

  @override
  State<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends State<BuyerOrdersScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  final OrderService _orderService = OrderService();
  String _filter = 'pending';

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openReviewForm(String orderId, Map<String, dynamic> data) async {
    final productId = data['productId']?.toString() ?? '';
    final sellerId = data['sellerId']?.toString() ?? '';
    if (productId.isEmpty || sellerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing product info for review.')),
      );
      return;
    }

    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddReviewScreen(
          orderId: orderId,
          productId: productId,
          productName: data['productName']?.toString() ?? 'Product',
          sellerId: sellerId,
          productImage: data['imageUrl']?.toString(),
        ),
      ),
    );

    if (!mounted || done != true) return;
    setState(() {});
  }

  String _peso(num v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return 'P$buf';
  }

  Widget _filterTab(String label, String value) {
    final selected = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _dark : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? _dark : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color c;
    switch (status) {
      case 'confirmed':
        c = _dark;
        break;
      case 'completed':
        c = Colors.blueGrey;
        break;
      case 'rejected':
        c = Colors.red;
        break;
      default:
        c = const Color(0xFFB8860B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
      ),
    );
  }

  Widget _thumbFallback(String name) {
    return Container(
      color: _accent,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _dark),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
            child: const Icon(Icons.receipt_long_outlined, size: 48, color: _dark),
          ),
          const SizedBox(height: 18),
          Text(
            'No $_filter orders yet',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text('Your submitted orders will appear here.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          if (widget.onBrowseMarketplace != null) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: widget.onBrowseMarketplace,
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Browse Marketplace'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _orderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final orderId = doc.id;
    final name = d['productName']?.toString() ?? 'Product';
    final qty = d['quantityLabel']?.toString() ?? '${d['quantity'] ?? ''} ${d['unit'] ?? ''}'.trim();
    final seller = d['sellerName']?.toString() ?? 'Farmer';
    final totalRaw = d['total'];
    final total = totalRaw is num ? totalRaw : (num.tryParse('$totalRaw') ?? 0);
    final status = (d['status'] ?? 'pending').toString();
    final method = d['deliveryMethod']?.toString() ?? '';
    final imageUrl = d['imageUrl']?.toString();
    final isReviewed = d['reviewedAt'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => _thumbFallback(name))
                      : _thumbFallback(name),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(qty, style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(seller, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  Text(
                    _peso(total),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _dark),
                  ),
                ],
              ),
              const Spacer(),
              if (status == 'completed') ...[
                if (!isReviewed)
                  OutlinedButton(
                    onPressed: () => _openReviewForm(orderId, d),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _dark,
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    child: const Text('Leave Review'),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'REVIEWED',
                      style: TextStyle(fontSize: 11, color: _dark, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
              if (method.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    method.toUpperCase(),
                    style: const TextStyle(fontSize: 11, color: _dark, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text('My Orders',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _filterTab('Pending', 'pending'),
              const SizedBox(width: 8),
              _filterTab('Confirmed', 'confirmed'),
              const SizedBox(width: 8),
              _filterTab('Completed', 'completed'),
              const SizedBox(width: 8),
              _filterTab('Rejected', 'rejected'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _orderService.buyerOrdersStream(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _dark));
              }
              if (snap.hasError) {
                return const Center(child: Text('Could not load your orders.'));
              }

              final all = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              )
                ..sort((a, b) {
                  final at = a.data()['createdAt'] as Timestamp?;
                  final bt = b.data()['createdAt'] as Timestamp?;
                  final ams = at?.millisecondsSinceEpoch ?? 0;
                  final bms = bt?.millisecondsSinceEpoch ?? 0;
                  return bms.compareTo(ams);
                });

              final docs = all
                  .where((d) => (d.data()['status'] ?? 'pending').toString() == _filter)
                  .toList();

              if (docs.isEmpty) return _emptyState();

              return RefreshIndicator(
                color: _dark,
                onRefresh: _refreshData,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _orderCard(docs[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}