// Verifying a recovery email: a 6-digit code sent to it, entered in a
// popup — a wrong code says so, the right one closes it as verified.
import 'package:agritrade/services/recovery_email_service.dart';
import 'package:agritrade/widgets/recovery_email_code_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeService implements RecoveryEmailService {
  final codes = <String>[];

  @override
  Future<RecoveryCodeRequest> requestCode(String email) async =>
      const RecoveryCodeRequest(sent: true, resendAfterSeconds: 60);

  @override
  Future<String?> confirmCode(String code) async {
    codes.add(code);
    return code == '123456' ? null : 'Incorrect verification code.';
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('a wrong code says so; the right one verifies', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeService();
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await verifyRecoveryEmail(
                context,
                'juan.backup@gmail.com',
                service: service,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Verify Recovery Email'), findsOneWidget);
    expect(find.text('juan.backup@gmail.com'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '111111');
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Incorrect verification code.'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '123456');
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Verify Recovery Email'), findsNothing);
    expect(result, isTrue);
    expect(service.codes, ['111111', '123456']);
  });

  testWidgets('the status reads Verified or Not verified', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            RecoveryEmailStatusChip(verified: true),
            RecoveryEmailStatusChip(verified: false),
          ],
        ),
      ),
    );
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
  });
}
