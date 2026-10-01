import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/order_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/retry_message.dart';
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

  Future<void> _openReviewForm(
    String orderId,
    Map<String, dynamic> data,
  ) async {
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

  void _showOrderDetails(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'pending').toString();
    final neededBy = data['neededBy'] as Timestamp?;
    final createdAt = data['createdAt'] as Timestamp?;
    final unit = (data['unit'] ?? '').toString();
    final quantity =
        data['quantityLabel']?.toString() ??
        '${data['quantity'] ?? ''} $unit'.trim();
    final unitPrice =
        (data['pricePerUnit'] as num?) ?? (data['unitPrice'] as num?);
    final subtotal = (data['subtotal'] as num?) ?? (data['total'] as num?) ?? 0;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(data['productName']?.toString() ?? 'Order details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('Current status', status.toUpperCase()),
              _detailLine('Seller', data['sellerName']?.toString() ?? 'Farmer'),
              _detailLine('Item', data['productName']?.toString() ?? 'Product'),
              _detailLine('Quantity', quantity),
              if (unitPrice != null)
                _detailLine(
                  'Price per unit',
                  formatPriceWithUnit(unitPrice, unit),
                ),
              _detailLine(
                'Order type',
                (data['pricingType'] ?? 'retail').toString().toUpperCase(),
              ),
              _detailLine('Total', _peso(subtotal)),
              _detailLine(
                'Delivery method',
                (data['deliveryMethod'] ?? 'Not specified').toString(),
              ),
              if ((data['buyerAddress'] ?? '').toString().isNotEmpty)
                _detailLine(
                  'Delivery address',
                  data['buyerAddress'].toString(),
                ),
              if (createdAt != null)
                _detailLine(
                  'Ordered',
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(createdAt.toDate()),
                ),
              if (neededBy != null)
                _detailLine(
                  'Needed by',
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(neededBy.toDate()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  Widget _filterTab(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
    );
  }

  Widget _statusBadge(String status) {
    Color c;
    switch (status) {
      case 'confirmed':
        c = _dark;
        break;
      case 'shipped':
        c = Colors.blue;
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
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _thumbFallback(String name) {
    return Container(
      color: _accent,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: _dark,
        ),
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
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: _dark,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No $_filter orders yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your submitted orders will appear here.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          if (widget.onBrowseMarketplace != null) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: widget.onBrowseMarketplace,
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Browse Marketplace'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
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
    final qty =
        d['quantityLabel']?.toString() ??
        '${d['quantity'] ?? ''} ${d['unit'] ?? ''}'.trim();
    final seller = d['sellerName']?.toString() ?? 'Farmer';
    final totalRaw = d['total'];
    final total = totalRaw is num ? totalRaw : num.tryParse('$totalRaw') ?? 0;
    final status = (d['status'] ?? 'pending').toString().toLowerCase();
    final method = (d['deliveryMethod'] ?? '').toString();
    final pricingType = (d['pricingType'] ?? 'retail').toString();
    final unit = (d['unit'] ?? '').toString();
    final pricePerUnit =
        (d['pricePerUnit'] as num?) ?? (d['unitPrice'] as num?);
    final imageUrl = d['imageUrl']?.toString();
    final isReviewed = d['reviewedAt'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _thumbFallback(name),
                        )
                      : _thumbFallback(name),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      qty,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: pricingType == 'wholesale'
                                ? Colors.green[50]
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            pricingType == 'wholesale' ? 'WHOLESALE' : 'RETAIL',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: pricingType == 'wholesale'
                                  ? Colors.green[800]
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                        if (pricePerUnit != null)
                          Text(
                            formatPriceWithUnit(pricePerUnit, unit),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          seller,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                _peso(total),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _dark,
                ),
              ),
              TextButton(
                onPressed: () => _showOrderDetails(d),
                style: TextButton.styleFrom(
                  foregroundColor: _dark,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('Details'),
              ),
              if (status == 'completed' || method.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (status == 'completed')
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'REVIEWED',
                            style: TextStyle(
                              fontSize: 11,
                              color: _dark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    if (method.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          method.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: _dark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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
          child: Text(
            'My Orders',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _filterTab('Pending', 'pending'),
              const SizedBox(width: 8),
              _filterTab('Confirmed', 'confirmed'),
              const SizedBox(width: 8),
              _filterTab('Shipped', 'shipped'),
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
                return const Center(
                  child: CircularProgressIndicator(color: _dark),
                );
              }
              if (snap.hasError) {
                return RetryMessage(
                  message:
                      'Could not load your orders. Check your connection and try again.',
                  onRetry: () => setState(() {}),
                );
              }

              final all =
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                    snap.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                  )..sort((a, b) {
                    final at = a.data()['createdAt'] as Timestamp?;
                    final bt = b.data()['createdAt'] as Timestamp?;
                    final ams = at?.millisecondsSinceEpoch ?? 0;
                    final bms = bt?.millisecondsSinceEpoch ?? 0;
                    return bms.compareTo(ams);
                  });

              final docs = all
                  .where(
                    (d) =>
                        (d.data()['status'] ?? 'pending').toString() == _filter,
                  )
                  .toList();
              final unreviewedCompleted = all.where((doc) {
                final data = doc.data();
                return (data['status'] ?? '').toString() == 'completed' &&
                    data['reviewedAt'] == null;
              }).length;

              return RefreshIndicator(
                color: _dark,
                onRefresh: _refreshData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  children: [
                    if (unreviewedCompleted > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F8E9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Leave a review for completed orders to earn the Trusted Buyer badge. $unreviewedCompleted order${unreviewedCompleted == 1 ? '' : 's'} still need a review.',
                          style: const TextStyle(
                            color: _dark,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (docs.isEmpty)
                      _emptyState()
                    else
                      ...docs.map(_orderCard),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
