import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Reusable "AgriTrade+" wordmark: "Agri" #2D392B, "Trade+" #7E5D09.
class AgriTradeText extends StatelessWidget {
  final double fontSize;
  const AgriTradeText({super.key, this.fontSize = 28});

  static const Color _agri = Color.fromARGB(255, 14, 50, 16);
  static const Color _trade = Color(0xFF7E5D09);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.lilitaOne(fontSize: fontSize),
        children: const [
          TextSpan(text: 'Agri', style: TextStyle(color: _agri)),
          TextSpan(text: 'Trade+', style: TextStyle(color: _trade)),
        ],
      ),
    );
  }
}
