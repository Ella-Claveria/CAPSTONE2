// Security → Devices & Sign-In Activity: what the list shows, which device
// can be removed, and that removing is confirmed first.
import 'package:agritrade/screen/sign_in_activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

final devices = [
  SignInDevice(
    id: 'this',
    name: 'samsung SM-A166P',
    platform: 'Android',
    firstSeen: DateTime(2026, 9, 1, 8),
    lastSeen: DateTime(2026, 10, 9, 14),
  ),
  SignInDevice(
    id: 'other',
    name: 'Google Pixel 8',
    platform: 'Android',
    firstSeen: DateTime(2026, 10, 9, 13),
    lastSeen: DateTime(2026, 10, 9, 13),
  ),
];

Future<List<String>> pump(
  WidgetTester tester, {
  String? highlight,
  List<SignInDevice>? list,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final removed = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: SignInActivityScreen(
        highlightDeviceId: highlight,
        devices: Stream.value(list ?? devices),
        currentDeviceId: Future.value('this'),
        removeDevice: (id) async => removed.add(id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return removed;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('lists the devices and says alerts do not block login', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('New Device Login Alerts'), findsOneWidget);
    expect(find.textContaining('The login itself is not blocked'), findsOne);
    expect(find.text('samsung SM-A166P'), findsOneWidget);
    expect(find.text('Google Pixel 8'), findsOneWidget);
    expect(find.textContaining('First logged in: Oct 9, 2026'), findsOne);
  });

  testWidgets('this device is marked and cannot be removed', (tester) async {
    await pump(tester);
    expect(find.text('This device'), findsOneWidget);
    // Only the other device has a Remove button.
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('the device an alert was about is pointed out', (tester) async {
    await pump(tester, highlight: 'other');
    expect(find.text('New login'), findsOneWidget);
  });

  testWidgets('removing asks first, and says it does not sign out', (
    tester,
  ) async {
    final removed = await pump(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not sign that device out'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
    await tester.pumpAndSettle();
    expect(removed, ['other']);
  });

  testWidgets('an account with no recorded devices says so', (tester) async {
    await pump(tester, list: const []);
    expect(find.text('No devices recorded yet.'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
  });
}
