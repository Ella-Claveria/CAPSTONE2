import 'package:agritrade/screen/buyer_market_view.dart';
import 'package:agritrade/services/public_farm_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a real Philippine coordinate is accepted', () {
    // Laurel, Batangas.
    expect(isValidPublicCoordinate(14.0445, 120.9320), isTrue);
  });

  test('missing, zero and out-of-range coordinates are rejected', () {
    expect(isValidPublicCoordinate(null, 120.9), isFalse);
    expect(isValidPublicCoordinate(14.0, null), isFalse);
    expect(isValidPublicCoordinate(0, 0), isFalse);
    expect(isValidPublicCoordinate(95, 120.9), isFalse);
    expect(isValidPublicCoordinate(14.0, 190), isFalse);
    expect(isValidPublicCoordinate(double.nan, 120.9), isFalse);
  });

  test('latitude and longitude the wrong way round are rejected', () {
    expect(isValidPublicCoordinate(120.9320, 14.0445), isFalse);
  });

  test('a point outside the Philippines is rejected', () {
    // Europe / Africa / the Americas — never a farm area here.
    expect(isValidPublicCoordinate(48.85, 2.35), isFalse);
    expect(isValidPublicCoordinate(-1.29, 36.82), isFalse);
    expect(isValidPublicCoordinate(37.42, -122.08), isFalse);
  });

  test('the map only tries to hold buyer and farm when they are near', () {
    expect(shouldFitBuyerAndFarm(4.8), isTrue);
    expect(shouldFitBuyerAndFarm(120), isTrue);
    // e.g. an emulator reporting a location in another country.
    expect(shouldFitBuyerAndFarm(11000), isFalse);
    expect(shouldFitBuyerAndFarm(null), isFalse);
  });
}
