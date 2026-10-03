import 'package:agritrade/main.dart' show rootNavigatorKey;
import 'package:agritrade/widgets/agri_dialog.dart';
import 'package:agritrade/widgets/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same root as AgriTradeApp (main.dart): the one rootNavigatorKey, and
/// the same `builder` wrapper around the Navigator.
Widget _app(Widget home) => MaterialApp(
  navigatorKey: rootNavigatorKey,
  home: home,
  builder: (context, child) => ConnectivityBanner(
    child: Listener(
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => KeyEventResult.ignored,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  ),
);

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const _Chat()),
        ),
        child: const Text('open chat'),
      ),
    ),
  );
}

class _Chat extends StatelessWidget {
  const _Chat();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chat'),
      actions: [
        IconButton(
          key: const Key('info'),
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('Info'))),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: 50,
            itemBuilder: (_, i) => ListTile(title: Text('message $i')),
          ),
        ),
        const TextField(
          key: Key('composer'),
          minLines: 1,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
        ),
      ],
    ),
  );
}

void main() {
  testWidgets(
    'tapping the chat input and opening the keyboard keeps one root Navigator',
    (tester) async {
      await tester.pumpWidget(_app(const _Home()));
      await tester.tap(find.text('open chat'));
      await tester.pumpAndSettle();

      for (var round = 0; round < 3; round++) {
        await tester.tap(find.byKey(const Key('composer')));
        // The keyboard sliding up/down changes the view insets over several
        // frames.
        for (final inset in [80.0, 200.0, 320.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.enterText(find.byKey(const Key('composer')), 'a\nb\nc');
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('info')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      expect(find.byType(Navigator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeatedly opening and closing popups keeps one root Navigator',
    (tester) async {
      await tester.pumpWidget(_app(const _Popups()));
      for (var round = 0; round < 4; round++) {
        await tester.tap(find.text('dialog'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('sheet'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archived'));
        await tester.pumpAndSettle();

        // System back with nothing open must not break the root either.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(find.byType(Navigator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Popups extends StatelessWidget {
  const _Popups();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        Builder(
          builder: (buttonContext) => IconButton(
            key: const Key('menu'),
            icon: const Icon(Icons.menu),
            onPressed: () => showAgriPopupMenu<String>(
              anchorContext: buttonContext,
              items: const [
                AgriMenuItem(
                  value: 'archived',
                  icon: Icons.archive_outlined,
                  label: 'Archived',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        TextButton(
          onPressed: () => showAgriConfirm(
            context: context,
            title: 'Confirm?',
            message: 'Test',
            confirmLabel: 'OK',
          ),
          child: const Text('dialog'),
        ),
        TextButton(
          onPressed: () => showAgriSheet<void>(
            context: context,
            builder: (sheetContext) => AgriSheetAction(
              icon: Icons.check,
              label: 'Pick',
              onTap: () => Navigator.pop(sheetContext),
            ),
          ),
          child: const Text('sheet'),
        ),
      ],
    ),
  );
}
