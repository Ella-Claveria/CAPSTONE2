import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_back_button.dart';

class AppTheme {
  // ---------- COLOURS ----------
  // The colour of the AgriTradeText wordmark (see brandText), so every
  // button in the app reads as the same dark green as the logo text.
  static const Color dark = Color.fromARGB(255, 14, 50, 16); // main dark green
  static const Color mid = Color(0xFF2E7D32); // brand green
  static const Color accent = Color(0xFFDCEDC8); // pale green
  static const Color bgLight = Colors.white; // splash / app background
  static const Color fieldFill = Color(0xFFF2F2F2); // textfield grey

  /// The one off-white page background for inner screens that sit their
  /// content on cards (Inventory, Order Details, Notifications…). Main
  /// tabs and forms are white.
  static const Color surface = Color(0xFFF7F8F6);

  /// The one pale green for soft highlight boxes, banners and selected
  /// rows. ([accent] is the stronger pale green, for chips and badges.)
  static const Color tint = Color(0xFFF1F7EC);

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
      colorScheme: ColorScheme.fromSeed(seedColor: mid, primary: dark),
      scaffoldBackgroundColor: bgLight,

      // <-- THIS is the line that changes the whole app's font.
      textTheme: montserratText,
      primaryTextTheme: montserratText,

      // Inner screens use AgriAppBar (widgets/agri_app_bar.dart); this is
      // the same dark green look as a fallback for any plain AppBar.
      appBarTheme: AppBarTheme(
        backgroundColor: dark,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),

      actionIconTheme: backButtonTheme,

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

