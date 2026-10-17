import 'package:flutter/material.dart';

// Outside the web: Flutter's own indicators (see busy_indicator.dart).

Widget busySpinner({required Color color, required double strokeWidth}) =>
    CircularProgressIndicator(strokeWidth: strokeWidth, color: color);

Widget busyBar({required Color color, required Color trackColor}) =>
    // Its height comes from BusyBar's box.
    LinearProgressIndicator(color: color, backgroundColor: trackColor);
