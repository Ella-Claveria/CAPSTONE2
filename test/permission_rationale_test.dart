// The "allow notifications" explanation uses the app's own popup, and its
// two buttons are the same size even when one label wraps.
import 'package:agritrade/widgets/agri_dialog.dart';
import 'package:agritrade/widgets/permission_rationale_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Not Now and Enable Notifications are the same size', (
    tester,
  ) async {
    // A small phone, where "Enable Notifications" does not fit on one line.
    tester.view.physicalSize = const Size(340, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showPermissionRationale(
                  context,
                  icon: Icons.notifications_active_outlined,
                  title: 'Stay Updated with AgriTrade+',
                  message: 'Allow notifications to receive important updates.',
                  denyLabel: 'Not Now',
                  allowLabel: 'Enable Notifications',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The shared popup design.
    expect(find.byType(AgriDialog), findsOneWidget);
    expect(find.byType(AgriFrostedCard), findsOneWidget);

    final notNow = tester.getSize(
      find.widgetWithText(AgriDialogButton, 'Not Now'),
    );
    final enable = tester.getSize(
      find.widgetWithText(AgriDialogButton, 'Enable Notifications'),
    );
    expect(notNow.width, enable.width);
    expect(notNow.height, enable.height);

    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
