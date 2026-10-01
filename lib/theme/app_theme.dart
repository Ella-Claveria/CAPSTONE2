import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ---------- COLOURS ----------
  // Matches the "Agri" half of the AgriTradeText wordmark, so every button
  // in the app reads as the same dark green as the logo text.
  static const Color dark = Color.fromARGB(255, 14, 50, 16); // main dark green
  static const Color mid = Color(0xFF2E7D32); // brand green
  static const Color accent = Color(0xFFDCEDC8); // pale green
  static const Color bgLight = Colors.white; // splash / app background
  static const Color fieldFill = Color(0xFFF2F2F2); // textfield grey

  // ==========================================================
  // THE GLOBAL THEME
  // ----------------------------------------------------------
  // Pass this into MaterialApp in main.dart:
  //
  //     theme: AppTheme.themeData(),
  //
  // That one line makes Montserrat the default everywhere.
  // ==========================================================
  static ThemeData themeData() {
    // Takes Flutter's standard set of text sizes (headings, body,
    // captions...) and rebuilds all of them in Montserrat.
    final montserratText = GoogleFonts.montserratTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: mid),
      scaffoldBackgroundColor: bgLight,

      // <-- THIS is the line that changes the whole app's font.
      textTheme: montserratText,
      primaryTextTheme: montserratText,

      appBarTheme: AppBarTheme(
        backgroundColor: mid,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),

      // Default look for every ElevatedButton in the app.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: dark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark,
          textStyle: GoogleFonts.montserrat(fontSize: 13.5),
        ),
      ),

      // Default look for every TextField.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        hintStyle: GoogleFonts.montserrat(fontSize: 13.5, color: Colors.grey),
        errorStyle: GoogleFonts.montserrat(fontSize: 11.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: mid, width: 1.4),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        contentTextStyle: GoogleFonts.montserrat(fontSize: 13.5),
      ),
    );
  }

  // ==========================================================
  // HELPER STYLES
  // ----------------------------------------------------------
  // You mostly won't need these now that the global theme handles
  // fonts — a plain Text('Hello') already renders in Montserrat. Keep
  // them for when you want a specific size or weight quickly.
  // ==========================================================

  static TextStyle heading(double size) => GoogleFonts.montserrat(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      );

  static TextStyle label() => GoogleFonts.montserrat(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      );

  static TextStyle body({Color? color, double size = 13.5}) =>
      GoogleFonts.montserrat(
        fontSize: size,
        color: color ?? Colors.grey[700],
      );

  static TextStyle buttonText() => GoogleFonts.montserrat(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      );

  // ---------- REUSABLE PIECES ----------

  static BoxDecoration authCard() => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static ButtonStyle primaryButton() => ElevatedButton.styleFrom(
        backgroundColor: dark,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      );

  // ---------- LOGIN-STYLE "GLOW" FIELD ----------
  // Pill-shaped, borderless field on its own white plate. At rest it only
  // has a faint lift shadow; the brand-green glow (in place of the usual
  // blue-glow neumorphic look) switches on around it while it's focused —
  // see the field wrapping this in LoginFormFields for the FocusNode that
  // drives [focused]. Used by the login form.
  static BoxDecoration glowFieldWrapper({bool focused = false}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: focused
            ? [
                BoxShadow(color: mid.withValues(alpha: 0.18), blurRadius: 12, spreadRadius: 0.5),
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3)),
              ]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
              ],
      );

  static InputDecoration inputBox({
    required String hint,
    required IconData icon,
    Widget? suffix,
    String? errorText,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey),
      prefixText: prefixText,
      prefixStyle: const TextStyle(color: dark, fontWeight: FontWeight.w600, fontSize: 15),
      suffixIcon: suffix,
      filled: true,
      fillColor: fieldFill,
      errorText: errorText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: mid, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }
}