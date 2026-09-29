import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/order_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/shimmer.dart';
import '../widgets/skeleton_loaders.dart';

// Body-only widget — it renders inside the FarmerHomeScreen Scaffold
// (which already provides the AgriTrade+ app bar and bottom nav).
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  final OrderService _orderService = OrderService();
  bool _isRefreshing = false;

  Future<void> _refreshOrders() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isRefreshing = false);
  }

  // 'pending' | 'confirmed' | 'shipped' | 'completed'
  String _filter = 'pending';
  final Map<String, int> _seenOrderCounts = <String, int>{};

  // Format a number with thousands separators, e.g. 12500 -> ₱12,500
  String _peso(num v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₱$buf';
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

  Future<void> _confirm(String id) async {
    final err = await _orderService.updateStatus(id, 'confirmed');
    if (!mounted) return;
    _snack(err ?? 'Order confirmed.');
  }

  Future<void> _markShipped(String id) async {
    final err = await _orderService.updateStatus(id, 'shipped');
    if (!mounted) return;
    _snack(err ?? 'Order marked shipped.');
  }

  Future<void> _markComplete(String id) async {
    final err = await _orderService.updateStatus(id, 'completed');
    if (!mounted) return;
    _snack(err ?? 'Order marked complete.');
  }

  Future<void> _reject(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject this order?'),
        content: const Text(
          'The buyer will be notified and the item quantity will be returned to your inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await _orderService.rejectOrder(id);
    if (!mounted) return;
    _snack(err ?? 'Order rejected.');
  }

  void _showDetails(Map<String, dynamic> d) {
    final name =
        d['productName']?.toString() ?? d['name']?.toString() ?? 'Product';
    final buyer = d['buyerName']?.toString() ?? 'Buyer';
    final status = (d['status'] ?? 'pending').toString();
    final pricingType = (d['pricingType'] ?? 'retail').toString();
    final unit = d['unit']?.toString() ?? '';
    final unitPrice = (d['pricePerUnit'] as num?) ?? (d['unitPrice'] as num?);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buyer: $buyer'),
            const SizedBox(height: 6),
            Text('Status: ${status[0].toUpperCase()}${status.substring(1)}'),
            const SizedBox(height: 6),
            Text('Pricing: ${pricingType == 'wholesale' ? 'Wholesale' : 'Retail'}'),
            if (unitPrice != null) ...[
              const SizedBox(height: 6),
              Text('Price: ${formatPriceWithUnit(unitPrice, unit)}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
            'Orders',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: _dark,
            onRefresh: _refreshOrders,
            child: _isRefreshing
                ? const OrdersTabSkeleton()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _orderService.farmerOrdersStream(),
                        builder: (context, snapshot) {
                          final counts = <String, int>{
                            'pending': 0,
                            'confirmed': 0,
                            'shipped': 0,
                            'completed': 0,
                          };
                          for (final doc in snapshot.data?.docs ?? const []) {
                            final status = (doc.data()['status'] ?? 'pending')
                                .toString()
                                .toLowerCase();
                            if (counts.containsKey(status)) {
                              counts[status] = counts[status]! + 1;
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _filterTab('Pending', 'pending', counts['pending']!),
                                const SizedBox(width: 8),
                                _filterTab('Confirmed', 'confirmed', counts['confirmed']!),
                                const SizedBox(width: 8),
                                _filterTab('Shipped', 'shipped', counts['shipped']!),
                                const SizedBox(width: 8),
                                _filterTab('Completed', 'completed', counts['completed']!),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _orderService.farmerOrdersStream(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return Shimmer(
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                  itemCount: 4,
                                  itemBuilder: (context, i) => const Padding(
                                    padding: EdgeInsets.only(bottom: 14),
                                    child: OrderCardSkeleton(),
                                  ),
                                ),
                              );
                            }
                            if (snap.hasError) {
                              return const Center(child: Text('Could not load orders.'));
                            }
                            final all = snap.data?.docs ?? [];
                            final docs = all
                                .where(
                                  (d) =>
                                      (d.data()['status'] ?? 'pending').toString() ==
                                      _filter,
                                )
                                .toList();
                            if (docs.isEmpty) return _emptyState();
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: docs.length,
                              itemBuilder: (context, i) => _orderCard(docs[i]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _filterTab(String label, String value, int count) {
    final selected = _filter == value;
    final seenCount = _seenOrderCounts[value] ?? 0;
    final unreadCount = count > seenCount ? count - seenCount : 0;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _filter = value;
          _seenOrderCounts[value] = count;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _dark : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? _dark : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
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
        c = const Color(0xFFB8860B); // amber for pending
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

  Widget _orderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final id = doc.id;
    final name =
        d['productName']?.toString() ?? d['name']?.toString() ?? 'Product';
    final unit = d['unit']?.toString() ?? '';
    final qtyLabel =
        d['quantityLabel']?.toString() ?? '${d['quantity'] ?? ''} $unit'.trim();
    final buyer = d['buyerName']?.toString() ?? 'Buyer';
    final totalRaw = d['total'];
    final total = totalRaw is num ? totalRaw : (num.tryParse('$totalRaw') ?? 0);
    final status = (d['status'] ?? 'pending').toString();
    final pricingType = (d['pricingType'] ?? 'retail').toString();
    final pricePerUnit = (d['pricePerUnit'] as num?) ?? (d['unitPrice'] as num?);
    final imageUrl = d['imageUrl']?.toString();

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
                      qtyLabel,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: pricingType == 'wholesale' ? Colors.green[50] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            pricingType == 'wholesale' ? 'WHOLESALE' : 'RETAIL',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: pricingType == 'wholesale' ? Colors.green[800] : Colors.grey[700],
                            ),
                          ),
                        ),
                        if (pricePerUnit != null)
                          Text(
                            formatPriceWithUnit(pricePerUnit, unit),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          buyer,
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
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
                ],
              ),
              const Spacer(),
              ..._actionButtons(id, status, {...d, 'id': id}),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _actionButtons(
    String id,
    String status,
    Map<String, dynamic> data,
  ) {
    final detailsButton = OutlinedButton(
      onPressed: () => _showDetails(data),
      style: OutlinedButton.styleFrom(
        foregroundColor: _dark,
        side: BorderSide(color: Colors.grey.shade400),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text('Details'),
    );

    switch (status) {
      case 'pending':
        return [
          OutlinedButton(
            onPressed: () => _reject(id),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reject'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _confirm(id),
            style: ElevatedButton.styleFrom(
              backgroundColor: _dark,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ];
      case 'confirmed':
        return [
          detailsButton,
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _markShipped(id),
            style: ElevatedButton.styleFrom(
              backgroundColor: _dark,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Mark Shipped'),
          ),
        ];
      case 'shipped':
        return [
          detailsButton,
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _markComplete(id),
            style: ElevatedButton.styleFrom(
              backgroundColor: _dark,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Mark Complete'),
          ),
        ];
      default:
        return [detailsButton];
    }
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
            'Orders from buyers will appear here.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
