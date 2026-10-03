import 'package:agritrade/screen/buyer_market_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distance is always worded as approximate', () {
    expect(approxDistanceLabel(4.83), 'Approx. 4.8 km away');
    expect(approxDistanceLabel(0.42), 'Approx. 0.4 km away');
    expect(approxDistanceLabel(9.96), 'Approx. 10.0 km away');
  });

  test('longer distances are rounded to whole kilometres', () {
    expect(approxDistanceLabel(12.4), 'Approx. 12 km away');
    expect(approxDistanceLabel(57.6), 'Approx. 58 km away');
  });

  test('very close reads as less than 0.1 km, never 0.0', () {
    expect(approxDistanceLabel(0.03), 'Approx. less than 0.1 km away');
  });

  test('no buyer location or no farm area', () {
    expect(approxDistanceLabel(null), 'Distance unavailable');
  });
}
