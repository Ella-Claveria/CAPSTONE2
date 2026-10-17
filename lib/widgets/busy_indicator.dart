import 'package:flutter/material.dart';

import 'busy_indicator_native.dart'
    if (dart.library.js_interop) 'busy_indicator_web.dart'
    as impl;

/// A spinning ring for long work such as building a report. On the web
/// the browser draws and turns it (CSS), so it keeps moving smoothly even
/// while the page is busy building the file and Flutter cannot draw new
/// frames. Elsewhere it is the usual [CircularProgressIndicator].
class BusySpinner extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final Color color;

  const BusySpinner({
    super.key,
    required this.color,
    this.size = 16,
    this.strokeWidth = 2.2,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: size,
        height: size,
        child: impl.busySpinner(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

/// A thin bar with a stripe sliding along it, for the same long work as
/// [BusySpinner] and, like it, drawn by the browser on the web.
class BusyBar extends StatelessWidget {
  final double height;
  final Color color;
  final Color trackColor;

  const BusyBar({
    super.key,
    required this.color,
    required this.trackColor,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: impl.busyBar(color: color, trackColor: trackColor),
      ),
    );
  }
}
