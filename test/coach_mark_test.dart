// The first-time tour: a bouncing arrow and a short label at each button,
// moved along by the user's own taps, never blocking them, and waiting
// while a popup is in front.
import 'package:agritrade/widgets/coach_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final addKey = GlobalKey();
  final ordersKey = GlobalKey();
  final steps = [
    CoachMarkStep(
      targetKey: addKey,
      title: 'List your first product',
      message: 'Tap here anytime to post crops.',
    ),
    CoachMarkStep(
      targetKey: ordersKey,
      title: 'Track incoming orders',
      message: 'Orders from buyers show up here.',
    ),
  ];

  Future<BuildContext> pumpHome(
    WidgetTester tester, {
    required VoidCallback onAdd,
  }) async {
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            home = context;
            return Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(height: 40),
                  TextButton(
                    key: ordersKey,
                    onPressed: () {},
                    child: const Text('Orders'),
                  ),
                  TextButton(
                    key: addKey,
                    onPressed: onAdd,
                    child: const Text('Add'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return home;
  }

  testWidgets('taps move the tour along and still work', (tester) async {
    var added = 0;
    final home = await pumpHome(tester, onAdd: () => added++);
    var finished = false;
    showCoachMarksOnce(
      context: home,
      prefsKey: 'walkthrough_seen_test',
      steps: steps,
    ).then((_) => finished = true);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('List your first product'), findsOneWidget);
    // No dark screen over the page.
    expect(find.byType(ModalBarrier), findsOneWidget); // the page's own

    // Tapping the button itself works, and brings up the next hint.
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(added, 1);
    expect(find.text('List your first product'), findsNothing);
    expect(find.text('Track incoming orders'), findsOneWidget);

    // Any tap, anywhere, ends it.
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
    expect(find.text('Track incoming orders'), findsNothing);
    expect(finished, isTrue);
  });

  testWidgets('waits while a popup is in front', (tester) async {
    final home = await pumpHome(tester, onAdd: () {});
    showDialog<void>(
      context: home,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your Market tab'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    showCoachMarksOnce(
      context: home,
      prefsKey: 'walkthrough_seen_popup_test',
      steps: steps,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);

    // Closing the popup does not count as a step.
    await tester.tap(find.text('Got it'));
    // (The arrow keeps bouncing, so the page never "settles".)
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('List your first product'), findsOneWidget);

    // Finish the tour so nothing is left running.
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump();
  });

  testWidgets('shown once per device', (tester) async {
    SharedPreferences.setMockInitialValues({'walkthrough_seen_test': true});
    final home = await pumpHome(tester, onAdd: () {});
    await showCoachMarksOnce(
      context: home,
      prefsKey: 'walkthrough_seen_test',
      steps: steps,
    );
    await tester.pump();
    expect(find.text('List your first product'), findsNothing);
  });
}
