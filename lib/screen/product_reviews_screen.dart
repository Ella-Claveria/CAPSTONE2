import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/agri_empty_state.dart';

/// The reviews of one product a buyer may see — those not removed by
/// moderation — newest first. Shared by the Product Details preview and
/// the full list below so both always count the same reviews.
List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleProductReviews(
  QuerySnapshot<Map<String, dynamic>>? snapshot,
) {
  return (snapshot?.docs ?? const [])
      .where((doc) => doc.data()['moderationStatus'] != 'removed')
      .toList()
    ..sort((a, b) {
      final at = a.data()['createdAt'] as Timestamp?;
      final bt = b.data()['createdAt'] as Timestamp?;
      return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
        at?.millisecondsSinceEpoch ?? 0,
      );
    });
}

double averageReviewRating(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> reviews,
) {
  if (reviews.isEmpty) return 0;
  return reviews
          .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0)
          .reduce((a, b) => a + b) /
      reviews.length;
}

/// Five stars filled to [rating], halves included.
class ReviewStars extends StatelessWidget {
  final double rating;
  final double size;
  const ReviewStars({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          rating >= index + 1
              ? Icons.star_rounded
              : rating >= index + 0.5
              ? Icons.star_half_rounded
              : Icons.star_border_rounded,
          size: size,
          color: rating >= index + 0.5 ? Colors.amber : Colors.grey[400],
        ),
      ),
    );
  }
}

/// Every review of one product, in full: the text, the buyer's photos, the
/// Verified Purchase mark and the farmer's reply. Opened from "View All" on
/// Product Details, whose preview cards only show a short excerpt.
class ProductReviewsScreen extends StatefulWidget {
  final String productId;
  final String productName;
  final String? farmerId;

  const ProductReviewsScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.farmerId,
  });

  @override
  State<ProductReviewsScreen> createState() => _ProductReviewsScreenState();
}

class _ProductReviewsScreenState extends State<ProductReviewsScreen> {
  static const Color _dark = AppTheme.dark;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews =
      FirebaseFirestore.instance
          .collection('productReviews')
          .where('productId', isEqualTo: widget.productId)
          .snapshots();

  Future<void> _reportReview(
    String reviewId,
    Map<String, dynamic> review,
  ) async {
    final reporter = FirebaseAuth.instance.currentUser;
    final sellerId = widget.farmerId ?? '';
    final reviewedBuyerId = review['buyerId']?.toString() ?? '';
    if (reporter == null || sellerId.isEmpty || reviewedBuyerId.isEmpty) return;

    final controller = TextEditingController();
    final confirmed = await showAgriDialog<bool>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.flag_outlined,
        tone: AgriTone.warning,
        title: const Text('Report this review?'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Tell us what is wrong with this review.',
          ),
        ),
        actions: [
          AgriDialogButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AgriDialogButton(
            label: 'Report',
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    final description = controller.text.trim();
    controller.dispose();
    if (confirmed != true || description.isEmpty || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'issueType': 'Review Report',
        'description': description,
        'reporterId': reporter.uid,
        'reporterName': reporter.displayName ?? 'User',
        'reportedUserId': reviewedBuyerId,
        'reportedUserName': (review['buyerName'] ?? 'Buyer').toString(),
        'targetType': 'review',
        'farmerId': sellerId,
        'productId': widget.productId,
        'productName': widget.productName,
        'reviewId': reviewId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review reported for admin review.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not report this review.')),
      );
    }
  }

  // The photos a buyer attached: the single `imageUrl` a review is saved
  // with, plus an `imageUrls` list where one exists.
  List<String> _photosOf(Map<String, dynamic> review) {
    final photos = <String>[];
    final single = review['imageUrl']?.toString() ?? '';
    if (single.isNotEmpty) photos.add(single);
    if (review['imageUrls'] is List) {
      for (final url in review['imageUrls'] as List) {
        final value = url?.toString() ?? '';
        if (value.isNotEmpty && !photos.contains(value)) photos.add(value);
      }
    }
    return photos;
  }

  void _openPhoto(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 4,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photos(List<String> photos) {
    const size = 96.0;
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => _openPhoto(photos[index]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              photos[index],
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: AppTheme.accent,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image, color: _dark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _review(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final review = doc.data();
    final reviewer = review['buyerName']?.toString() ?? 'Buyer';
    final reviewerId = review['buyerId']?.toString() ?? '';
    final text = review['comment']?.toString() ?? '';
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final created = (review['createdAt'] as Timestamp?)?.toDate();
    final reply = (review['sellerReply'] ?? '').toString();
    final photos = _photosOf(review);
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final canReport = viewerId != reviewerId && viewerId != widget.farmerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Initials only — a review shows the buyer's name, not their
            // profile.
            ProfileAvatar(photoUrl: null, name: reviewer, radius: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reviewer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      ReviewStars(rating: rating, size: 15),
                      if (created != null)
                        Text(
                          DateFormat('MMM d, y').format(created),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (canReport)
              IconButton(
                tooltip: 'Report review',
                visualDensity: VisualDensity.compact,
                onPressed: () => _reportReview(doc.id, review),
                icon: Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        // Every review is tied to the buyer's own completed order (see
        // firestore.rules).
        if ((review['orderId'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.verified_outlined, size: 14, color: _dark),
              SizedBox(width: 4),
              Text(
                'Verified Purchase',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _dark,
                ),
              ),
            ],
          ),
        ],
        if (text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        if (photos.isNotEmpty) ...[const SizedBox(height: 10), _photos(photos)],
        if (reply.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reply from the farmer',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reply,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AgriAppBar(title: 'Buyer Reviews'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reviews,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _dark));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load reviews.',
                style: TextStyle(color: Colors.grey[700]),
              ),
            );
          }
          final docs = visibleProductReviews(snapshot.data);
          if (docs.isEmpty) {
            return const Center(
              child: AgriEmptyState(
                icon: Icons.rate_review_outlined,
                title: 'No reviews yet',
                subtitle:
                    'Be the first to review this product after completing '
                    'an order.',
                padding: EdgeInsets.all(32),
              ),
            );
          }
          final average = averageReviewRating(docs);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            itemCount: docs.length + 1,
            separatorBuilder: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1, thickness: 1, color: Colors.grey[200]),
            ),
            itemBuilder: (context, index) {
              if (index > 0) return _review(docs[index - 1]);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        average.toStringAsFixed(1),
                        style: AppTheme.heading(30).copyWith(height: 1),
                      ),
                      const SizedBox(width: 10),
                      ReviewStars(rating: average, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          docs.length == 1
                              ? '(1 review)'
                              : '(${docs.length} reviews)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
