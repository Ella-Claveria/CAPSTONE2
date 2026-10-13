import 'package:agritrade/data/ph_locations_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a geocoder city name matches its PSGC spelling', () {
    expect(phPlaceKey('Tanauan City'), phPlaceKey('City of Tanauan'));
    expect(phPlaceKey('Malvar'), phPlaceKey('Malvar'));
    expect(phPlaceKey('Santo Tomas'), phPlaceKey('City of Sto. Tomas'));
    expect(phPlaceKey('Dasmariñas'), phPlaceKey('City of Dasmarinas'));
  });

  test('a geocoder barangay name matches its PSGC spelling', () {
    expect(phPlaceKey('Poblacion'), phPlaceKey('Poblacion (Pob.)'));
    expect(phPlaceKey('Brgy. San Pedro I'), phPlaceKey('San Pedro I'));
    expect(phPlaceKey('Barangay 1'), phPlaceKey('Barangay 1 (Pob.)'));
  });

  test('different places stay different', () {
    expect(phPlaceKey('San Pedro I'), isNot(phPlaceKey('San Pedro II')));
    expect(phPlaceKey('Santa Rosa'), isNot(phPlaceKey('Santo Tomas')));
  });

  test('only one match counts as a detected barangay', () {
    final service = PhLocationsService.instance;
    const barangays = [
      PhBarangay(code: '1', name: 'Poblacion (Pob.)'),
      PhBarangay(code: '2', name: 'San Andres'),
      PhBarangay(code: '3', name: 'San Andres (Pob.)'),
    ];
    expect(service.matchBarangay(barangays, 'Poblacion')?.code, '1');
    expect(service.matchBarangay(barangays, 'San Andres'), isNull);
    expect(service.matchBarangay(barangays, 'Bagong Pook'), isNull);
  });
}
