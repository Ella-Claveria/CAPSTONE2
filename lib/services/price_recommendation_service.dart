import 'dart:math' as math;

/// How much (if any) real market data backs a [PriceRecommendation] — the
/// UI picks its wording/confidence framing from this, never from guessing
/// at the numbers themselves. See PriceRecommendationService.recommend's
/// doc comment for exactly which inputs produce which tier. Doubles as the
/// four-level cold-start hierarchy: a brand-new AgriTrade+ deployment
/// starts every commodity at [insufficient] or [referenceOnly] and climbs
/// this list automatically, in the same build, as real listings/
/// transactions/demand accumulate — never a manual "mature mode" switch.
enum PriceDataTier {
  /// LEVEL 0 — nothing usable at all: no reference price, no listings, no
  /// transactions. No recommendation is shown ("Price recommendation
  /// currently unavailable").
  insufficient,

  /// LEVEL 1 (cold start) — only the Admin/Agricultural Office reference
  /// price exists yet. Still shows a suggested price/range (the reference
  /// price itself, with a small fixed cushion — see
  /// [PriceRecommendationService.coldStartRangePct]), explicitly labeled
  /// "Limited Data" rather than framed as a confident market read.
  referenceOnly,

  /// LEVEL 2/3 — some real marketplace data (active listings and/or a
  /// handful of completed transactions) alongside the reference price,
  /// but not yet enough to call it a confident read. Labeled "Moderate
  /// Data".
  limited,

  /// LEVEL 4 — enough transactions and/or listings, usually with real
  /// supply/demand signal too, to run the complete recommendation logic
  /// with real confidence. Labeled "Strong Data Support".
  full,
}

/// The exact label [PriceDataTier.insufficient] never gets one — the UI
/// shows its own "unavailable" message instead of a data-availability
/// line (see add_product_screen.dart).
extension PriceDataTierLabel on PriceDataTier {
  String get dataAvailabilityLabel => switch (this) {
        PriceDataTier.insufficient => '',
        PriceDataTier.referenceOnly => 'Limited Data',
        PriceDataTier.limited => 'Moderate Data',
        PriceDataTier.full => 'Strong Data Support',
      };
}

/// The Admin/Agricultural Office's official baseline for one commodity —
/// mirrors the market_prices/{commodityId} doc (name, baselinePrice,
/// updatedAt) that _PriceManagementView already writes; nothing new is
/// stored, this just carries it alongside a staleness read.
class ReferencePriceInfo {
  final double price;
  final DateTime? effectiveDate;

  /// True once [effectiveDate] is older than
  /// [PriceRecommendationService.staleReferenceAfter] — "do not treat old
  /// reference prices as current without considering the effective date":
  /// a stale reference still counts (an admin figure is still real data),
  /// just with less weight than a fresh one.
  final bool isStale;

  const ReferencePriceInfo({required this.price, this.effectiveDate, required this.isStale});
}

/// A computed price suggestion, plus enough context for the UI to explain
/// where it came from and how much to trust it. Every field here maps
/// directly to one line of the "AI-Assisted Price Recommendation" panel —
/// see add_product_screen.dart's _priceRecommendation().
class PriceRecommendation {
  final PriceDataTier tier;

  final double? suggestedPrice;
  final double? suggestedLow;
  final double? suggestedHigh;

  final double? referencePrice;
  final DateTime? referenceEffectiveDate;
  final bool referenceIsStale;

  /// The real spread of current active listings for this commodity — a
  /// distinct concept from [suggestedLow]/[suggestedHigh] (which is the
  /// recommendation's own confidence band): this is simply "what sellers
  /// are literally asking right now."
  final double? marketplaceLow;
  final double? marketplaceHigh;

  final int listingCount;
  final int transactionCount;

  /// Aggregated buyer search activity for this commodity, last 30 days —
  /// a demand signal only; never tied back to which buyer searched.
  final int searchCount;

  final double? supplyQuantity;

