import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/admin_session_service.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../widgets/change_email_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/login_form_fields.dart';
import 'admin_dashboard_screen.dart'
    show AdminEmptyState, AdminPalette, AdminStatusBadge, AdminThemeScope;
import 'admin_filter_controls.dart';
import 'admin_notifications.dart';
import 'admin_sub_nav.dart';

// The Admin's own account, reached from the account button at the bottom
// of the sidebar: Manage Account, with the account's details and its
// settings.

/// The signed-in Admin's name and photo as stored on their account; the
/// name is "Admin" when none is.
typedef AdminProfile = ({String name, String? photoUrl});

Future<AdminProfile>? _profile;
String? _profileUid;

/// Ticks when the Admin edits their profile, so whatever shows the name
/// (the account button in the sidebar) asks for it again.
final ValueNotifier<int> adminProfileChanged = ValueNotifier<int>(0);

/// [AdminProfile] for whoever is signed in. Read once per account, and
/// again after Edit Profile, so the sidebar and Manage Account can both
/// ask for it freely.
Future<AdminProfile> adminProfile() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (_profile == null || uid != _profileUid) {
    _profileUid = uid;
    _profile = _loadAdminProfile();
  }
  return _profile!;
}

Future<AdminProfile> _loadAdminProfile() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return (name: 'Admin', photoUrl: null);
  var name = 'Admin';
  String? photoUrl = user.photoURL;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    for (final value in [
      doc.data()?['fullName'],
      doc.data()?['name'],
      user.displayName,
    ]) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        name = text;
        break;
      }
    }
    final stored = (doc.data()?['photoUrl'] ?? '').toString().trim();
    if (stored.isNotEmpty) photoUrl = stored;
  } catch (_) {
    // Falls through to the plain role name, and is asked again next time.
    _profile = null;
  }
  return (name: name, photoUrl: photoUrl);
}

/// Account button > Manage Account: the account's details, then its
/// settings and its security, each under a small grey heading, with the
/// action on each row as dark green text. Changing the email or password
/// opens the same re-authenticating dialogs as before.
Future<void> showAdminManageAccount(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ManageAccount(),
  );
}

// The dialog's text colours: the portal palette's titles, and its grey
// for notes and headings (AdminPalette.light textPrimary/textSecondary).
const Color _ink = Color(0xFF17241A);
const Color _note = Color(0xFF676D78);

// The dialog's buttons (Change, View, Manage, the pencil, Close): a dark
// green that still reads as green at text size, where the app's main dark
// green (AppTheme.dark) looks almost black.
const Color _action = Color(0xFF1B5E20);

class _ManageAccount extends StatefulWidget {
  const _ManageAccount();

  @override
  State<_ManageAccount> createState() => _ManageAccountState();
}

class _ManageAccountState extends State<_ManageAccount> {
  late Future<AdminProfile> _account = adminProfile();
  final _auth = AuthService();

