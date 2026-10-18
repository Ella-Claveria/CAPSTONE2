// Manage Account: one plain list without duplicates (Notification
// Settings and Help & Support live in the Profile menu), no dark mode and
// no language switch — the app is English only.
import 'package:agritrade/screen/manage_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('no duplicates, no dark mode, no language switch', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'AgriTrade+',
      packageName: 'agritrade',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ManageAccountScreen(recoveryEmailVerified: Stream.value(false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage Account'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.textContaining('Notification'), findsNothing);
    expect(find.text('Help & Support'), findsNothing);
    expect(find.textContaining('Dark mode'), findsNothing);
    expect(find.textContaining('Language'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });
}
