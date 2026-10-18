import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/order_format.dart';
import '../theme/app_theme.dart';
import '../widgets/retry_message.dart';
import 'buyer_saved_products_screen.dart' show buyerSubScreenAppBar;
import 'farmer_reviews_screen.dart' show RatingStars;
import 'order_details_screen.dart';
import 'product_detail_screen.dart';
import '../widgets/agri_empty_state.dart';

/// The reviews this buyer has written. Every review belongs to one of
/// their own completed orders — a review's document id is that order's id,
/// and firestore.rules refuses one for anything else — so each card can
/// open both the product and the order it came from.
class BuyerMyReviewsScreen extends StatefulWidget {
  const BuyerMyReviewsScreen({super.key});

  @override
  State<BuyerMyReviewsScreen> createState() => _BuyerMyReviewsScreenState();
}

class _BuyerMyReviewsScreenState extends State<BuyerMyReviewsScreen> {
  static const Color _dark = AppTheme.dark;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews =
      FirebaseFirestore.instance
          .collection('productReviews')
          .where(
            'buyerId',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
          )
          .snapshots();

  Future<void> _openProduct(String productId) async {
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();
    } catch (_) {}
    if (!mounted) return;
    final data = doc?.data();
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This listing is no longer available.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: productId, data: data),
      ),
    );
  }

  void _openOrder(String orderId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailsScreen(orderId: orderId, role: OrderRole.buyer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buyerSubScreenAppBar('My Reviews'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reviews,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return RetryMessage(
              message:
                  'Could not load your reviews. Check your connection and try again.',
              onRetry: () => setState(() {}),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: _dark));
          }
          final docs =
              snapshot.data!.docs
                  .where((d) => d.data()['moderationStatus'] != 'removed')
                  .toList()
                ..sort((a, b) {
                  final at = a.data()['createdAt'] as Timestamp?;
                  final bt = b.data()['createdAt'] as Timestamp?;
                  return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                    at?.millisecondsSinceEpoch ?? 0,
                  );
                });
          if (docs.isEmpty) return _empty();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _reviewCard(docs[index]),
          );
        },
      ),
    );
  }

  Widget _reviewCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final productName = (data['productName'] ?? 'Product').toString();
    final productId = (data['productId'] ?? '').toString();
    final rating = (data['rating'] as num?)?.toDouble() ?? 0;
    final comment = (data['comment'] ?? '').toString().trim();
    final reply = (data['sellerReply'] ?? '').toString().trim();
    final created = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          Text(
            productName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              RatingStars(rating),
              const SizedBox(width: 8),
              if (created != null)
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(context).formatMediumDate(created),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                  ),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ],
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Farmer's reply",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    reply,
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          // Wrap, not Row: on a narrow phone the second link drops to the
          // next line instead of overflowing.
          Wrap(
            spacing: 4,
            children: [
              if (productId.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openProduct(productId),
                  icon: const Icon(Icons.storefront_outlined, size: 16),
                  label: const Text('View product'),
                  style: _linkStyle,
                ),
              TextButton.icon(
                onPressed: () => _openOrder(doc.id),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('View order'),
                style: _linkStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final ButtonStyle _linkStyle = TextButton.styleFrom(
    foregroundColor: _dark,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
  );

  Widget _empty() {
    return const Center(
      child: AgriEmptyState(
        icon: Icons.rate_review_outlined,
        title: 'No reviews yet',
        subtitle:
            'Once an order is completed, you can review the product from '
            'your Orders.',
        padding: EdgeInsets.all(32),
      ),
    );
  }
}
