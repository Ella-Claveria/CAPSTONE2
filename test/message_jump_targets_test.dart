import 'package:agritrade/screen/conversation_tools_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in chat: a reversed, lazily built message list (like ChatScreen)
/// whose items are wrapped by MessageJumpTargets, plus an (i) button that
/// pushes an info page which can return a message id to jump to.
class _FakeChat extends StatefulWidget {
  const _FakeChat();

  @override
  State<_FakeChat> createState() => _FakeChatState();
}

class _FakeChatState extends State<_FakeChat> {
  final _scroll = ScrollController();
  final _targets = MessageJumpTargets();
  bool? lastJumpFound;

  @override
  void dispose() {
    _scroll.dispose();
    _targets.dispose();
    super.dispose();
  }

  Future<void> _openInfo() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Conversation Info')),
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.pop(context, 'm150'),
              child: const Text('result m150'),
            ),
          ),
        ),
      ),
    );
    if (id == null || !mounted) return;
    lastJumpFound = await _targets.jumpTo(_scroll, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            key: const Key('info'),
            icon: const Icon(Icons.info_outline),
            onPressed: _openInfo,
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scroll,
        reverse: true,
        itemCount: 200,
        itemBuilder: (context, i) => _targets.wrap(
          'm$i',
          SizedBox(height: 60, child: Text('message $i')),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Chat → Info → Back, repeatedly, without framework errors', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeChat()));

    for (var round = 0; round < 5; round++) {
      await tester.tap(find.byKey(const Key('info')));
      await tester.pumpAndSettle();
      expect(find.text('Conversation Info'), findsOneWidget);

      // Alternate the AppBar back button and the system back.
      if (round.isEven) {
        await tester.tap(find.byType(BackButton));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.text('Chat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a search result jumps to an older message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FakeChat()));
    expect(find.text('message 150'), findsNothing);

    await tester.tap(find.byKey(const Key('info')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('result m150'));
    await tester.pumpAndSettle();

    final state = tester.state<_FakeChatState>(find.byType(_FakeChat));
    expect(state.lastJumpFound, isTrue);
    expect(find.text('message 150'), findsOneWidget);
    // The highlight clears itself.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the chat right after a jump is safe', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _FakeChat()),
            ),
            child: const Text('open chat'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('info')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('result m150'));
    await tester.pumpAndSettle();
    // Leave the chat while the 2-second highlight timer is still pending.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