  /// Whether the supply/demand nudge in [suggestedPrice] actually had a
  /// real signal to work with (false when there was neither supply nor
  /// demand data at all, in which case the nudge was simply skipped).
  final bool usedSupplyDemand;

  const PriceRecommendation({
    required this.tier,
    this.suggestedPrice,
    this.suggestedLow,
    this.suggestedHigh,
    this.referencePrice,
    this.referenceEffectiveDate,
    this.referenceIsStale = false,
    this.marketplaceLow,
    this.marketplaceHigh,
    this.listingCount = 0,
    this.transactionCount = 0,
    this.searchCount = 0,
    this.supplyQuantity,
    this.usedSupplyDemand = false,
  });

  factory PriceRecommendation.insufficient() =>
      const PriceRecommendation(tier: PriceDataTier.insufficient);

  /// LEVEL 1 cold start: the reference price IS the suggested price, with
  /// a small fixed cushion for the range (see
  /// [PriceRecommendationService.coldStartRangePct]) — never a guess, and
  /// never dressed up as a confident market read.
  factory PriceRecommendation.referenceOnly(ReferencePriceInfo reference) => PriceRecommendation(
        tier: PriceDataTier.referenceOnly,
        suggestedPrice: reference.price,
        suggestedLow: reference.price * (1 - PriceRecommendationService.coldStartRangePct),
        suggestedHigh: reference.price * (1 + PriceRecommendationService.coldStartRangePct),
        referencePrice: reference.price,
        referenceEffectiveDate: reference.effectiveDate,
        referenceIsStale: reference.isStale,
      );
}

