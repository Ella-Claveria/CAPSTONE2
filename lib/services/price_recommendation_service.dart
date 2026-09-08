import 'dart:math' as math;

/// A computed price suggestion, plus enough context for the UI to explain
/// where it came from and how much to trust it.
class PriceRecommendation {
  final double median;
  final double low;
  final double high;
  final int listingCount;
  final int transactionCount;
  final bool hasBaseline;
  final double? baselinePrice;

  /// True when there are fewer than 3 real listings/sales behind the
  /// number — the UI should show this as a rough starting point, not a
  /// confident market read.
  final bool limitedData;

  const PriceRecommendation({
    required this.median,
    required this.low,
    required this.high,
    required this.listingCount,
    required this.transactionCount,
    required this.hasBaseline,
    required this.baselinePrice,
    required this.limitedData,
  });
}

/// Pure, testable logic behind the "AI-Driven Price Recommendation"
/// feature. Firestore access stays in the screen; this class only does
/// name matching and the median/mean/stddev math.
class PriceRecommendationService {
  const PriceRecommendationService._();

  // Words too generic to prove two listings are the same commodity
  // (e.g. "Free-Range Chicken" vs "Free-Range Duck" share "free"/"range").
  static const Set<String> _stopWords = {
    'the', 'and', 'for', 'with', 'from', 'per', 'sack', 'kilo', 'kilogram',
    'kilograms', 'fresh', 'organic', 'premium', 'local', 'native', 'free',
    'range', 'quality', 'best', 'grade', 'farm', 'raised', 'young', 'small',
    'large', 'big',
  };

  static Set<String> significantWords(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3 && !_stopWords.contains(w))
        .toSet();
  }

  /// Whether [typedName] and [otherName] likely describe the same
  /// commodity — either one contains the other, or they share a
  /// meaningful word (ignoring generic descriptors).
  static bool namesLikelyMatch(String typedName, String otherName) {
    final typed = typedName.toLowerCase().trim();
    final other = otherName.toLowerCase().trim();
    if (typed.isEmpty || other.isEmpty) return false;
    if (typed.contains(other) || other.contains(typed)) return true;
    return significantWords(typedName)
        .intersection(significantWords(otherName))
        .isNotEmpty;
  }

  /// Builds a recommendation from real price points. [baselinePrice] (the
  /// admin-set official price, if any) is counted twice so it anchors the
  /// median without letting a single outlier listing swing it too far.
  static PriceRecommendation? recommend({
    required List<double> listingPrices,
    required List<double> transactionPrices,
    double? baselinePrice,
  }) {
    final hasBaseline = baselinePrice != null && baselinePrice > 0;
    final pool = <double>[...listingPrices, ...transactionPrices];
    if (hasBaseline) {
      pool.addAll([baselinePrice, baselinePrice]);
    }
    if (pool.isEmpty) return null;

    pool.sort();
    final n = pool.length;
    final mean = pool.reduce((a, b) => a + b) / n;
    final variance =
        pool.map((p) => (p - mean) * (p - mean)).reduce((a, b) => a + b) / n;
    final stdDev = math.sqrt(variance);
    final median =
        n.isOdd ? pool[n ~/ 2] : (pool[n ~/ 2 - 1] + pool[n ~/ 2]) / 2;
    final low = math.max(pool.first, mean - stdDev);
    final high = math.min(pool.last, mean + stdDev);

    return PriceRecommendation(
      median: median,
      low: low,
      high: high,
      listingCount: listingPrices.length,
      transactionCount: transactionPrices.length,
      hasBaseline: hasBaseline,
      baselinePrice: hasBaseline ? baselinePrice : null,
      limitedData: (listingPrices.length + transactionPrices.length) < 3,
    );
  }
}
