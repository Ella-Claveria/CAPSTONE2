// The splash screen's walking-farmer loader: one walk across while the app
// starts (then he stands at the end), and standing still when the phone
// has animations turned off.
import 'package:agritrade/widgets/branded_loading_screen.dart';
import 'package:agritrade/widgets/walking_farmer_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WalkingFarmerLoader.resetWalk);

  testWidgets('walks across once, then stands at the end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WalkingFarmerLoader), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue); // still walking

    // After the one crossing nothing moves any more — he does not start
    // over.
    await tester.pump(WalkingFarmerLoader.crossing);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('nothing to wait for when he never set off', () async {
    await WalkingFarmerLoader.untilWalkDone().timeout(
      const Duration(milliseconds: 100),
    );
  });

  testWidgets('the splash can wait until he reaches the end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    var done = false;
    WalkingFarmerLoader.untilWalkDone().then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isFalse); // still walking

    await tester.pump(WalkingFarmerLoader.crossing);
    expect(done, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('stands still with animations off', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: WalkingFarmerLoader()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
