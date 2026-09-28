import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Reusable "AgriTrade+" wordmark: "Agri" #0E3210, "Trade+" #B4823C (the
// same gold sampled straight from the logo mark's arrow, so the wordmark
// always matches the actual icon instead of an unrelated brown).
// Pass light: true for the version sitting on a dark green background
// (e.g. the login hero) — white "Agri", brighter gold "Trade+".
class AgriTradeText extends StatelessWidget {
  final double fontSize;
  final bool light;
  const AgriTradeText({super.key, this.fontSize = 28, this.light = false});

  static const Color _agri = Color.fromARGB(255, 14, 50, 16);
  static const Color _trade = Color(0xFFB4823C);
  static const Color _agriLight = Colors.white;
  static const Color _tradeLight = Color(0xFFF3C449);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.lilitaOne(fontSize: fontSize),
        children: [
          TextSpan(text: 'Agri', style: TextStyle(color: light ? _agriLight : _agri)),
          TextSpan(text: 'Trade+', style: TextStyle(color: light ? _tradeLight : _trade)),
        ],
      ),
    );
  }
}
