// Change Password in two steps: the passwords, then the 6-digit code sent
// to the login email — a wrong current password stops at step one, and
// the password only changes with the right code.
import 'package:agritrade/services/password_change_service.dart';
import 'package:agritrade/widgets/change_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeService implements PasswordChangeService {
  final calls = <String>[];

  @override
  String get email => 'juan@gmail.com';

  @override
  Future<PasswordCodeRequest> requestCode({String? currentPassword}) async {
    calls.add('request:${currentPassword ?? '-'}');
    if (currentPassword != null && currentPassword != 'OldPassword1!') {
      return const PasswordCodeRequest(error: 'Current password is incorrect.');
    }
    return const PasswordCodeRequest(sent: true, resendAfterSeconds: 60);
  }

  @override
  Future<String?> confirm({
    required String code,
    required String newPassword,
  }) async {
    calls.add('confirm:$code:$newPassword');
    return code == '123456' ? null : 'Incorrect verification code.';
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('passwords, then the emailed code', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeService();
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => changed = await showChangePasswordDialog(
                context,
                service: service,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'WrongPass1!');
    await tester.enterText(fields.at(1), 'NewPassword12!');
    await tester.enterText(fields.at(2), 'NewPassword12!');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(find.text('Confirm Password Change'), findsNothing);

    await tester.enterText(fields.at(0), 'OldPassword1!');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Confirm Password Change'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '123456');
    await tester.pump();
    await tester.tap(find.text('Change Password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(changed, isTrue);
    expect(service.calls.last, 'confirm:123456:NewPassword12!');
  });
}
