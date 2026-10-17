// The "allow notifications" explanation uses the app's own popup, and its
// two buttons are stacked, the same size, with the main choice on top.
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
    // Wide enough for the test font (much wider than Montserrat) to fit
    // "Enable Notifications" on one line, as Montserrat does on a phone.
    tester.view.physicalSize = const Size(480, 700);
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
    // Stacked: the main choice on top, each label on one line.
    expect(
      tester.getTopLeft(find.widgetWithText(AgriDialogButton, 'Not Now')).dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.widgetWithText(AgriDialogButton, 'Enable Notifications'),
            )
            .dy,
      ),
    );
    expect(enable.height, lessThan(60));

    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
