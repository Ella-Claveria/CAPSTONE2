// The two registration pieces that can be checked without Firebase: the
// RSBA number rules, and the searchable "Select Barangay" sheet.
import 'package:agritrade/data/laurel_barangays.dart';
import 'package:agritrade/services/rsba_number.dart';
import 'package:agritrade/widgets/barangay_location_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

String typed(String text) {
  var value = TextEditingValue(text: text);
  for (final TextInputFormatter formatter in kRsbaInputFormatters) {
    value = formatter.formatEditUpdate(TextEditingValue.empty, value);
  }
  return value.text;
}

Widget pickerHost(ValueChanged<String?> onResult, {String? selected}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              onResult(await showBarangayPicker(context, selected: selected)),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('RSBA number', () {
    test('15 to 17 letters and numbers is valid', () {
      expect(isValidRsba('A' * 14), isFalse);
      expect(isValidRsba('A' * 15), isTrue);
      expect(isValidRsba('0410340120001234'), isTrue);
      expect(isValidRsba('AB12' * 4 + 'C'), isTrue); // 17
      expect(isValidRsba('A' * 18), isFalse);
      expect(isValidRsba('04-10-34-012-0001'), isFalse);
      expect(isValidRsba(''), isFalse);
    });

    test('stored without spaces around it, in capitals', () {
      expect(normalizeRsba('  ab12cd34ef56gh7 '), 'AB12CD34EF56GH7');
      expect(isValidRsba('ab12cd34ef56gh7'), isTrue);
    });

    test('nothing is flagged while the number is still being typed', () {
      expect(rsbaError(''), isNull);
      expect(rsbaError('ABC123'), isNull);
    });

    test('an unfinished number is an error once the field is left', () {
      expect(rsbaError('ABC123', touched: true), kRsbaInvalidMessage);
      expect(rsbaError('ABC123', submitted: true), kRsbaInvalidMessage);
      expect(rsbaError('A' * 15, touched: true), isNull);
      expect(rsbaError('', submitted: true), 'RSBA No. is required.');
    });

    test('no message spells out the accepted length', () {
      for (final text in [kRsbaHint, kRsbaInvalidMessage, kRsbaLabel]) {
        expect(text.contains('15'), isFalse);
        expect(text.contains('17'), isFalse);
      }
    });

    test('the field keeps out symbols and stops at the longest length', () {
      expect(typed('04-10 34_012.0001'), '0410340120001');
      expect(typed('abc'), 'ABC');
      expect(typed('1' * 30).length, kRsbaMaxLength);
    });
  });

  group('Select Barangay sheet', () {
    testWidgets('lists every Laurel barangay and returns the one tapped', (
      tester,
    ) async {
      String? result = 'unset';
      await tester.pumpWidget(pickerHost((value) => result = value));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Select Barangay'), findsOneWidget);
      expect(find.text(kLaurelBarangays.first), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bugaan');
      await tester.pumpAndSettle();
      expect(find.text('Bugaan East'), findsOneWidget);
      expect(find.text('Bugaan West'), findsOneWidget);
      expect(find.text(kLaurelBarangays.first), findsNothing);

      await tester.tap(find.text('Bugaan West'));
      await tester.pumpAndSettle();
      expect(result, 'Bugaan West');
      expect(find.text('Select Barangay'), findsNothing);
    });

    testWidgets('closing it chooses nothing', (tester) async {
      String? result = 'unset';
      await tester.pumpWidget(
        pickerHost((value) => result = value, selected: 'Gulod'),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('a search with no match says so', (tester) async {
      await tester.pumpWidget(pickerHost((_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'manila');
      await tester.pumpAndSettle();
      expect(find.textContaining('No barangay in Laurel matches'), findsOne);
    });

    testWidgets('the current barangay is marked', (tester) async {
      await tester.pumpWidget(pickerHost((_) {}, selected: 'As-Is'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('fits a small phone with the keyboard open', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(pickerHost((_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Select Barangay'), findsOneWidget);
    });
  });
}
