import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One stop of a coach-mark tour: a widget to spotlight (via [targetKey])
/// plus the tip shown next to it.
class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String message;

  const CoachMarkStep({required this.targetKey, required this.title, required this.message});
}

/// Shows a subtle spotlighted walkthrough over up to a couple of key
/// buttons — once ever per device per [prefsKey]. Call this after the
/// screen's first frame (e.g. from a post-frame callback in initState), by
/// which point every step's [CoachMarkStep.targetKey] must already be
/// attached to a laid-out widget.
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
  await _CoachMarkOverlay.show(context, steps);
}

class _CoachMarkOverlay {
  static Future<void> show(BuildContext context, List<CoachMarkStep> steps) {
    final completer = Completer<void>();
    late OverlayEntry entry;
    var index = 0;

    void close() {
      entry.remove();
      if (!completer.isCompleted) completer.complete();
    }

    void advance() {
      if (index < steps.length - 1) {
        index++;
        entry.markNeedsBuild();
      } else {
        close();
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) {
        final step = steps[index];
        final box = step.targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) {
          // Target isn't on screen (e.g. a different tab is showing) — bail
          // out quietly rather than drawing a spotlight pointing at nothing.
          WidgetsBinding.instance.addPostFrameCallback((_) => close());
          return const SizedBox.shrink();
        }

        final topLeft = box.localToGlobal(Offset.zero);
        final size = box.size;
        final center = topLeft + Offset(size.width / 2, size.height / 2);
        final radius = (size.longestSide / 2) + 14;
        final screenSize = MediaQuery.of(overlayContext).size;
        final calloutBelow = center.dy < screenSize.height / 2;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: advance,
                child: CustomPaint(
                  size: screenSize,
                  painter: _SpotlightPainter(center: center, radius: radius),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              top: calloutBelow ? (center.dy + radius + 16) : null,
              bottom: calloutBelow ? null : (screenSize.height - (center.dy - radius) + 16),
              child: _CoachMarkCard(
                step: step,
                stepNumber: index + 1,
                totalSteps: steps.length,
                onNext: advance,
                onSkip: close,
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(entry);
    return completer.future;
  }
}

class _SpotlightPainter extends CustomPainter {
  final Offset center;
  final double radius;
  const _SpotlightPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    final scrim = Path.combine(PathOperation.difference, overlayPath, holePath);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.68));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.radius != radius;
}

class _CoachMarkCard extends StatelessWidget {
  final CoachMarkStep step;
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _CoachMarkCard({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  static const Color _dark = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    final isLast = stepNumber == totalSteps;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(step.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                if (totalSteps > 1)
                  Text('$stepNumber/$totalSteps', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
            const SizedBox(height: 6),
            Text(step.message, style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: onSkip, child: const Text('Skip', style: TextStyle(color: Colors.black45))),
                ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(isLast ? 'Got it' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
