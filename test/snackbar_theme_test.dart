// System messages (SnackBars) are readable: white text on the brand's dark
// green — the text used to fall back to the dark body colour.
import 'package:agritrade/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('a SnackBar shows white text on dark green', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password updated successfully.')),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    final text = tester.widget<RichText>(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(RichText),
      ),
    );
    expect(text.text.style?.color, Colors.white);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, AppTheme.dark);
  });
}
