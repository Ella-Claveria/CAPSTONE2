// A pending farmer application on the Admin Portal: who applied, the
// details to check, anything needing a second look, and the decisions.
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/verification_queue_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget card, {double width = 1300}) {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: AdminThemeScope(
        palette: AdminPalette.light,
        child: Scaffold(body: SingleChildScrollView(child: card)),
      ),
    ),
  );
}

FilledButton _approve(WidgetTester tester) => tester.widget<FilledButton>(
  find.ancestor(of: find.text('Approve'), matching: find.byType(FilledButton)),
);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  const profile = {
    'fullName': 'Ellen Gonzales',
    'email': 'ellengonzales64@gmail.com',
    'barangay': 'San Gabriel',
    'rsbaNumber': '04-10-12-034-000123',
  };

  testWidgets('shows the applicant, the details and the decisions', (
    tester,
  ) async {
    await _pump(
      tester,
      const FarmerApplicationCard(uid: 'a', profile: profile, verif: null),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Ellen Gonzales'), findsOneWidget);
    expect(find.text('Pending Review'), findsOneWidget);
    for (final label in ['RSBA NO.', 'EMAIL', 'BARANGAY', 'SUBMITTED']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('San Gabriel'), findsOneWidget);
    expect(find.text('View Details'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(_approve(tester).onPressed, isNotNull);
  });

  testWidgets('points out a shared RSBA No.; fits a narrow window', (
    tester,
  ) async {
    await _pump(
      tester,
      const FarmerApplicationCard(
        uid: 'b',
        profile: profile,
        verif: null,
        sameFarmerId: ['Juan Cruz'],
      ),
      width: 700,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text('This RSBA No. is also on another farmer account: Juan Cruz.'),
      findsOneWidget,
    );
  });

  testWidgets('with nothing to check, Approve is unavailable', (tester) async {
    await _pump(
      tester,
      const FarmerApplicationCard(
        uid: 'c',
        profile: {'fullName': 'No Number'},
        verif: null,
      ),
    );
    expect(_approve(tester).onPressed, isNull);
    expect(find.textContaining('nothing to check'), findsOneWidget);
  });
}
