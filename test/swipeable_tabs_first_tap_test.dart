import 'package:agritrade/widgets/docked_nav_bar.dart';
import 'package:agritrade/widgets/swipeable_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A home screen in miniature: a bottom bar whose taps set the tab, and the
// tabs as SwipeableTabs pages.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: DockedNavBar(
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _index = i),
              child: Center(child: Text('nav$i')),
            ),
          ),
      ],
    ),
    body: SwipeableTabs(
      index: _index,
      onIndexChanged: (i) => setState(() => _index = i),
      children: [for (var i = 0; i < 4; i++) Center(child: Text('page$i'))],
    ),
  );
}

void main() {
  // The first tap after the home screen opens (e.g. right after login)
  // used to do nothing; only a second tap changed the tab.
  for (final first in [1, 2, 3]) {
    testWidgets('the very first tap on tab $first opens it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Shell()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('nav$first'));
      await tester.pumpAndSettle();

      expect(find.text('page$first'), findsOneWidget);
      expect(find.text('page0'), findsNothing);
    });
  }
}
