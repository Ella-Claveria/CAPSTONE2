import 'package:agritrade/services/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> component(
  String name,
  List<String> types, {
  String? short,
}) => {'long_name': name, 'short_name': short ?? name, 'types': types};

Map<String, dynamic> result(List<Map<String, dynamic>> components) => {
  'address_components': components,
};

void main() {
  final philippines = component('Philippines', [
    'country',
    'political',
  ], short: 'PH');

  test(
    'Malvar, Batangas: municipality, province and region in the right places',
    () {
      final addr = parseGeocodeResults([
        result([
          component('San Pioquinto', [
            'sublocality_level_1',
            'sublocality',
            'political',
          ]),
          component('Malvar', ['locality', 'political']),
          component('Batangas', ['administrative_area_level_2', 'political']),
          component('Calabarzon', ['administrative_area_level_1', 'political']),
          philippines,
        ]),
      ]);
      expect(addr.barangay, 'San Pioquinto');
      expect(addr.city, 'Malvar');
      // The province — not the region, which is what level_1 is here.
      expect(addr.province, 'Batangas');
      expect(addr.region, 'Calabarzon');
      expect(addr.countryCode, 'PH');
    },
  );

  test('pieces missing from the top result are taken from later ones', () {
    final addr = parseGeocodeResults([
      // A plus-code / street result with almost nothing in it.
      result([
        component('3525+XR', ['plus_code']),
        philippines,
      ]),
      result([
        component('Malvar', ['locality', 'political']),
        component('Batangas', ['administrative_area_level_2', 'political']),
        component('Calabarzon', ['administrative_area_level_1', 'political']),
        philippines,
      ]),
    ]);
    expect(addr.city, 'Malvar');
    expect(addr.province, 'Batangas');
    expect(addr.barangay, isNull);
    expect(addr.isEmpty, isFalse);
  });

  test('Metro Manila has no province level: the region stands in', () {
    final addr = parseGeocodeResults([
      result([
        component('Quezon City', ['locality', 'political']),
        component('Metro Manila', ['administrative_area_level_1', 'political']),
        philippines,
      ]),
    ]);
    expect(addr.city, 'Quezon City');
    expect(addr.province, 'Metro Manila');
  });

  test('a missing field does not discard the rest', () {
    final addr = parseGeocodeResults([
      result([
        component('Batangas', ['administrative_area_level_2', 'political']),
        philippines,
      ]),
    ]);
    expect(addr.city, isNull);
    expect(addr.province, 'Batangas');
    expect(addr.countryCode, 'PH');
  });

  test('nothing usable gives an empty address, not a crash', () {
    expect(parseGeocodeResults(const []).isEmpty, isTrue);
    expect(parseGeocodeResults([result(const [])]).isEmpty, isTrue);
  });
}