  Future<void> _editProfile(AdminProfile? profile) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(
        name: profile?.name ?? '',
        photoUrl: profile?.photoUrl,
      ),
    );
    if (saved == true && mounted) {
      setState(() => _account = adminProfile());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read each build, so a changed email shows once its dialog closes.
    final email = _auth.currentEmail ?? 'Not available';
    final googleOnly = !_auth.hasPasswordProvider;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: const Text(
        'Manage Account',
        style: TextStyle(
          color: _ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading('Account Information'),
              FutureBuilder<AdminProfile>(
                future: _account,
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  final name = profile?.name ?? '…';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _ProfileAvatar(
                            photoUrl: profile?.photoUrl,
                            onTap: profile == null
                                ? null
                                : () => _editProfile(profile),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Administrator',
                                  style: TextStyle(color: _note, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit Profile',
                            onPressed: profile == null
                                ? null
                                : () => _editProfile(profile),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: _action,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Full name · Email · Role, on one line.
                      Text(
                        '$name · $email · Administrator',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _ink, fontSize: 13),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const _Heading('Account Settings'),
              _SettingRow(
                icon: Icons.mail_outline_rounded,
                title: 'Change Email',
                note: 'Update registered email',
                action: 'Change',
                onPressed: () async {
                  await showChangeEmailDialog(context);
                  if (mounted) setState(() {});
                },
              ),
              _SettingRow(
                icon: Icons.lock_outline_rounded,
                title: 'Change Password',
                note: googleOnly
                    ? 'Managed by your Google Account'
                    : 'Verify current password',
                action: 'Change',
                onPressed: () async {
                  // Forget the password saved for the login form once it
                  // has actually changed.
                  if (await showChangePasswordDialog(context)) {
                    await LoginFormFields.clearSavedAdminPassword();
                  }
                },
              ),
              const SizedBox(height: 22),
              const _Heading('Security and Login'),
              _SettingRow(
                icon: Icons.history_rounded,
                title: 'Login Activity',
                note: 'Successful logins, failed attempts, and sign-outs',
                action: 'View',
                onPressed: () {
                  Navigator.of(context).pop();
                  AdminSubNav.audit.value = AuditSection.login;
                  adminOpenPageRequest.value = AdminNotificationTarget.auditLog;
                },
              ),
              _SettingRow(
                icon: Icons.verified_user_outlined,
                title: 'Two-Factor Authentication',
                note: 'Additional login protection',
                action: 'Manage',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _LoginProtectionDialog(email: email),
                ),
              ),
              _SettingRow(
                icon: Icons.devices_outlined,
                title: 'Active Sessions',
                note: 'Review logged-in devices',
                action: 'View',
                onPressed: () => showAdminActiveSessions(context),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _action,
            side: const BorderSide(color: _action),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A section's small grey uppercase heading.
class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _note,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// The account's photo, or a person on a light grey circle. With [onTap],
/// a small camera badge says it can be changed (Edit Profile).
class _ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final VoidCallback? onTap;
  const _ProfileAvatar({this.photoUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    final avatar = CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFF1F2F4),
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      onForegroundImageError: url.isEmpty ? null : (_, _) {},
      child: const Icon(Icons.person_outline_rounded, color: _ink, size: 22),
    );
    if (onTap == null) return avatar;
    return Tooltip(
      message: 'Change photo',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _action,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One setting: an outline icon, its title and a grey note, and its
/// action as dark green text on the right.
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final String action;
  final VoidCallback onPressed;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.note,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 19, color: _ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _note, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _TextAction(label: action, onPressed: onPressed),
        ],
      ),
    );
  }
}

/// A text-only action in the app's dark green, underlined while hovered.
class _TextAction extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _TextAction({required this.label, required this.onPressed});

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              widget.label,
              style: TextStyle(
                color: _action,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                decoration: _hovered
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: _action,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pencil (or the photo): the Admin's photo and name, saved on their
/// account — Firebase Authentication's photo and display name, and the
/// `users` record the portal reads. The photo is uploaded the same way as
/// the mobile app's profile photos (CloudinaryService).
class _EditProfileDialog extends StatefulWidget {
  final String name;
  final String? photoUrl;
  const _EditProfileDialog({required this.name, this.photoUrl});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final _controller = TextEditingController(
    text: widget.name == 'Admin' ? '' : widget.name,
  );
  bool _saving = false;
  String? _error;

  // A new photo picked, not saved yet; or the current one to be removed.
  Uint8List? _picked;
  String _pickedName = 'profile.jpg';
  bool _remove = false;

  static const int _maxPhotoBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxPhotoBytes) {
        setState(() => _error = 'Choose a photo smaller than 5 MB.');
        return;
      }
      setState(() {
        _picked = bytes;
        _pickedName = file.name.isEmpty ? 'profile.jpg' : file.name;
        _remove = false;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'That photo could not be opened.');
    }
  }

  Future<void> _save() async {
    final name = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final update = <String, Object?>{'fullName': name};
      final picked = _picked;
      if (picked != null) {
        final url = await CloudinaryService().uploadImageBytes(
          picked,
          name: _pickedName,
        );
        if (url == null || url.isEmpty) {
          throw const _PhotoUploadFailed();
        }
        await user.updatePhotoURL(url);
        update['photoUrl'] = url;
      } else if (_remove) {
        await user.updatePhotoURL(null);
        update['photoUrl'] = FieldValue.delete();
      }
      await user.updateDisplayName(name);
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update(update);
      } on FirebaseException catch (e) {
        // No `users` record for this Admin: the Auth profile is enough.
        if (e.code != 'not-found') rethrow;
      }
      _profile = null;
      adminProfileChanged.value++;
      if (mounted) Navigator.of(context).pop(true);
    } on _PhotoUploadFailed {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'The photo could not be uploaded. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Your profile could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = (widget.photoUrl ?? '').trim();
    final ImageProvider? image = _picked != null
        ? MemoryImage(_picked!)
        : (!_remove && current.isNotEmpty ? NetworkImage(current) : null);
    final hasPhoto = image != null;

    return AlertDialog(
      title: const Text('Edit Profile'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFFF1F3F5),
                  foregroundImage: image,
                  onForegroundImageError: image == null ? null : (_, _) {},
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: _ink,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 4,
                        children: [
                          _TextAction(
                            label: hasPhoto ? 'Change photo' : 'Upload photo',
                            onPressed: _saving ? () {} : _pickPhoto,
                          ),
                          if (hasPhoto)
                            _TextAction(
                              label: 'Remove',
                              onPressed: _saving
                                  ? () {}
                                  : () => setState(() {
                                      _picked = null;
                                      _remove = true;
                                    }),
                            ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text(
                          'JPG or PNG, up to 5 MB.',
                          style: TextStyle(color: _note, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              enabled: !_saving,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _PhotoUploadFailed implements Exception {
  const _PhotoUploadFailed();
}

/// Two-Factor Authentication > Manage: what protects the Admin's login
/// besides the password, and whether each one is on for this account.
/// Nothing here is a setting: the sign-in alert follows whether the email
/// is verified, and the other two are always on for an Admin account.
class _LoginProtectionDialog extends StatelessWidget {
  final String email;
  const _LoginProtectionDialog({required this.email});

  @override
  Widget build(BuildContext context) {
    // The sign-in alert is only ever sent to a verified address (see
    // sendSignInAlert in functions/admin_session.js).
    final alertsOn = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    Widget item(IconData icon, String title, String note, {bool on = true}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 19, color: AppTheme.dark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: const TextStyle(color: _note, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                on ? 'On' : 'Off',
                style: TextStyle(
                  color: on ? AppTheme.dark : _note,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      title: const Text('Two-Factor Authentication'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Besides your password, these protect logins to this account:',
              style: TextStyle(color: _note, fontSize: 13),
            ),
            const SizedBox(height: 8),
            item(
              Icons.mark_email_read_outlined,
              'Sign-in alerts by email',
              alertsOn
                  ? 'An email goes to $email each time this account logs in.'
                  : 'Sent only to a verified email address. Use Change Email '
                        'to verify one for this account.',
              on: alertsOn,
            ),
            item(
              Icons.devices_outlined,
              'One active session',
              'Logging in on another browser ends the session here.',
            ),
            item(
              Icons.lock_clock_outlined,
              'Login lockout',
              '${AuthService.loginMaxFailedAttempts} wrong passwords in a row '
                  'lock the login for 5 minutes.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Manage Account > Active Sessions: the devices signed in to this Admin
/// account, from its session history — this browser first, then any other
/// session still signed in (each with Revoke Session), then recent ones
/// that have ended. Revoking goes through the revokeAdminSession Cloud
/// Function (AdminSessionService.revoke); the list follows the session
/// record live, so it updates by itself once the server has done it.
Future<void> showAdminActiveSessions(BuildContext context) {
  // A dialog sits outside the page's AdminThemeScope: hand the palette in.
  final palette =
      context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
      AdminPalette.light;
  return showDialog<void>(
    context: context,
    builder: (_) => AdminThemeScope(
      palette: palette,
      child: _ActiveSessionsDialog(palette: palette),
    ),
  );
}

class _ActiveSessionsDialog extends StatefulWidget {
  final AdminPalette palette;
  const _ActiveSessionsDialog({required this.palette});

  @override
  State<_ActiveSessionsDialog> createState() => _ActiveSessionsDialogState();
}

class _ActiveSessionsDialogState extends State<_ActiveSessionsDialog> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final Future<String?> _localId = _uid == null
      ? Future.value(null)
      : AdminSessionService.localId(_uid);
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _record =
      _uid == null ? null : AdminSessionService.watchRecord(_uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _history =
      _uid == null ? null : AdminSessionService.recentSessions(_uid, limit: 20);

  static String _when(DateTime? at) {
    if (at == null) return '—';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return DateFormat('MMM d, y · h:mm a').format(at);
  }

  Future<void> _revoke(
    AdminSessionEntry session, {
    required int otherActive,
  }) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminThemeScope(
        palette: widget.palette,
        child: _RevokeSessionDialog(
          palette: widget.palette,
          session: session,
          othersToo: otherActive > 1,
        ),
      ),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${session.device} was signed out.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      title: Row(children: [const Expanded(child: Text('Active Sessions'))]),
      content: SizedBox(
        width: 600,
        height: 520,
        child: _uid == null
            ? Center(
                child: Text(
                  'Please log in again.',
                  style: TextStyle(color: c.textSecondary),
                ),
              )
            : FutureBuilder<String?>(
                future: _localId,
                builder: (context, local) =>
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _record,
                      builder: (context, record) =>
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: _history,
                            builder: (context, history) {
                              if (history.hasError || record.hasError) {
                                return Center(
                                  child: Text(
                                    'The sessions could not be loaded. Check '
                                    'your connection and try again.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              }
                              if (!history.hasData ||
                                  local.connectionState !=
                                      ConnectionState.done) {
                                return const Center(child: AdminLoadingBar());
                              }
                              final entries = buildAdminSessionEntries(
                                record: record.data?.data(),
                                history: [
                                  for (final d in history.data!.docs)
                                    (id: d.id, data: d.data()),
                                ],
                                localId: local.data,
                              );
                              return _list(c, entries);
                            },
                          ),
                    ),
              ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _list(AdminPalette c, List<AdminSessionEntry> entries) {
    final current = [
      for (final e in entries)
        if (e.isCurrent) e,
    ];
    final others = [
      for (final e in entries)
        if (!e.isCurrent && e.active) e,
    ];
    final ended = [
      for (final e in entries)
        if (!e.isCurrent && !e.active) e,
    ].take(8).toList();

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );

    return ListView(
      children: [
        Text(
          'Devices signed in to your Admin account. The portal keeps one '
          'active session at a time: logging in on another device ends the '
          'one before.',
          style: TextStyle(fontSize: 12.5, color: c.textSecondary),
        ),
        heading('This device'),
        if (current.isEmpty)
          _card(
            c,
            icon: Icons.computer_outlined,
            title: 'This browser',
            lines: const [
              'Its session is not on record. Log out and in again to '
                  'record it.',
            ],
          )
        else
          _sessionCard(
            c,
            current.first,
            trailing: AdminStatusBadge(
              text: 'Current session',
              color: c.green,
              bg: c.greenBg,
            ),
          ),
        heading('Other active sessions'),
        if (others.isEmpty)
          Container(
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: const AdminEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No other active sessions',
              subtitle: 'Only this device is signed in to your account.',
            ),
          )
        else
          for (final session in others)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _sessionCard(
                c,
                session,
                trailing: OutlinedButton(
                  onPressed: () => _revoke(session, otherActive: others.length),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.red,
                    side: BorderSide(color: c.red.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Revoke Session'),
                ),
              ),
            ),
        if (ended.isNotEmpty) ...[
          heading('Recent sessions'),
          for (final session in ended)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _sessionCard(
                c,
                session,
                muted: true,
                trailing: AdminStatusBadge(
                  text: 'Ended',
                  color: c.textSecondary,
                  bg: c.border.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _sessionCard(
    AdminPalette c,
    AdminSessionEntry session, {
    required Widget trailing,
    bool muted = false,
  }) {
    return _card(
      c,
      icon: session.onPhone
          ? Icons.smartphone_outlined
          : Icons.computer_outlined,
      title: session.device,
      lines: [
        [
          session.location ?? 'Location unknown',
          if (session.active)
            'Last active ${_when(session.lastActiveAt).toLowerCase()}'
          else
            '${session.endLabel} ${_when(session.endedAt ?? session.startedAt).toLowerCase()}',
        ].join(' · '),
        'Logged in ${_when(session.startedAt)}',
      ],
      trailing: trailing,
      muted: muted,
    );
  }

  Widget _card(
    AdminPalette c, {
    required IconData icon,
    required String title,
    required List<String> lines,
    Widget? trailing,
    bool muted = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: muted ? c.surface : c.greenBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: muted ? c.textMuted : c.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted ? c.textSecondary : c.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final line in lines) ...[
                  const SizedBox(height: 2),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }
}

/// "Sign out this device?": the session, the warning, and the password —
/// revoking needs it entered again (the server checks it was within the
/// last five minutes). Stays open, with the reason, if it does not work;
/// pops true once the server has signed the session out.
class _RevokeSessionDialog extends StatefulWidget {
  final AdminPalette palette;
  final AdminSessionEntry session;

  /// More than one other session is signed in: they all end together.
  final bool othersToo;

  const _RevokeSessionDialog({
    required this.palette,
    required this.session,
    required this.othersToo,
  });

  @override
  State<_RevokeSessionDialog> createState() => _RevokeSessionDialogState();
}

class _RevokeSessionDialogState extends State<_RevokeSessionDialog> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_working) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final error = await AdminSessionService.revoke(
      sessionId: widget.session.id,
      password: _password.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _working = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final passwordLogin = AuthService().hasPasswordProvider;
    return AlertDialog(
      title: const Text('Sign out this device?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Are you sure you want to sign out this device? This device '
              'will lose access to your AgriTrade+ account.',
              style: TextStyle(fontSize: 13.5, color: c.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.session.onPhone
                        ? Icons.smartphone_outlined
                        : Icons.computer_outlined,
                    size: 18,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        widget.session.device,
                        if (widget.session.location != null)
                          widget.session.location!,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.othersToo) ...[
              const SizedBox(height: 10),
              Text(
                'Every other device signed in to this account will be signed '
                'out too.',
                style: TextStyle(fontSize: 12, color: c.amber),
              ),
            ],
            const SizedBox(height: 14),
            if (passwordLogin)
              TextField(
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                enabled: !_working,
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  labelText: 'Your password',
                  helperText: 'Needed to confirm it is you.',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              )
            else
              Text(
                'Signing out a device needs a password login. This account '
                'logs in with Google.',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.red, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working || !passwordLogin ? null : _confirm,
          style: FilledButton.styleFrom(backgroundColor: c.red),
          child: Text(_working ? 'Revoking…' : 'Revoke Session'),
        ),
      ],
    );
  }
}
