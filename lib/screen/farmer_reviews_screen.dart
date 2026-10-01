import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FarmerReviewsScreen extends StatelessWidget {
  const FarmerReviewsScreen({super.key});

  static const _green = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    final sellerId = FirebaseAuth.instance.currentUser?.uid;
    if (sellerId == null || sellerId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Log in to view your reviews.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buyer Reviews'),
        backgroundColor: Colors.white,
        foregroundColor: _green,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('productReviews')
            .where('sellerId', isEqualTo: sellerId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load your reviews.'));
          }
          final reviews =
              (snapshot.data?.docs ?? const []).where((doc) {
                final review = doc.data();
                final rating = review['rating'];
                return review['moderationStatus'] != 'removed' &&
                    rating is num &&
                    rating >= 1 &&
                    rating <= 5;
              }).toList()..sort((a, b) {
                final aDate = a.data()['createdAt'] as Timestamp?;
                final bDate = b.data()['createdAt'] as Timestamp?;
                return (bDate?.millisecondsSinceEpoch ?? 0).compareTo(
                  aDate?.millisecondsSinceEpoch ?? 0,
                );
              });

          if (reviews.isEmpty) {
            return const Center(
              child: Text('You do not have any buyer reviews yet.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final review = reviews[index].data();
              final rating = (review['rating'] as num).toInt();
              final comment = (review['comment'] ?? '').toString();
              final imageUrl = (review['imageUrl'] ?? '').toString();
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7EFE4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (review['productName'] ?? 'Product').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (star) => Icon(
                            star < rating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: Colors.amber,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (review['buyerName'] ?? 'Buyer').toString(),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(comment, style: const TextStyle(height: 1.4)),
                    ],
                    if (imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
