import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The splash screen's loading indicator: a little farmer in a salakot
/// walks once, left to right, along a thin track that fills dark green
/// behind him — brisk at first, slowing as he nears the end, where he
/// stops and stands if the app is still loading. Legs and arms swing with
/// each step (the steps slow with him) and the body bobs slightly. Drawn
/// in code (no image or package).
///
/// It does not report real progress — it only shows the app is working.
/// With animations turned off on the phone it stands still mid-track.
class WalkingFarmerLoader extends StatefulWidget {
  /// Width of the track the farmer walks along.
  final double width;

  const WalkingFarmerLoader({super.key, this.width = 190});

  /// How long the one walk across takes.
  static const Duration crossing = Duration(milliseconds: 3000);

  /// Completes once the farmer has finished his walk, so the phone's
  /// splash can stay up until he reaches the end even when the app loads
  /// faster than that (see AppRouter). Right away when the walk is over, or
  /// when he never set off.
  static Future<void> untilWalkDone() async {
    final started = _walkStartedAt;
    if (started == null) return;
    final left = crossing - DateTime.now().difference(started);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  // When the walk began, for the whole app run. Starting up shows the
  // loading screen more than once in a row (app start, then the signed-in
  // check), each a new widget — they all continue this one walk instead of
  // starting another, so he crosses only once.
  static DateTime? _walkStartedAt;

  /// Starts the walk afresh (tests only).
  @visibleForTesting
  static void resetWalk() => _walkStartedAt = null;

  @override
  State<WalkingFarmerLoader> createState() => _WalkingFarmerLoaderState();
}

class _WalkingFarmerLoaderState extends State<WalkingFarmerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _walk = AnimationController(
    vsync: this,
    duration: WalkingFarmerLoader.crossing,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _walk
        ..stop()
        ..value = 0.5;
    } else if (!_walk.isAnimating && !_walk.isCompleted) {
      // Pick up where the walk already is (or stand at the end when it is
      // over) — once per app run, no starting over.
      final started = WalkingFarmerLoader._walkStartedAt ??= DateTime.now();
      final done =
          DateTime.now().difference(started).inMilliseconds /
          WalkingFarmerLoader.crossing.inMilliseconds;
      _walk.value = done.clamp(0.0, 1.0);
      if (!_walk.isCompleted) _walk.forward();
    }
  }

  @override
  void dispose() {
    _walk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.width,
        height: _FarmerPainter.height + 8,
        // Its own layer, so each frame of the walk redraws only him.
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _walk,
            builder: (context, _) => CustomPaint(
              painter: _FarmerPainter(
                // Eases in and out: he sets off gently (while the phone is
                // busiest starting the app) and slows to a stop at the end.
                progress: Curves.easeInOutSine.transform(_walk.value),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FarmerPainter extends CustomPainter {
  /// 0 → 1 across the track.
  final double progress;

  _FarmerPainter({required this.progress});

  static const double height = 46;

  // The figure is drawn a little larger than its sketch size.
  static const double _scale = 1.05;

  // Strides across the track (one stride is two steps). The steps follow
  // the distance walked, so they slow as he does, and end feet together.
  static const double _strides = 6;

  static const Color _straw = Color(0xFFD9A441);
  static const Color _strawDark = Color(0xFFB7832B);
  static const Color _skin = Color(0xFFC68642);
  static const Color _shirt = AppTheme.mid;
  static const Color _pants = Color(0xFF3E4A3D);
  static const Color _track = Color(0xFFE4EBE1);

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height - 3;
    // Room at both ends so the farmer is fully on the track.
    const margin = 12.0;
    final x = margin + (size.width - margin * 2) * progress;

    // ---- The track, filled behind the farmer ----
    final trackPaint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(margin, groundY),
      Offset(size.width - margin, groundY),
      trackPaint..color = _track,
    );
    if (x > margin) {
      canvas.drawLine(
        Offset(margin, groundY),
        Offset(x, groundY),
        trackPaint..color = AppTheme.dark,
      );
    }

    // ---- The walk cycle ----
    final phase = progress * _strides * 2 * math.pi;
    final swing = math.sin(phase); // -1 … 1
    final bob = (1 - math.cos(phase * 2)) / 2 * 1.2; // 0 when standing

    canvas.save();
    canvas.translate(x, groundY - 3 - bob);
    canvas.scale(_scale);
    _drawFarmer(canvas, swing);
    canvas.restore();
  }

  // Facing right. The origin is between the feet; y goes up (negative).
  void _drawFarmer(Canvas canvas, double swing) {
    final limb = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const hip = Offset(0, -12);
    const shoulder = Offset(0.5, -24);
    const legLength = 12.0;
    const armLength = 9.5;
    final legAngle = swing * 0.5; // about ±29°
    final armAngle = -swing * 0.6;

    Offset end(Offset from, double length, double angle) =>
        from + Offset(math.sin(angle) * length, math.cos(angle) * length);

    // Back leg and back arm first, a shade darker, so the near ones read
    // in front.
    limb
      ..strokeWidth = 3.2
      ..color = Color.lerp(_pants, Colors.black, 0.25)!;
    canvas.drawLine(hip, end(hip, legLength, -legAngle), limb);
    limb
      ..strokeWidth = 2.6
      ..color = Color.lerp(_shirt, Colors.black, 0.3)!;
    canvas.drawLine(shoulder, end(shoulder, armLength, -armAngle), limb);

    // Body (shirt).
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0.3, -18), width: 7.5, height: 13),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(body, Paint()..color = _shirt);

    // Near leg and arm, with a foot.
    limb
      ..strokeWidth = 3.2
      ..color = _pants;
    final foot = end(hip, legLength, legAngle);
    canvas.drawLine(hip, foot, limb);
    canvas.drawLine(
      foot,
      foot + const Offset(2.6, 0),
      limb..color = const Color(0xFF2B2B2B),
    );
    limb
      ..strokeWidth = 2.6
      ..color = _shirt;
    final hand = end(shoulder, armLength, armAngle);
    canvas.drawLine(shoulder, hand, limb);
    canvas.drawCircle(hand, 1.5, Paint()..color = _skin);

    // Head.
    canvas.drawCircle(const Offset(1.4, -29), 3.8, Paint()..color = _skin);

    // Salakot: a wide, shallow cone with a darker rim.
    final hat = Path()
      ..moveTo(-9.5, -31)
      ..lineTo(12, -31)
      ..lineTo(1.6, -38.5)
      ..close();
    canvas.drawPath(hat, Paint()..color = _straw);
    canvas.drawLine(
      const Offset(-9.5, -31),
      const Offset(12, -31),
      Paint()
        ..color = _strawDark
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FarmerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
