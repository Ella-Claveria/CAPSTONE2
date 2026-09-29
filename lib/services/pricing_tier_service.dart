class PricingTierQuote {
  final String pricingType;
  final double unitPrice;
  final num quantity;
  final num subtotal;
  final num? quantityToWholesale;

  const PricingTierQuote({
    required this.pricingType,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
    this.quantityToWholesale,
  });

  bool get isWholesale => pricingType == 'wholesale';
}

class PricingTierService {
  const PricingTierService._();

  static bool wholesaleAvailable(Map<String, dynamic> product) {
    final price = _asDouble(product['wholesalePrice']);
    final minimum = _asNum(product['wholesaleMinimumQuantity']);
    final explicit = product['wholesaleEnabled'];
    if (explicit is bool) {
      return explicit && price != null && price > 0 && minimum != null && minimum > 0;
    }
    // Backward compatibility for listings created before wholesaleEnabled.
    return price != null && price > 0 && minimum != null && minimum > 0;
  }

  static PricingTierQuote quote({
    required num quantity,
    required num retailPrice,
    bool wholesaleEnabled = false,
    num? wholesalePrice,
    num? wholesaleMinimumQuantity,
  }) {
    final safeQuantity = quantity < 0 ? 0 : quantity;
    final retail = retailPrice < 0 ? 0.0 : retailPrice.toDouble();
    final wholesale = wholesalePrice?.toDouble();
    final minimum = wholesaleMinimumQuantity;

    final canWholesale = wholesaleEnabled &&
        wholesale != null &&
        wholesale > 0 &&
        minimum != null &&
        minimum > 0;

    if (canWholesale && safeQuantity >= minimum) {
      return PricingTierQuote(
        pricingType: 'wholesale',
        unitPrice: wholesale,
        quantity: safeQuantity,
        subtotal: safeQuantity * wholesale,
        quantityToWholesale: 0,
      );
    }

    return PricingTierQuote(
      pricingType: 'retail',
      unitPrice: retail,
      quantity: safeQuantity,
      subtotal: safeQuantity * retail,
      quantityToWholesale: canWholesale ? (minimum - safeQuantity).clamp(0, minimum) : null,
    );
  }

  static double? _asDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  static num? _asNum(dynamic raw) {
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '');
  }
}
