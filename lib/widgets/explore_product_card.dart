import 'package:flutter/material.dart';

import '../data/commodity_master_list.dart';
import '../services/harvest_info.dart';
import '../services/image_helper.dart';
import '../services/market_price_helpers.dart';
import '../theme/app_theme.dart';
import 'save_product_button.dart';

/// One product in the Buyer Explore grid: image on top, then category (and
/// rating), name, price, the wholesale badge, stock and the farmer.
///
/// Every card in the grid is the same height — [extentFor] — whatever its
/// name length or whether it has a rating or a wholesale badge. That height
/// is worked out from the column width and the device's text size instead
/// of a fixed aspect ratio, so the text block always has the room its lines
/// need: nothing overflows on a narrow phone or with a larger system font.
class ExploreProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  /// Whether the buyer has liked this listing, and what the heart
  /// on the image does. The heart is only drawn when [onToggleSave] is
  /// given.
  final bool saved;
  final VoidCallback? onToggleSave;

  /// The farmer line at the bottom. Left out on the farmer's own public
  /// profile, where every card would repeat the same name.
  final bool showFarmer;

  const ExploreProductCard({
    super.key,
    required this.data,
    this.onTap,
    this.saved = false,
    this.onToggleSave,
    this.showFarmer = true,
  });

  static const Color _dark = AppTheme.dark;

  // Width : height of the product image, the same on every card.
  static const double _imageAspectRatio = 4 / 3;

  // Line heights (font size x height) of the text block at normal text
  // size; they grow with the system font scale.
  static const double _categoryLine = 10 * 1.3;
  static const double _nameLines = 13.5 * 1.2 * 2; // always room for 2 lines
  static const double _priceLine = 16 * 1.25;
  static const double _badgeLine = 10 * 1.2;
  static const double _stockLine = 11 * 1.3;
  static const double _farmerLine = 11 * 1.3;
  static const double _scaledHeight =
      _categoryLine +
      _nameLines +
      _priceLine +
      _badgeLine +
      _stockLine +
      _farmerLine;

  // Everything that does not scale: padding (8 + 8), the gaps between
  // lines, the badge's own padding and the divider — plus a little slack
  // for font rounding.
  static const double _fixedHeight = 16 + 2 + 4 + 4 + 3 + 6 + 1 + 5 + 6;

  /// Height of a card that is [width] wide.
  static double extentFor(
    double width,
    TextScaler textScaler, {
    bool showFarmer = true,
  }) {
    final scale = textScaler.scale(100) / 100;
    final full =
        width / _imageAspectRatio + _fixedHeight + _scaledHeight * scale;
    // Without the farmer line: no gap, divider, gap, or the line itself.
    return showFarmer ? full : full - (6 + 1 + 5) - _farmerLine * scale;
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'Unnamed Product').toString();
    final category = (data['category'] ?? 'General').toString();
    final farmer = (data['farmerName'] ?? 'Local Farmer').toString();
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final wholesalePrice = (data['wholesalePrice'] as num?)?.toDouble();
    final wholesaleEnabled =
        data['wholesaleEnabled'] == true ||
        (data['wholesaleEnabled'] == null &&
            wholesalePrice != null &&
            wholesalePrice > 0);
    final quantity = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewCount = data['reviewCount'];
    final harvested = harvestDateOf(data);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: _imageAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProductImage(data: data),
                  if (onToggleSave != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: LikeHeart(liked: saved, onTap: onToggleSave),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category, with the rating (if any) on the same line.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.3,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[500],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        // Only once the product actually has reviews.
                        if (rating != null &&
                            (reviewCount is! num || reviewCount > 0)) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 1),
                          Flexible(
                            child: Text(
                              reviewCount == null
                                  ? rating.toStringAsFixed(1)
                                  : '${rating.toStringAsFixed(1)} ($reviewCount)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                    ),
                    // A one-line name leaves its second line empty here, so
                    // the price row sits at the same height on every card.
                    const Spacer(),
                    // Only scales down when the price is genuinely wider
                    // than the card (e.g. ₱12,500.00/kg liveweight).
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatPriceWithUnit(price, unit),
                        maxLines: 1,
                        style: const TextStyle(
                          color: _dark,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The badge's line is kept even without wholesale, so
                    // cards with and without it line up.
                    Visibility(
                      visible: wholesaleEnabled,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Wholesale available',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color: _dark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        '${formatStock(quantity, unit)} left',
                        if (harvested != null) harvestLabel(harvested),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                    if (showFarmer) ...[
                      const SizedBox(height: 6),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Colors.grey[200],
                      ),
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
                            child: Text(
                              farmer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ProductImage({required this.data});

  static const Color _dark = AppTheme.dark;

  Widget _placeholder(IconData icon) => Container(
    color: const Color(0xFFDCEDC8),
    child: Icon(icon, size: 48, color: _dark),
  );

  @override
  Widget build(BuildContext context) {
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
        fallback: _placeholder(Icons.eco_rounded),
      );
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(color: _dark)),
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(Icons.broken_image),
      );
    }
    return _placeholder(Icons.eco_rounded);
  }
}
