import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/product_service.dart';
import '../services/image_helper.dart';
import 'product_detail_screen.dart';

class BuyerExploreScreen extends StatefulWidget {
  const BuyerExploreScreen({super.key});

  @override
  State<BuyerExploreScreen> createState() => _BuyerExploreScreenState();
}

class _BuyerExploreScreenState extends State<BuyerExploreScreen> {
  static const Color _dark = Color(0xFF1B5E20);

  String _selectedCategory = 'All Postings';
  final List<String> _categories = const [
    'All Postings',
    'Vegetables',
    'Livestock',
    'Fruits',
  ];

  final ProductService _productService = ProductService();

  Future<void> _refreshProducts() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(),
        _buildCategoryChips(),
        const SizedBox(height: 4),
        Expanded(child: _buildProductGrid()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: TextField(
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 13.5, color: Colors.black87),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
            hintText: 'Search crops, livestock, or farmers...',
            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13.5),
          ),
          onChanged: (value) {},
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          return ChoiceChip(
            label: Text(category),
            selected: selected,
            onSelected: (_) => setState(() => _selectedCategory = category),
            selectedColor: _dark,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : _dark,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: selected ? _dark : _dark.withValues(alpha: 0.3)),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productService.allProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _dark));
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong loading products.', style: TextStyle(color: Colors.black54)));
        }
        var docs = snapshot.data?.docs ?? [];

        if (_selectedCategory != 'All Postings') {
          docs = docs.where((doc) {
            final category = (doc.data()['category'] ?? '').toString();
            return category.toLowerCase() == _selectedCategory.toLowerCase();
          }).toList();
        }

        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No products available yet.\nCheck back soon!',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 16)),
            ),
          );
        }

        return RefreshIndicator(
          color: _dark,
          onRefresh: _refreshProducts,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            itemBuilder: (context, index) => _buildProductCard(docs[index]),
          ),
        );
      },
    );
  }

  Widget _buildProductCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = data['name'] ?? 'Unnamed Product';
    final category = data['category'] ?? 'General';
    final farmer = data['farmerName'] ?? 'Local Farmer';
    final price = data['price'] ?? 0;
    final quantity = data['quantity'] ?? 0;
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewCount = data['reviewCount'];

    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: doc.id, data: data)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 10,
              child: SizedBox(width: double.infinity, child: _buildProductImage(data)),
            ),
            Expanded(
              flex: 15,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.toString().toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.black87, height: 1.2)),
                    const SizedBox(height: 2),
                    if (rating != null)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(rating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
                          if (reviewCount != null) ...[
                            const SizedBox(width: 2),
                            Text('($reviewCount)', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ],
                        ],
                      ),
                    const Spacer(),
                    Text("₱$price",
                        style: const TextStyle(color: _dark, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 1),
                    Text("$quantity left", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    const SizedBox(height: 6),
                    Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 7,
                          backgroundColor: Color(0xFFDCEDC8),
                          child: Icon(Icons.person, size: 9, color: _dark),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(farmer, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(Map<String, dynamic> data) {
    final base64 = data['imageBase64']?.toString();
    final imageUrl = (data['imageUrl']?.toString().isNotEmpty == true)
        ? data['imageUrl']?.toString()
        : (data['imageUrls'] is List && (data['imageUrls'] as List).isNotEmpty)
            ? (data['imageUrls'] as List).first?.toString()
            : null;

    if (base64 != null && base64.isNotEmpty) {
      return Base64Image(
        base64Data: base64,
        fit: BoxFit.cover,
        fallback: Container(
          color: const Color(0xFFDCEDC8),
          child: const Icon(Icons.eco_rounded, size: 48, color: _dark),
        ),
      );
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(color: _dark)),
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFFDCEDC8),
          child: const Icon(Icons.broken_image, size: 48, color: _dark),
        ),
      );
    }
    return Container(
      color: const Color(0xFFDCEDC8),
      child: const Icon(Icons.eco_rounded, size: 48, color: _dark),
    );
  }
}