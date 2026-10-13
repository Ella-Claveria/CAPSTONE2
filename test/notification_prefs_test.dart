import 'package:agritrade/services/notification_permission_prompt.dart';
import 'package:agritrade/services/notification_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing saved: every notification is on', () {
    const prefs = NotificationPrefs();
    for (final pref in NotificationPref.values) {
      expect(prefs.isOn(pref), isTrue, reason: pref.key);
      expect(prefs.pushes(pref), isTrue, reason: pref.key);
    }
  });

  test('a category switched off stays off, and only that one', () {
    final prefs = NotificationPrefs.fromUser({
      'notificationPrefs': {'orders': false},
    });
    expect(prefs.isOn(NotificationPref.orders), isFalse);
    expect(prefs.isOn(NotificationPref.messages), isTrue);
    expect(prefs.pushes(NotificationPref.orders), isFalse);
    expect(prefs.pushes(NotificationPref.messages), isTrue);
  });

  test('account notices cannot be switched off', () {
    final prefs = NotificationPrefs.fromUser({
      'notificationPrefs': {'account': false},
    });
    expect(NotificationPref.account.alwaysOn, isTrue);
    expect(prefs.isOn(NotificationPref.account), isTrue);
  });

  test('the master switch stops every push', () {
    final prefs = NotificationPrefs.fromUser({
      'notificationPrefs': {'push': false},
    });
    expect(prefs.isOn(NotificationPref.push), isFalse);
    for (final pref in NotificationPref.values) {
      expect(prefs.pushes(pref), isFalse, reason: pref.key);
    }
  });

  test('anything that is not a switch is ignored', () {
    final prefs = NotificationPrefs.fromUser({
      'notificationPrefs': {'orders': 'no', 'messages': null},
    });
    expect(prefs.isOn(NotificationPref.orders), isTrue);
    expect(prefs.isOn(NotificationPref.messages), isTrue);
    expect(
      NotificationPrefs.fromUser(null).isOn(NotificationPref.push),
      isTrue,
    );
  });

  test('the keys are the ones the server reads', () {
    expect(
      [for (final pref in NotificationPref.values) pref.key],
      ['push', 'orders', 'messages', 'account', 'system'],
    );
  });

  test('the reason is given before the phone is asked', () {
    expect(kNotificationRationaleTitle, 'Stay Updated');
    expect(
      kNotificationRationaleMessage,
      'Allow notifications to receive important updates about your account, '
      'orders, messages, verification status, and other AgriTrade+ '
      'activities.',
    );
  });
}
