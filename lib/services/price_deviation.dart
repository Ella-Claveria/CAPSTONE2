/// Every threshold used by the Add Product price warnings, in one place —
/// change a number here and the warnings, the Post confirmation and the
/// moderation flag all follow.
class PriceDeviationConfig {
  /// More than this % above the suggested upper price needs a confirmation
  /// before posting (anything above the range up to this is a mild note).
  static const double confirmAbovePct = 10;

  /// More than this % above the suggested upper price also flags the
  /// listing for possible Admin Moderation review.
  static const double flagAbovePct = 25;

  /// More than this % below the suggested lower price needs a confirmation
  /// before posting (anything below the range up to this is a mild note).
  static const double confirmBelowPct = 10;

  /// More than this % below the suggested lower price gets the strong
  /// underpricing warning. Never flagged — underpricing only hurts the
  /// farmer.
  static const double strongBelowPct = 25;

  /// After "Post Anyway", the same warning is not shown again unless the
  /// price moves by more than this % (or lands in a different level).
  static const double reconfirmChangePct = 5;

  // Moderation-flag wording. Deliberately neutral: a flag asks an Admin to
  // review the price; it never labels the farmer (e.g. as price gouging).
  static const String highPriceFlagLabel = 'Unusually High Price';
  static const String highPriceFlagReason = 'Price exceeds AI suggested range';
  static const String highPriceFlagStatus = 'Price Review Required';
}

/// The same three levels apply on both sides of the range; the thresholds
/// come from [PriceDeviationConfig] (above: confirmAbovePct/flagAbovePct,
/// below: confirmBelowPct/strongBelowPct).
enum PriceDeviationLevel {
  /// Outside the range, up to the confirm threshold — a note only.
  mild,

  /// Past the confirm threshold, up to the strong one — needs confirmation.
  confirm,

  /// Past the strong threshold — needs confirmation; above the range this
  /// also flags the listing (see [PriceDeviation.shouldFlag]).
  strong,
}

/// How far a farmer's price sits outside one suggested range. Retail prices
/// are only ever evaluated against the retail range and wholesale against
/// the wholesale range — the caller passes the matching range in.
class PriceDeviation {
  final bool isAbove;
  final double percent;
  final double enteredPrice;
  final double lower;
  final double upper;

  /// The recommendation's data availability label, e.g. "Moderate Data".
  final String dataAvailability;

  /// True when the range itself rests on limited data, so the warning is
  /// worded more softly and says so.
  final bool limitedData;

  const PriceDeviation._({
    required this.isAbove,
    required this.percent,
    required this.enteredPrice,
    required this.lower,
    required this.upper,
    required this.dataAvailability,
    required this.limitedData,
  });

  /// Returns null when [price] is inside the range. [lower]/[upper] are compared as displayed (2 decimals)
  /// so the maths the farmer sees always adds up.
  static PriceDeviation? evaluate({
    required double price,
    required double lower,
    required double upper,
    required String dataAvailability,
    required bool limitedData,
  }) {
    final lo = double.parse(lower.toStringAsFixed(2));
    final hi = double.parse(upper.toStringAsFixed(2));
    if (price <= 0 || hi <= 0) return null;

    if (price > hi) {
      return PriceDeviation._(
        isAbove: true,
        percent: (price - hi) / hi * 100,
        enteredPrice: price,
        lower: lo,
        upper: hi,
        dataAvailability: dataAvailability,
        limitedData: limitedData,
      );
    }
    if (lo > 0 && price < lo) {
      return PriceDeviation._(
        isAbove: false,
        percent: (lo - price) / lo * 100,
        enteredPrice: price,
        lower: lo,
        upper: hi,
        dataAvailability: dataAvailability,
        limitedData: limitedData,
      );
    }
    return null;
  }

  PriceDeviationLevel get level {
    final strongPct = isAbove
        ? PriceDeviationConfig.flagAbovePct
        : PriceDeviationConfig.strongBelowPct;
    final confirmPct = isAbove
        ? PriceDeviationConfig.confirmAbovePct
        : PriceDeviationConfig.confirmBelowPct;
    if (percent > strongPct) return PriceDeviationLevel.strong;
    if (percent > confirmPct) return PriceDeviationLevel.confirm;
    return PriceDeviationLevel.mild;
  }

  /// The end of the range the price is measured against.
  double get comparisonPrice => isAbove ? upper : lower;

  /// Rounded to 1 decimal place, e.g. "21.3".
  String get percentLabel => percent.toStringAsFixed(1);

  String get directionLabel => isAbove ? 'above' : 'below';

  /// Everything except the mild level asks the farmer to confirm on Post.
  bool get needsConfirmation => level != PriceDeviationLevel.mild;

  /// Only far-above-range prices are flagged for moderation; a low price
  /// never is.
  bool get shouldFlag => isAbove && level == PriceDeviationLevel.strong;

  /// Whether a confirmation given at [confirmedPrice]/[confirmedLevel]
  /// still covers this price (same level, no meaningful price change).
  bool coveredBy(double confirmedPrice, PriceDeviationLevel confirmedLevel) {
    if (confirmedLevel != level || confirmedPrice <= 0) return false;
    final change = (enteredPrice - confirmedPrice).abs() / confirmedPrice * 100;
    return change <= PriceDeviationConfig.reconfirmChangePct;
  }
}
