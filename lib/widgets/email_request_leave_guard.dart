import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'agri_dialog.dart';

/// The "Leave This Process?" confirmation, shown when the user goes Back
/// while an account email request (password reset, verification code,
/// email change) is still being sent.
///
/// One instance per screen. It never shows two dialogs at once.
///
/// Once the question is on screen it is the user's to answer: a request
/// finishing in the meantime must not close it, navigate, or change the
/// screen behind it. So a screen does not act on a finished request
/// directly — it hands what it wants to do to [whenResolved], which runs
/// it straight away if nothing is being asked, holds it until the user
/// picks Stay, and drops it if they pick Leave.
///
/// Leaving does not cancel a request that has already been submitted, and
/// nothing here says it does: the dialog only asks whether to leave.
class EmailLeaveConfirm {
  DialogRoute<bool>? _route;
  NavigatorState? _navigator;
  final List<VoidCallback> _held = [];
  bool _left = false;

  bool get isOpen => _route != null;

  /// True once the user has chosen Leave. Nothing held is ever run after
  /// that, and anything handed to [whenResolved] later is ignored.
  bool get left => _left;

  /// True if the user chose Leave. False for Stay, for a dismissed dialog,
  /// and when a confirmation is already showing.
  Future<bool> show(BuildContext context) async {
    if (isOpen || _left) return false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      barrierColor: agriBarrierColor,
      builder: (dialogContext) => const _LeaveDialog(),
    );
    _route = route;
    _navigator = navigator;
    final leave = await navigator.push(route) == true;
    if (!identical(_route, route)) return false; // closed by [dismiss]
    _route = null;
    _navigator = null;

    final held = List<VoidCallback>.of(_held);
    _held.clear();
    if (leave) {
      _left = true;
    } else {
      for (final action in held) {
        action();
      }
    }
    return leave;
  }

  /// What to do with a finished request: [action] runs now if the question
  /// is not on screen, after Stay if it is, and never after Leave.
  void whenResolved(VoidCallback action) {
    if (_left) return;
    if (isOpen) {
      _held.add(action);
    } else {
      action();
    }
  }

  /// For a screen that is going away: closes the question if it is open
  /// and forgets anything held.
  void dismiss() {
    final route = _route;
    final navigator = _navigator;
    _route = null;
    _navigator = null;
    _held.clear();
    if (route != null && navigator != null && route.isActive) {
      navigator.removeRoute(route);
    }
  }
}

/// Wraps a screen (or dialog) that sends an account email. While
/// [processing] is true, every way of going Back — the app's Back button,
/// the Android back button or gesture — asks "Leave This Process?" first.
/// When it is false, Back behaves exactly as it would without this widget.
///
/// The screen owns [confirm] and applies each finished request through
/// [EmailLeaveConfirm.whenResolved], keeping [processing] true until that
/// has run — so nothing on the screen changes, and nothing navigates,
/// while the question is waiting for an answer.
class EmailRequestLeaveGuard extends StatefulWidget {
  /// Whether an email request is being sent (or its result is still
  /// waiting to be applied).
  final bool processing;
  final EmailLeaveConfirm confirm;
  final Widget child;

  const EmailRequestLeaveGuard({
    super.key,
    required this.processing,
    required this.confirm,
    required this.child,
  });

  @override
  State<EmailRequestLeaveGuard> createState() => _EmailRequestLeaveGuardState();
}

class _EmailRequestLeaveGuardState extends State<EmailRequestLeaveGuard> {
  @override
  void dispose() {
    widget.confirm.dismiss();
    super.dispose();
  }

  // The only navigation this flow performs, and only on the user's Leave.
  Future<void> _onBlockedBack() async {
    final leave = await widget.confirm.show(context);
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !widget.processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBlockedBack();
      },
      child: widget.child,
    );
  }
}

class _LeaveDialog extends StatelessWidget {
  const _LeaveDialog();

  static const double _buttonHeight = 46;
  static const Color _warning = Color(0xFFEF6C00);

  // Both buttons: same height and pill shape, with a label that shrinks
  // rather than wraps.
  Widget _button({
    required String label,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_buttonHeight / 2),
    );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    const padding = EdgeInsets.symmetric(horizontal: 12);
    return Expanded(
      child: SizedBox(
        height: _buttonHeight,
        child: filled
            ? ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: padding,
                  shape: shape,
                ),
                child: child,
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.mid,
                  side: const BorderSide(color: AppTheme.mid, width: 1.2),
                  padding: padding,
                  shape: shape,
                ),
                child: child,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: _warning,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Leave This Process?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dark,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Your email request is still being processed. Are you '
                    'sure you want to leave this screen?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _button(
                      label: 'Stay',
                      filled: false,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 10),
                    _button(
                      label: 'Leave',
                      filled: true,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
