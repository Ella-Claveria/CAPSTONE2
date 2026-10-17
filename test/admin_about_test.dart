// About AgriTrade+: what the platform is, its two parts, and the project
// details — with placeholders, never made-up names, until they are given.
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_info_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'AgriTrade+',
      packageName: 'agritrade',
      version: '1.0.0',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminAbout(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(1280, 800), const Size(400, 640)]) {
    testWidgets('shows the platform, its parts and the project at '
        '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      await open(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.text('About AgriTrade+'), findsOneWidget);
      expect(
        find.text('Agricultural & Livestock Trading Platform'),
        findsOneWidget,
      );
      expect(find.text('Mobile Application'), findsOneWidget);
      expect(find.text('Admin Portal'), findsOneWidget);
      // The build's version is read once per run, in the first test.
      if (size.width > 1000) expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('Academic Capstone Project'), findsOneWidget);
      // Not given yet: marked, not invented.
      expect(find.text('[Project team name — to be provided]'), findsOne);
      expect(find.text('[School name — to be provided]'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('About AgriTrade+'), findsNothing);
    });
  }
}
