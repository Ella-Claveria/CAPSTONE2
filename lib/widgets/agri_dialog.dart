import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../l10n/tr.dart';

/// The one popup design for the whole AgriTrade+ mobile app (Farmer and
/// Buyer): a frosted card — ~88% white over a light blur, thin light
/// border, soft shadow — on a slightly dimmed background, in Montserrat.
///
/// Colour rules: dark green for titles, primary buttons, links and
/// accents; orange only for warnings; red only for destructive actions.
///
/// Use [showAgriDialog]/[AgriDialog] for dialogs, [showAgriConfirm] for a
/// plain yes/no, and [showAgriSheet] for bottom sheets.

/// How far the page behind a popup is dimmed.
const Color agriBarrierColor = Color(0x61000000); // black, ~38%

enum AgriTone {
  /// Ordinary confirmations and information.
  normal,

  /// Caution — orange icon and highlight.
  warning,

  /// Deletes/removes something — red action.
  destructive,
}

Color agriToneColor(AgriTone tone) => switch (tone) {
  AgriTone.normal => AppTheme.dark,
  AgriTone.warning => Colors.orange.shade800,
  AgriTone.destructive => Colors.red.shade700,
};

/// The frosted surface every popup sits on.
class AgriFrostedCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const AgriFrostedCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// A dialog in the AgriTrade+ style. Shaped like [AlertDialog] (title,
/// content, actions) so screens can switch over without restructuring.
/// Text in [title]/[content] picks up the right Montserrat styles by
/// default; pass [AgriDialogButton]s as [actions].
class AgriDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  /// Optional icon shown in a tinted circle above the title.
  final IconData? icon;
  final AgriTone tone;

  /// Wraps [content] in a scroll view, for long or form-like content.
  final bool scrollable;

  const AgriDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.icon,
    this.tone = AgriTone.normal,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final toneColor = agriToneColor(tone);
    final centered = icon != null;

    Widget? body = content == null
        ? null
        : DefaultTextStyle.merge(
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.black87,
              height: 1.45,
            ),
            child: content!,
          );
    if (body != null && scrollable) {
      body = Flexible(child: SingleChildScrollView(child: body));
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      // On a phone the screen sets the width. On a wide window (the Admin
      // Portal in a browser) it stays a popup instead of stretching from
      // edge to edge.
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
      child: AgriFrostedCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tone == AgriTone.normal
                        ? AppTheme.accent
                        : toneColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: toneColor, size: 23),
                ),
                const SizedBox(height: 14),
              ],
              if (title != null)
                DefaultTextStyle.merge(
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.dark,
                  ),
                  child: title!,
                ),
              if (title != null && body != null) const SizedBox(height: 8),
              ?body,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                _actionsRow(context, centered: centered),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Two actions side by side (secondary left, primary right as passed);
  // anything else stacked full-width.
  Widget _actionsRow(BuildContext context, {bool centered = false}) {
    // A lone button on a wide window (the Admin Portal in a browser) is
    // only as wide as its label, centred, instead of a bar across the
    // whole popup. On a phone it stays full-width, easy to reach.
    if (actions.length == 1 && MediaQuery.sizeOf(context).width >= 600) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: IntrinsicWidth(child: actions.single),
        ),
      );
    }
    // Two buttons on a wide window: each only as wide as its label — under
    // the text when the popup is centred (it has an icon), at the right
    // otherwise — instead of two bars filling the popup. A label too long
    // for the room wraps.
    if (actions.length == 2 && MediaQuery.sizeOf(context).width >= 600) {
      return IntrinsicHeight(
        child: Row(
          mainAxisAlignment: centered
              ? MainAxisAlignment.center
              : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The first (usually Cancel) as wide as its label; the second
            // takes what is left if its label is long.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: actions[0],
            ),
            const SizedBox(width: 10),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96),
                child: actions[1],
              ),
            ),
          ],
        ),
      );
    }
    if (actions.length <= 2) {
      // Equal widths, and equal heights too: when one label is long enough
      // to wrap ("Enable Notifications"), the other button grows with it
      // instead of sitting shorter beside it.
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: actions[i]),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          actions[i],
        ],
      ],
    );
  }
}

enum AgriButtonKind {
  /// Dark green, filled.
  primary,

  /// White/transparent with a dark green outline.
  secondary,

  /// Soft red fill, red outline and red text — for delete/remove/log out.
  destructive,
}

