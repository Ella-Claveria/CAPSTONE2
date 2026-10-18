// The Market tab's first-time hints: nothing until the farmer scrolls, then
// one hint per card as it comes into view — in order, one at a time — and
// each only once.
import 'package:agritrade/widgets/market_tab_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MarketTabHints> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hints = MarketTabHints(currentUid: () => 'farmer-1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification ||
                    n is ScrollEndNotification) {
                  hints.onScroll(
                    context,
                    userScroll:
                        n is ScrollUpdateNotification && n.dragDetails != null,
                  );
                }
                return false;
              },
              child: ListView(
                children: [
                  // Like the welcome header and stats above the cards.
                  const SizedBox(height: 300),
                  for (var i = 0; i < 4; i++) ...[
                    Container(
                      key: hints.keys[i],
                      height: 300,
                      color: Colors.green.shade50,
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return hints;
  }

  // Lets the hints' storage reads and frames run (the arrow keeps
  // bouncing, so the page never "settles").
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder titled(int i) => find.text(kMarketGuideItems[i].title);

  testWidgets('nothing until the farmer scrolls; then the cards in order', (
    tester,
  ) async {
    await pumpTab(tester);
    await settle(tester);
    // The first card is in place already, but nothing shows on opening.
    expect(titled(0), findsNothing);

    // A small scroll: the first card's hint, and only that one.
    await tester.drag(find.byType(ListView), const Offset(0, -20));
    await settle(tester);
    expect(titled(0), findsOneWidget);
    expect(titled(1), findsNothing);

    // Scrolling on past it puts it away, and the next card's hint comes
    // when that card is in view — never two at once.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await settle(tester);
    expect(titled(0), findsNothing);
    expect(titled(1), findsOneWidget);
    expect(titled(2), findsNothing);

    // A tap puts it away too; the next one waits for its card.
    await tester.tapAt(const Offset(200, 700));
    await settle(tester);
    expect(titled(1), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await settle(tester);
    expect(titled(2), findsOneWidget);

    await tester.tapAt(const Offset(200, 700));
    await settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await settle(tester);
    expect(titled(3), findsOneWidget);
    await tester.tapAt(const Offset(200, 700));
    await settle(tester);
    expect(titled(3), findsNothing);

    // All four shown: remembered for this account.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('market_tab_hints_next_farmer-1'), 4);
  });

  testWidgets('already seen: nothing more', (tester) async {
    SharedPreferences.setMockInitialValues({
      'market_tab_hints_next_farmer-1': 4,
    });
    await pumpTab(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -20));
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      expect(titled(i), findsNothing);
    }
  });
}
