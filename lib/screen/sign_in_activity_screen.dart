import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/device_trust_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/agri_dialog.dart';

/// One device the account has signed in on, as shown in the list.
class SignInDevice {
  final String id;
  final String name;
  final String platform;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  const SignInDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.firstSeen,
    this.lastSeen,
  });

  factory SignInDevice.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    DateTime? date(String key) {
      final value = data[key];
      return value is Timestamp ? value.toDate() : null;
    }

    final name = (data['deviceName'] ?? '').toString().trim();
    return SignInDevice(
      id: doc.id,
      name: name.isEmpty ? 'Unknown device' : name,
      platform: (data['platform'] ?? '').toString().trim(),
      firstSeen: date('firstSeenAt'),
      lastSeen: date('lastSeenAt'),
    );
  }
}

/// Security → Devices & Sign-In Activity.
///
/// Lists the devices this account has signed in on (the signed-in user's
/// own `users/{uid}/trustedDevices`, nobody else's), when each was first
/// and last used, and lets the user remove one they no longer recognize.
///
/// This is the alerts phase of new-device security: a sign-in on a device
/// not in this list sends an email and a notification, but is not blocked.
/// Removing a device only takes it off the list, so its next sign-in is
/// reported as new again — it does not sign that device out. The screen
/// says so, and points to changing the password for that.
class SignInActivityScreen extends StatefulWidget {
  /// A device to point out when the screen opens — the one a "New Device
  /// Sign-In" notification was about.
  final String? highlightDeviceId;

  /// For tests: stand in for Firestore and the installation id.
  final Stream<List<SignInDevice>>? devices;
  final Future<String>? currentDeviceId;
  final Future<void> Function(String deviceId)? removeDevice;

  const SignInActivityScreen({
    super.key,
    this.highlightDeviceId,
    this.devices,
    this.currentDeviceId,
    this.removeDevice,
  });

  @override
  State<SignInActivityScreen> createState() => _SignInActivityScreenState();
}

class _SignInActivityScreenState extends State<SignInActivityScreen> {
  late final Stream<List<SignInDevice>> _devices =
      widget.devices ?? _ownDevices();
  late final Future<String> _currentDeviceId =
      widget.currentDeviceId ?? DeviceTrustService.instance.currentDeviceId();

  CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('trustedDevices');
  }

  Stream<List<SignInDevice>> _ownDevices() {
    final collection = _collection;
    if (collection == null) return Stream.value(const []);
    return collection.snapshots().map((snap) {
      final devices = snap.docs.map(SignInDevice.fromDoc).toList();
      // Most recently used first; sorted here so no index is needed.
      devices.sort(
        (a, b) =>
            (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)),
      );
      return devices;
    });
  }

  TextStyle _text(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.montserrat(
        fontSize: size,
        color: color ?? Colors.black87,
        fontWeight: weight ?? FontWeight.w400,
        height: 1.4,
      );

  String _when(DateTime? date) =>
      date == null ? '—' : DateFormat('MMM d, y · h:mm a').format(date);

  Future<void> _remove(SignInDevice device) async {
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.phonelink_erase_outlined,
      tone: AgriTone.destructive,
      title: 'Remove this device?',
      message:
          '${device.name} will be taken off your list, and you will be '
          'alerted if it logs in again.\n\n'
          'This does not sign that device out. If you do not recognize '
          'it, change your password.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    try {
      await (widget.removeDevice?.call(device.id) ??
          _collection?.doc(device.id).delete());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Device removed.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove the device. Please try again.'),
        ),
      );
    }
  }

  Widget _alertsCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.accent.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, color: AppTheme.mid, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'New Device Login Alerts',
                      style: _text(
                        13.5,
                        color: AppTheme.dark,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.mid,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'On',
                      style: _text(
                        11,
                        color: Colors.white,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'When your account is logged in to on a device not listed '
                'here, we email you and send a notification. The login '
                'itself is not blocked.',
                style: _text(12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _deviceCard(SignInDevice device, String currentId) {
    final isCurrent = device.id == currentId;
    final highlighted = device.id == widget.highlightDeviceId;
    final isPhone = device.platform != 'Web';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? Colors.orange.shade400 : Colors.grey.shade200,
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isPhone ? Icons.smartphone_rounded : Icons.computer_rounded,
              color: AppTheme.mid,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: _text(14, weight: FontWeight.w600)),
                if (isCurrent || highlighted) ...[
                  const SizedBox(height: 2),
                  Text(
                    isCurrent ? 'This device' : 'New login',
                    style: _text(
                      11.5,
                      color: isCurrent ? AppTheme.mid : Colors.orange.shade800,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                if (device.platform.isNotEmpty)
                  Text(
                    device.platform,
                    style: _text(12, color: Colors.black54),
                  ),
                Text(
                  'First logged in: ${_when(device.firstSeen)}',
                  style: _text(12, color: Colors.black54),
                ),
                Text(
                  'Last active: ${_when(device.lastSeen)}',
                  style: _text(12, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (!isCurrent)
            TextButton(
              onPressed: () => _remove(device),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: Text(
                'Remove',
                style: GoogleFonts.montserrat(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: const AgriAppBar(title: 'Devices & Login Activity'),
      body: FutureBuilder<String>(
        future: _currentDeviceId,
        builder: (context, idSnap) {
          return StreamBuilder<List<SignInDevice>>(
            stream: _devices,
            builder: (context, snapshot) {
              final devices = snapshot.data;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _alertsCard(),
                  const SizedBox(height: 18),
                  Text(
                    'DEVICES SIGNED IN TO THIS ACCOUNT',
                    style: _text(
                      10.5,
                      color: Colors.grey[600],
                      weight: FontWeight.w700,
                    ).copyWith(letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 10),
                  if (snapshot.hasError)
                    Text(
                      'Could not load your devices. Please try again.',
                      style: _text(13, color: Colors.black54),
                    )
                  else if (devices == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.mid),
                      ),
                    )
                  else if (devices.isEmpty)
                    Text(
                      'No devices recorded yet.',
                      style: _text(13, color: Colors.black54),
                    )
                  else
                    for (final device in devices)
                      _deviceCard(device, idSnap.data ?? ''),
                  const SizedBox(height: 8),
                  Text(
                    // Change Password itself is one step back, beside this
                    // screen in the account settings.
                    'See a device you do not recognize? Change your password '
                    'in your account settings so it can no longer be used to '
                    'log in.',
                    style: _text(12, color: Colors.black54),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