/// A popup action button in the AgriTrade+ style.
class AgriDialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AgriButtonKind kind;

  /// A shorter, narrower button for tips (see coach_mark.dart), where a
  /// full-size dialog button would be too heavy.
  final bool compact;

  /// Shows a spinner instead of the label (and ignores taps).
  final bool loading;

  const AgriDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AgriButtonKind.secondary,
    this.loading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    );
    final textStyle = GoogleFonts.montserrat(
      fontSize: compact ? 12.5 : 13,
      fontWeight: FontWeight.w600,
    );
    // A slim pill (about 40 high): a popup's buttons should not outweigh
    // its message.
    final padding = compact
        ? const EdgeInsets.symmetric(vertical: 6, horizontal: 16)
        : const EdgeInsets.symmetric(vertical: 9, horizontal: 18);
    final minimumSize = compact ? const Size(0, 32) : const Size(0, 40);
    const tapTargetSize = MaterialTapTargetSize.shrinkWrap;
    final Widget child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: kind == AgriButtonKind.primary
                  ? Colors.white
                  : AppTheme.dark,
            ),
          )
        : Text(label, textAlign: TextAlign.center, style: textStyle);
    final tap = loading ? null : onPressed;

    switch (kind) {
      case AgriButtonKind.primary:
        return ElevatedButton(
          onPressed: tap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.dark,
            foregroundColor: Colors.white,
            // Not ready yet (e.g. the code is not complete): a faded green,
            // still the same button, instead of a grey one.
            disabledBackgroundColor: AppTheme.dark.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            padding: padding,
            minimumSize: minimumSize,
            tapTargetSize: tapTargetSize,
            shape: shape,
          ),
          child: child,
        );
      case AgriButtonKind.secondary:
        return OutlinedButton(
          onPressed: tap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.6),
            foregroundColor: AppTheme.dark,
            side: const BorderSide(color: AppTheme.dark, width: 1.2),
            padding: padding,
            minimumSize: minimumSize,
            tapTargetSize: tapTargetSize,
            shape: shape,
          ),
          child: child,
        );
      case AgriButtonKind.destructive:
        return ElevatedButton(
          onPressed: tap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red.shade700,
            // A red outline, like the green one on the secondary button,
            // so it reads as a button (Remove, Log Out, Delete…).
            side: BorderSide(color: Colors.red.shade700, width: 1.2),
            elevation: 0,
            padding: padding,
            minimumSize: minimumSize,
            tapTargetSize: tapTargetSize,
            shape: shape,
          ),
          child: child,
        );
    }
  }
}

/// [showDialog] with the AgriTrade+ dimmed barrier.
Future<T?> showAgriDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: agriBarrierColor,
    builder: builder,
  );
}

/// A two-button confirmation. Returns true only for [confirmLabel].
/// [tone] decides the confirm button: dark green normally, red for
/// [AgriTone.destructive]; [AgriTone.warning] gives an orange icon.
Future<bool> showAgriConfirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  // Defaults to "Cancel" in the app's language.
  String? cancelLabel,
  AgriTone tone = AgriTone.normal,
  IconData? icon,
  bool barrierDismissible = true,
}) async {
  final result = await showAgriDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => AgriDialog(
      icon: icon,
      tone: tone,
      title: Text(title),
      content: Text(message),
      actions: [
        AgriDialogButton(
          label: cancelLabel ?? (tr(dialogContext).cancel),
          onPressed: () => Navigator.pop(dialogContext, false),
        ),
        AgriDialogButton(
          label: confirmLabel,
          kind: tone == AgriTone.destructive
              ? AgriButtonKind.destructive
              : AgriButtonKind.primary,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
  return result == true;
}

/// [showModalBottomSheet] in the AgriTrade+ style: the sheet floats as a
/// frosted card with a drag handle, over the dimmed barrier. [builder]
/// returns only the sheet's content.
///
/// [avoidKeyboard] lifts the sheet above an open keyboard; pass false when
/// the content already pads itself for the keyboard.
Future<T?> showAgriSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  String? title,
  bool avoidKeyboard = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: agriBarrierColor,
    builder: (sheetContext) => AgriSheetFrame(
      title: title,
      avoidKeyboard: avoidKeyboard,
      child: Builder(builder: builder),
    ),
  );
}

/// For larger sheets that already lay out their own header, handle and
/// keyboard padding (location picker, calculator, forms): the same frosted
/// surface and dimmed barrier as [showAgriSheet], as a full-width panel with
/// rounded top corners, with the content left exactly as it is.
Future<T?> showAgriPanelSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: agriBarrierColor,
    builder: (sheetContext) => AgriFrostedCard(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Builder(builder: builder),
    ),
  );
}

/// The frosted card + drag handle (+ optional title) around a bottom
/// sheet's content. Used by [showAgriSheet].
class AgriSheetFrame extends StatelessWidget {
  final Widget child;
  final String? title;
  final bool avoidKeyboard;

