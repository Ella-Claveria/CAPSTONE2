// Sales Performance's y-axis: round steps, and a top that is a whole
// number of steps, so no two axis labels land on top of each other.
import 'package:agritrade/screen/market_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round steps with the top on a step', () {
    expect(salesChartScale(560), (max: 600.0, step: 200.0));
    expect(salesChartScale(100), (max: 150.0, step: 50.0));
    expect(salesChartScale(4800), (max: 6000.0, step: 2000.0));
    expect(salesChartScale(0), (max: 100.0, step: 25.0));
  });

  test('the best day always fits under the top', () {
    for (final best in [1.0, 37.0, 560.0, 999.0, 1234.0, 75000.0]) {
      final scale = salesChartScale(best);
      expect(scale.max, greaterThanOrEqualTo(best));
      expect(
        scale.max / scale.step,
        closeTo((scale.max / scale.step).round(), 1e-9),
      );
      expect(scale.max / scale.step, inInclusiveRange(2, 6));
    }
  });

  test('the welcome card shows the first name only', () {
    expect(firstNameOf('Daniella Claveria'), 'Daniella');
    expect(firstNameOf('  Juan Carlos Dela Cruz '), 'Juan');
    expect(firstNameOf('Ana'), 'Ana');
    expect(firstNameOf(''), 'Farmer');
  });
}
