// "Leave This Process?" must be the user's to answer: a request that
// finishes while it is on screen may not close it, navigate, or change the
// screen behind it. These drive a stand-in for the Forgot Password screen
// (same guard, same EmailLeaveConfirm.whenResolved pattern) with a request
// the test completes by hand.
import 'dart:async';

import 'package:agritrade/widgets/email_request_leave_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The request in flight; completing it with null means "sent", with a
/// message means it failed.
late Completer<String?> request;

class _ResetScreen extends StatefulWidget {
  const _ResetScreen();

  @override
  State<_ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<_ResetScreen> {
  final _leaveConfirm = EmailLeaveConfirm();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  Future<void> _send() async {
    setState(() => _sending = true);
    final error = await request.future;
    if (!mounted) return;
    _leaveConfirm.whenResolved(() {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error;
        _sent = error == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return EmailRequestLeaveGuard(
      processing: _sending,
      confirm: _leaveConfirm,
      child: Scaffold(
        body: Column(
          children: [
            Text(_sent ? 'Check Your Email' : 'Reset your password'),
            if (_sending) const Text('sending'),
            if (_error != null) Text(_error!),
            TextButton(onPressed: _send, child: const Text('Send Reset Link')),
          ],
        ),
      ),
    );
  }
}

const question = 'Leave This Process?';

Future<NavigatorState> startRequest(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  request = Completer<String?>();
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Text('login'))),
  );
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.push(MaterialPageRoute(builder: (_) => const _ResetScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send Reset Link'));
  await tester.pump();
  expect(find.text('sending'), findsOneWidget);
  return nav;
}

Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute(); // the Android back button
  await tester.pumpAndSettle();
}

Future<void> finishRequest(WidgetTester tester, [String? error]) async {
  request.complete(error);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String answer) async {
  await tester.tap(find.text(answer));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('1. Back while loading, Stay before it finishes', (tester) async {
    await startRequest(tester);
    await pressBack(tester);
    expect(find.text(question), findsOneWidget);

    await choose(tester, 'Stay');
    expect(find.text(question), findsNothing);
    expect(find.text('sending'), findsOneWidget);

    await finishRequest(tester);
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. Back while loading, request finishes, then Stay', (
    tester,
  ) async {
    await startRequest(tester);
    await pressBack(tester);
    await finishRequest(tester);

    // The question is still up and the screen behind it has not moved on.
    expect(find.text(question), findsOneWidget);
    expect(find.text('Check Your Email'), findsNothing);
    expect(find.text('sending'), findsOneWidget);

    await choose(tester, 'Stay');
    expect(find.text(question), findsNothing);
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.text('sending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3. Back while loading, request finishes, then Leave', (
    tester,
  ) async {
    await startRequest(tester);
    await pressBack(tester);
    await finishRequest(tester);
    expect(find.text(question), findsOneWidget);

    await choose(tester, 'Leave');
    expect(find.text(question), findsNothing);
    expect(find.text('login'), findsOneWidget);
    expect(find.text('Check Your Email'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('4. Back while loading, Leave at once', (tester) async {
    await startRequest(tester);
    await pressBack(tester);
    await choose(tester, 'Leave');
    expect(find.text('login'), findsOneWidget);

    // The request finishing later changes nothing and throws nothing.
    await finishRequest(tester);
    expect(find.text('login'), findsOneWidget);
    expect(find.text(question), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. No Back: the request finishes normally', (tester) async {
    final nav = await startRequest(tester);
    await finishRequest(tester);
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.text(question), findsNothing);

    // Nothing is processing any more, so Back just goes back.
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text(question), findsNothing);
    expect(find.text('login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('6. The request fails while the question is open', (
    tester,
  ) async {
    await startRequest(tester);
    await pressBack(tester);
    await finishRequest(tester, 'No internet connection.');

    expect(find.text(question), findsOneWidget);
    expect(find.text('No internet connection.'), findsNothing);

    await choose(tester, 'Stay');
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('sending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back twice never stacks two questions', (tester) async {
    final nav = await startRequest(tester);
    await nav.maybePop();
    await tester.pump();
    await nav.maybePop(); // closes the question (same as Stay)
    await tester.pumpAndSettle();
    expect(find.text(question), findsNothing);
    expect(find.text('sending'), findsOneWidget);

    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text(question), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