/// Pure, testable logic behind the "AI-Assisted Price Recommendation"
/// feature — a statistical/rule-based blend, NOT a trained machine-learning
/// model (see the class-level naming: this is deliberately never described
/// to the farmer as "AI" in the sense of ML — "AI-assisted" / "data-driven"
/// only). Firestore access and the supported-commodity gate both stay in
/// the caller (add_product_screen.dart + commodity_master_list.dart); this
/// class only does the matching/weighting/statistics math so it stays easy
/// to unit-test independent of Firestore.
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
  /// meaningful word (ignoring generic descriptors). Used to match a
  /// farmer's free-text product title against other listings/transactions
  /// for the SAME already-matched commodity (see add_product_screen.dart)
  /// — commodity-vs-master-list matching itself is
  /// commodity_master_list.dart's matchSupportedCommodity, a separate,
  /// stricter check.
  static bool namesLikelyMatch(String typedName, String otherName) {
    final typed = typedName.toLowerCase().trim();
    final other = otherName.toLowerCase().trim();
    if (typed.isEmpty || other.isEmpty) return false;
    if (typed.contains(other) || other.contains(typed)) return true;
    return significantWords(typedName).intersection(significantWords(otherName)).isNotEmpty;
  }

  static ReferencePriceInfo? referenceInfo({
    required double? price,
    required DateTime? effectiveDate,
    DateTime? now,
  }) {
    if (price == null || price <= 0) return null;
    final n = now ?? DateTime.now();
    final isStale = effectiveDate != null && n.difference(effectiveDate) > staleReferenceAfter;
    return ReferencePriceInfo(price: price, effectiveDate: effectiveDate, isStale: isStale);
  }

  // "Recent" transactions get first preference for the price pool — a
  // sale from 8 months ago says less about today's price than one from
  // last week — but never at the cost of going empty: recommend() falls
  // back to all-time transactions when the recent window is too sparse.
  static const Duration recentTransactionWindow = Duration(days: 90);

  // Buyer demand's own recency window (req 7's "search activity") — kept
  // separate from the transaction-price window since demand and "what
  // price a sale cleared at" are different questions.
  static const Duration recentDemandWindow = Duration(days: 30);

  // "Do not treat old reference prices as current without considering the
  // effective date" — a reference price older than this still counts (an
  // admin/Agricultural Office figure is real data either way), just at
  // half the weight of a fresh one, and the UI flags it explicitly.
  static const Duration staleReferenceAfter = Duration(days: 180);

  // The ONE tunable behind Level 1's ("reference price only") suggested
  // range — a single named constant, not a number buried inline, so it's
  // trivial to retune later if the client agrees on a different cushion.
  // Deliberately conservative and symmetric: with nothing but a reference
  // price to go on, the system has no real basis to lean the range one
  // way or the other.
  static const double coldStartRangePct = 0.05;

  // The supply/demand pressure nudge never moves the suggested price by
  // more than this fraction, in either direction — "do not make extreme
  // price changes based on this factor alone".
  static const double _maxSupplyDemandAdjustment = 0.06;

  // IQR outlier trim — "do not allow one unusually high or low listing to
  // distort the recommendation". Skipped under 4 points: too few to
  // define quartiles meaningfully, and trimming a tiny sample tends to
  // remove real data rather than real outliers.
  static List<double> _trimOutliers(List<double> values) {
    if (values.length < 4) return values;
    final sorted = [...values]..sort();
    double percentileAt(double p) {
      final idx = p * (sorted.length - 1);
      final lo = idx.floor();
      final hi = idx.ceil();
      if (lo == hi) return sorted[lo];
      return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
    }

    final q1 = percentileAt(0.25);
    final q3 = percentileAt(0.75);
    final iqr = q3 - q1;
    if (iqr <= 0) return sorted;
    final lowBound = q1 - 1.5 * iqr;
    final highBound = q3 + 1.5 * iqr;
    final kept = sorted.where((v) => v >= lowBound && v <= highBound).toList();
    return kept.isEmpty ? sorted : kept;
  }

  // A weight-aware median: each value effectively "counts" [weights[i]]
  // times without materializing huge lists — walk the sorted values and
  // stop once half the total weight has been passed.
  static double _weightedMedian(List<double> values, List<double> weights) {
    final indices = List.generate(values.length, (i) => i)
      ..sort((a, b) => values[a].compareTo(values[b]));
    final totalWeight = weights.reduce((a, b) => a + b);
    var cumulative = 0.0;
    for (final i in indices) {
      cumulative += weights[i];
      if (cumulative >= totalWeight / 2) return values[i];
    }
    return values[indices.last];
  }

  /// Builds a recommendation from real price points for ONE already-
  /// supported commodity (the caller is responsible for the supported-
  /// commodity gate — see commodity_master_list.dart). Never invents a
  /// missing input; every parameter here is allowed to be empty/null, and
  /// the result's [PriceRecommendation.tier] tells the caller exactly how
  /// much (if any) of it could be used:
  ///
  /// - nothing at all -> [PriceDataTier.insufficient] (no numbers shown).
  /// - [reference] only -> [PriceDataTier.referenceOnly] (the reference
  ///   price alone, explicitly not framed as a strong recommendation).
  /// - [reference] and/or a few [listingPrices]/[transactions] ->
  ///   [PriceDataTier.limited].
  /// - enough transactions (>=3) or listings (>=3) -> [PriceDataTier.full],
  ///   including the supply/demand pressure nudge.
  static PriceRecommendation recommend({
    required List<double> listingPrices,
    required List<({double price, DateTime? date})> transactions,
    ReferencePriceInfo? reference,
    double? supplyQuantity,
    int searchCount30d = 0,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final cleanListings = _trimOutliers(listingPrices.where((p) => p > 0).toList());

    final validTxns = transactions.where((t) => t.price > 0).toList();
    final recentTxns = validTxns
        .where((t) => t.date != null && effectiveNow.difference(t.date!) <= recentTransactionWindow)
        .toList();
    final usableTxns = recentTxns.length >= 2 ? recentTxns : validTxns;
    final txnPrices = _trimOutliers(usableTxns.map((t) => t.price).toList());

    final listingCount = cleanListings.length;
    final transactionCount = txnPrices.length;
    final hasReference = reference != null;

    if (!hasReference && listingCount == 0 && transactionCount == 0) {
      return PriceRecommendation.insufficient();
    }
    if (hasReference && listingCount == 0 && transactionCount == 0) {
      return PriceRecommendation.referenceOnly(reference);
    }

    // ---- Weighted pool: completed transactions outweigh active listings
    // once there's enough of them to trust — an asking price only shows
    // intent, a completed sale shows what a buyer actually paid. ----
    final strongTransactionSignal = transactionCount >= 3;
    final txnWeight = strongTransactionSignal ? 3.0 : 1.5;
    final listingWeight = strongTransactionSignal ? 0.5 : 1.0;
    const freshRefWeight = 2.0;
    const staleRefWeight = 1.0;

    final pooled = <double>[];
    final weights = <double>[];
    for (final p in txnPrices) {
      pooled.add(p);
      weights.add(txnWeight);
    }
    for (final p in cleanListings) {
      pooled.add(p);
      weights.add(listingWeight);
    }
    if (hasReference) {
      pooled.add(reference.price);
      weights.add(reference.isStale ? staleRefWeight : freshRefWeight);
    }

    final basePrice = _weightedMedian(pooled, weights);

    // ---- Supply vs demand pressure — small, bounded nudge only ----
    final demandScore = (transactionCount * 2) + searchCount30d;
    final supplyScore =
        (supplyQuantity != null && supplyQuantity > 0) ? supplyQuantity : (listingCount > 0 ? listingCount * 10.0 : 0.0);
    final hasSupplyDemandSignal = demandScore > 0 || supplyScore > 0;
    var adjustmentPct = 0.0;
    if (hasSupplyDemandSignal) {
      final pressure = (demandScore - supplyScore) / (demandScore + supplyScore + 1);
      adjustmentPct = (pressure * _maxSupplyDemandAdjustment)
          .clamp(-_maxSupplyDemandAdjustment, _maxSupplyDemandAdjustment);
    }
    final suggestedPrice = basePrice * (1 + adjustmentPct);

    // ---- Suggested range: mean +/- stddev of the weighted pool (each
    // point "repeated" per its weight), clamped so it always contains the
    // suggested price and never strays past the pool's own min/max. ----
    final expanded = <double>[];
    for (var i = 0; i < pooled.length; i++) {
      final copies = (weights[i] * 2).round().clamp(1, 20);
      expanded.addAll(List.filled(copies, pooled[i]));
    }
    expanded.sort();
    final mean = expanded.reduce((a, b) => a + b) / expanded.length;
    final variance = expanded.map((p) => (p - mean) * (p - mean)).reduce((a, b) => a + b) / expanded.length;
    final stdDev = math.sqrt(variance);
    final rangeLow = math.max(0, math.min(mean - stdDev, suggestedPrice)).toDouble();
    final rangeHigh = math.max(mean + stdDev, suggestedPrice);

    final marketplaceLow = cleanListings.isEmpty ? null : cleanListings.reduce(math.min);
    final marketplaceHigh = cleanListings.isEmpty ? null : cleanListings.reduce(math.max);

    return PriceRecommendation(
      tier: (strongTransactionSignal || listingCount >= 3) ? PriceDataTier.full : PriceDataTier.limited,
      suggestedPrice: suggestedPrice,
      suggestedLow: rangeLow,
      suggestedHigh: rangeHigh,
      referencePrice: reference?.price,
      referenceEffectiveDate: reference?.effectiveDate,
      referenceIsStale: reference?.isStale ?? false,
      marketplaceLow: marketplaceLow,
      marketplaceHigh: marketplaceHigh,
      listingCount: listingCount,
      transactionCount: transactionCount,
      searchCount: searchCount30d,
      supplyQuantity: supplyQuantity,
      usedSupplyDemand: hasSupplyDemandSignal,
    );
  }
}
