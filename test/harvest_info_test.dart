import 'package:agritrade/services/harvest_info.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 3, 15, 30);

  test('label is derived only from the farmer-provided date', () {
    expect(harvestLabel(DateTime(2026, 10, 3, 6), now: now), 'Harvested today');
    // Calendar days, not 24-hour periods.
    expect(
      harvestLabel(DateTime(2026, 10, 2, 23, 59), now: now),
      'Harvested 1 day ago',
    );
    expect(
      harvestLabel(DateTime(2026, 10, 1), now: now),
      'Harvested 2 days ago',
    );
    expect(
      harvestLabel(DateTime(2026, 9, 26), now: now),
      'Harvested 7 days ago',
    );
    expect(
      harvestLabel(DateTime(2026, 9, 25), now: now),
      'Harvested on Sep 25, 2026',
    );
  });

  test('"Recently Harvested" means within the last two days', () {
    expect(isRecentlyHarvested(DateTime(2026, 10, 3), now: now), isTrue);
    expect(isRecentlyHarvested(DateTime(2026, 10, 1), now: now), isTrue);
    expect(isRecentlyHarvested(DateTime(2026, 9, 30), now: now), isFalse);
    expect(isRecentlyHarvested(DateTime(2026, 10, 4), now: now), isFalse);
  });

  test('harvest wording is for produce only', () {
    final harvestDate = Timestamp.fromDate(DateTime(2026, 10, 3));
    expect(
      harvestDateOf({'category': 'Vegetables', 'harvestDate': harvestDate}),
      DateTime(2026, 10, 3),
    );
    expect(
      harvestDateOf({'category': 'Livestock', 'harvestDate': harvestDate}),
      isNull,
    );
    expect(harvestDateOf({'category': 'Fruits'}), isNull);
  });
}
