// System messages: 2 seconds each, and a new one replaces the one showing
// instead of waiting behind it; a message with a button keeps its time.
import 'package:agritrade/widgets/app_scaffold_messenger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('2 seconds, newest replaces the one showing', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScaffoldMessenger(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('A')));
    await tester.pump();
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('B')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
  });

  test('a message with a button keeps its own time', () {
    final withAction = SnackBar(
      content: const Text('x'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    expect(identical(shortenedSnackBar(withAction), withAction), isTrue);
    expect(
      shortenedSnackBar(const SnackBar(content: Text('x'))).duration,
      AppScaffoldMessenger.shortDuration,
    );
  });
}
