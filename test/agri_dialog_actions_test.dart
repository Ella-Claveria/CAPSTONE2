import 'package:agritrade/widgets/agri_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(
  WidgetTester tester,
  List<Widget> actions, {
  bool stacked = false,
}) async {
  // A typical phone.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AgriDialog(
          icon: Icons.info_outline_rounded,
          title: const Text('Account already registered'),
          content: const Text('Please log in to continue.'),
          stackedActions: stacked,
          actions: actions,
        ),
      ),
    ),
  );
  await tester.pump();
}

AgriDialogButton _button(String label, [AgriButtonKind? kind]) =>
    AgriDialogButton(
      label: label,
      kind: kind ?? AgriButtonKind.secondary,
      onPressed: () {},
    );

Rect _rect(WidgetTester tester, String label) => tester.getRect(
  find.ancestor(of: find.text(label), matching: find.byType(AgriDialogButton)),
);

void main() {
  // The test font draws every character as a square, so labels are kept
  // short here to fit half the popup.
  testWidgets('short labels sit side by side, slim', (tester) async {
    await _show(tester, [
      _button('Cancel'),
      _button('Login', AgriButtonKind.primary),
    ]);
    final cancel = _rect(tester, 'Cancel');
    final login = _rect(tester, 'Login');
    expect(cancel.top, login.top);
    expect(cancel.left, lessThan(login.left));
    expect(cancel.height, closeTo(40, 1.5));
    expect(login.height, closeTo(40, 1.5));
  });

  testWidgets('a label too long for half the popup stacks the pair, main '
      'action on top, without growing taller', (tester) async {
    await _show(tester, [
      _button('Register a different email'),
      _button('Go to Login', AgriButtonKind.primary),
    ]);
    final other = _rect(tester, 'Register a different email');
    final login = _rect(tester, 'Go to Login');
    expect(login.bottom, lessThanOrEqualTo(other.top));
    expect(login.width, other.width);
    expect(login.height, closeTo(40, 1.5));
    expect(other.height, closeTo(40, 1.5));
  });

  testWidgets('stackedActions keeps one layout for any set of buttons', (
    tester,
  ) async {
    await _show(stacked: true, tester, [
      _button('Cancel'),
      _button('Go to Login', AgriButtonKind.primary),
    ]);
    final cancel = _rect(tester, 'Cancel');
    final login = _rect(tester, 'Go to Login');
    expect(login.bottom, lessThanOrEqualTo(cancel.top));
    expect(login.width, cancel.width);
  });
}
