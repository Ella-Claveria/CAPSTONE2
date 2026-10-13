// The Admin Portal's timing logs and loading skeletons: timing must never
// change what a query returns, and a skeleton must be the size of the card
// it stands in for.
import 'dart:async';

import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_overview_widgets.dart';
import 'package:agritrade/services/admin_perf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminPerf', () {
    late List<String> logs;
    late void Function(String? message, {int? wrapWidth}) original;

    setUp(() {
      logs = [];
      original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
    });
    tearDown(() => debugPrint = original);

    test('time returns the result unchanged and logs it once', () async {
      final result = await AdminPerf.time(
        'orders',
        () async => [1, 2, 3],
        describe: (r) => '${r.length} docs',
      );
      expect(result, [1, 2, 3]);
      expect(logs.single, startsWith('[AdminPerf] orders: '));
      expect(logs.single, endsWith('— 3 docs'));
    });

    test('a failure is logged and rethrown unchanged', () async {
      await expectLater(
        AdminPerf.time<int>('reports', () async => throw StateError('denied')),
        throwsStateError,
      );
      expect(logs.single, contains('reports'));
      expect(logs.single, contains('FAILED'));
    });

    test('a slow query is tagged SLOW', () async {
      await AdminPerf.time('big', () async {
        await Future<void>.delayed(
          AdminPerf.slow + const Duration(milliseconds: 60),
        );
        return 0;
      });
      expect(logs.single, startsWith('[AdminPerf] SLOW big: '));
    });

    test(
      'firstEvent passes every event through and logs only the first',
      () async {
        final events = await AdminPerf.firstEvent(
          'users stream',
          Stream.fromIterable(['a', 'b', 'c']),
          describe: (e) => 'got $e',
        ).toList();
        expect(events, ['a', 'b', 'c']);
        expect(logs.length, 1);
        expect(logs.single, contains('users stream, first snapshot'));
        expect(logs.single, endsWith('— got a'));
      },
    );
  });

  testWidgets('a chart skeleton is exactly the size of the card it replaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          onToggleTheme: () {},
          child: const Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: AdminChartCardSkeleton()),
                Expanded(
                  child: AdminChartCard(
                    title: 'Sales Performance',
                    subtitle: 'Monthly sales from completed orders',
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(AdminChartCardSkeleton)).height,
      tester.getSize(find.byType(AdminChartCard)).height,
    );
    // The shimmer animates forever; stop it before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