  const AgriSheetFrame({
    super.key,
    required this.child,
    this.title,
    this.avoidKeyboard = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom:
              12 +
              (avoidKeyboard ? MediaQuery.of(context).viewInsets.bottom : 0),
        ),
        child: AgriFrostedCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                  child: Text(
                    title!,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.dark,
                    ),
                  ),
                )
              else
                const SizedBox(height: 6),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of a bottom-sheet action menu (e.g. Take a photo, Archive).
class AgriSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const AgriSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red.shade700 : AppTheme.dark;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: destructive ? color : Colors.black87,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// One row of an [showAgriPopupMenu] menu.
class AgriMenuItem<T> {
  final T value;
  final IconData icon;
  final String label;
  final bool destructive;

  const AgriMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
  });
}

/// A compact frosted menu that drops down from the widget whose
/// [BuildContext] is [anchorContext] (e.g. a header icon button), aligned to
/// its right edge. Resolves to the tapped item's value, or null when
/// dismissed. For screen-level menus; actions on one specific item still use
/// [showAgriSheet].
///
/// With [upward] the menu instead opens above the anchor, aligned to its
/// left edge, with a small pointer at the anchor (e.g. the chat + button).
/// It doesn't take focus, so an open keyboard and the field under it stay
/// as they are.
Future<T?> showAgriPopupMenu<T>({
  required BuildContext anchorContext,
  required List<AgriMenuItem<T>> items,
  double width = 210,
  bool upward = false,
}) {
  final anchorBox = anchorContext.findRenderObject() as RenderBox;
  final anchor = anchorBox.localToGlobal(Offset.zero) & anchorBox.size;
  const pointerHeight = 7.0;
  const pointerWidth = 16.0;

  return showGeneralDialog<T>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(
      anchorContext,
    ).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: upward ? 0.03 : 0.08),
    transitionDuration: const Duration(milliseconds: 160),
    requestFocus: !upward,
    pageBuilder: (dialogContext, _, _) {
      final screen = MediaQuery.sizeOf(dialogContext);
      final card = AgriFrostedCard(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                _AgriMenuRow(
                  item: item,
                  labelColor: upward ? AppTheme.dark : null,
                  onTap: () => Navigator.pop(dialogContext, item.value),
                ),
            ],
          ),
        ),
      );
      if (!upward) {
        // Each row is about 42 high; near the bottom of the screen the
        // menu opens above its anchor instead, so it is never cut off.
        final menuHeight = items.length * 42.0 + 12;
        final safe = MediaQuery.viewPaddingOf(dialogContext);
        final fitsBelow =
            anchor.bottom + 2 + menuHeight <= screen.height - safe.bottom - 8;
        return Stack(
          children: [
            Positioned(
              top: fitsBelow ? anchor.bottom + 2 : null,
              bottom: fitsBelow ? null : screen.height - anchor.top + 2,
              right: (screen.width - anchor.right).clamp(12.0, screen.width),
              width: width,
              child: card,
            ),
          ],
        );
      }
      final cardBottom = screen.height - anchor.top + pointerHeight + 2;
      return Stack(
        children: [
          Positioned(
            bottom: cardBottom,
            left: anchor.left.clamp(12.0, screen.width - width - 12),
            width: width,
            child: card,
          ),
          Positioned(
            bottom: cardBottom - pointerHeight + 0.5,
            left: anchor.center.dx - pointerWidth / 2,
            child: CustomPaint(
              size: const Size(pointerWidth, pointerHeight),
              painter: _MenuPointerPainter(),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          alignment: Alignment(
            // Grow out of the anchor's corner.
            (anchor.center.dx / MediaQuery.sizeOf(anchorContext).width) * 2 - 1,
            ((upward ? anchor.top : anchor.bottom) /
                        MediaQuery.sizeOf(anchorContext).height) *
                    2 -
                1,
          ),
          child: child,
        ),
      );
    },
  );
}

/// The little downward triangle linking an upward menu to its button.
class _MenuPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: 0.94),
    );
  }

  @override
  bool shouldRepaint(_MenuPointerPainter oldDelegate) => false;
}

class _AgriMenuRow<T> extends StatelessWidget {
  final AgriMenuItem<T> item;
  final VoidCallback onTap;
  final Color? labelColor;

  const _AgriMenuRow({
    required this.item,
    required this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.destructive ? Colors.red.shade700 : AppTheme.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(item.icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: GoogleFonts.montserrat(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: item.destructive
                      ? color
                      : labelColor ?? Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
