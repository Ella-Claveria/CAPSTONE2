import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/commodity_master_list.dart';
import '../services/market_price_helpers.dart';
import 'product_detail_screen.dart';

class FarmerStorefrontScreen extends StatelessWidget {
  final String farmerId;

  const FarmerStorefrontScreen({super.key, required this.farmerId});

  static const _green = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Farmer Profile'),
        backgroundColor: Colors.white,
        foregroundColor: _green,
        elevation: 1,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('publicProfiles')
            .doc(farmerId)
            .snapshots(),
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }
          if (profileSnap.hasError || !profileSnap.data!.exists) {
            return const Center(child: Text('Farmer profile is unavailable.'));
          }
          final profile = profileSnap.data!.data()!;
          final name = (profile['name'] ?? profile['fullName'] ?? 'Farmer')
              .toString();
          final photoUrl = profile['photoUrl']?.toString() ?? '';
          final barangay = profile['barangay']?.toString() ?? '';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFDCEDC8),
                    backgroundImage: photoUrl.isNotEmpty
                        ? NetworkImage(photoUrl)
                        : null,
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, color: _green, size: 32)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (barangay.isNotEmpty)
                          Text(
                            barangay,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        if (profile['approvalStatus'] == 'approved')
                          const Text(
                            'Verified farmer',
                            style: TextStyle(
                              color: _green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Products',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('products')
                    .where('farmerId', isEqualTo: farmerId)
                    .snapshots(),
                builder: (context, productSnap) {
                  if (productSnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(color: _green),
                      ),
                    );
                  }
                  final products = (productSnap.data?.docs ?? const [])
                      .where(
                        (doc) =>
                            doc.data()['isArchived'] != true &&
                            doc.data()['isSuspended'] != true,
                      )
                      .toList();
                  if (productSnap.hasError) {
                    return const Text('Could not load this farmer’s products.');
                  }
                  if (products.isEmpty) {
                    return const Text('No active products right now.');
                  }
                  return Column(
                    children: products.map((doc) {
                      final data = doc.data();
                      final productName = (data['name'] ?? 'Product')
                          .toString();
                      final image = (data['imageUrl'] ?? '').toString();
                      final price =
                          (data['retailPrice'] as num?) ??
                          (data['price'] as num?) ??
                          0;
                      final unit =
                          (data['unit'] ?? unitForProductName(productName))
                              .toString();
                      final rating = (data['rating'] as num?)?.toDouble();
                      final reviews =
                          (data['reviewCount'] as num?)?.toInt() ?? 0;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: image.isEmpty
                              ? const CircleAvatar(
                                  child: Icon(Icons.eco_outlined),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    image,
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                          title: Text(
                            productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${formatPriceWithUnit(price, unit)}${rating != null && reviews > 0 ? ' · ${rating.toStringAsFixed(1)} ★ ($reviews)' : ''}',
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(
                                productId: doc.id,
                                data: data,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 18),
              const Text(
                'Buyer Reviews',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('productReviews')
                    .where('sellerId', isEqualTo: farmerId)
                    .snapshots(),
                builder: (context, reviewSnap) {
                  if (reviewSnap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _green),
                    );
                  }
                  if (reviewSnap.hasError) {
                    return const Text('Could not load buyer reviews.');
                  }
                  final reviews = (reviewSnap.data?.docs ?? const [])
                      .where(
                        (doc) => doc.data()['moderationStatus'] != 'removed',
                      )
                      .toList();
                  if (reviews.isEmpty) {
                    return const Text('No buyer reviews yet.');
                  }
                  return Column(
                    children: reviews.map((doc) {
                      final review = doc.data();
                      final stars = (review['rating'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (review['productName'] ?? 'Product').toString(),
                        ),
                        subtitle: Text(
                          (review['comment'] ?? 'Rated by buyer').toString(),
                        ),
                        trailing: Text(
                          '${stars.toStringAsFixed(1)} ★',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
