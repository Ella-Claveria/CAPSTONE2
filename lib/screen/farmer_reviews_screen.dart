import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/review_stats.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/profile_avatar.dart';

/// Five stars for [rating], with half stars.
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;

  const RatingStars(this.rating, {super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 5; i++)
        Icon(
          rating >= i + 1
              ? Icons.star_rounded
              : rating >= i + 0.5
              ? Icons.star_half_rounded
              : Icons.star_border_rounded,
          size: size,
          color: rating >= i + 0.5 ? Colors.amber : Colors.grey[400],
        ),
    ],
  );
}

/// A farmer's buyer reviews: every product's ([productId] null — "View All
/// Reviews" on the Profile), or one product's ("View Reviews" on a product).
/// Shows the rating worked out from the valid reviews, each review, and the
/// farmer's reply under it; the farmer can reply to (or edit their reply
/// to) each review.
class FarmerReviewsScreen extends StatefulWidget {
  final String? productId;
  final String? productName;

  const FarmerReviewsScreen({super.key, this.productId, this.productName});

  @override
  State<FarmerReviewsScreen> createState() => _FarmerReviewsScreenState();
}

class _FarmerReviewsScreenState extends State<FarmerReviewsScreen> {
  static const _green = AppTheme.dark;

  final String? _sellerId = FirebaseAuth.instance.currentUser?.uid;
  bool get _forProduct => (widget.productId ?? '').isNotEmpty;

  // Created once — not on every rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews = _forProduct
      ? FirebaseFirestore.instance
            .collection('productReviews')
            .where('productId', isEqualTo: widget.productId)
            .snapshots()
      : FirebaseFirestore.instance
            .collection('productReviews')
            .where('sellerId', isEqualTo: _sellerId)
            .snapshots();

  // Buyers' public photos, looked up once per buyer.
  final Map<String, Future<String?>> _buyerPhotos = {};

  Future<String?> _buyerPhoto(String buyerId) =>
      _buyerPhotos.putIfAbsent(buyerId, () async {
        if (buyerId.isEmpty) return null;
        try {
          final profile = await FirebaseFirestore.instance
              .collection('publicProfiles')
              .doc(buyerId)
              .get();
          return profile.data()?['photoUrl']?.toString();
        } catch (_) {
          return null;
        }
      });

  Future<void> _replyToReview(
    QueryDocumentSnapshot<Map<String, dynamic>> review,
  ) async {
    final existing = review.data()['sellerReply']?.toString() ?? '';
    final controller = TextEditingController(text: existing);
    final reply = await showAgriDialog<String>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        title: Text(existing.isEmpty ? 'Reply to review' : 'Edit your reply'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Write a helpful reply to the buyer',
          ),
        ),
        actions: [
          AgriDialogButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(dialogContext),
          ),
          AgriDialogButton(
            label: 'Save reply',
            kind: AgriButtonKind.primary,
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || reply == null || reply.isEmpty || reply == existing) {
      return;
    }
    try {
      // One reply per review: saving again replaces it.
      await review.reference.update({
        'sellerReply': reply,
        'sellerReplyAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Could not save your reply.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sellerId == null || _sellerId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Log in to view your reviews.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AgriAppBar(
        title: _forProduct ? 'Product Reviews' : 'Buyer Reviews',
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reviews,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _green,
                ),
              ),
            );
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return const Center(child: Text('Could not load your reviews.'));
          }
          final reviews =
              (snapshot.data?.docs ?? const [])
                  .where((doc) => isValidReview(doc.data()))
                  .toList()
                ..sort((a, b) {
                  final aDate = a.data()['createdAt'] as Timestamp?;
                  final bDate = b.data()['createdAt'] as Timestamp?;
                  return (bDate?.millisecondsSinceEpoch ?? 0).compareTo(
                    aDate?.millisecondsSinceEpoch ?? 0,
                  );
                });
          final summary = summarizeReviews(reviews.map((doc) => doc.data()));
          final productName =
              widget.productName ??
              (reviews.isEmpty
                  ? 'Product'
                  : (reviews.first.data()['productName'] ?? 'Product')
                        .toString());

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              _summaryCard(
                _forProduct ? productName : 'Overall Product Rating',
                summary,
              ),
              const SizedBox(height: 10),
              for (final review in reviews) _reviewCard(review),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(String title, RatingSummary summary) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        if (summary.count == 0)
          Text(
            'No reviews yet',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          )
        else ...[
          Row(
            children: [
              Text(
                formatRating(summary.average),
                style: GoogleFonts.montserrat(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: _green,
                ),
              ),
              const SizedBox(width: 10),
              RatingStars(summary.average, size: 20),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Based on ${reviewCountLabel(summary.count)}',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _reviewCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final review = doc.data();
    final rating = (review['rating'] as num).toDouble();
    final buyerName = (review['buyerName'] ?? 'Buyer').toString();
    final buyerId = (review['buyerId'] ?? '').toString();
    final comment = (review['comment'] ?? '').toString();
    final imageUrl = (review['imageUrl'] ?? '').toString();
    final createdAt = review['createdAt'];
    final reply = (review['sellerReply'] ?? '').toString();
    final repliedAt = review['sellerReplyAt'];
    final farmerName =
        FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ==
            true
        ? FirebaseAuth.instance.currentUser!.displayName!.trim()
        : 'You';
    String date(dynamic value) =>
        value is Timestamp ? DateFormat('MMM d, y').format(value.toDate()) : '';
    final muted = GoogleFonts.montserrat(fontSize: 11, color: Colors.grey[600]);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_forProduct)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                (review['productName'] ?? 'Product').toString(),
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<String?>(
                future: _buyerPhoto(buyerId),
                builder: (context, photo) => ProfileAvatar(
                  photoUrl: photo.data,
                  name: buyerName,
                  radius: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buyerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        RatingStars(rating, size: 15),
                        if (date(createdAt).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(date(createdAt), style: muted),
                        ],
                      ],
                    ),
                    // Tied to the buyer's own completed order.
                    if ((review['orderId'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_outlined,
                              size: 13,
                              color: _green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Verified Purchase',
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _green,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ],
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imageUrl,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$farmerName (Farmer)',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _green,
                          ),
                        ),
                      ),
                      if (date(repliedAt).isNotEmpty)
                        Text(date(repliedAt), style: muted),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    reply,
                    style: GoogleFonts.montserrat(
                      fontSize: 12.5,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _replyToReview(doc),
              icon: const Icon(Icons.reply_outlined, size: 16),
              label: Text(reply.isEmpty ? 'Reply' : 'Edit reply'),
              style: TextButton.styleFrom(
                foregroundColor: _green,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: GoogleFonts.montserrat(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
