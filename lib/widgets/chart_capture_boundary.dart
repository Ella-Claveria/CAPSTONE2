import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Wraps a chart widget in a [RepaintBoundary] so the Export flow can
/// capture it as a PNG via [captureFrom] — the only place in this codebase
/// that reads pixels back off a rendered widget, since PNG export is the
/// one format that needs the chart to look exactly like it does on
/// screen rather than being rebuilt from raw numbers.
class ChartCaptureBoundary extends StatelessWidget {
  final GlobalKey captureKey;
  final Widget child;

  const ChartCaptureBoundary({super.key, required this.captureKey, required this.child});

  /// Renders [key]'s subtree to a PNG. Returns null if the key isn't
  /// currently attached to a live RenderRepaintBoundary (e.g. the chart
  /// was never scrolled into view, or has no data and rendered nothing).
  static Future<Uint8List?> captureFrom(GlobalKey key, {double pixelRatio = 2.0}) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: captureKey, child: child);
  }
}

/// Stable keys for the 5 chart-backed sections PNG export can capture —
/// held as static fields (not created per-build) since exactly one
/// Analytics Dashboard is ever live at a time, and the Export dialog needs
/// to reach the currently-rendered chart from outside the widget that
/// built it.
class DashboardChartKeys {
  DashboardChartKeys._();

  static final salesOverview = GlobalKey();
  static final salesByCategory = GlobalKey();
  static final priceTrend = GlobalKey();
  static final registrations = GlobalKey();
  static final verificationStatus = GlobalKey();
}
