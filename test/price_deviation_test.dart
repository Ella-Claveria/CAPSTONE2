import 'package:agritrade/services/price_deviation.dart';
import 'package:flutter_test/flutter_test.dart';

PriceDeviation? _evaluate(double price, {bool limitedData = false}) =>
    PriceDeviation.evaluate(
      price: price,
      lower: 180,
      upper: 206.09,
      dataAvailability: limitedData ? 'Limited Data' : 'Moderate Data',
      limitedData: limitedData,
    );

void main() {
  test('price inside the suggested range gives no warning', () {
    expect(_evaluate(200), isNull);
    expect(_evaluate(206.09), isNull);
    expect(_evaluate(180), isNull);
  });

  test('about 5% above is a mild warning with no confirmation', () {
    final deviation = _evaluate(216.39)!;
    expect(deviation.isAbove, isTrue);
    expect(deviation.level, PriceDeviationLevel.mild);
    expect(deviation.needsConfirmation, isFalse);
    expect(deviation.shouldFlag, isFalse);
  });

  test('21.3% above needs confirmation but is not flagged', () {
    final deviation = _evaluate(250)!;
    expect(deviation.percentLabel, '21.3');
    expect(deviation.level, PriceDeviationLevel.confirm);
    expect(deviation.needsConfirmation, isTrue);
    expect(deviation.shouldFlag, isFalse);
    expect(deviation.comparisonPrice, 206.09);
  });

  test('more than 25% above needs confirmation and is flagged', () {
    final deviation = _evaluate(300)!;
    expect(deviation.level, PriceDeviationLevel.strong);
    expect(deviation.needsConfirmation, isTrue);
    expect(deviation.shouldFlag, isTrue);
  });

  test('up to 10% below is a mild warning with no confirmation', () {
    final deviation = _evaluate(170)!;
    expect(deviation.isAbove, isFalse);
    expect(deviation.level, PriceDeviationLevel.mild);
    expect(deviation.needsConfirmation, isFalse);
  });

  test('12.5% below needs confirmation', () {
    final deviation = PriceDeviation.evaluate(
      price: 140,
      lower: 160,
      upper: 200,
      dataAvailability: 'Moderate Data',
      limitedData: false,
    )!;
    expect(deviation.percentLabel, '12.5');
    expect(deviation.level, PriceDeviationLevel.confirm);
    expect(deviation.needsConfirmation, isTrue);
    expect(deviation.comparisonPrice, 160);
    expect(deviation.shouldFlag, isFalse);
  });

  test('more than 25% below is strong but never flagged', () {
    final deviation = _evaluate(90)!;
    expect(deviation.isAbove, isFalse);
    expect(deviation.percentLabel, '50.0');
    expect(deviation.level, PriceDeviationLevel.strong);
    expect(deviation.needsConfirmation, isTrue);
    expect(deviation.shouldFlag, isFalse);
  });

  test('a confirmation covers the same price but not a meaningful change', () {
    final deviation = _evaluate(250)!;
    expect(deviation.coveredBy(250, PriceDeviationLevel.confirm), isTrue);
    expect(deviation.coveredBy(245, PriceDeviationLevel.confirm), isTrue);
    expect(deviation.coveredBy(220, PriceDeviationLevel.confirm), isFalse);
    expect(deviation.coveredBy(250, PriceDeviationLevel.strong), isFalse);
  });
}
