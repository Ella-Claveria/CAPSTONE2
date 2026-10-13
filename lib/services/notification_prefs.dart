import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The kinds of notification a user can switch on or off. The keys are
/// the ones saved under `users/{uid}.notificationPrefs` and read by the
/// server before it sends a push (functions/notification_policy.js).
enum NotificationPref {
  /// The master switch: off stops every push.
  push('push'),
  orders('orders'),
  messages('messages'),

  /// Verification, warnings, account status, sign-in alerts. Shown, but
  /// always on: these are about the account's safety and standing.
  account('account'),
  system('system');

  const NotificationPref(this.key);
  final String key;

  bool get alwaysOn => this == NotificationPref.account;

  String get label => switch (this) {
    NotificationPref.push => 'Push Notifications',
    NotificationPref.orders => 'Order Updates',
    NotificationPref.messages => 'Messages',
    NotificationPref.account => 'Account & Verification Updates',
    NotificationPref.system => 'System Announcements',
  };

  String get description => switch (this) {
    NotificationPref.push =>
      'Alerts on this phone, even when AgriTrade+ is closed.',
    NotificationPref.orders =>
      'New orders, confirmations, shipping and completed orders.',
    NotificationPref.messages => 'New chat messages.',
    NotificationPref.account =>
      'Verification status, warnings and login alerts. Always on, and '
          'also sent by email.',
    NotificationPref.system => 'Announcements and maintenance notices.',
  };
}

/// A user's saved notification preferences. A switch that was never
/// touched is on. Pure, so it can be tested without Firestore.
class NotificationPrefs {
  final Map<String, bool> _saved;
  const NotificationPrefs([this._saved = const {}]);

  factory NotificationPrefs.fromUser(Map<String, dynamic>? user) {
    final raw = user?['notificationPrefs'];
    return NotificationPrefs({
      if (raw is Map)
        for (final entry in raw.entries)
          if (entry.value is bool) entry.key.toString(): entry.value as bool,
    });
  }

  bool isOn(NotificationPref pref) =>
      pref.alwaysOn || (_saved[pref.key] ?? true);

  /// Whether the phone is buzzed for [pref]: its own switch, and the
  /// master one. The notification is saved in the app either way.
  bool pushes(NotificationPref pref) =>
      isOn(NotificationPref.push) && isOn(pref);
}

/// Reads and saves the signed-in user's [NotificationPrefs] on their own
/// account record.
class NotificationPrefsService {
  NotificationPrefsService._();

  static DocumentReference<Map<String, dynamic>>? _user() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Stream<NotificationPrefs> watch() {
    final user = _user();
    if (user == null) return Stream.value(const NotificationPrefs());
    return user.snapshots().map(
      (snap) => NotificationPrefs.fromUser(snap.data()),
    );
  }

  /// Saves one switch. Throws if it could not be saved.
  static Future<void> set(NotificationPref pref, bool on) async {
    final user = _user();
    if (user == null || pref.alwaysOn) return;
    await user.update({'notificationPrefs.${pref.key}': on});
  }
}
