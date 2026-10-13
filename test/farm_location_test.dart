// "Use my location" on Farmer Registration: recognizing a barangay from a
// looked-up address, deciding whether a position is in Laurel, and what
// the map confirmation screen shows and lets through.
import 'package:agritrade/data/laurel_barangay_match.dart';
import 'package:agritrade/data/laurel_barangays.dart';
import 'package:agritrade/screen/confirm_farm_location_screen.dart';
import 'package:agritrade/services/geocoding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Real OpenStreetMap answers for three points in Laurel.
const osmBugaan = {
  'neighbourhood': 'Barangay 2',
  'village': 'Bugaan East',
  'town': 'Laurel',
  'state': 'Batangas',
  'region': 'Calabarzon',
  'country_code': 'ph',
};
const osmSanGabriel = {
  'village': 'San Gabriel',
  'town': 'Laurel',
  'state': 'Batangas',
  'region': 'Calabarzon',
  'country_code': 'ph',
};
const osmNiyugan = {
  'hamlet': 'Mamimilit',
  'village': 'Niyugan',
  'town': 'Laurel',
  'state': 'Batangas',
  'country_code': 'ph',
};

Future<FarmLocationResult?> pumpScreen(
  WidgetTester tester,
  Future<ResolvedAddress?> Function(double, double) lookup, {
  double lat = kLaurelCenterLat,
  double lng = kLaurelCenterLng,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FarmLocationResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.push<FarmLocationResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => ConfirmFarmLocationScreen(
                    initialLat: lat,
                    initialLng: lng,
                    lookup: lookup,
                    mapBuilder: (_) => const ColoredBox(color: Colors.grey),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('barangay names', () {
    test('every listed barangay matches itself', () {
      for (final name in kLaurelBarangays) {
        expect(laurelBarangayNamed(name), name);
      }
    });

    test('spelling, spacing and abbreviations are evened out', () {
      expect(laurelBarangayNamed('  san   gabriel '), 'San Gabriel');
      expect(laurelBarangayNamed('Sta. Maria'), 'Santa Maria');
      expect(laurelBarangayNamed('STA MARIA'), 'Santa Maria');
      expect(laurelBarangayNamed('Busobuso'), 'Buso-buso');
      expect(laurelBarangayNamed('As Is'), 'As-Is');
      expect(laurelBarangayNamed('Brgy. 2'), 'Barangay 2');
      expect(laurelBarangayNamed('Poblacion 3'), 'Barangay 3');
      expect(laurelBarangayNamed('Jose Leviste'), 'J. Leviste');
      expect(laurelBarangayNamed('Barangay Gulod'), 'Gulod');
    });

    test('a name that is not one of Laurel\'s matches nothing', () {
      for (final other in ['Mamimilit', 'Talisay', 'Barangay 9', 'San', '']) {
        expect(laurelBarangayNamed(other), isNull);
      }
      expect(laurelBarangayNamed(null), isNull);
    });

    test('a barangay is only matched when the fields agree on one', () {
      expect(matchLaurelBarangay(['Mamimilit', 'Niyugan']), 'Niyugan');
      expect(
        matchLaurelBarangay(['San Gabriel', 'san gabriel']),
        'San Gabriel',
      );
      // Two different supported barangays in one address: not sure.
      expect(matchLaurelBarangay(['Barangay 2', 'Bugaan East']), isNull);
      expect(matchLaurelBarangay(['Mamimilit', null]), isNull);
      expect(matchLaurelBarangay(const []), isNull);
    });
  });

  group('reading a position', () {
    test('a clear address in Laurel suggests its barangay', () {
      final reading = readFarmLocation(
        parseOsmAddress(osmNiyugan),
        14.072,
        120.9,
      );
      expect(reading.inLaurel, isTrue);
      expect(reading.barangay, 'Niyugan');
      expect(reading.municipality, 'Laurel');
      expect(reading.province, 'Batangas');
    });

    test('an address naming two barangays suggests neither', () {
      final reading = readFarmLocation(
        parseOsmAddress(osmBugaan),
        14.05,
        120.932,
      );
      expect(reading.inLaurel, isTrue);
      expect(reading.barangay, isNull);
    });

    test(
      'another town is outside Laurel, even one with a same-named barangay',
      () {
        final reading = readFarmLocation(
          parseOsmAddress(const {
            'village': 'San Gabriel',
            'town': 'Talisay',
            'state': 'Batangas',
          }),
          // Close enough to pass a distance check on its own.
          kLaurelCenterLat + 0.03,
          kLaurelCenterLng,
        );
        expect(reading.inLaurel, isFalse);
        expect(reading.barangay, isNull);
      },
    );

    test('with no address, only a plainly distant position is turned away', () {
      final near = readFarmLocation(null, kLaurelCenterLat, kLaurelCenterLng);
      expect(near.lookedUp, isFalse);
      expect(near.inLaurel, isTrue);
      expect(near.barangay, isNull);
      // Manila.
      expect(readFarmLocation(null, 14.5995, 120.9842).inLaurel, isFalse);
    });
  });

  group('map confirmation screen', () {
    testWidgets('a matched barangay is suggested and can be confirmed', (
      tester,
    ) async {
      await pumpScreen(tester, (_, _) async => parseOsmAddress(osmSanGabriel));
      expect(find.text('San Gabriel (suggested)'), findsOneWidget);
      expect(find.text('Laurel'), findsOneWidget);
      expect(find.text('Batangas'), findsOneWidget);
      final confirm = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirm Location'),
      );
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('a failed lookup still opens the map, and asks for a pick', (
      tester,
    ) async {
      await pumpScreen(tester, (_, _) async => null);
      expect(find.byType(ColoredBox), findsWidgets); // the map area
      expect(find.text('Not selected'), findsOneWidget);
      expect(find.textContaining('select your Barangay to continue'), findsOne);
      expect(find.text('Select Barangay'), findsOneWidget);
      final confirm = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirm Location'),
      );
      expect(confirm.onPressed, isNull);
    });

    testWidgets('an unclear address gives the agreed message, not a guess', (
      tester,
    ) async {
      await pumpScreen(tester, (_, _) async => parseOsmAddress(osmBugaan));
      expect(
        find.text(
          "We found your location, but couldn't identify your Barangay "
          'automatically. Please select your Barangay to continue.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('(suggested)'), findsNothing);
    });

    testWidgets('picking by hand enables Confirm and is what comes back', (
      tester,
    ) async {
      await pumpScreen(tester, (_, _) async => null);
      await tester.tap(find.text('Select Barangay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gulod'));
      await tester.pumpAndSettle();
      expect(find.text('Gulod'), findsOneWidget);
      expect(find.text('Change Barangay'), findsOneWidget);
      await tester.tap(find.text('Confirm Location'));
      await tester.pumpAndSettle();
      // Back on the screen that opened it.
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Confirm Location'), findsNothing);
    });

    testWidgets('a position outside Laurel cannot be confirmed', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        (_, _) async => parseOsmAddress(const {
          'village': 'Poblacion',
          'city': 'Tanauan',
          'state': 'Batangas',
        }),
        lat: 14.0863,
        lng: 121.1497,
      );
      expect(
        find.text('This location is outside Laurel, Batangas.'),
        findsOneWidget,
      );
      expect(find.text('Select Barangay'), findsNothing);
      final confirm = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirm Location'),
      );
      expect(confirm.onPressed, isNull);
    });
  });
}
