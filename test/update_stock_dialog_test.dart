// Farmer Profile → My Products → Update Quantity. Cancelling used to
// crash the dialog ("A TextEditingController was used after being
// disposed"), because the controller was disposed while the dialog was
// still closing. These drive the dialog through each way of leaving it.
import 'package:agritrade/widgets/update_stock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class Host extends StatefulWidget {
  final String unit;
  final num quantity;
  const Host({super.key, this.unit = 'kg', this.quantity = 25});

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  /// Every result the dialog has come back with ('none' for null).
  final results = <String>[];
  final messages = <String>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final result = await showUpdateStockDialog(
              context,
              name: 'Native Tomato',
              currentQuantity: widget.quantity,
              unit: widget.unit,
              onInvalid: (_, message) => messages.add(message),
            );
            results.add(result?.toString() ?? 'none');
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<HostState> pump(
  WidgetTester tester, {
  String unit = 'kg',
  num quantity = 25,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Host(unit: unit, quantity: quantity),
    ),
  );
  return tester.state<HostState>(find.byType(Host));
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('Update Available Stock'), findsOneWidget);
}

/// Taps [label] and then pumps the closing animation one frame at a time,
/// failing on the first frame that throws — which is where the disposed
/// controller used to show up.
Future<void> tapAndClose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull, reason: 'frame $i after $label');
  }
  await tester.pumpAndSettle();
  expect(find.text('Update Available Stock'), findsNothing);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Cancel closes cleanly and saves nothing', (tester) async {
    final host = await pump(tester);
    await open(tester);
    await tapAndClose(tester, 'Cancel');
    expect(host.results, ['none']);
  });

  testWidgets('editing and then cancelling still saves nothing', (
    tester,
  ) async {
    final host = await pump(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField), '999');
    await tapAndClose(tester, 'Cancel');
    expect(host.results, ['none']);
  });

  testWidgets('Save returns the quantity entered', (tester) async {
    final host = await pump(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField), '40.5');
    await tapAndClose(tester, 'Save');
    expect(host.results, ['40.5']);
  });

  testWidgets('an invalid quantity keeps the dialog open and says why', (
    tester,
  ) async {
    final host = await pump(tester);
    await open(tester);
    for (final bad in ['', 'abc', '-3']) {
      await tester.enterText(find.byType(TextField), bad);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Update Available Stock'), findsOneWidget);
    }
    expect(host.messages, hasLength(3));
    expect(host.messages.first, contains('valid, non-negative'));
    expect(host.results, isEmpty);
  });

  testWidgets('a count-based unit takes whole numbers only', (tester) async {
    final host = await pump(tester, unit: 'piece', quantity: 12);
    await open(tester);
    // Shown without decimals.
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(host.messages.single, contains('whole number'));
    await tester.enterText(find.byType(TextField), '30');
    await tapAndClose(tester, 'Save');
    expect(host.results, ['30']);
  });

  testWidgets('opening and cancelling repeatedly never fails', (tester) async {
    final host = await pump(tester);
    for (var i = 0; i < 5; i++) {
      await open(tester);
      await tapAndClose(tester, 'Cancel');
    }
    expect(host.results, List.filled(5, 'none'));
  });

  testWidgets('the Android back button closes it without saving', (
    tester,
  ) async {
    final host = await pump(tester);
    await open(tester);
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('Update Available Stock'), findsNothing);
    expect(host.results, ['none']);
  });

  testWidgets('fits a small phone with the keyboard open, and cancels', (
    tester,
  ) async {
    final host = await pump(tester, size: const Size(360, 640));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await open(tester);
    expect(tester.takeException(), isNull);
    await tapAndClose(tester, 'Cancel');
    expect(host.results, ['none']);
  });
}