      // Every button in the app is pill-shaped, for consistency.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark,
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.montserrat(fontSize: 13.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark,
          shape: const StadiumBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark,
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: const StadiumBorder()),
      ),

      // Default look for every TextField: curved edges — a pill on one
      // line, rounded corners on a several-line box.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        hintStyle: GoogleFonts.montserrat(fontSize: 13.5, color: Colors.grey),
        errorStyle: GoogleFonts.montserrat(fontSize: 11.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: mid, width: 1.4),
        ),
      ),

      // Fallback popup look for any dialog/sheet not built with
      // widgets/agri_dialog.dart (e.g. date pickers): same rounded white
      // card, Montserrat, dark-green title and the same dimmed barrier.
      // New popups should use agri_dialog.dart for the full frosted style.
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        barrierColor: const Color(0x61000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: dark,
        ),
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13,
          color: Colors.black87,
          height: 1.45,
        ),
      ),
      // The calendar (Report Delay, harvest date, needed-by date…) in the
      // same look as every other popup: a white card with rounded corners,
      // a dark-green Montserrat heading, the chosen day filled dark green,
      // and pill Cancel / OK buttons like AgriDialogButton.
      datePickerTheme: _datePickerTheme(),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        helpTextStyle: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
        dialHandColor: dark,
        dialBackgroundColor: tint,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : tint,
        ),
        hourMinuteTextColor: dark,
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        dayPeriodShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        dayPeriodColor: accent,
        dayPeriodTextColor: dark,
        entryModeIconColor: dark,
        cancelButtonStyle: _pickerCancelButton,
        confirmButtonStyle: _pickerConfirmButton,
      ),

      // Every dropdown list and popup menu opens as the same white panel
      // with rounded corners (it used to take the app's greenish surface
      // colour), with the current choice shown in pale green.
      canvasColor: Colors.white,
      focusColor: accent.withValues(alpha: 0.7),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.montserrat(
          fontSize: 13.5,
          color: Colors.black87,
        ),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Color(0x61000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Every system message (SnackBar): white text on the brand's dark
      // green, floating with rounded corners. The text colour has to be set
      // here — without one it fell back to the dark body text and could
      // not be read on the dark bar.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark,
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: accent,
        closeIconColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Picker buttons, shaped like AgriDialogButton: Cancel outlined, the
  // confirm button filled dark green.
  static final ButtonStyle _pickerCancelButton = TextButton.styleFrom(
    foregroundColor: dark,
    backgroundColor: Colors.white,
    side: const BorderSide(color: dark, width: 1.2),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
    textStyle: GoogleFonts.montserrat(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
  );
  static final ButtonStyle _pickerConfirmButton = TextButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: dark,
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
    textStyle: GoogleFonts.montserrat(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
  );

  static DatePickerThemeData _datePickerTheme() {
    OutlineInputBorder pill(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: color, width: width),
        );
    return DatePickerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      headerBackgroundColor: Colors.white,
      headerForegroundColor: dark,
      headerHelpStyle: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey[600],
      ),
      headerHeadlineStyle: GoogleFonts.montserrat(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: dark,
      ),
      dividerColor: Colors.grey.shade200,
      subHeaderForegroundColor: dark,
      toggleButtonTextStyle: GoogleFonts.montserrat(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: dark,
      ),
      weekdayStyle: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey[600],
      ),
      dayStyle: GoogleFonts.montserrat(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      dayForegroundColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return Colors.grey.shade400;
        }
        return Colors.black87;
      }),
      dayBackgroundColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? dark : Colors.transparent,
      ),
      dayOverlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.6)),
      todayForegroundColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) {
          return Colors.grey.shade400;
        }
        return dark;
      }),
      todayBackgroundColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? dark : Colors.transparent,
      ),
      todayBorder: const BorderSide(color: mid, width: 1.4),
      yearStyle: GoogleFonts.montserrat(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      yearForegroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : dark,
      ),
      yearBackgroundColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? dark : Colors.transparent,
      ),
      // Typing the date instead (the pencil): the same pill field as the
      // rest of the app.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        border: pill(Colors.grey.shade300),
        enabledBorder: pill(Colors.grey.shade300),
        focusedBorder: pill(mid, 1.4),
        errorBorder: pill(Colors.redAccent, 1.2),
        focusedErrorBorder: pill(Colors.redAccent, 1.4),
      ),
      cancelButtonStyle: _pickerCancelButton,
      confirmButtonStyle: _pickerConfirmButton,
    );
  }

  // Every app bar's Back button, on every screen: the shared white circle
  // with a dark green arrow instead of Flutter's plain arrow. Only the
  // icon changes — what the button does when tapped is untouched.
  static final ActionIconThemeData backButtonTheme = ActionIconThemeData(
    backButtonIconBuilder: (context) => const AppBackIcon(),
  );

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
      GoogleFonts.montserrat(fontSize: size, color: color ?? Colors.grey[700]);

  // The "AgriTrade+" wordmark: the whole word in one colour — the brand's
  // dark green, or white where it sits on a dark background. Rendered by
  // AgriTradeText; anything else that draws the brand name uses this too.
  // Montserrat Bold — the bundled Montserrat (pubspec.yaml), the same as
  // the password reset page's wordmark, so it is the same everywhere.
  static TextStyle brandText({double fontSize = 28, bool light = false}) =>
      TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w700,
        letterSpacing: fontSize * 0.01,
        fontSize: fontSize,
        color: light ? Colors.white : dark,
      );

  // Lilita One, bundled in assets/fonts (see pubspec.yaml), for the few
  // display headings that use it ("Verify Your Email").
  static const String brandFontFamily = 'LilitaOne';

  static TextStyle buttonText() =>
      GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.bold);

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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
  );

  // ---------- LOGIN-STYLE "GLOW" FIELD ----------
  // Pill-shaped, borderless field on its own white plate. At rest it only
  // has a faint lift shadow; the brand-green glow (in place of the usual
  // blue-glow neumorphic look) switches on around it while it's focused —
  // see the field wrapping this in LoginFormFields for the FocusNode that
  // drives [focused]. Used by the login form.
  static BoxDecoration glowFieldWrapper({bool focused = false}) =>
      BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: mid.withValues(alpha: 0.18),
                  blurRadius: 12,
                  spreadRadius: 0.5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
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
      prefixStyle: const TextStyle(
        color: dark,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
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
