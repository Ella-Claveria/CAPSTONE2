import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// One stop of a first-time tour: a widget to point at (via [targetKey])
/// plus the short hint shown next to it.
class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String message;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.message,
  });
}

/// A light first-time tour, once ever per device per [prefsKey]: a small
/// bouncing arrow and a short label pointing at each button in turn. It
/// never darkens or blocks the screen — every tap still does what it
/// always does — and it is the user's own taps that move it along: any tap
/// anywhere puts the next hint up, and the last one away. While a popup or
/// another screen is in front of [context]'s screen (the Market tab guide,
/// a page opened from the tour), the hints wait, hidden, and taps there do
/// not count. Completes when the tour is over.
///
/// Call it after the screen's first frame (e.g. from a post-frame callback
/// in initState).
Future<void> showCoachMarksOnce({
  required BuildContext context,
  required String prefsKey,
  required List<CoachMarkStep> steps,
}) async {
  if (steps.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefsKey) ?? false) return;
    await prefs.setBool(prefsKey, true);
  } catch (_) {
    return; // Can't remember "seen" — safer to skip than nag every launch.
  }

  // Give the frame a moment to settle (layout/animations) before measuring.
  await Future.delayed(const Duration(milliseconds: 500));
  if (!context.mounted) return;

  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachHints(
      host: context,
      steps: steps,
      onDone: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return done.future;
}

class _CoachHints extends StatefulWidget {
  /// The screen the tour belongs to.
  final BuildContext host;
  final List<CoachMarkStep> steps;
  final VoidCallback onDone;

  const _CoachHints({
    required this.host,
    required this.steps,
    required this.onDone,
  });

  @override
  State<_CoachHints> createState() => _CoachHintsState();
}

class _CoachHintsState extends State<_CoachHints>
    with SingleTickerProviderStateMixin {
  // The arrow's gentle bounce; it also redraws the hint every frame, so it
  // follows its button and notices when the screen is covered.
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  var _index = 0;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _bounce.dispose();
    super.dispose();
  }

  bool get _hostShowing {
    if (!widget.host.mounted) return false;
    return ModalRoute.of(widget.host)?.isCurrent ?? true;
  }

  // Fingers that went down while the hint was showing. A tap is judged by
  // where it started: one on a popup's button closes the popup before
  // the tour sees it lift, and must not count as a step.
  final _downWhileShowing = <int>{};

  // Any tap — a lifted finger — while a hint is up moves the tour along.
  // The tap itself still reaches whatever was under it.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (_hostShowing) _downWhileShowing.add(event.pointer);
      return;
    }
    if (event is PointerCancelEvent) {
      _downWhileShowing.remove(event.pointer);
      return;
    }
    if (event is! PointerUpEvent) return;
    final counts = _downWhileShowing.remove(event.pointer);
    if (!counts || _finished || !_hostShowing) return;
    if (_index < widget.steps.length - 1) {
      setState(() => _index++);
    } else {
      _finish();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    // Not while the pointer event is still being handled.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return const SizedBox.shrink();
    if (!widget.host.mounted) {
      _finish();
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _bounce,
        builder: (context, _) {
          if (!_hostShowing) return const SizedBox.shrink();
          final step = widget.steps[_index];
          final box =
              step.targetKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.attached || !box.hasSize) {
            return const SizedBox.shrink();
          }
          final target = box.localToGlobal(Offset.zero) & box.size;
          return _hint(context, step, target);
        },
      ),
    );
  }

  Widget _hint(BuildContext context, CoachMarkStep step, Rect target) {
    final screen = MediaQuery.sizeOf(context);
    // Above a button in the lower half of the screen, below one higher up.
    final above = target.center.dy > screen.height / 2;
    const bubbleWidth = 250.0;
    const arrowSize = 30.0;
    const gap = 6.0;
    final lift = Curves.easeInOut.transform(_bounce.value) * 7;
    final left = (target.center.dx - bubbleWidth / 2)
        .clamp(16.0, math.max(16.0, screen.width - bubbleWidth - 16))
        .toDouble();

    final arrow = Icon(
      above ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
      size: arrowSize,
      color: AppTheme.accent,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    final bubble = _HintBubble(
      title: step.title,
      message: step.message,
      stepNumber: _index + 1,
      totalSteps: widget.steps.length,
    );

    return Stack(
      children: [
        // A soft ring around the button.
        Positioned.fromRect(
          rect: Rect.fromCircle(
            center: target.center,
            radius: target.shortestSide / 2 + 8 + lift * 0.4,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.9),
                width: 2.5,
              ),
            ),
          ),
        ),
        // The arrow, nudging toward the button.
        Positioned(
          left: target.center.dx - arrowSize / 2,
          top: above
              ? target.top - gap - arrowSize - lift
              : target.bottom + gap + lift,
          child: arrow,
        ),
        Positioned(
          left: left,
          width: bubbleWidth,
          top: above ? null : target.bottom + gap + arrowSize + 12,
          bottom: above
              ? screen.height - target.top + gap + arrowSize + 12
              : null,
          child: bubble,
        ),
      ],
    );
  }
}

/// The hint's label: dark green, small, with the step count.
class _HintBubble extends StatelessWidget {
  final String title;
  final String message;
  final int stepNumber;
  final int totalSteps;

  const _HintBubble({
    required this.title,
    required this.message,
    required this.stepNumber,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: AppTheme.dark,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (totalSteps > 1)
                  Text(
                    '$stepNumber/$totalSteps',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              stepNumber < totalSteps
                  ? 'Tap anywhere to continue'
                  : 'Tap anywhere to close',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: AppTheme.accent.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
