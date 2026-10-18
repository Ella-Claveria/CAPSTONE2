// Report Delay: the reason from a dropdown, a box for "Other" (at most 100
// characters), and Send to Buyer only once it can be sent — closing with
// what was filled in, and without errors after it has closed.
import 'package:agritrade/screen/order_actions.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  const order = OrderInfo('o1', {
    'status': 'confirmed',
    'buyerName': 'Junior Pesigan',
  });

  testWidgets('Other needs its reason; Send returns what was filled in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DelayReport? report;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                report = await showModalBottomSheet<DelayReport>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: ReportDelaySheet(order: order),
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

    ElevatedButton send() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Send to Buyer'),
    );

    // A dropdown, no "Other" box yet, and nothing to send without a date.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Weather / Natural Disaster'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Specify the reason'), findsNothing);
    expect(send().onPressed, isNull);

    // Choose Other: its box appears, at most 100 characters.
    await tester.tap(find.text('Weather / Natural Disaster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    final other = find.widgetWithText(TextField, 'Specify the reason');
    expect(other, findsOneWidget);
    expect(tester.widget<TextField>(other).maxLength, 100);

    // A date, but Other still needs its reason.
    await tester.tap(find.text('Choose a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(send().onPressed, isNull);

    await tester.enterText(other, 'Truck broke down');
    await tester.pump();
    expect(send().onPressed, isNotNull);

    await tester.tap(find.text('Send to Buyer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(report, isNotNull);
    expect(report!.reason, 'other');
    expect(report!.otherReason, 'Truck broke down');
  });

  test('the reason shown is the farmer\'s own words for Other', () {
    expect(
      const OrderInfo('o', {
        'delay': {'reason': 'other', 'otherReason': 'Truck broke down'},
      }).delayReasonLabel,
      'Truck broke down',
    );
    expect(
      const OrderInfo('o', {
        'delay': {'reason': 'weather'},
      }).delayReasonLabel,
      'Weather / Natural Disaster',
    );
  });
}
