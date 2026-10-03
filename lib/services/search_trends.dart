/// Trending Searches, worked out from the `searchTrends` collection.
///
/// Each document there is one normalized search term with a count per day:
///   { term: 'kamote', days: { '2026-10-03': 4, '2026-10-04': 2 }, ... }
/// written only by the aggregateSearchTrend Cloud Function. A buyer counts
/// at most once per term per day, and the documents hold no buyer ids — so
/// what reaches the app is already an anonymous total.
library;

/// The calendar day the Cloud Function files a search under (Philippine
/// time, UTC+8, no daylight saving), as 'YYYY-MM-DD'.
String trendDayKey(DateTime moment) {
  final manila = moment.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${manila.year}-${two(manila.month)}-${two(manila.day)}';
}

/// The most-searched terms over the last [days] days, most searched first.
///
/// A term needs at least [minCount] searches in that period to count as
/// trending at all — with too little real activity this returns an empty
/// list (the section is then hidden) rather than promoting a single search
/// to a "trend".
List<String> topTrendingTerms(
  Iterable<Map<String, dynamic>> trendDocs, {
  required DateTime now,
  int days = 7,
  int minCount = 2,
  int limit = 8,
}) {
  final oldest = trendDayKey(now.subtract(Duration(days: days - 1)));
  final newest = trendDayKey(now);

  final totals = <String, int>{};
  for (final doc in trendDocs) {
    final term = (doc['term'] ?? '').toString().trim();
    final perDay = doc['days'];
    if (term.isEmpty || perDay is! Map) continue;
    var total = 0;
    perDay.forEach((day, count) {
      final key = day.toString();
      // 'YYYY-MM-DD' strings sort the same way the dates do.
      if (key.compareTo(oldest) >= 0 &&
          key.compareTo(newest) <= 0 &&
          count is num) {
        total += count.toInt();
      }
    });
    if (total >= minCount) totals[term] = (totals[term] ?? 0) + total;
  }

  final ranked = totals.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [for (final entry in ranked.take(limit)) entry.key];
}
