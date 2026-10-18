// The farmer's reply box on a review: typed and sent right on the card,
// with no popup — and no error once it is sent.
import 'package:agritrade/screen/farmer_reviews_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _Review {
  final updates = <String>[];
  Future<void> send(String reply) async => updates.add(reply);
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pump(WidgetTester tester, _Review review, String existing) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewReplyBox(existing: existing, onSend: review.send),
          ),
        ),
      );

  testWidgets('type and send right on the card', (tester) async {
    final review = _Review();
    await pump(tester, review, '');

    // The box is there at once — no Reply button to open first.
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    IconButton send() => tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.send_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(send().onPressed, isNull); // nothing typed yet

    await tester.enterText(field, '  Thank you for buying!  ');
    await tester.pump();
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(review.updates.single, 'Thank you for buying!');
  });

  testWidgets('a saved reply can be edited, and left as it was', (
    tester,
  ) async {
    final review = _Review();
    await pump(tester, review, 'Thank you!');
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Edit reply'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Thank you!'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(review.updates, isEmpty);
  });
}
