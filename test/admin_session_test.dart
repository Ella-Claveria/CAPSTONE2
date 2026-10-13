import 'package:agritrade/screen/admin_notifications.dart';
import 'package:agritrade/services/admin_session_service.dart';
import 'package:agritrade/services/audit_log_service.dart';
import 'package:agritrade/widgets/admin_session_dialogs.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 11, 21);
  Map<String, dynamic> record({
    String id = 'session-a',
    String status = 'active',
    Duration quietFor = const Duration(minutes: 1),
  }) => {
    'activeSessionId': id,
    'sessionStatus': status,
    'lastActiveAt': Timestamp.fromDate(now.subtract(quietFor)),
  };

  group('is the account in use on another device (asked at login)', () {
    test('no session on record: no', () {
      expect(adminSessionActiveElsewhere(null, null, now: now), isFalse);
    });

    test('another browser, in use: yes', () {
      expect(adminSessionActiveElsewhere(record(), null, now: now), isTrue);
      expect(
        adminSessionActiveElsewhere(record(), 'session-b', now: now),
        isTrue,
      );
    });

    test('this same browser: no', () {
      expect(
        adminSessionActiveElsewhere(record(), 'session-a', now: now),
        isFalse,
      );
    });

    test('logged out there: no', () {
      expect(
        adminSessionActiveElsewhere(record(status: 'ended'), null, now: now),
        isFalse,
      );
    });

    test('left open and gone quiet: no', () {
      expect(
        adminSessionActiveElsewhere(
          record(
            quietFor:
                AdminSessionService.staleAfter + const Duration(minutes: 1),
          ),
          null,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('a browser coming back already logged in', () {
    test('holds the active session: stays in', () {
      expect(
        adminSessionStanding(record(), 'session-a', now: now),
        AdminSessionStanding.current,
      );
    });

    test('was replaced by a login elsewhere: ended here', () {
      expect(
        adminSessionStanding(record(id: 'session-b'), 'session-a', now: now),
        AdminSessionStanding.endedHere,
      );
      // Even after the other one has gone quiet: it was still replaced.
      expect(
        adminSessionStanding(
          record(id: 'session-b', quietFor: const Duration(hours: 5)),
          'session-a',
          now: now,
        ),
        AdminSessionStanding.endedHere,
      );
    });

    test('no session on record: free to become it', () {
      expect(
        adminSessionStanding(null, null, now: now),
        AdminSessionStanding.free,
      );
      expect(
        adminSessionStanding(null, 'session-a', now: now),
        AdminSessionStanding.free,
      );
    });

    test('remembers no session id while one is in use: not turned away', () {
      expect(
        adminSessionStanding(record(), null, now: now),
        AdminSessionStanding.free,
      );
    });

    test('never held one and the other has gone quiet: free', () {
      expect(
        adminSessionStanding(
          record(quietFor: const Duration(hours: 2)),
          null,
          now: now,
        ),
        AdminSessionStanding.free,
      );
    });
  });

  test('the session events are audit actions', () {
    expect(
      AuditAction.all,
      containsAll([
        AuditAction.newDeviceLogin,
        AuditAction.sessionReplaced,
        AuditAction.sessionForcedLogout,
      ]),
    );
  });

  test('a login is a notification; a session picked up again is not', () {
    final items = buildAdminNotifications(
      orders: const [],
      users: const [],
      reports: const [],
      announcements: const [],
      signIns: [
        (
          id: 'session-b',
          data: {
            'startedAt': Timestamp.fromDate(
              now.subtract(const Duration(minutes: 5)),
            ),
            'deviceName': 'Chrome on Windows',
            'newDevice': true,
          },
        ),
        (
          id: 'session-c',
          data: {
            'startedAt': Timestamp.fromDate(
              now.subtract(const Duration(minutes: 3)),
            ),
            'deviceName': 'Edge on Windows',
            'announced': false,
          },
        ),
      ],
      now: now,
    );
    expect(items, hasLength(1));
    expect(items.single.title, 'New Admin login detected');
    expect(items.single.detail, contains('new device'));
    expect(items.single.detail, contains('Chrome on Windows'));
    expect(items.single.target, AdminNotificationTarget.auditLog);
  });

  testWidgets('the conflict popup offers Cancel and Continue', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                answer = await showAdminSessionConflictDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Account already logged in'), findsOneWidget);
    expect(
      find.text(
        'This Admin account is currently active on another device. '
        'Continuing will sign out the previous session.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue & Sign Out Other Device'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('the ended popup says why and returns to login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAdminSessionEndedDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Session ended'), findsOneWidget);
    expect(
      find.text('Your Admin account was logged in on another device.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(find.text('Session ended'), findsNothing);
  });
}
