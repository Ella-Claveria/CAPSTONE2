import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// Reusable "AgriTrade+" wordmark, in one colour: the whole word is the
// brand's dark green (see AppTheme.brandText — the one shared style for
// it). Pass light: true for the version sitting on a dark background
// (e.g. the login hero), where it is white instead.
class AgriTradeText extends StatelessWidget {
  final double fontSize;
  final bool light;
  const AgriTradeText({super.key, this.fontSize = 28, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      'AgriTrade+',
      style: AppTheme.brandText(fontSize: fontSize, light: light),
    );
  }
}
