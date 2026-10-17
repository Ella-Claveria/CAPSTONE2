// Manage Account > Active Sessions: which session is this browser's, which
// others are still signed in (and can be revoked), and which have ended.
import 'package:agritrade/services/admin_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final record = {
    'activeSessionId': 'phone-session-000001',
    'lastActiveAt': DateTime(2026, 10, 16, 10, 40),
  };
  final history = [
    (
      id: 'this-browser-0000001',
      data: <String, dynamic>{
        'deviceName': 'Chrome on Windows',
        'platform': 'Windows',
        'location': 'Laurel, Batangas',
        'status': 'active',
        'startedAt': DateTime(2026, 10, 16, 9),
        'lastActiveAt': DateTime(2026, 10, 16, 9),
      },
    ),
    (
      id: 'phone-session-000001',
      data: <String, dynamic>{
        'deviceName': 'Chrome on Android',
        'platform': 'Android',
        'location': 'Unknown',
        'status': 'active',
        'startedAt': DateTime(2026, 10, 16, 10),
        'lastActiveAt': DateTime(2026, 10, 16, 10),
      },
    ),
    (
      id: 'old-session-00000001',
      data: <String, dynamic>{
        'deviceName': 'Edge on Windows',
        'platform': 'Windows',
        'status': 'ended',
        'endReason': 'revoked',
        'startedAt': DateTime(2026, 10, 15, 8),
        'endedAt': DateTime(2026, 10, 15, 9),
      },
    ),
  ];

  test('this browser, other active sessions and ended ones are told apart', () {
    final entries = buildAdminSessionEntries(
      record: record,
      history: history,
      localId: 'this-browser-0000001',
    );
    // Newest first.
    expect(entries.map((e) => e.id), [
      'phone-session-000001',
      'this-browser-0000001',
      'old-session-00000001',
    ]);

    final current = entries.singleWhere((e) => e.isCurrent);
    expect(current.device, 'Chrome on Windows');
    expect(current.location, 'Laurel, Batangas');

    final other = entries.singleWhere((e) => !e.isCurrent && e.active);
    expect(other.onPhone, isTrue);
    // "Unknown" is no location at all.
    expect(other.location, isNull);
    // The active session on record: last heard from by its heartbeat.
    expect(other.lastActiveAt, DateTime(2026, 10, 16, 10, 40));

    final ended = entries.singleWhere((e) => !e.active);
    expect(ended.endLabel, 'Signed out from Active Sessions');
    expect(ended.endedAt, DateTime(2026, 10, 15, 9));
  });

  test('a browser holding no session id has no current session', () {
    final entries = buildAdminSessionEntries(
      record: record,
      history: history,
      localId: null,
    );
    expect(entries.where((e) => e.isCurrent), isEmpty);
  });
}
