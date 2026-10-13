import 'package:agritrade/services/admin_device_location.dart';
import 'package:agritrade/services/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the place is named barangay, municipality, province', () {
    expect(
      adminLocationLabel(
        const ResolvedAddress(
          barangay: 'Poblacion',
          city: 'Laurel',
          province: 'Batangas',
        ),
      ),
      'Poblacion, Laurel, Batangas',
    );
    // Whatever part the lookup found is used.
    expect(
      adminLocationLabel(
        const ResolvedAddress(city: 'Laurel', province: 'Batangas'),
      ),
      'Laurel, Batangas',
    );
  });

  test('no address is no location', () {
    expect(adminLocationLabel(null), isNull);
    expect(adminLocationLabel(const ResolvedAddress()), isNull);
  });

  test('the phone app is never asked for it', () async {
    expect(await AdminDeviceLocation.current(), isNull);
  });
}
