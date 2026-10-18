import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../services/notification_permission_prompt.dart';
import '../services/notification_prefs.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/permission_rationale_dialog.dart';
import '../l10n/tr.dart';

/// Profile → Notification Preferences: which notifications also buzz the
/// phone. Every notification is still kept in the app's Notifications
/// list, whatever is switched off here.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen>
    with WidgetsBindingObserver {
  final Stream<NotificationPrefs> _prefs = NotificationPrefsService.watch();

  // What the phone itself allows; null until it has been read.
  AuthorizationStatus? _permission;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the phone's own settings: the answer may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readPermission();
  }

  Future<void> _readPermission() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (mounted) setState(() => _permission = settings.authorizationStatus);
    } catch (_) {}
  }

  bool get _allowedByPhone =>
      _permission == AuthorizationStatus.authorized ||
      _permission == AuthorizationStatus.provisional;

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _set(NotificationPref pref, bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Push is the phone's to allow first. It is explained before the
      // phone is asked, and only asked when the user chose to turn it on.
      if (pref == NotificationPref.push && on && !_allowedByPhone) {
        final proceed = await showPermissionRationale(
          context,
          icon: Icons.notifications_active_outlined,
          title: kNotificationRationaleTitle,
          message: kNotificationRationaleMessage,
          denyLabel: 'Not Now',
          allowLabel: 'Allow',
        );
        if (!proceed) return;
        await PushNotificationService().setupFCM(requestPermission: true);
        await _readPermission();
        if (!_allowedByPhone) {
          if (mounted) {
            _say('Push notifications are disabled in device settings.');
          }
          return;
        }
      }
      await NotificationPrefsService.set(pref, on);
      // On again: make sure this phone is on the account's list.
      if (pref == NotificationPref.push && on) {
        await PushNotificationService().setupFCM();
      }
    } catch (_) {
      if (mounted) _say('Could not save this setting. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AgriAppBar(title: tr(context).notificationSettings),
      body: StreamBuilder<NotificationPrefs>(
        stream: _prefs,
        builder: (context, snapshot) {
          final prefs = snapshot.data ?? const NotificationPrefs();
          final blockedByPhone = _permission != null && !_allowedByPhone;
          final pushOn = prefs.isOn(NotificationPref.push) && !blockedByPhone;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _card([
                _switch(
                  NotificationPref.push,
                  value: pushOn,
                  onChanged: (on) => _set(NotificationPref.push, on),
                ),
                if (blockedByPhone)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.red[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Push notifications are disabled in device '
                            'settings.',
                            style: AppTheme.body(
                              size: 12.5,
                            ).copyWith(color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              _card([
                for (final pref in const [
                  NotificationPref.orders,
                  NotificationPref.messages,
                  NotificationPref.account,
                  NotificationPref.system,
                ])
                  _switch(
                    pref,
                    value: prefs.isOn(pref),
                    // Nothing to choose while push itself is off, and
                    // account notices cannot be switched off at all.
                    onChanged: pref.alwaysOn || !pushOn
                        ? null
                        : (on) => _set(pref, on),
                  ),
              ]),
              const SizedBox(height: 14),
              Text(
                'Every notification is kept in your Notifications list, '
                'even when its alert is switched off here. Important '
                'account notices are also sent to your email.',
                style: AppTheme.body(
                  size: 12.5,
                ).copyWith(color: Colors.grey[600]),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
    ),
    child: Column(children: children),
  );

  Widget _switch(
    NotificationPref pref, {
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: _busy ? null : onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: AppTheme.dark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        pref.label,
        style: AppTheme.body(size: 14.5).copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          pref.description,
          style: AppTheme.body(size: 12.5).copyWith(color: Colors.grey[600]),
        ),
      ),
    );
  }
}
