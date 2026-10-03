import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Harvest information on a product listing (`products/{id}.harvestDate`).
///
/// It is whatever date the farmer entered — the app never inspects the
/// photo or judges freshness itself. Everything shown to buyers is derived
/// from that one date by the plain rules below.

/// The categories that have a harvest date. Livestock and the rest don't
/// get a harvest field or "harvested N days ago" wording.
const Set<String> kHarvestDateCategories = {'Vegetables', 'Fruits'};

bool categoryHasHarvestDate(String? category) =>
    kHarvestDateCategories.contains(category?.trim());

/// A product's harvest date, if its category has one and the farmer set it.
DateTime? harvestDateOf(Map<String, dynamic> product) {
  if (!categoryHasHarvestDate(product['category']?.toString())) return null;
  final value = product['harvestDate'];
  return value is Timestamp ? value.toDate() : null;
}

int _daysSince(DateTime harvested, DateTime now) => DateTime(
  now.year,
  now.month,
  now.day,
).difference(DateTime(harvested.year, harvested.month, harvested.day)).inDays;

/// "Harvested today", "Harvested 1 day ago", "Harvested 2 days ago" … up
/// to a week; after that (or for a date entered in the future) the date
/// itself: "Harvested on Oct 1, 2026".
String harvestLabel(DateTime harvested, {DateTime? now}) {
  final days = _daysSince(harvested, now ?? DateTime.now());
  if (days == 0) return 'Harvested today';
  if (days == 1) return 'Harvested 1 day ago';
  if (days > 1 && days <= 7) return 'Harvested $days days ago';
  return 'Harvested on ${DateFormat('MMM d, y').format(harvested)}';
}

/// "Recently Harvested" means exactly this: the farmer's harvest date is
/// today or within the last two days.
bool isRecentlyHarvested(DateTime harvested, {DateTime? now}) {
  final days = _daysSince(harvested, now ?? DateTime.now());
  return days >= 0 && days <= 2;
}
