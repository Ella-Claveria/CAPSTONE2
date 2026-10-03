import 'package:agritrade/services/search_trends.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 4 Oct 2026, 10:00 in the Philippines.
  final now = DateTime.utc(2026, 10, 4, 2);

  Map<String, dynamic> trend(String term, Map<String, int> days) => {
    'term': term,
    'days': days,
  };

  test('days are filed in Philippine time', () {
    expect(trendDayKey(DateTime.utc(2026, 10, 3, 15, 59)), '2026-10-03');
    expect(trendDayKey(DateTime.utc(2026, 10, 3, 16)), '2026-10-04');
  });

  test('ranks by searches in the last 7 days, most searched first', () {
    final terms = topTrendingTerms([
      trend('kamote', {'2026-10-04': 2, '2026-10-01': 1}),
      trend('native chicken', {'2026-10-03': 5}),
      trend('ube', {'2026-10-02': 2}),
    ], now: now);
    expect(terms, ['native chicken', 'kamote', 'ube']);
  });

  test('old activity does not count', () {
    final terms = topTrendingTerms([
      // Exactly 7 days back (28 Sep - 4 Oct) is the oldest day counted.
      trend('kamote', {'2026-09-28': 2}),
      trend('cassava', {'2026-09-27': 40, '2026-08-01': 90}),
    ], now: now);
    expect(terms, ['kamote']);
  });

  test('a single search is not a trend, and no data means no section', () {
    expect(
      topTrendingTerms([
        trend('kamote', {'2026-10-04': 1}),
      ], now: now),
      isEmpty,
    );
    expect(topTrendingTerms(const [], now: now), isEmpty);
  });

  test('shows at most eight terms', () {
    final terms = topTrendingTerms([
      for (var i = 0; i < 12; i++) trend('term $i', {'2026-10-04': 2 + i}),
    ], now: now);
    expect(terms.length, 8);
    expect(terms.first, 'term 11');
  });

  test('ignores malformed documents', () {
    final terms = topTrendingTerms([
      {
        'term': '',
        'days': {'2026-10-04': 9},
      },
      {'term': 'kamote'},
      {
        'term': 'ube',
        'days': {'2026-10-04': 'many'},
      },
      trend('saging', {'2026-10-04': 3}),
    ], now: now);
    expect(terms, ['saging']);
  });
}
