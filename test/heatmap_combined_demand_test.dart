// The Demand Heatmap shows one demand: completed purchases and buyer
// searches together, a purchase counting twice a search (Objective 4.1.2 —
// "where buyers search and purchase products").
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchases and searches add up per area, purchases weigh more', () {
    final combined = DashboardAnalyticsService.combinedDemandByArea(
      [
        (area: 'Poblacion', orderCount: 3, revenue: 900, lat: 14.0, lng: 120.9),
        (area: 'Ticub', orderCount: 1, revenue: 200, lat: 14.1, lng: 121.0),
      ],
      [
        (area: 'Ticub', searches: 6, lat: null, lng: null),
        (area: 'Gulod', searches: 2, lat: 14.2, lng: 121.1),
      ],
    );
    // Ticub: 1×2 + 6 = 8; Poblacion: 3×2 = 6; Gulod: 2.
    expect([for (final a in combined) a.area], ['Ticub', 'Poblacion', 'Gulod']);
    expect(combined.first.score, 8);
    expect(combined.first.purchases, 1);
    expect(combined.first.searches, 6);
    // An area searched but never bought from still shows, with its place.
    expect(combined.last.lat, 14.2);
    // The purchase side's location is kept.
    expect(combined.first.lat, 14.1);
  });
}
